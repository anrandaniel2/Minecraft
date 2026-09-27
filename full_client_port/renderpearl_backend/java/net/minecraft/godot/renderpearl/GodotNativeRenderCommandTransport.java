package net.minecraft.godot.renderpearl;

import org.graalvm.nativeimage.PinnedObject;
import org.graalvm.nativeimage.c.function.CFunction;
import org.graalvm.nativeimage.c.type.CCharPointer;
import org.graalvm.word.UnsignedWord;
import org.graalvm.word.WordFactory;

import java.util.Objects;

/**
 * GraalVM Native Image transport for the neutral RenderPearl frame ABI.
 *
 * This is intentionally a native C call, not a Godot call. The matching C
 * function validates/copies the frame into the GDExtension mailbox; only the C
 * executor will later translate that mailbox into Godot RenderingDevice work.
 */
public final class GodotNativeRenderCommandTransport implements RenderCommandTransport {
    @Override
    public int submit(byte[] frame) {
        Objects.requireNonNull(frame, "frame");
        if (frame.length == 0) {
            return -1;
        }
        try (PinnedObject pinnedFrame = PinnedObject.create(frame)) {
            CCharPointer data = pinnedFrame.addressOfArrayElement(0);
            UnsignedWord size = WordFactory.unsigned(frame.length);
            return submitFrame(data, size);
        }
    }

    /** Native-image smoke path proving Java -> C command submission end to end. */
    public static int submitSmokeFrame() {
        RenderCommandWriter writer = new RenderCommandWriter();
        writer.beginFrame(0L, 1, 1);
        // The native sink must see a declared color target before this pass.
        // GpuFormat.RGBA8_UNORM is ordinal 6 in the extracted 26.3 ABI.
        writer.createTexture(1, 0x08, 6, 1, 1, 1, 1);
        writer.beginRenderPass(1, 0, 0.0f, 0.0f, 0.0f, 1.0f, 0.0);
        writer.endRenderPass();
        return new GodotNativeRenderCommandTransport().submit(writer.finishFrame());
    }

    /**
     * The mailbox keeps only the latest frame. A reload flush must not submit
     * the next chunk until Godot has taken this one, or the upload is dropped.
     */
    @Override
    public void waitUntilDrained(long timeoutMs) {
        long deadline = System.nanoTime() + timeoutMs * 1_000_000L;
        try {
            while (System.nanoTime() < deadline) {
                if (framePending() == 0) {
                    return;
                }
                Thread.sleep(2L);
            }
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
        } catch (UnsatisfiedLinkError unavailable) {
            System.err.println("MINECRAFT_GD_CLIENT drain unavailable");
        }
    }

    @CFunction("minecraft_render_submit_frame")
    private static native int submitFrame(CCharPointer frame, UnsignedWord frameSize);

    @CFunction("minecraft_render_frame_pending")
    private static native int framePending();
}
