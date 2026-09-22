package net.minecraft.client;

import net.minecraft.godot.renderpearl.GodotNativeRenderCommandTransport;
import org.graalvm.nativeimage.IsolateThread;
import org.graalvm.nativeimage.c.function.CEntryPoint;

/**
 * C ABI exported by GraalVM Native Image.  This file deliberately contains no
 * Godot imports; Godot is adapted in src/godot_bridge.c.
 */
public final class MinecraftNativeEntrypoints {
    private MinecraftNativeEntrypoints() {
    }

    @CEntryPoint(name = "minecraft_bootstrap")
    public static void bootstrap(IsolateThread thread) {
        Minecraft.initialize();
    }

    @CEntryPoint(name = "minecraft_touch_down")
    public static void touchDown(IsolateThread thread, int pointerId, int x, int y, int width, int height) {
        Minecraft.touchDown(pointerId, x, y, width, height);
    }

    @CEntryPoint(name = "minecraft_touch_move")
    public static void touchMove(IsolateThread thread, int pointerId, int x, int y, int width, int height) {
        Minecraft.touchMove(pointerId, x, y, width, height);
    }

    @CEntryPoint(name = "minecraft_touch_up")
    public static void touchUp(IsolateThread thread, int pointerId) {
        Minecraft.touchUp(pointerId);
    }

    @CEntryPoint(name = "minecraft_touch_reset")
    public static void touchReset(IsolateThread thread) {
        Minecraft.resetTouchControls();
    }

    @CEntryPoint(name = "minecraft_set_virtual_joystick_mask")
    public static void setVirtualJoystickMask(IsolateThread thread, int actionMask) {
        Minecraft.setVirtualJoystickMask(actionMask);
    }

    @CEntryPoint(name = "minecraft_add_camera_drag")
    public static void addCameraDrag(IsolateThread thread, int deltaX, int deltaY) {
        Minecraft.addCameraDrag(deltaX, deltaY);
    }

    /**
     * Native-image smoke entry for the RenderPearl command transport. It emits
     * a tiny valid frame through the Java -> C mailbox without importing Godot.
     */
    @CEntryPoint(name = "minecraft_render_submit_protocol_smoke_frame")
    public static int submitRenderProtocolSmokeFrame(IsolateThread thread) {
        return GodotNativeRenderCommandTransport.submitSmokeFrame();
    }

    @CEntryPoint(name = "minecraft_touch_mask")
    public static int touchMask(IsolateThread thread) {
        return Minecraft.getTouchMask();
    }

    @CEntryPoint(name = "minecraft_active_touch_count")
    public static int activeTouchCount(IsolateThread thread) {
        return Minecraft.getActiveTouchCount();
    }
}
