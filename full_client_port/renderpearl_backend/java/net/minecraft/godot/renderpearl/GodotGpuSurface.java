package net.minecraft.godot.renderpearl;

import com.mojang.renderpearl.api.commands.CommandEncoder;
import com.mojang.renderpearl.api.device.GpuSurface;
import com.mojang.renderpearl.api.textures.GpuTextureView;

import java.util.Collection;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.function.BooleanSupplier;

/**
 * Surface lifecycle adapter for a Godot-owned viewport target.
 *
 * Godot owns presentation, so this class never exposes or dereferences the
 * RenderPearl window handle. It carries the configured viewport dimensions to
 * {@link GodotGpuDevice}, and tracks acquire/present ordering. The frame-loop
 * blit is accepted rather than copied into an SDL swapchain: GuiRenderer
 * already drew into the Godot color target that the viewport presents.
 */
final class GodotGpuSurface implements GpuSurface {
    private final GodotGpuDevice device;
    private final long windowHandle;
    private final BooleanSupplier isWindowAlive;
    private Optional<Configuration> configuration = Optional.empty();
    private boolean acquired;
    private boolean closed;
    private int presentedTextureId;

    GodotGpuSurface(GodotGpuDevice device, long windowHandle, BooleanSupplier isWindowAlive) {
        this.device = Objects.requireNonNull(device, "device");
        this.windowHandle = windowHandle;
        this.isWindowAlive = Objects.requireNonNull(isWindowAlive, "isWindowAlive");
    }

    @Override
    public void configure(Configuration configuration) {
        requireOpen();
        Configuration checked = Objects.requireNonNull(configuration, "configuration");
        if (checked.width() <= 0 || checked.height() <= 0) {
            throw new IllegalArgumentException("Godot surface dimensions must be positive");
        }
        if (!supportedPresentModes().contains(checked.presentMode())) {
            throw new UnsupportedOperationException("Godot surface does not support " + checked.presentMode());
        }
        acquired = false;
        this.configuration = Optional.of(checked);
        device.configureTarget(checked.width(), checked.height());
    }

    @Override
    public Optional<Configuration> currentConfiguration() {
        requireOpen();
        return configuration;
    }

    @Override
    public Collection<PresentMode> supportedPresentModes() {
        requireOpen();
        // Godot presents on its own frame cadence. FIFO is the portable
        // RenderPearl representation of this behavior on desktop and Android.
        return List.of(PresentMode.FIFO);
    }

    @Override
    public boolean isSuboptimal() {
        requireOpen();
        return false;
    }

    @Override
    public boolean isAcquired() {
        requireOpen();
        return acquired;
    }

    @Override
    public void acquireNextTexture() {
        requireOpen();
        if (configuration.isEmpty()) {
            throw new IllegalStateException("Godot surface must be configured before acquireNextTexture");
        }
        if (!isWindowAlive.getAsBoolean()) {
            throw new IllegalStateException("Godot viewport is no longer available");
        }
        if (acquired) {
            throw new IllegalStateException("Godot surface texture is already acquired");
        }
        acquired = true;
    }

    @Override
    public void blitFromTexture(CommandEncoder encoder, GpuTextureView textureView) {
        requireOpen();
        requireAcquired();
        Objects.requireNonNull(encoder, "encoder");
        if (!(textureView instanceof GodotGpuTextureView view)) {
            throw new IllegalArgumentException("Blit source was not created by the Godot GpuDevice");
        }
        // Minecraft's frame loop blits the main render target onto the window
        // surface after GuiRenderer/GameRenderer have submitted their passes.
        // Those passes already target a Godot color texture, so accepting the
        // blit keeps renderFrame alive without inventing a second window.
        presentedTextureId = view.nativeHandle();
        if (windowHandle == 0L && presentedTextureId <= 0) {
            throw new IllegalStateException("Godot surface has no viewport identity or blit source");
        }
    }

    int presentedTextureId() {
        return presentedTextureId;
    }

    @Override
    public void present() {
        requireOpen();
        requireAcquired();
        // The eventual native executor presents through Godot's frame loop;
        // this method only completes RenderPearl surface ownership today.
        acquired = false;
    }

    @Override
    public void close() {
        acquired = false;
        configuration = Optional.empty();
        closed = true;
    }

    private void requireOpen() {
        if (closed || device.isClosed()) {
            throw new IllegalStateException("Godot surface is closed");
        }
    }

    private void requireAcquired() {
        if (!acquired) {
            throw new IllegalStateException("Godot surface texture has not been acquired");
        }
    }
}
