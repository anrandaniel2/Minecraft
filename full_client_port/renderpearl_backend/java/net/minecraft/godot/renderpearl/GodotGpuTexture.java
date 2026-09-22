package net.minecraft.godot.renderpearl;

import com.mojang.renderpearl.api.GpuFormat;
import com.mojang.renderpearl.api.textures.GpuTexture;

import java.util.Objects;

/** CPU-side metadata/lifetime half of a Godot-backed RenderPearl texture. */
final class GodotGpuTexture implements GpuTexture {
    private final GodotRenderResourceRegistry registry;
    private final GodotRenderResourceRegistry.Handle handle;
    private final String label;
    private final int usage;
    private final GpuFormat format;
    private final int width;
    private final int height;
    private final int depthOrLayers;
    private final int mipLevels;

    GodotGpuTexture(
            GodotRenderResourceRegistry registry,
            String label,
            int usage,
            GpuFormat format,
            int width,
            int height,
            int depthOrLayers,
            int mipLevels
    ) {
        this.registry = Objects.requireNonNull(registry, "registry");
        this.label = Objects.requireNonNull(label, "label");
        this.format = Objects.requireNonNull(format, "format");
        if (width <= 0 || height <= 0 || depthOrLayers <= 0 || mipLevels <= 0) {
            throw new IllegalArgumentException("Texture dimensions and mip levels must be positive");
        }
        this.usage = usage;
        this.width = width;
        this.height = height;
        this.depthOrLayers = depthOrLayers;
        this.mipLevels = mipLevels;
        this.handle = registry.allocate(GodotRenderResourceRegistry.Kind.TEXTURE);
    }

    int nativeHandle() {
        return handle.id();
    }

    @Override
    public int getWidth(int mipLevel) {
        return mipDimension(width, mipLevel);
    }

    @Override
    public int getHeight(int mipLevel) {
        return mipDimension(height, mipLevel);
    }

    @Override
    public int getDepthOrLayers() {
        requireOpen();
        return depthOrLayers;
    }

    @Override
    public int getMipLevels() {
        requireOpen();
        return mipLevels;
    }

    @Override
    public GpuFormat getFormat() {
        requireOpen();
        return format;
    }

    @Override
    public int usage() {
        requireOpen();
        return usage;
    }

    @Override
    public String getLabel() {
        requireOpen();
        return label;
    }

    @Override
    public boolean isClosed() {
        return handle.isClosed();
    }

    @Override
    public void close() {
        registry.close(handle);
    }

    private int mipDimension(int dimension, int mipLevel) {
        requireOpen();
        if (mipLevel < 0 || mipLevel >= mipLevels) {
            throw new IllegalArgumentException("Invalid mip level " + mipLevel + " for " + mipLevels + " levels");
        }
        return Math.max(1, dimension >> mipLevel);
    }

    private void requireOpen() {
        registry.requireOpen(handle, GodotRenderResourceRegistry.Kind.TEXTURE);
    }
}
