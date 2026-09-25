package net.minecraft.godot.renderpearl;

import com.mojang.blaze3d.platform.NativeImage;
import com.mojang.renderpearl.api.buffers.GpuBuffer;
import com.mojang.renderpearl.api.buffers.GpuBufferSlice;
import com.mojang.renderpearl.api.buffers.TransientMemory;
import com.mojang.renderpearl.api.commands.CommandEncoder;
import com.mojang.renderpearl.api.commands.GpuFence;
import com.mojang.renderpearl.api.commands.GpuQueryPool;
import com.mojang.renderpearl.api.commands.RenderPass;
import com.mojang.renderpearl.api.commands.RenderPassDescriptor;
import com.mojang.renderpearl.api.textures.GpuTexture;
import com.mojang.renderpearl.api.textures.GpuTextureView;
import org.joml.Vector4fc;

import java.nio.ByteBuffer;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.OptionalDouble;
import java.util.function.Consumer;

/**
 * RenderPearl command encoder that owns one Godot offscreen frame.
 *
 * The encoder starts a neutral command frame, turns supported 26.3
 * RenderPassDescriptor instances into GodotRenderPass objects, and atomically
 * submits the completed frame through RenderCommandTransport. The production
 * transport is native; tests use an in-memory validator/capture.
 */
final class GodotCommandEncoder implements CommandEncoder {
    private final RenderCommandWriter writer;
    private final RenderCommandTransport transport;
    private final int targetWidth;
    private final int targetHeight;
    private final Runnable sharedFrameSubmit;
    private final GodotGpuDevice device;
    private GodotTransientMemory transientMemory;
    private GodotRenderPass activePass;
    private boolean submitted;

    GodotCommandEncoder(
            long frameId,
            int targetWidth,
            int targetHeight,
            RenderCommandTransport transport
    ) {
        this(frameId, targetWidth, targetHeight, transport, writer -> { });
    }

    /**
     * Creates an encoder with a device-owned declaration prelude. Resource
     * allocation packets must precede writes and render passes, so a device
     * records its live buffer/texture descriptors immediately after FRAME_BEGIN.
     */
    GodotCommandEncoder(
            long frameId,
            int targetWidth,
            int targetHeight,
            RenderCommandTransport transport,
            Consumer<RenderCommandWriter> framePrelude
    ) {
        if (targetWidth <= 0 || targetHeight <= 0) {
            throw new IllegalArgumentException("Offscreen target dimensions must be positive");
        }
        this.targetWidth = targetWidth;
        this.targetHeight = targetHeight;
        this.transport = Objects.requireNonNull(transport, "transport");
        this.sharedFrameSubmit = null;
        this.device = null;
        this.writer = new RenderCommandWriter();
        writer.beginFrame(frameId, targetWidth, targetHeight);
        Objects.requireNonNull(framePrelude, "framePrelude").accept(writer);
    }

    /**
     * Appends to a device-owned frame. Minecraft 26.3 records GUI uploads and
     * draws on encoders it never submits; {@code Minecraft.renderFrame} submits
     * a later encoder. Those commands have to share one frame or the viewport
     * only receives the empty final submit.
     */
    GodotCommandEncoder(
            RenderCommandWriter sharedWriter,
            int targetWidth,
            int targetHeight,
            RenderCommandTransport transport,
            Runnable sharedFrameSubmit
    ) {
        this(sharedWriter, targetWidth, targetHeight, transport, sharedFrameSubmit, null);
    }

    GodotCommandEncoder(
            RenderCommandWriter sharedWriter,
            int targetWidth,
            int targetHeight,
            RenderCommandTransport transport,
            Runnable sharedFrameSubmit,
            GodotGpuDevice device
    ) {
        if (targetWidth <= 0 || targetHeight <= 0) {
            throw new IllegalArgumentException("Offscreen target dimensions must be positive");
        }
        this.writer = Objects.requireNonNull(sharedWriter, "sharedWriter");
        this.targetWidth = targetWidth;
        this.targetHeight = targetHeight;
        this.transport = Objects.requireNonNull(transport, "transport");
        this.sharedFrameSubmit = Objects.requireNonNull(sharedFrameSubmit, "sharedFrameSubmit");
        this.device = device;
    }

    @Override
    public void submit() {
        requireOpen();
        logClientScreen();
        if (activePass != null) {
            throw new IllegalStateException("Cannot submit while a RenderPass is still open");
        }
        if (sharedFrameSubmit != null) {
            sharedFrameSubmit.run();
        } else {
            byte[] frame = writer.finishFrame();
            int result = transport.submit(frame);
            if (result <= 0) {
                throw new IllegalStateException("Native RenderPearl frame submission failed: " + result);
            }
        }
        submitted = true;
    }

    @Override
    public TransientMemory transientMemory() {
        requireOpen();
        if (device == null) {
            throw unsupported("transient memory");
        }
        if (transientMemory == null) {
            transientMemory = new GodotTransientMemory(device);
        }
        return transientMemory;
    }

    @Override
    public RenderPass createRenderPass(RenderPassDescriptor descriptor) {
        requireOpen();
        if (activePass != null) {
            throw new IllegalStateException("Render passes cannot be nested");
        }
        Objects.requireNonNull(descriptor, "descriptor");
        List<?> colors = descriptor.colorAttachments();
        if (colors.size() != 1) {
            throw new UnsupportedOperationException("Godot backend initially supports exactly one color attachment");
        }

        RenderPassDescriptor.Attachment<?> colorAttachment =
                (RenderPassDescriptor.Attachment<?>) colors.getFirst();
        GodotGpuTextureView colorView = requireTextureView(colorAttachment.textureView(), "color");
        float[] clearColor = clearColor(colorAttachment.clearValue());

        int depthTextureId = 0;
        double clearDepth = 0.0; // Minecraft 26.3 uses reversed-Z depth.
        RenderPassDescriptor.Attachment<?> depthAttachment = descriptor.depthAttachment();
        if (depthAttachment != null) {
            GodotGpuTextureView depthView = requireTextureView(depthAttachment.textureView(), "depth");
            depthTextureId = sourceTextureHandle(depthView);
            clearDepth = clearDepth(depthAttachment.clearValue());
        }

        // The executor looks attachments up as textures. A view handle is a
        // separate registry id and would reject the pass after the clear.
        writer.beginRenderPass(
                sourceTextureHandle(colorView),
                depthTextureId,
                clearColor[0], clearColor[1], clearColor[2], clearColor[3], clearDepth
        );
        GodotRenderPass pass = new GodotRenderPass(
                writer,
                targetWidth,
                targetHeight,
                () -> activePass = null
        );
        activePass = pass;
        if (descriptor.renderArea() != null) {
            RenderPass.RenderArea area = descriptor.renderArea();
            pass.enableScissor(area.x(), area.y(), area.width(), area.height());
        }
        return pass;
    }

    @Override
    public void clearColorTexture(GpuTexture texture, Vector4fc color) {
        requireOpenOutsidePass();
        Objects.requireNonNull(color, "color");
        GodotGpuTexture colorTexture = requireTexture(texture);
        writer.beginRenderPass(
                colorTexture.nativeHandle(), 0, color.x(), color.y(), color.z(), color.w(), 0.0
        );
        writer.endRenderPass();
    }

    @Override
    public void clearColorAndDepthTextures(GpuTexture colorTexture, Vector4fc color, GpuTexture depthTexture, double depth) {
        clearColorAndDepthTextures(colorTexture, color, depthTexture, depth, 0, 0, 0, 0, 0);
    }

    @Override
    public void clearColorAndDepthTextures(
            GpuTexture colorTexture,
            Vector4fc color,
            GpuTexture depthTexture,
            double depth,
            int regionX,
            int regionY,
            int regionWidth,
            int regionHeight,
            int mipLevel
    ) {
        requireOpenOutsidePass();
        Objects.requireNonNull(color, "color");
        if (mipLevel != 0) {
            throw unsupported("clears of a non-zero mip");
        }
        GodotGpuTexture colorTarget = requireTexture(colorTexture);
        int depthId = depthTexture == null ? 0 : requireTexture(depthTexture).nativeHandle();
        writer.beginRenderPass(
                colorTarget.nativeHandle(), depthId, color.x(), color.y(), color.z(), color.w(), depth
        );
        if (regionWidth > 0 && regionHeight > 0) {
            writer.setScissor(regionX, regionY, regionWidth, regionHeight);
        }
        writer.endRenderPass();
    }

    @Override
    public void clearDepthTexture(GpuTexture texture, double depth) {
        requireOpenOutsidePass();
        Objects.requireNonNull(texture, "texture");
        // GuiRenderer always clears depth before the main UI pass. The viewport
        // drawer does not attach that depth image, so a thrown clear would abort
        // the Java UI without changing the presented color target.
    }

    @Override
    public void writeToBuffer(GpuBufferSlice destination, ByteBuffer data) {
        requireOpenOutsidePass();
        Objects.requireNonNull(destination, "destination");
        Objects.requireNonNull(data, "data");
        if (!(destination.buffer() instanceof GodotGpuBuffer buffer)) {
            throw new IllegalArgumentException("Destination buffer was not created by GodotRenderPearlBackend");
        }
        ByteBuffer source = data.duplicate();
        if (source.remaining() > destination.length()) {
            throw new IllegalArgumentException("Write data exceeds destination buffer slice");
        }
        byte[] bytes = new byte[source.remaining()];
        source.get(bytes);
        buffer.writeFrom(destination.offset(), ByteBuffer.wrap(bytes));
        writer.writeBuffer(buffer.nativeHandle(), destination.offset(), bytes);
        buffer.clearDirty(destination.offset(), bytes.length);
    }

    @Override
    public void copyToBuffer(GpuBufferSlice source, GpuBufferSlice target) {
        requireOpenOutsidePass();
        Objects.requireNonNull(source, "source");
        Objects.requireNonNull(target, "target");
        if (!(source.buffer() instanceof GodotGpuBuffer sourceBuffer)
                || !(target.buffer() instanceof GodotGpuBuffer targetBuffer)) {
            throw new IllegalArgumentException("Buffer copy requires Godot RenderPearl buffers");
        }
        if (source.length() > Integer.MAX_VALUE || target.length() < source.length()) {
            throw new IllegalArgumentException("Buffer copy range is larger than the destination slice");
        }
        int length = (int) source.length();
        byte[] bytes = sourceBuffer.copyRange(source.offset(), length);
        targetBuffer.writeFrom(target.offset(), ByteBuffer.wrap(bytes));
        writer.writeBuffer(targetBuffer.nativeHandle(), target.offset(), bytes);
        targetBuffer.clearDirty(target.offset(), length);
    }

    @Override
    public void writeToTexture(GpuTexture texture, NativeImage image) {
        writeToTexture(texture, image, 0, 0, 0, 0);
    }

    @Override
    public void writeToTexture(
            GpuTexture texture,
            NativeImage image,
            int mipLevel,
            int depthOrLayer,
            int destX,
            int destY
    ) {
        Objects.requireNonNull(image, "image");
        if (depthOrLayer != 0) {
            throw unsupported("NativeImage uploads to a non-zero array layer");
        }
        writeToTexture(
                texture,
                ByteBuffer.wrap(rgbaBytes(image)),
                mipLevel,
                1,
                destX,
                destY,
                image.getWidth(),
                image.getHeight()
        );
    }

    @Override
    public void writeToTexture(
            GpuTexture texture,
            ByteBuffer data,
            int mipLevel,
            int depthOrLayers,
            int destX,
            int destY,
            int width,
            int height
    ) {
        requireOpenOutsidePass();
        if (!(texture instanceof GodotGpuTexture godotTexture)) {
            throw new IllegalArgumentException("Texture was not created by GodotRenderPearlBackend");
        }
        Objects.requireNonNull(data, "data");
        if (device != null) {
            device.ensureTextureRecorded(godotTexture, writer);
        }
        if (width <= 0 || height <= 0 || depthOrLayers <= 0 || destX < 0 || destY < 0) {
            throw new IllegalArgumentException("Texture upload dimensions and destination must be valid");
        }
        int mipWidth = godotTexture.getWidth(mipLevel);
        int mipHeight = godotTexture.getHeight(mipLevel);
        if (depthOrLayers > godotTexture.getDepthOrLayers() ||
                destX > mipWidth - width || destY > mipHeight - height) {
            throw new IllegalArgumentException("Texture upload range lies outside the target texture");
        }
        ByteBuffer source = data.duplicate();
        byte[] bytes = new byte[source.remaining()];
        source.get(bytes);
        writer.writeTexture(
                godotTexture.nativeHandle(), width, height, depthOrLayers, destX, destY, mipLevel, bytes
        );
    }

    @Override
    public void copyBufferToTexture(
            GpuBufferSlice source,
            int sourceX,
            int sourceY,
            int sourceWidth,
            int sourceHeight,
            GpuTexture destination,
            int destinationX,
            int destinationY,
            int copyWidth,
            int copyHeight,
            int mipLevel,
            int arrayLayer
    ) {
        requireOpen();
        if (!(source.buffer() instanceof GodotGpuBuffer buffer)) {
            throw new IllegalArgumentException("Buffer-to-texture copy source was not created by GodotRenderPearlBackend");
        }
        GodotGpuTexture texture = requireTexture(destination);
        int width = copyWidth > 0 ? copyWidth : Math.max(sourceWidth, 1);
        int height = copyHeight > 0 ? copyHeight : Math.max(sourceHeight, 1);
        byte[] pixels = regionBytes(
                buffer, source, sourceX, sourceY, sourceWidth, sourceHeight, width, height);
        int mip = mipLevel >= 0 && mipLevel < texture.getMipLevels() ? mipLevel : 0;
        int destX = Math.max(destinationX, 0);
        int destY = Math.max(destinationY, 0);
        int mipWidth = texture.getWidth(mip);
        int mipHeight = texture.getHeight(mip);
        if (pixels.length == 0 || destX >= mipWidth || destY >= mipHeight
                || width > mipWidth - destX || height > mipHeight - destY) {
            System.err.println("TEX_UPLOAD_SKIP " + width + "x" + height + " at " + destX + "," + destY
                    + " mip " + mip + " texture " + mipWidth + "x" + mipHeight
                    + " bytes " + pixels.length);
            return;
        }
        // The texture may have been created after this frame's resource prelude.
        if (device != null) {
            device.ensureTextureRecorded(texture, writer);
        } else {
            texture.recordCreate(writer);
        }
        writer.writeTexture(texture.nativeHandle(), width, height, 1, destX, destY, mip, pixels);
        if (arrayLayer > 0) {
            System.err.println("TEX_UPLOAD_LAYER " + arrayLayer + " stored at mip " + mip);
        }
    }

    private static byte[] regionBytes(
            GodotGpuBuffer buffer,
            GpuBufferSlice source,
            int sourceX,
            int sourceY,
            int sourceWidth,
            int sourceHeight,
            int copyWidth,
            int copyHeight
    ) {
        int available = (int) Math.min(source.length(), Integer.MAX_VALUE);
        byte[] full = buffer.copyRange(source.offset(), available);
        if (sourceWidth <= 0 || sourceHeight <= 0 || copyWidth <= 0 || copyHeight <= 0
                || available % (sourceWidth * (long) sourceHeight) != 0) {
            return full;
        }
        int bytesPerPixel = available / (sourceWidth * sourceHeight);
        if (sourceX == 0 && sourceY == 0 && copyWidth == sourceWidth && copyHeight == sourceHeight) {
            return full;
        }
        if (sourceX < 0 || sourceY < 0 || copyWidth > sourceWidth - sourceX || copyHeight > sourceHeight - sourceY
                || bytesPerPixel <= 0) {
            // A mismatched region must not abort resource reload. The whole
            // staging image is still a valid upload for this texture.
            return full;
        }
        byte[] region = new byte[copyWidth * copyHeight * bytesPerPixel];
        for (int row = 0; row < copyHeight; row++) {
            int from = ((sourceY + row) * sourceWidth + sourceX) * bytesPerPixel;
            System.arraycopy(full, from, region, row * copyWidth * bytesPerPixel, copyWidth * bytesPerPixel);
        }
        return region;
    }

    @Override
    public void copyTextureToBuffer(GpuTexture source, GpuBuffer target, long offset, Runnable callback, int mipLevel) {
        throw unsupported("texture-to-buffer copies");
    }

    @Override
    public void copyTextureToBuffer(
            GpuTexture source,
            GpuBuffer target,
            long offset,
            Runnable callback,
            int sourceX,
            int sourceY,
            int sourceWidth,
            int sourceHeight,
            int mipLevel
    ) {
        throw unsupported("regional texture-to-buffer copies");
    }

    @Override
    public void copyTextureToTexture(
            GpuTexture source,
            GpuTexture target,
            int sourceX,
            int sourceY,
            int sourceZ,
            int destinationX,
            int destinationY,
            int destinationZ,
            int mipLevel
    ) {
        throw unsupported("texture-to-texture copies");
    }

    @Override
    public GpuFence createFence() {
        requireOpen();
        return new GodotGpuFence();
    }

    @Override
    public void writeTimestamp(GpuQueryPool pool, int index) {
        // TimerQuery records around frames. Missing GPU timestamps are skipped
        // by the client when the pool returns empty values.
        if (pool != null && (index < 0 || index >= pool.size())) {
            throw new IndexOutOfBoundsException("Timestamp query index " + index);
        }
    }

    private void requireOpen() {
        if (submitted) {
            throw new IllegalStateException("Command encoder was already submitted");
        }
    }

    private void requireOpenOutsidePass() {
        requireOpen();
        if (activePass != null) {
            throw new IllegalStateException("Operation is not valid inside a RenderPass");
        }
    }

    private static GodotGpuTexture requireTexture(GpuTexture texture) {
        if (!(texture instanceof GodotGpuTexture godotTexture)) {
            throw new IllegalArgumentException("Texture was not created by GodotRenderPearlBackend");
        }
        return godotTexture;
    }

    /**
     * NativeImage.getPixel returns ARGB. Godot RGBA8 is tightly packed R, G, B, A.
     * Luminance glyphs become .rrrr so the extracted text shader can sample coverage.
     */
    private static byte[] rgbaBytes(NativeImage image) {
        int width = image.getWidth();
        int height = image.getHeight();
        int count = width * height;
        byte[] rgba = new byte[count * 4];
        if ("RGBA".equals(image.format().name())) {
            int[] pixels = image.getPixels();
            if (pixels.length < count) {
                throw new IllegalArgumentException("NativeImage pixel array is shorter than its dimensions");
            }
            for (int index = 0; index < count; index++) {
                int argb = pixels[index];
                rgba[index * 4] = (byte) ((argb >>> 16) & 0xFF);
                rgba[index * 4 + 1] = (byte) ((argb >>> 8) & 0xFF);
                rgba[index * 4 + 2] = (byte) (argb & 0xFF);
                rgba[index * 4 + 3] = (byte) ((argb >>> 24) & 0xFF);
            }
            return rgba;
        }
        ByteBuffer raw = image.getPixelBytes().duplicate();
        raw.order(java.nio.ByteOrder.LITTLE_ENDIAN);
        String format = image.format().name();
        int components = switch (format) {
            case "RGB" -> 3;
            case "LUMINANCE_ALPHA" -> 2;
            case "LUMINANCE" -> 1;
            default -> throw new IllegalArgumentException("Unsupported NativeImage format " + format);
        };
        if (raw.remaining() < count * components) {
            throw new IllegalArgumentException("NativeImage byte buffer is shorter than its dimensions");
        }
        for (int index = 0; index < count; index++) {
            int red;
            int green;
            int blue;
            int alpha = 255;
            if (components == 1) {
                red = green = blue = raw.get() & 0xFF;
                alpha = red;
            } else if (components == 2) {
                red = green = blue = raw.get() & 0xFF;
                alpha = raw.get() & 0xFF;
            } else {
                red = raw.get() & 0xFF;
                green = raw.get() & 0xFF;
                blue = raw.get() & 0xFF;
            }
            rgba[index * 4] = (byte) red;
            rgba[index * 4 + 1] = (byte) green;
            rgba[index * 4 + 2] = (byte) blue;
            rgba[index * 4 + 3] = (byte) alpha;
        }
        return rgba;
    }

    private static long nextScreenLogNanos;

    /** LoadingOverlay stays up until resource reload finishes, so name it in the CI log. */
    private static void logClientScreen() {
        long now = System.nanoTime();
        if (now < nextScreenLogNanos) {
            return;
        }
        nextScreenLogNanos = now + 10_000_000_000L;
        try {
            Class<?> minecraftClass = Class.forName("net.minecraft.client.Minecraft");
            Object minecraft = minecraftClass.getMethod("getInstance").invoke(null);
            Object gui = declaredField(minecraft, "gui");
            Object screen = gui.getClass().getMethod("screen").invoke(gui);
            Object overlay = gui.getClass().getMethod("overlay").invoke(gui);
            String progress = "";
            if (overlay != null) {
                try {
                    Object value = declaredField(overlay, "currentProgress");
                    progress = " progress " + value;
                    Object reload = declaredField(overlay, "reload");
                    if (reload != null) {
                        progress += " reloadDone " + reload.getClass().getMethod("isDone").invoke(reload);
                        progress += reloadCounters(reload);
                    }
                } catch (ReflectiveOperationException ignored) {
                    progress = "";
                }
            }
            System.err.println("MINECRAFT_GD_CLIENT screen " + simpleName(screen)
                    + " overlay " + simpleName(overlay) + progress);
        } catch (Throwable error) {
            System.err.println("MINECRAFT_GD_CLIENT screen unknown " + error.getClass().getSimpleName());
        }
    }

    /** Names the listener still preparing so a stuck reload is visible without a thread dump. */
    private static String reloadCounters(Object reload) {
        StringBuilder details = new StringBuilder();
        appendReloadCounters(reload, details, 0);
        String text = details.toString();
        return text.length() <= 160 ? text : text.substring(0, 160);
    }

    private static void appendReloadCounters(Object owner, StringBuilder details, int depth) {
        if (owner == null || depth > 2) {
            return;
        }
        Class<?> type = owner.getClass();
        while (type != null && type != Object.class) {
            for (var field : type.getDeclaredFields()) {
                if (java.lang.reflect.Modifier.isStatic(field.getModifiers())) {
                    continue;
                }
                Object value;
                try {
                    field.setAccessible(true);
                    value = field.get(owner);
                } catch (ReflectiveOperationException ignored) {
                    continue;
                }
                String name = field.getName();
                if (value instanceof java.util.concurrent.atomic.AtomicInteger counter
                        && (name.contains("Task") || name.contains("Reload"))) {
                    details.append(' ').append(name).append('=').append(counter.get());
                } else if (value instanceof java.util.Collection<?> pending && name.contains("prepar")) {
                    details.append(' ').append(name).append('=').append(pending.size());
                    int shown = 0;
                    for (Object listener : pending) {
                        if (shown++ >= 3) {
                            break;
                        }
                        details.append(' ').append(listener == null ? "null" : listener.getClass().getSimpleName());
                    }
                }
            }
            type = type.getSuperclass();
        }
    }

    private static Object declaredField(Object owner, String name) throws ReflectiveOperationException {
        var field = owner.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return field.get(owner);
    }

    private static String simpleName(Object value) {
        return value == null ? "none" : value.getClass().getSimpleName();
    }

    private static int sourceTextureHandle(GodotGpuTextureView view) {
        if (!(view.texture() instanceof GodotGpuTexture texture)) {
            throw new IllegalArgumentException("Texture view source was not created by GodotRenderPearlBackend");
        }
        return texture.nativeHandle();
    }

    private static GodotGpuTextureView requireTextureView(GpuTextureView view, String attachmentName) {
        if (!(view instanceof GodotGpuTextureView godotView)) {
            throw new IllegalArgumentException(
                    attachmentName + " attachment was not created by GodotRenderPearlBackend"
            );
        }
        return godotView;
    }

    private static float[] clearColor(Object value) {
        if (value instanceof Optional<?> optional) {
            if (optional.orElse(null) instanceof Vector4fc color) {
                return new float[] {color.x(), color.y(), color.z(), color.w()};
            }
            // Empty clear means load the existing attachment. Negative alpha is
            // the no-clear signal; it is not a displayable color.
            return new float[] {0.0f, 0.0f, 0.0f, -1.0f};
        }
        return new float[] {0.0f, 0.0f, 0.0f, 1.0f};
    }

    private static double clearDepth(Object value) {
        if (value instanceof OptionalDouble depth && depth.isPresent()) {
            return depth.getAsDouble();
        }
        return 0.0;
    }

    private static UnsupportedOperationException unsupported(String feature) {
        return new UnsupportedOperationException("Godot CommandEncoder has not implemented " + feature);
    }
}
