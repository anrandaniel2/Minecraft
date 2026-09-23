package minecraft.nativeimage;

import net.minecraft.godot.ExtractedClientInput;
import net.minecraft.godot.ExtractedClientLauncher;
import net.minecraft.godot.renderpearl.GodotNativeRenderCommandTransport;
import org.graalvm.nativeimage.IsolateThread;
import org.graalvm.nativeimage.c.function.CEntryPoint;

/**
 * C ABI exported by the GraalVM native image of the extracted 26.3 client.
 *
 * These entry points do not replace net.minecraft.client.Minecraft and do not import Godot.
 * The Godot adapter is {@code src/godot_bridge.c}.
 */
public final class MinecraftNativeEntrypoints {
    private MinecraftNativeEntrypoints() {
    }

    @CEntryPoint(name = "minecraft_bootstrap")
    public static void bootstrap(IsolateThread thread) {
        // Read the marker so native-image cannot delete the ASCII bytes.
        if (ExtractedClientLauncher.imageMarkerByte(0) == 0) {
            return;
        }
        ExtractedClientLauncher.start();
    }

    @CEntryPoint(name = "minecraft_client_running")
    public static int clientRunning(IsolateThread thread) {
        if (ExtractedClientLauncher.failure() != null && ExtractedClientLauncher.client() == null) {
            return -1;
        }
        return ExtractedClientLauncher.isRunning() ? 1 : 0;
    }

    @CEntryPoint(name = "minecraft_client_stop")
    public static void clientStop(IsolateThread thread) {
        ExtractedClientLauncher.stop();
    }

    @CEntryPoint(name = "minecraft_touch_down")
    public static void touchDown(IsolateThread thread, int pointerId, int x, int y, int width, int height) {
        ExtractedClientInput.touchDown(pointerId, x, y, width, height);
    }

    @CEntryPoint(name = "minecraft_touch_move")
    public static void touchMove(IsolateThread thread, int pointerId, int x, int y, int width, int height) {
        ExtractedClientInput.touchMove(pointerId, x, y, width, height);
    }

    @CEntryPoint(name = "minecraft_touch_up")
    public static void touchUp(IsolateThread thread, int pointerId) {
        ExtractedClientInput.touchUp(pointerId);
    }

    @CEntryPoint(name = "minecraft_touch_reset")
    public static void touchReset(IsolateThread thread) {
        ExtractedClientInput.reset();
    }

    @CEntryPoint(name = "minecraft_set_virtual_joystick_mask")
    public static void setVirtualJoystickMask(IsolateThread thread, int actionMask) {
        ExtractedClientInput.setVirtualJoystickMask(actionMask);
    }

    @CEntryPoint(name = "minecraft_add_camera_drag")
    public static void addCameraDrag(IsolateThread thread, int deltaX, int deltaY) {
        ExtractedClientInput.addCameraDrag(deltaX, deltaY);
    }

    /**
     * Native-image smoke entry for the RenderPearl command transport. It emits
     * a tiny valid frame through the Java to C mailbox without importing Godot.
     */
    @CEntryPoint(name = "minecraft_render_submit_protocol_smoke_frame")
    public static int submitRenderProtocolSmokeFrame(IsolateThread thread) {
        return GodotNativeRenderCommandTransport.submitSmokeFrame();
    }

    @CEntryPoint(name = "minecraft_touch_mask")
    public static int touchMask(IsolateThread thread) {
        return ExtractedClientInput.touchMask();
    }

    @CEntryPoint(name = "minecraft_active_touch_count")
    public static int activeTouchCount(IsolateThread thread) {
        return ExtractedClientInput.activeTouchCount();
    }
}
