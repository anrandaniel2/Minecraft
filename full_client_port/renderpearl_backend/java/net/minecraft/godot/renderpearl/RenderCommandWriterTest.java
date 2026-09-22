package net.minecraft.godot.renderpearl;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.List;

/** Minimal dependency-free protocol test, run by full-client preflight CI. */
public final class RenderCommandWriterTest {
    private RenderCommandWriterTest() {
    }

    public static void main(String[] args) {
        RenderCommandWriter writer = new RenderCommandWriter();
        writer.beginFrame(42L, 1280, 720);
        writer.createBuffer(1, 0x10, 4096L);
        writer.writeBuffer(1, 0L, new byte[] {1, 2, 3, 4, 5});
        writer.createTexture(2, 0x08, 7, 1280, 720, 1, 1);
        writer.beginRenderPass(2, 0, 0.1f, 0.2f, 0.3f, 1.0f, 1.0);
        writer.setPipeline(3);
        writer.setVertexBuffer(0, 1, 0L, 128L);
        writer.drawIndexed(36, 1, 0, 0, 0);
        writer.endRenderPass();
        byte[] frame = writer.finishFrame();

        List<Integer> opcodes = decodeOpcodes(frame);
        List<Integer> expected = List.of(
                RenderCommandProtocol.FRAME_BEGIN,
                RenderCommandProtocol.CREATE_BUFFER,
                RenderCommandProtocol.WRITE_BUFFER,
                RenderCommandProtocol.CREATE_TEXTURE,
                RenderCommandProtocol.BEGIN_RENDER_PASS,
                RenderCommandProtocol.SET_PIPELINE,
                RenderCommandProtocol.SET_VERTEX_BUFFER,
                RenderCommandProtocol.DRAW_INDEXED,
                RenderCommandProtocol.END_RENDER_PASS,
                RenderCommandProtocol.FRAME_END
        );
        if (!opcodes.equals(expected)) {
            throw new AssertionError("Unexpected packet sequence: " + opcodes);
        }

        RenderCommandWriter invalid = new RenderCommandWriter();
        invalid.beginFrame(1L, 1, 1);
        expectIllegalState(() -> invalid.draw(3, 1, 0, 0));
        invalid.beginRenderPass(1, 0, 0.0f, 0.0f, 0.0f, 1.0f, 1.0);
        expectIllegalState(invalid::finishFrame);
    }

    private static List<Integer> decodeOpcodes(byte[] frame) {
        ByteBuffer bytes = ByteBuffer.wrap(frame).order(ByteOrder.LITTLE_ENDIAN);
        List<Integer> opcodes = new ArrayList<>();
        while (bytes.hasRemaining()) {
            if (bytes.remaining() < RenderCommandProtocol.HEADER_BYTES) {
                throw new AssertionError("Truncated packet header");
            }
            int opcode = Short.toUnsignedInt(bytes.getShort());
            bytes.getShort(); // reserved
            long packetSize = Integer.toUnsignedLong(bytes.getInt());
            if (packetSize < RenderCommandProtocol.HEADER_BYTES
                    || packetSize % RenderCommandProtocol.PACKET_ALIGNMENT != 0
                    || packetSize > bytes.remaining() + RenderCommandProtocol.HEADER_BYTES) {
                throw new AssertionError("Invalid packet size: " + packetSize);
            }
            opcodes.add(opcode);
            bytes.position((int) (bytes.position() - RenderCommandProtocol.HEADER_BYTES + packetSize));
        }
        return opcodes;
    }

    private static void expectIllegalState(Runnable action) {
        try {
            action.run();
        } catch (IllegalStateException expected) {
            return;
        }
        throw new AssertionError("Expected IllegalStateException");
    }
}
