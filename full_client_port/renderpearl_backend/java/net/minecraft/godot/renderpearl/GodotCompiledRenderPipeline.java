package net.minecraft.godot.renderpearl;

import com.mojang.renderpearl.api.pipeline.CompiledRenderPipeline;

import java.util.Objects;

/** Handle/lifetime representation of a pipeline accepted by the native executor. */
final class GodotCompiledRenderPipeline implements CompiledRenderPipeline {
    private final GodotRenderResourceRegistry registry;
    private final GodotRenderResourceRegistry.Handle handle;

    GodotCompiledRenderPipeline(GodotRenderResourceRegistry registry) {
        this.registry = Objects.requireNonNull(registry, "registry");
        this.handle = registry.allocate(GodotRenderResourceRegistry.Kind.PIPELINE);
    }

    int nativeHandle() {
        registry.requireOpen(handle, GodotRenderResourceRegistry.Kind.PIPELINE);
        return handle.id();
    }

    @Override
    public boolean isClosed() {
        return handle.isClosed();
    }

    @Override
    public void close() {
        registry.close(handle);
    }
}
