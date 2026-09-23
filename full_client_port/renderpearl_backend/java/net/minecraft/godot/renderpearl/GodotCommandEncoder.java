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
    private final RenderCommandWriter writer = new RenderCommandWriter();
    private final RenderCommandTransport transport;
    private final int targetWidth;
    private final int targetHeight;
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
        writer.beginFrame(frameId, targetWidth, targetHeight);
        Objects.requireNonNull(framePrelude, "framePrelude").accept(writer);
    }

    @Override
    public void submit() {
        requireOpen();
        if (activePass != null) {
            throw new IllegalStateException("Cannot submit while a RenderPass is still open");
        }
        byte[] frame = writer.finishFrame();
        int result = transport.submit(frame);
        if (result <= 0) {
            throw new IllegalStateException("Native RenderPearl frame submission failed: " + result);
        }
        submitted = true;
    }

    @Override
    public TransientMemory transientMemory() {
        throw unsupported("transient memory");
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
            depthTextureId = depthView.nativeHandle();
            clearDepth = clearDepth(depthAttachment.clearValue());
        }

        writer.beginRenderPass(
                colorView.nativeHandle(),
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
        throw unsupported("standalone color clears");
    }

    @Override
    public void clearColorAndDepthTextures(GpuTexture colorTexture, Vector4fc color, GpuTexture depthTexture, double depth) {
        throw unsupported("standalone color/depth clears");
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
        throw unsupported("regional color/depth clears");
    }

    @Override
    public void clearDepthTexture(GpuTexture texture, double depth) {
        throw unsupported("standalone depth clears");
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
    }

    @Override
    public void copyToBuffer(GpuBufferSlice source, GpuBufferSlice target) {
        throw unsupported("buffer-to-buffer copies");
    }

    @Override
    public void writeToTexture(GpuTexture texture, NativeImage image) {
        throw unsupported("NativeImage texture uploads");
    }

    @Override
    public void writeToTexture(GpuTexture texture, NativeImage image, int depthOrLayer, int destX, int destY, int mipLevel) {
        throw unsupported("regional NativeImage texture uploads");
    }

    @Override
    public void writeToTexture(
            GpuTexture texture,
            ByteBuffer data,
            int width,
            int height,
            int depthOrLayers,
            int destX,
            int destY,
            int mipLevel
    ) {
        throw unsupported("byte-buffer texture uploads");
    }

    @Override
    public void copyBufferToTexture(
            GpuBufferSlice source,
            int sourceX,
            int sourceY,
            int sourceWidth,
            int sourceHeight,
            GpuTexture target,
            int destinationX,
            int destinationY,
            int destinationZ,
            int copyWidth,
            int copyHeight,
            int arrayLayer
    ) {
        throw unsupported("buffer-to-texture copies");
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
        throw unsupported("GPU fences");
    }

    @Override
    public void writeTimestamp(GpuQueryPool pool, int index) {
        throw unsupported("timestamp queries");
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

    private static GodotGpuTextureView requireTextureView(GpuTextureView view, String attachmentName) {
        if (!(view instanceof GodotGpuTextureView godotView)) {
            throw new IllegalArgumentException(
                    attachmentName + " attachment was not created by GodotRenderPearlBackend"
            );
        }
        return godotView;
    }

    private static float[] clearColor(Object value) {
        if (value instanceof Optional<?> optional && optional.orElse(null) instanceof Vector4fc color) {
            return new float[] {color.x(), color.y(), color.z(), color.w()};
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
