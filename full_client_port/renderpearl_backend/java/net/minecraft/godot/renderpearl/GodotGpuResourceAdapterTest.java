package net.minecraft.godot.renderpearl;

import com.mojang.renderpearl.api.buffers.GpuBufferSlice;

import java.nio.ByteBuffer;

/** Runtime smoke test against the real extracted RenderPearl resource classes. */
public final class GodotGpuResourceAdapterTest {
    private GodotGpuResourceAdapterTest() {
    }

    public static void main(String[] args) {
        GodotRenderResourceRegistry registry = new GodotRenderResourceRegistry();
        GodotGpuBuffer buffer = new GodotGpuBuffer(registry, 0x10, 16L);
        if (buffer.size() != 16L || buffer.usage() != 0x10 || registry.liveCount() != 1) {
            throw new AssertionError("Buffer metadata was not retained");
        }

        try (GpuBufferSlice.MappedView mapped = buffer.map(4L, 4L, false, true)) {
            mapped.data().put(new byte[] {10, 20, 30, 40});
        }
        try (GpuBufferSlice.MappedView mapped = buffer.map(4L, 4L, true, false)) {
            ByteBuffer data = mapped.data();
            for (int expected : new int[] {10, 20, 30, 40}) {
                if (Byte.toUnsignedInt(data.get()) != expected) {
                    throw new AssertionError("Mapped staging bytes changed");
                }
            }
        }

        buffer.close();
        if (!buffer.isClosed() || registry.liveCount() != 0) {
            throw new AssertionError("Buffer close did not release native handle");
        }
        expectIllegalState(buffer::size);
    }

    private static void expectIllegalState(Runnable action) {
        try {
            action.run();
        } catch (IllegalStateException expected) {
            return;
        }
        throw new AssertionError("Expected closed resource to reject access");
    }
}
