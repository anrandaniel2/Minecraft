package net.minecraft.godot.renderpearl;

/**
 * Native boundary used by the Java RenderPearl backend.
 *
 * The eventual GraalVM implementation invokes minecraft_render_submit_frame in
 * the C GDExtension and returns the native validator's positive packet count,
 * or a negative validation error. This interface makes the Java backend
 * testable without importing Godot or loading a native library.
 */
@FunctionalInterface
interface RenderCommandTransport {
    int submit(byte[] frame);
}
