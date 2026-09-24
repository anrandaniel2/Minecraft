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
import com.mojang.renderpearl.api.pipeline.BlendFunction;
import com.mojang.renderpearl.api.pipeline.ColorTargetState;
import com.mojang.renderpearl.api.pipeline.CompiledRenderPipeline;
import com.mojang.renderpearl.api.pipeline.RenderPipeline;
import com.mojang.renderpearl.api.pipeline.ShaderSource;
import com.mojang.renderpearl.api.pipeline.ShaderType;
import com.mojang.renderpearl.api.vertex.VertexFormat;
import com.mojang.renderpearl.api.vertex.VertexFormatElement;
import net.minecraft.resources.Identifier;
import com.mojang.renderpearl.api.textures.AddressMode;
import com.mojang.renderpearl.api.textures.FilterMode;
import com.mojang.renderpearl.api.textures.GpuSampler;
import com.mojang.renderpearl.api.textures.GpuTexture;
import com.mojang.renderpearl.api.textures.GpuTextureView;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
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
    private RenderCommandWriter openFrame;
    private final List<GodotGpuBuffer> buffers = new ArrayList<>();
    private final List<GodotGpuTexture> textures = new ArrayList<>();
    private final List<GodotCompiledRenderPipeline> pipelines = new ArrayList<>();
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
    public GpuSurface createSurface(long windowHandle, BooleanSupplier isIconified) {
        requireOpen();
        Objects.requireNonNull(isIconified, "isIconified");
        return new GodotGpuSurface(this, windowHandle, isIconified);
    }

    @Override
    public CommandEncoder createCommandEncoder() {
        requireOpen();
        if (openFrame == null) {
            openFrame = new RenderCommandWriter();
            openFrame.beginFrame(nextFrameId.getAndIncrement(), targetWidth, targetHeight);
        }
        // GuiRenderer.upload() and GuiRenderer.draw() each create an encoder and
        // never submit it. Keep one frame open until Minecraft.renderFrame submits.
        recordLiveResources(openFrame);
        return new GodotCommandEncoder(openFrame, targetWidth, targetHeight, transport, this::submitOpenFrame);
    }

    private void submitOpenFrame() {
        RenderCommandWriter frame = openFrame;
        if (frame == null) {
            return;
        }
        openFrame = null;
        byte[] bytes = frame.finishFrame();
        int result = transport.submit(bytes);
        if (result <= 0) {
            throw new IllegalStateException("Native RenderPearl frame submission failed: " + result);
        }
    }

    private void recordLiveResources(RenderCommandWriter writer) {
        List<GodotGpuBuffer> frameBuffers;
        List<GodotGpuTexture> frameTextures;
        List<GodotCompiledRenderPipeline> framePipelines;
        synchronized (resourcesLock) {
            buffers.removeIf(GodotGpuBuffer::isClosed);
            textures.removeIf(GodotGpuTexture::isClosed);
            pipelines.removeIf(GodotCompiledRenderPipeline::isClosed);
            frameBuffers = List.copyOf(buffers);
            frameTextures = List.copyOf(textures);
            framePipelines = List.copyOf(pipelines);
        }
        for (GodotGpuBuffer buffer : frameBuffers) {
            buffer.recordCreate(writer);
        }
        for (GodotGpuTexture texture : frameTextures) {
            texture.recordCreate(writer);
        }
        for (GodotCompiledRenderPipeline pipeline : framePipelines) {
            pipeline.recordCreate(writer);
        }
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
        CompiledPipelineDescription description;
        try {
            description = describePipeline(pipeline, shaderSource);
        } catch (RuntimeException ignored) {
            // A failed future aborts Minecraft resource reload before GuiRenderer
            // can draw. Unknown or not-yet-translated pipelines stay family 0 and
            // are skipped by the viewport executor instead of failing startup.
            description = new CompiledPipelineDescription(
                    GodotCompiledRenderPipeline.FAMILY_UNKNOWN,
                    0,
                    GodotCompiledRenderPipeline.BLEND_OPAQUE,
                    0,
                    new GodotCompiledRenderPipeline.Attribute[0],
                    utf8(pipeline.getLocation()),
                    new byte[0],
                    new byte[0]
            );
        }
        return CompletableFuture.completedFuture(new PipelinePending(description));
    }

    @Override
    public GpuQueryPool createTimestampQueryPool(int size) {
        requireOpen();
        return new GodotGpuQueryPool(size);
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

    @SuppressWarnings("unchecked")
    private CompiledPipelineDescription describePipeline(RenderPipeline pipeline, ShaderSource shaderSource) {
        Identifier vertexShader = shaderIdentifier(pipeline, ShaderType.VERTEX);
        Identifier fragmentShader = shaderIdentifier(pipeline, ShaderType.FRAGMENT);
        int family = pipelineFamily(pipeline.getLocation(), vertexShader, fragmentShader);
        validateShaderSource(shaderSource, vertexShader, ShaderType.VERTEX);
        validateShaderSource(shaderSource, fragmentShader, ShaderType.FRAGMENT);
        VertexFormat format = pipeline.getVertexFormatBindings().isEmpty()
                ? null
                : pipeline.getVertexFormatBinding(0);
        GodotCompiledRenderPipeline.Attribute[] attributes = vertexAttributes(format, family);
        return new CompiledPipelineDescription(
                family,
                pipeline.getPrimitiveTopology().ordinal(),
                blendCode(pipeline),
                format == null ? 0 : format.getVertexSize(),
                attributes,
                utf8(pipeline.getLocation()),
                utf8(vertexShader),
                utf8(fragmentShader)
        );
    }

    @SuppressWarnings("unchecked")
    private static Identifier shaderIdentifier(RenderPipeline pipeline, ShaderType type) {
        for (Map.Entry<?, ?> entry : pipeline.getShaders().entrySet()) {
            if (entry.getKey() == type && entry.getValue() instanceof Identifier identifier) {
                return identifier;
            }
        }
        return null;
    }

    private static void validateShaderSource(
            ShaderSource shaderSource,
            Identifier identifier,
            ShaderType type
    ) {
        if (identifier == null) {
            return;
        }
        try {
            // Touch the source so a present shader is resolved, but never fail
            // compilation. Unknown world pipelines are family 0 and skipped
            // when drawing; a failed future would abort client startup.
            shaderSource.getShader(identifier, type);
        } catch (RuntimeException ignored) {
            // Missing includes or not-yet-translated shaders stay descriptive.
        }
    }

    private static int pipelineFamily(Identifier location, Identifier vertexShader, Identifier fragmentShader) {
        String key = (text(location) + " " + text(vertexShader) + " " + text(fragmentShader))
                .toLowerCase(Locale.ROOT);
        boolean gui = key.contains("gui");
        // "gui_textured" also contains the substring "gui_text", so textured
        // pipelines have to be classified before text pipelines.
        if (gui && (key.contains("textured") || key.contains("position_tex") || key.contains("panorama"))) {
            return GodotCompiledRenderPipeline.FAMILY_GUI_TEXTURED;
        }
        if (key.contains("gui_text") || key.contains("text_grayscale")
                || (gui && key.contains("/text")) || key.contains("core/text")) {
            return GodotCompiledRenderPipeline.FAMILY_GUI_TEXT;
        }
        if (key.contains("core/gui") || key.contains("pipeline/gui") || key.contains(":gui")) {
            return GodotCompiledRenderPipeline.FAMILY_GUI_COLOR;
        }
        return GodotCompiledRenderPipeline.FAMILY_UNKNOWN;
    }

    @SuppressWarnings("unchecked")
    private static int blendCode(RenderPipeline pipeline) {
        List<?> states = pipeline.getColorTargetStates();
        if (states.isEmpty() || !(states.getFirst() instanceof ColorTargetState state)) {
            return GodotCompiledRenderPipeline.BLEND_OPAQUE;
        }
        Optional<BlendFunction> blend = state.blendFunction();
        if (blend.isEmpty()) {
            return GodotCompiledRenderPipeline.BLEND_OPAQUE;
        }
        BlendFunction function = blend.get();
        if (function == BlendFunction.TRANSLUCENT) {
            return GodotCompiledRenderPipeline.BLEND_ALPHA;
        }
        if (function == BlendFunction.TRANSLUCENT_PREMULTIPLIED_ALPHA) {
            return GodotCompiledRenderPipeline.BLEND_PREMULTIPLIED;
        }
        if (function == BlendFunction.ADDITIVE) {
            return GodotCompiledRenderPipeline.BLEND_ADDITIVE;
        }
        if (function == BlendFunction.INVERT) {
            return GodotCompiledRenderPipeline.BLEND_INVERT;
        }
        return GodotCompiledRenderPipeline.BLEND_ALPHA;
    }

    @SuppressWarnings("unchecked")
    private static GodotCompiledRenderPipeline.Attribute[] vertexAttributes(VertexFormat format, int family) {
        if (format == null) {
            return new GodotCompiledRenderPipeline.Attribute[0];
        }
        List<VertexFormatElement> elements = format.getElements();
        GodotCompiledRenderPipeline.Attribute[] attributes =
                new GodotCompiledRenderPipeline.Attribute[elements.size()];
        for (int index = 0; index < elements.size(); index++) {
            VertexFormatElement element = elements.get(index);
            attributes[index] = new GodotCompiledRenderPipeline.Attribute(
                    shaderLocation(element.name(), family),
                    element.offset(),
                    element.format().ordinal()
            );
        }
        return attributes;
    }

    private static int shaderLocation(String elementName, int family) {
        if ("Position".equals(elementName)) {
            return 0;
        }
        if ("Color".equals(elementName)) {
            return family == GodotCompiledRenderPipeline.FAMILY_GUI_TEXTURED ? 2 : 1;
        }
        if ("UV0".equals(elementName)) {
            return family == GodotCompiledRenderPipeline.FAMILY_GUI_TEXTURED ? 1 : 2;
        }
        return 255;
    }

    private static String text(Identifier identifier) {
        return identifier == null ? "" : identifier.toString();
    }

    private static byte[] utf8(Identifier identifier) {
        return text(identifier).getBytes(StandardCharsets.UTF_8);
    }

    private record CompiledPipelineDescription(
            int family,
            int topology,
            int blend,
            int vertexStride,
            GodotCompiledRenderPipeline.Attribute[] attributes,
            byte[] location,
            byte[] vertexShader,
            byte[] fragmentShader
    ) {
    }

    private final class PipelinePending implements CompiledRenderPipeline.Pending {
        private final CompiledPipelineDescription description;
        private GodotCompiledRenderPipeline compiled;

        private PipelinePending(CompiledPipelineDescription description) {
            this.description = description;
        }

        @Override
        public synchronized CompiledRenderPipeline finishCompile() {
            requireOpen();
            if (compiled == null || compiled.isClosed()) {
                compiled = new GodotCompiledRenderPipeline(
                        registry,
                        description.family(),
                        description.topology(),
                        description.blend(),
                        description.vertexStride(),
                        description.attributes(),
                        description.location(),
                        description.vertexShader(),
                        description.fragmentShader()
                );
                synchronized (resourcesLock) {
                    pipelines.add(compiled);
                }
            }
            return compiled;
        }
    }
}
