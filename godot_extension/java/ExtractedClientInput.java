package net.minecraft.godot;

import net.minecraft.client.KeyboardHandler;
import net.minecraft.client.Minecraft;
import net.minecraft.client.MouseHandler;
import net.minecraft.client.input.KeyEvent;

/**
 * Host touch state for the extracted client.
 *
 * The bit mask matches the existing C ABI. Movement bits are applied to the
 * extracted {@link KeyboardHandler}; camera pixels are applied to
 * {@link MouseHandler}. Neither path imports Godot.
 */
public final class ExtractedClientInput {
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
    private static final int ALLOWED_ACTIONS = TOUCH_FORWARD | TOUCH_BACKWARD | TOUCH_LEFT
            | TOUCH_RIGHT | TOUCH_JUMP | TOUCH_SNEAK;

    /** GLFW key codes used by the extracted client's default bindings. */
    private static final int KEY_SPACE = 32;
    private static final int KEY_A = 65;
    private static final int KEY_D = 68;
    private static final int KEY_S = 83;
    private static final int KEY_W = 87;
    private static final int KEY_LEFT_SHIFT = 340;
    private static final int PRESS = 1;
    private static final int RELEASE = 0;

    private static final TouchPoint[] TOUCHES = new TouchPoint[MAX_TOUCHES];
    private static int touchMask;
    private static int virtualJoystickMask;
    private static int pendingYaw;
    private static int pendingPitch;
    /** Written only on the extracted client thread. */
    private static int appliedMask;

    static {
        for (int i = 0; i < TOUCHES.length; i++) {
            TOUCHES[i] = new TouchPoint();
        }
    }

    private ExtractedClientInput() {
    }

    public static void touchDown(int pointerId, int x, int y, int viewportWidth, int viewportHeight) {
        updateTouch(pointerId, x, y, viewportWidth, viewportHeight, true);
    }

    public static void touchMove(int pointerId, int x, int y, int viewportWidth, int viewportHeight) {
        updateTouch(pointerId, x, y, viewportWidth, viewportHeight, true);
    }

    public static void touchUp(int pointerId) {
        synchronized (ExtractedClientInput.class) {
            TouchPoint point = getTouch(pointerId);
            if (point != null) {
                point.active = false;
                recomputeTouchMask();
            }
        }
        dispatch();
    }

    public static void reset() {
        synchronized (ExtractedClientInput.class) {
            for (TouchPoint point : TOUCHES) {
                point.active = false;
                point.pointerId = -1;
            }
            touchMask = 0;
            virtualJoystickMask = 0;
            pendingYaw = 0;
            pendingPitch = 0;
        }
        dispatch();
    }

    public static void addCameraDrag(int deltaX, int deltaY) {
        synchronized (ExtractedClientInput.class) {
            pendingYaw += deltaX;
            pendingPitch += deltaY;
        }
        dispatch();
    }

    public static void setVirtualJoystickMask(int actionMask) {
        synchronized (ExtractedClientInput.class) {
            virtualJoystickMask = actionMask & ALLOWED_ACTIONS;
            if (virtualJoystickMask != 0) {
                virtualJoystickMask |= TOUCH_ACTIVE;
            }
        }
        dispatch();
    }

    public static int touchMask() {
        synchronized (ExtractedClientInput.class) {
            return touchMask | virtualJoystickMask;
        }
    }

    public static int activeTouchCount() {
        synchronized (ExtractedClientInput.class) {
            int count = 0;
            for (TouchPoint point : TOUCHES) {
                if (point.active) {
                    count++;
                }
            }
            return count;
        }
    }

    private static void updateTouch(
            int pointerId, int x, int y, int viewportWidth, int viewportHeight, boolean active
    ) {
        synchronized (ExtractedClientInput.class) {
            if (pointerId < 0 || viewportWidth <= 0 || viewportHeight <= 0) {
                return;
            }
            TouchPoint point = getTouch(pointerId);
            if (point == null) {
                point = getFreeTouch();
            }
            if (point == null) {
                return;
            }
            point.pointerId = pointerId;
            point.active = active;
            point.x = clamp01((float) x / viewportWidth);
            point.y = clamp01((float) y / viewportHeight);
            recomputeTouchMask();
        }
        dispatch();
    }

    private static void dispatch() {
        final int mask;
        final int yaw;
        final int pitch;
        synchronized (ExtractedClientInput.class) {
            mask = touchMask | virtualJoystickMask;
            yaw = pendingYaw;
            pitch = pendingPitch;
            pendingYaw = 0;
            pendingPitch = 0;
        }
        Minecraft current = ExtractedClientLauncher.client();
        if (current == null) {
            restoreDrag(yaw, pitch);
            return;
        }
        try {
            current.execute(() -> apply(current, mask, yaw, pitch));
        } catch (RuntimeException failure) {
            restoreDrag(yaw, pitch);
            failure.printStackTrace(System.err);
        }
    }

    private static void restoreDrag(int yaw, int pitch) {
        if (yaw == 0 && pitch == 0) {
            return;
        }
        synchronized (ExtractedClientInput.class) {
            pendingYaw += yaw;
            pendingPitch += pitch;
        }
    }

    private static void apply(Minecraft current, int mask, int yaw, int pitch) {
        try {
            long window = current.getWindow().handle();
            KeyboardHandler keyboard = current.keyboardHandler;
            int changed = appliedMask ^ mask;
            pressChanged(keyboard, window, changed, mask, TOUCH_FORWARD, KEY_W);
            pressChanged(keyboard, window, changed, mask, TOUCH_BACKWARD, KEY_S);
            pressChanged(keyboard, window, changed, mask, TOUCH_LEFT, KEY_A);
            pressChanged(keyboard, window, changed, mask, TOUCH_RIGHT, KEY_D);
            pressChanged(keyboard, window, changed, mask, TOUCH_JUMP, KEY_SPACE);
            pressChanged(keyboard, window, changed, mask, TOUCH_SNEAK, KEY_LEFT_SHIFT);
            appliedMask = mask & ALLOWED_ACTIONS;
            if (yaw != 0 || pitch != 0) {
                MouseHandler mouse = current.mouseHandler;
                double x = mouse.xpos() + yaw;
                double y = mouse.ypos() + pitch;
                mouse.onMove(window, x, y, yaw, pitch);
            }
        } catch (RuntimeException failure) {
            restoreDrag(yaw, pitch);
            failure.printStackTrace(System.err);
        }
    }

    private static void pressChanged(
            KeyboardHandler keyboard, long window, int changed, int mask, int bit, int key
    ) {
        if ((changed & bit) == 0) {
            return;
        }
        int action = (mask & bit) != 0 ? PRESS : RELEASE;
        keyboard.keyPress(window, action, new KeyEvent(key, key, 0));
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
            } else if (point.x >= 0.76f && point.y >= 0.58f) {
                result |= TOUCH_JUMP;
            } else if (point.x >= 0.56f && point.y >= 0.72f) {
                result |= TOUCH_SNEAK;
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
