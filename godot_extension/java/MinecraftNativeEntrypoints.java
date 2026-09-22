package net.minecraft.client;

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

    @CEntryPoint(name = "minecraft_touch_mask")
    public static int touchMask(IsolateThread thread) {
        return Minecraft.getTouchMask();
    }

    @CEntryPoint(name = "minecraft_active_touch_count")
    public static int activeTouchCount(IsolateThread thread) {
        return Minecraft.getActiveTouchCount();
    }
}
