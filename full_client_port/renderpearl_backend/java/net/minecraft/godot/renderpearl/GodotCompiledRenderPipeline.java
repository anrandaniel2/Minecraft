package net.minecraft.godot.renderpearl;

import com.mojang.renderpearl.api.pipeline.CompiledRenderPipeline;

import java.util.Arrays;
import java.util.Objects;

/**
 * Handle/lifetime representation of a pipeline accepted by the native executor.
 *
 * The descriptor is replayed at the start of every frame, alongside live
 * buffers and textures, because the native sink only retains resources that
 * the current command stream declares.
 */
final class GodotCompiledRenderPipeline implements CompiledRenderPipeline {
    static final int FAMILY_UNKNOWN = 0;
    static final int FAMILY_GUI_COLOR = 1;
    static final int FAMILY_GUI_TEXTURED = 2;
    static final int FAMILY_GUI_TEXT = 3;

    static final int BLEND_ALPHA = 0;
    static final int BLEND_PREMULTIPLIED = 1;
    static final int BLEND_OPAQUE = 2;
    static final int BLEND_ADDITIVE = 3;
    static final int BLEND_INVERT = 4;

    record Attribute(int location, int offset, int format) {
    }

    private final GodotRenderResourceRegistry registry;
    private final GodotRenderResourceRegistry.Handle handle;
    private final int family;
    private final int topology;
    private final int blend;
    private final int vertexStride;
    private final Attribute[] attributes;
    private final byte[] location;
    private final byte[] vertexShader;
    private final byte[] fragmentShader;

    /** Handle-only pipeline used by command-stream tests that do not compile shaders. */
    GodotCompiledRenderPipeline(GodotRenderResourceRegistry registry) {
        this(registry, FAMILY_UNKNOWN, 0, BLEND_OPAQUE, 0, new Attribute[0], new byte[0], new byte[0], new byte[0]);
    }

    GodotCompiledRenderPipeline(
            GodotRenderResourceRegistry registry,
            int family,
            int topology,
            int blend,
            int vertexStride,
            Attribute[] attributes,
            byte[] location,
            byte[] vertexShader,
            byte[] fragmentShader
    ) {
        this.registry = Objects.requireNonNull(registry, "registry");
        if (family < FAMILY_UNKNOWN || family > FAMILY_GUI_TEXT) {
            throw new IllegalArgumentException("Unknown pipeline family " + family);
        }
        if (vertexStride < 0) {
            throw new IllegalArgumentException("Vertex stride must not be negative");
        }
        this.family = family;
        this.topology = topology;
        this.blend = blend;
        this.vertexStride = vertexStride;
        this.attributes = Arrays.copyOf(Objects.requireNonNull(attributes, "attributes"), attributes.length);
        this.location = copy(location);
        this.vertexShader = copy(vertexShader);
        this.fragmentShader = copy(fragmentShader);
        this.handle = registry.allocate(GodotRenderResourceRegistry.Kind.PIPELINE);
    }

    int nativeHandle() {
        registry.requireOpen(handle, GodotRenderResourceRegistry.Kind.PIPELINE);
        return handle.id();
    }

    /** Emits the pipeline declaration outside a render pass. */
    void recordCreate(RenderCommandWriter writer) {
        Objects.requireNonNull(writer, "writer");
        int[] locations = new int[attributes.length];
        int[] offsets = new int[attributes.length];
        int[] formats = new int[attributes.length];
        for (int index = 0; index < attributes.length; index++) {
            locations[index] = attributes[index].location();
            offsets[index] = attributes[index].offset();
            formats[index] = attributes[index].format();
        }
        writer.compilePipeline(
                nativeHandle(),
                family,
                topology,
                blend,
                vertexStride,
                locations,
                offsets,
                formats,
                location,
                vertexShader,
                fragmentShader
        );
    }

    @Override
    public boolean isClosed() {
        return handle.isClosed();
    }

    @Override
    public void close() {
        registry.close(handle);
    }

    private static byte[] copy(byte[] value) {
        return value == null ? new byte[0] : Arrays.copyOf(value, value.length);
    }
}
