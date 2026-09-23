package net.minecraft.godot.renderpearl;

import com.mojang.renderpearl.api.device.GpuDebugOptions;
import com.mojang.renderpearl.api.device.GpuDevice;

/** Smoke test for the extracted-client GpuBackend seam. */
public final class GodotGpuBackendTest {
    private GodotGpuBackendTest() {
    }

    public static void main(String[] args) {
        GodotGpuBackend backend = new GodotGpuBackend(320, 180, frame -> frame.length);
        if (!"godot".equals(backend.getName())) {
            throw new AssertionError("Godot backend name was not godot");
        }
        backend.loadLibrary();
        long handle = backend.createWindow("Minecraft", 640, 360, 0L);
        if (handle != GodotGpuBackend.WINDOW_HANDLE) {
            throw new AssertionError("Godot backend opened or rejected the viewport window handle");
        }
        GpuDevice device = backend.createDevice(new GpuDebugOptions(0, false, false, false));
        if (!(device instanceof GodotGpuDevice)) {
            throw new AssertionError("Godot backend did not create a Godot GpuDevice");
        }
        if (backend.createDevice(new GpuDebugOptions(0, false, false, false)) != device) {
            throw new AssertionError("Godot backend created a second device");
        }
        backend.unloadLibrary();
        device.close();
    }
}
