package net.minecraft.godot;

import java.lang.reflect.Field;

/**
 * Forces LWJGL's JDK 25 FFM binding class to exist before the native image
 * is closed.
 *
 * {@code org.lwjgl.system.JNI} builds {@code JNIBindingsImpl} with
 * {@code Lookup.defineHiddenClass}. Native image rejects that at runtime.
 * Initializing this holder at image build time stores the generated class in
 * a static field, which is the supported way to keep it.
 */
public final class LwjglJniBindings {
    public static final Class<?> BINDINGS_CLASS;
    public static final Object BINDINGS;

    static {
        try {
            org.lwjgl.system.Library.initialize();
            Class<?> jni = Class.forName("org.lwjgl.system.JNI");
            Field field = jni.getDeclaredField("jni");
            field.setAccessible(true);
            Object bindings = field.get(null);
            if (bindings == null) {
                throw new IllegalStateException("LWJGL JNI bindings were not generated");
            }
            BINDINGS = bindings;
            BINDINGS_CLASS = bindings.getClass();
        } catch (ReflectiveOperationException failure) {
            throw new ExceptionInInitializerError(failure);
        }
    }

    private LwjglJniBindings() {
    }

    /** Referenced from the launcher so native-image cannot drop this holder. */
    public static Class<?> bindingsClass() {
        return BINDINGS_CLASS;
    }
}
