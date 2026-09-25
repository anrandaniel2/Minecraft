package net.minecraft.godot.renderpearl;

import com.mojang.renderpearl.api.textures.GpuTexture;
import com.mojang.renderpearl.api.textures.GpuTextureView;

import java.util.Objects;

/** A bounded view over a GodotGpuTexture's mip chain. */
final class GodotGpuTextureView implements GpuTextureView {
    private final GodotRenderResourceRegistry registry;
    private final GodotRenderResourceRegistry.Handle handle;
    private final GodotGpuTexture texture;
    private final int baseMipLevel;
    private final int mipLevels;

    GodotGpuTextureView(
            GodotRenderResourceRegistry registry,
            GodotGpuTexture texture,
            int baseMipLevel,
            int mipLevels
    ) {
        this.registry = Objects.requireNonNull(registry, "registry");
        this.texture = Objects.requireNonNull(texture, "texture");
        if (baseMipLevel < 0 || mipLevels <= 0 || baseMipLevel + mipLevels > texture.getMipLevels()) {
            throw new IllegalArgumentException("Texture view mip range is outside the source texture");
        }
        this.baseMipLevel = baseMipLevel;
        this.mipLevels = mipLevels;
        this.handle = registry.allocate(GodotRenderResourceRegistry.Kind.TEXTURE_VIEW);
    }

    int nativeHandle() {
        if (texture.isClosed()) {
            throw new IllegalStateException("Texture view source texture is closed");
        }
        return handle.rawId();
    }

    @Override
    public boolean isClosed() {
        return handle.isClosed();
    }

    @Override
    public GpuTexture texture() {
        // TextureAtlas.uploadInitialContents closes the temporary sprite view and then
        // calls texture() to close that view's source. The view handle is bookkeeping;
        // the source texture stays reachable until it is closed itself.
        return texture;
    }

    @Override
    public int baseMipLevel() {
        return baseMipLevel;
    }

    @Override
    public int mipLevels() {
        return mipLevels;
    }

    @Override
    public int getWidth(int mipLevel) {
        return texture.getWidth(resolveMipLevel(mipLevel));
    }

    @Override
    public int getHeight(int mipLevel) {
        return texture.getHeight(resolveMipLevel(mipLevel));
    }

    @Override
    public void close() {
        registry.close(handle);
    }

    private int resolveMipLevel(int viewMipLevel) {
        if (texture.isClosed()) {
            throw new IllegalStateException("Texture view source texture is closed");
        }
        if (viewMipLevel < 0 || viewMipLevel >= mipLevels) {
            throw new IllegalArgumentException("Invalid view mip level " + viewMipLevel);
        }
        return baseMipLevel + viewMipLevel;
    }
}
