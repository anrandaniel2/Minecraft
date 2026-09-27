package net.minecraft.godot.renderpearl;

import com.mojang.renderpearl.api.device.GpuBackend;
import com.mojang.renderpearl.api.device.GpuDebugOptions;
import com.mojang.renderpearl.api.device.GpuDevice;

import java.util.Objects;

/**
 * RenderPearl backend that draws into the Godot viewport.
 *
 * The extracted client selects a backend with {@code new GlBackend()} /
 * {@code new VulkanBackend()} inside {@code PreferredGraphicsApi}. A classpath
 * overlay rewrites the default slot to this class. This type has no Godot
 * imports: {@link #createWindow} returns a sentinel handle and does not open a
 * native window, and {@link #createDevice} returns {@link GodotGpuDevice}.
 */
public final class GodotGpuBackend implements GpuBackend {
    /** Non-zero handle so stock {@code Window} does not treat creation as failed. */
    public static final long WINDOW_HANDLE = 1L;

    private final RenderCommandTransport transport;
    private int width;
    private int height;
    private GodotGpuDevice device;

    /**
     * No-arg constructor used by the extracted client's backend list.
     * The native transport is loaded reflectively so this class can compile
     * without GraalVM; native-image still supplies the transport at runtime.
     */
    public GodotGpuBackend() {
        this(viewportDimension("minecraft.godot.width", 1280), viewportDimension("minecraft.godot.height", 720), null);
    }

    public GodotGpuBackend(int width, int height, RenderCommandTransport transport) {
        if (width <= 0 || height <= 0) {
            throw new IllegalArgumentException("Godot backend viewport must be positive");
        }
        this.width = width;
        this.height = height;
        this.transport = transport;
    }

    @Override
    public String getName() {
        return "godot";
    }

    @Override
    public void loadLibrary() {
        // RenderingDevice is already owned by the Godot process. Do not load
        // Vulkan or OpenGL next to it.
    }

    @Override
    public void unloadLibrary() {
    }

    @Override
    public long createWindow(String title, int width, int height, long monitor) {
        Objects.requireNonNull(title, "title");
        if (width <= 0 || height <= 0) {
            throw new IllegalArgumentException("Godot window size must be positive");
        }
        this.width = width;
        this.height = height;
        if (device != null && !device.isClosed()) {
            device.configureTarget(width, height);
        }
        return WINDOW_HANDLE;
    }

    @Override
    public GpuDevice createDevice(GpuDebugOptions options) {
        Objects.requireNonNull(options, "options");
        if (device != null && !device.isClosed()) {
            return device;
        }
        device = new GodotGpuDevice(width, height, transport == null ? nativeTransport() : transport);
        return device;
    }

    private static RenderCommandTransport nativeTransport() {
        try {
            Class<?> type = Class.forName("net.minecraft.godot.renderpearl.GodotNativeRenderCommandTransport");
            return (RenderCommandTransport) type.getDeclaredConstructor().newInstance();
        } catch (ReflectiveOperationException failure) {
            throw new IllegalStateException("Godot native render transport is unavailable", failure);
        }
    }

    private static int viewportDimension(String property, int fallback) {
        String value = System.getProperty(property);
        if (value == null || value.isBlank()) {
            return fallback;
        }
        try {
            int parsed = Integer.parseInt(value);
            return parsed > 0 ? parsed : fallback;
        } catch (NumberFormatException ignored) {
            return fallback;
        }
    }
}
