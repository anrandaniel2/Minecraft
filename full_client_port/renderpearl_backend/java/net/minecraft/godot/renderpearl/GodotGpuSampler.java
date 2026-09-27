package net.minecraft.godot.renderpearl;

import com.mojang.renderpearl.api.textures.AddressMode;
import com.mojang.renderpearl.api.textures.FilterMode;
import com.mojang.renderpearl.api.textures.GpuSampler;

import java.util.Objects;
import java.util.OptionalDouble;

/** CPU-side metadata/lifetime half of a Godot-backed RenderPearl sampler. */
final class GodotGpuSampler implements GpuSampler {
    private final GodotRenderResourceRegistry registry;
    private final GodotRenderResourceRegistry.Handle handle;
    private final AddressMode addressModeU;
    private final AddressMode addressModeV;
    private final FilterMode minFilter;
    private final FilterMode magFilter;
    private final int maxAnisotropy;
    private final OptionalDouble maxLod;

    GodotGpuSampler(
            GodotRenderResourceRegistry registry,
            AddressMode addressModeU,
            AddressMode addressModeV,
            FilterMode minFilter,
            FilterMode magFilter,
            int maxAnisotropy,
            OptionalDouble maxLod
    ) {
        this.registry = Objects.requireNonNull(registry, "registry");
        this.addressModeU = Objects.requireNonNull(addressModeU, "addressModeU");
        this.addressModeV = Objects.requireNonNull(addressModeV, "addressModeV");
        this.minFilter = Objects.requireNonNull(minFilter, "minFilter");
        this.magFilter = Objects.requireNonNull(magFilter, "magFilter");
        if (maxAnisotropy < 1) {
            throw new IllegalArgumentException("maxAnisotropy must be at least one");
        }
        this.maxAnisotropy = maxAnisotropy;
        this.maxLod = Objects.requireNonNull(maxLod, "maxLod");
        this.handle = registry.allocate(GodotRenderResourceRegistry.Kind.SAMPLER);
    }

    int nativeHandle() {
        requireOpen();
        return handle.id();
    }

    @Override
    public AddressMode getAddressModeU() {
        requireOpen();
        return addressModeU;
    }

    @Override
    public AddressMode getAddressModeV() {
        requireOpen();
        return addressModeV;
    }

    @Override
    public FilterMode getMinFilter() {
        requireOpen();
        return minFilter;
    }

    @Override
    public FilterMode getMagFilter() {
        requireOpen();
        return magFilter;
    }

    @Override
    public int getMaxAnisotropy() {
        requireOpen();
        return maxAnisotropy;
    }

    @Override
    public OptionalDouble getMaxLod() {
        requireOpen();
        return maxLod;
    }

    @Override
    public boolean isClosed() {
        return handle.isClosed();
    }

    @Override
    public void close() {
        registry.close(handle);
    }

    private void requireOpen() {
        registry.requireOpen(handle, GodotRenderResourceRegistry.Kind.SAMPLER);
    }
}
