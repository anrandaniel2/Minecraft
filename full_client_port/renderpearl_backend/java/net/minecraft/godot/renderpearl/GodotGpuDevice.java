package net.minecraft.godot.renderpearl;

import com.mojang.renderpearl.api.GpuFormat;
import com.mojang.renderpearl.api.buffers.GpuBuffer;
import com.mojang.renderpearl.api.commands.CommandEncoder;
import com.mojang.renderpearl.api.commands.GpuQueryPool;
import com.mojang.renderpearl.api.device.DeviceFeatures;
import com.mojang.renderpearl.api.device.DeviceInfo;
import com.mojang.renderpearl.api.device.DeviceLimits;
import com.mojang.renderpearl.api.device.DeviceType;
import com.mojang.renderpearl.api.device.GpuDevice;
import com.mojang.renderpearl.api.device.GpuSurface;
import com.mojang.renderpearl.api.device.HintsAndWorkarounds;
import com.mojang.renderpearl.api.pipeline.CompiledRenderPipeline;
import com.mojang.renderpearl.api.pipeline.RenderPipeline;
import com.mojang.renderpearl.api.pipeline.ShaderSource;
import com.mojang.renderpearl.api.textures.AddressMode;
import com.mojang.renderpearl.api.textures.FilterMode;
import com.mojang.renderpearl.api.textures.GpuSampler;
import com.mojang.renderpearl.api.textures.GpuTexture;
import com.mojang.renderpearl.api.textures.GpuTextureView;

import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.OptionalDouble;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Executor;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.BooleanSupplier;
import java.util.function.Supplier;

/**
 * RenderPearl {@link GpuDevice} entry point for the Godot backend.
 *
 * It owns the Java-side resource registry, constructs real extracted 26.3
 * resource and encoder interfaces, and emits completed command encoders to a
 * Godot-free transport. The native packet executor remains responsible for
 * turning resource/pipeline commands into Godot RenderingDevice objects.
 */
public final class GodotGpuDevice implements GpuDevice {
    private static final DeviceLimits LIMITS = new DeviceLimits(
            1, 256, 16_384, Integer.MAX_VALUE, 0, 1, 0
    );
    private static final DeviceFeatures FEATURES = new DeviceFeatures(
            false, false, false, false, false, false, false, true
    );
    private static final HintsAndWorkarounds HINTS = new HintsAndWorkarounds(
            false, false, true, false
    );
    private static final DeviceInfo DEVICE_INFO = new DeviceInfo(
            "Godot RenderPearl adapter",
            "Godot Engine",
            "Godot RenderingDevice command transport",
            true,
            "godot-gdextension",
            1.0f,
            LIMITS,
            FEATURES,
            Set.of(),
            HINTS,
            DeviceType.OTHER
    );

    private final GodotRenderResourceRegistry registry = new GodotRenderResourceRegistry();
    private final RenderCommandTransport transport;
    private final AtomicLong nextFrameId = new AtomicLong();
    private final Object resourcesLock = new Object();
    private final List<GodotGpuBuffer> buffers = new ArrayList<>();
    private final List<GodotGpuTexture> textures = new ArrayList<>();
    private volatile int targetWidth;
    private volatile int targetHeight;
    private volatile boolean closed;

    /**
     * Creates a device which delivers each completed frame to the supplied
     * neutral transport. It accepts a target size before a surface has been
     * configured so initial resource loading can create command encoders.
     */
    public GodotGpuDevice(int targetWidth, int targetHeight, RenderCommandTransport transport) {
        setTargetSize(targetWidth, targetHeight);
        this.transport = Objects.requireNonNull(transport, "transport");
    }

    @Override
    public GpuSurface createSurface(long windowHandle, BooleanSupplier isWindowAlive) {
        requireOpen();
        Objects.requireNonNull(isWindowAlive, "isWindowAlive");
        return new GodotGpuSurface(this, windowHandle, isWindowAlive);
    }

    @Override
    public CommandEncoder createCommandEncoder() {
        requireOpen();
        List<GodotGpuBuffer> frameBuffers;
        List<GodotGpuTexture> frameTextures;
        synchronized (resourcesLock) {
            buffers.removeIf(GodotGpuBuffer::isClosed);
            textures.removeIf(GodotGpuTexture::isClosed);
            frameBuffers = List.copyOf(buffers);
            frameTextures = List.copyOf(textures);
        }
        return new GodotCommandEncoder(
                nextFrameId.getAndIncrement(),
                targetWidth,
                targetHeight,
                transport,
                writer -> {
                    for (GodotGpuBuffer buffer : frameBuffers) {
                        buffer.recordCreate(writer);
                    }
                    for (GodotGpuTexture texture : frameTextures) {
                        texture.recordCreate(writer);
                    }
                }
        );
    }

    @Override
    public GpuSampler createSampler(
            AddressMode addressModeU,
            AddressMode addressModeV,
            FilterMode minFilter,
            FilterMode magFilter,
            int maxAnisotropy,
            OptionalDouble lodBias
    ) {
        requireOpen();
        return new GodotGpuSampler(
                registry,
                Objects.requireNonNull(addressModeU, "addressModeU"),
                Objects.requireNonNull(addressModeV, "addressModeV"),
                Objects.requireNonNull(minFilter, "minFilter"),
                Objects.requireNonNull(magFilter, "magFilter"),
                maxAnisotropy,
                Objects.requireNonNull(lodBias, "lodBias")
        );
    }

    @Override
    public GpuTexture createTexture(
            Supplier<String> label,
            int usage,
            GpuFormat format,
            int width,
            int height,
            int depthOrLayers,
            int mipLevels
    ) {
        requireOpen();
        Objects.requireNonNull(label, "label");
        return createTexture(label.get(), usage, format, width, height, depthOrLayers, mipLevels);
    }

    @Override
    public GpuTexture createTexture(
            String label,
            int usage,
            GpuFormat format,
            int width,
            int height,
            int depthOrLayers,
            int mipLevels
    ) {
        requireOpen();
        GodotGpuTexture texture = new GodotGpuTexture(
                registry,
                Objects.requireNonNull(label, "label"),
                usage,
                Objects.requireNonNull(format, "format"),
                width,
                height,
                depthOrLayers,
                mipLevels
        );
        synchronized (resourcesLock) {
            textures.add(texture);
        }
        return texture;
    }

    @Override
    public GpuTextureView createTextureView(GpuTexture texture) {
        GodotGpuTexture godotTexture = requireTexture(texture);
        return new GodotGpuTextureView(registry, godotTexture, 0, godotTexture.getMipLevels());
    }

    @Override
    public GpuTextureView createTextureView(GpuTexture texture, int baseMipLevel, int mipLevels) {
        return new GodotGpuTextureView(registry, requireTexture(texture), baseMipLevel, mipLevels);
    }

    @Override
    public GpuBuffer createBuffer(Supplier<String> label, int usage, long size) {
        requireOpen();
        Objects.requireNonNull(label, "label");
        // RenderPearl's GpuBuffer does not expose labels. Evaluate the supplier
        // now to retain its normal validation/lifecycle behavior.
        Objects.requireNonNull(label.get(), "label.get()");
        GodotGpuBuffer buffer = new GodotGpuBuffer(registry, usage, size);
        synchronized (resourcesLock) {
            buffers.add(buffer);
        }
        return buffer;
    }

    @Override
    public GpuBuffer createBuffer(Supplier<String> label, int usage, ByteBuffer initialData) {
        requireOpen();
        Objects.requireNonNull(label, "label");
        Objects.requireNonNull(label.get(), "label.get()");
        GodotGpuBuffer buffer = new GodotGpuBuffer(
                registry, usage, Objects.requireNonNull(initialData, "initialData")
        );
        synchronized (resourcesLock) {
            buffers.add(buffer);
        }
        return buffer;
    }

    @Override
    public List<String> getLastDebugMessages() {
        requireOpen();
        return List.of();
    }

    @Override
    public boolean isDebuggingEnabled() {
        requireOpen();
        return false;
    }

    @Override
    public CompletableFuture<CompiledRenderPipeline.Pending> compilePipeline(
            RenderPipeline pipeline,
            ShaderSource shaderSource,
            Executor executor
    ) {
        requireOpen();
        Objects.requireNonNull(pipeline, "pipeline");
        Objects.requireNonNull(shaderSource, "shaderSource");
        Objects.requireNonNull(executor, "executor");
        // Returning a fabricated handle would make later native draw failures
        // look like successful shader compilation. Keep this boundary honest
        // until GLSL-to-Godot shader/pipeline translation is implemented.
        return CompletableFuture.failedFuture(new UnsupportedOperationException(
                "Godot RenderingDevice pipeline translation is not implemented yet"
        ));
    }

    @Override
    public GpuQueryPool createTimestampQueryPool(int size) {
        requireOpen();
        throw new UnsupportedOperationException("Godot RenderPearl timestamp queries are not implemented");
    }

    @Override
    public DeviceInfo getDeviceInfo() {
        requireOpen();
        return DEVICE_INFO;
    }

    @Override
    public void close() {
        closed = true;
    }

    void configureTarget(int width, int height) {
        requireOpen();
        setTargetSize(width, height);
    }

    boolean isClosed() {
        return closed;
    }

    private GodotGpuTexture requireTexture(GpuTexture texture) {
        requireOpen();
        if (!(texture instanceof GodotGpuTexture godotTexture)) {
            throw new IllegalArgumentException("Texture was not created by this Godot GpuDevice");
        }
        return godotTexture;
    }

    private void setTargetSize(int width, int height) {
        if (width <= 0 || height <= 0) {
            throw new IllegalArgumentException("Godot render target dimensions must be positive");
        }
        targetWidth = width;
        targetHeight = height;
    }

    private void requireOpen() {
        if (closed) {
            throw new IllegalStateException("Godot GpuDevice is closed");
        }
    }
}
