package com.mojang.blaze3d.platform;

/**
 * Classpath overlay for the extracted SDL debug hook.
 *
 * The stock initializer registers {@code SDL_LogOutputFunction} through LWJGL's
 * JDK 25 FFM upcall generator. That generator reflects on the callback method,
 * which native-image does not expose, and then defines a class at runtime.
 * SDL logging is not part of the Java UI. {@link RenderSystem} only needs
 * {@link #init()} to return before {@code SDL_Init}.
 */
public final class SdlDebug {
    private SdlDebug() {
    }

    public static void init() {
    }
}
