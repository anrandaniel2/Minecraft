// Decompiled sample integration surface for minecraft-client.jar 26.3.
//
// The complete Minecraft client is not included in this sample source tree.  This
// class deliberately stays engine-agnostic: it keeps the touch state only.  The
// GDExtension bridge adapts Godot input events to these methods.
package net.minecraft.client;

import java.util.Arrays;

/**
 * Minimal, compilable integration surface based on the decompiled Minecraft class.
 *
 * <p>Touch input is represented in normalized viewport coordinates so the game
 * logic is independent of Godot, screen density, and a particular touch UI. The
 * native bridge is the only Godot-specific layer.</p>
 */
public final class Minecraft implements Runnable {
    public static final String VERSION = "26.3";
    public static final String VERSION_TYPE = "release";

    /** Direction/action bits returned by {@link #getTouchMask()}. */
    public static final int TOUCH_FORWARD = 1;
    public static final int TOUCH_BACKWARD = 1 << 1;
    public static final int TOUCH_LEFT = 1 << 2;
    public static final int TOUCH_RIGHT = 1 << 3;
    public static final int TOUCH_JUMP = 1 << 4;
    public static final int TOUCH_SNEAK = 1 << 5;
    public static final int TOUCH_ACTIVE = 1 << 6;

    private static final int MAX_TOUCHES = 10;
    private static final float MOVE_PAD_X = 0.20f;
    private static final float MOVE_PAD_Y = 0.76f;
    private static final float MOVE_DEAD_ZONE = 0.055f;

    private static final TouchPoint[] TOUCHES = new TouchPoint[MAX_TOUCHES];
    private static int touchMask;
    private static boolean initialized;

    static {
        for (int i = 0; i < TOUCHES.length; i++) {
            TOUCHES[i] = new TouchPoint();
        }
    }

    private Minecraft() {
        // The full 26.3 constructor depends on the rest of the client source.
    }

    /** Starts the engine-independent game/input layer. Safe to call more than once. */
    public static synchronized void initialize() {
        if (initialized) {
            return;
        }
        initialized = true;
        resetTouchControls();
    }

    /**
     * Starts tracking a touch. Coordinates are pixels in a viewport of
     * {@code viewportWidth} by {@code viewportHeight}.
     */
    public static synchronized void touchDown(int pointerId, int x, int y, int viewportWidth, int viewportHeight) {
        updateTouch(pointerId, x, y, viewportWidth, viewportHeight, true);
    }

    /** Updates a touch that is already active. */
    public static synchronized void touchMove(int pointerId, int x, int y, int viewportWidth, int viewportHeight) {
        updateTouch(pointerId, x, y, viewportWidth, viewportHeight, true);
    }

    /** Stops tracking a touch pointer. */
    public static synchronized void touchUp(int pointerId) {
        TouchPoint point = getTouch(pointerId);
        if (point != null) {
            point.active = false;
            recomputeTouchMask();
        }
    }

    /** Clears all active touch state, for focus loss, pause, or a cancelled gesture. */
    public static synchronized void resetTouchControls() {
        for (TouchPoint point : TOUCHES) {
            point.active = false;
            point.pointerId = -1;
        }
        touchMask = 0;
    }

    /** Returns a stable bit mask of the current movement/action state. */
    public static synchronized int getTouchMask() {
        return touchMask;
    }

    /** Returns the number of contacts currently known to the touch controller. */
    public static synchronized int getActiveTouchCount() {
        int count = 0;
        for (TouchPoint point : TOUCHES) {
            if (point.active) {
                count++;
            }
        }
        return count;
    }

    /** Convenience query for game code which consumes individual actions. */
    public static synchronized boolean isTouchActionPressed(int action) {
        return (touchMask & action) != 0;
    }

    @Override
    public void run() {
        // The actual Minecraft loop belongs to the complete client source tree.
        // Godot drives its own frame loop; this sample exposes input state only.
    }

    public static void main(String[] args) {
        initialize();
        System.out.println("Minecraft " + VERSION + " touch input surface ready");
    }

    private static void updateTouch(int pointerId, int x, int y, int viewportWidth, int viewportHeight, boolean active) {
        if (pointerId < 0 || viewportWidth <= 0 || viewportHeight <= 0) {
            return;
        }
        TouchPoint point = getTouch(pointerId);
        if (point == null) {
            point = getFreeTouch();
        }
        if (point == null) {
            return; // Ignore contacts beyond MAX_TOUCHES rather than corrupting input state.
        }

        point.pointerId = pointerId;
        point.active = active;
        point.x = clamp01((float) x / viewportWidth);
        point.y = clamp01((float) y / viewportHeight);
        recomputeTouchMask();
    }

    private static TouchPoint getTouch(int pointerId) {
        for (TouchPoint point : TOUCHES) {
            if (point.active && point.pointerId == pointerId) {
                return point;
            }
        }
        return null;
    }

    private static TouchPoint getFreeTouch() {
        for (TouchPoint point : TOUCHES) {
            if (!point.active) {
                return point;
            }
        }
        return null;
    }

    private static void recomputeTouchMask() {
        int result = 0;
        for (TouchPoint point : TOUCHES) {
            if (!point.active) {
                continue;
            }
            result |= TOUCH_ACTIVE;

            // The left half is an analog-style move pad. A diagonal contact can
            // set two direction bits, preserving the expected Minecraft movement.
            if (point.x < 0.5f) {
                float dx = point.x - MOVE_PAD_X;
                float dy = point.y - MOVE_PAD_Y;
                if (dx < -MOVE_DEAD_ZONE) {
                    result |= TOUCH_LEFT;
                } else if (dx > MOVE_DEAD_ZONE) {
                    result |= TOUCH_RIGHT;
                }
                if (dy < -MOVE_DEAD_ZONE) {
                    result |= TOUCH_FORWARD;
                } else if (dy > MOVE_DEAD_ZONE) {
                    result |= TOUCH_BACKWARD;
                }
            } else {
                // Right side supplies the two action buttons. Keeping this rule
                // here makes it reusable by any host, not just the Godot demo UI.
                if (point.x >= 0.76f && point.y >= 0.58f) {
                    result |= TOUCH_JUMP;
                } else if (point.x >= 0.56f && point.y >= 0.72f) {
                    result |= TOUCH_SNEAK;
                }
            }
        }
        touchMask = result;
    }

    private static float clamp01(float value) {
        return Math.max(0.0f, Math.min(1.0f, value));
    }

    private static final class TouchPoint {
        private int pointerId = -1;
        private float x;
        private float y;
        private boolean active;
    }
}
