package net.minecraft.godot.renderpearl;

import com.mojang.renderpearl.api.GpuFormat;
import com.mojang.renderpearl.api.buffers.GpuBufferSlice;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.List;

/** Direct-draw render-pass smoke test against the extracted 26.3 RenderPearl API. */
public final class GodotRenderPassTest {
    private GodotRenderPassTest() {
    }

    public static void main(String[] args) {
        GodotRenderResourceRegistry registry = new GodotRenderResourceRegistry();
        GodotGpuTexture colorTarget = new GodotGpuTexture(
                registry, "color", 0x08, GpuFormat.RGBA8_UNORM, 64, 64, 1, 1
        );
        GodotGpuBuffer vertexBuffer = new GodotGpuBuffer(registry, 0x10, 128L);
        GodotCompiledRenderPipeline pipeline = new GodotCompiledRenderPipeline(registry);
        RenderCommandWriter writer = new RenderCommandWriter();
        writer.beginFrame(7L, 64, 64);
        writer.beginRenderPass(colorTarget.nativeHandle(), 0, 0.0f, 0.0f, 0.0f, 1.0f, 0.0);

        GodotRenderPass pass = new GodotRenderPass(writer, 64, 64);
        pass.setPipeline(pipeline);
        pass.setVertexBuffer(0, new GpuBufferSlice(vertexBuffer, 0L, 64L));
        pass.enableScissor(2, 3, 40, 50);
        pass.draw(3, 1, 0, 0);
        pass.drawIndexed(6, 1, 0, 0, 0);
        pass.close();
        byte[] frame = writer.finishFrame();

        List<Integer> expected = List.of(
                RenderCommandProtocol.FRAME_BEGIN,
                RenderCommandProtocol.BEGIN_RENDER_PASS,
                RenderCommandProtocol.SET_PIPELINE,
                RenderCommandProtocol.SET_VERTEX_BUFFER,
                RenderCommandProtocol.SET_SCISSOR,
                RenderCommandProtocol.DRAW,
                RenderCommandProtocol.DRAW_INDEXED,
                RenderCommandProtocol.END_RENDER_PASS,
                RenderCommandProtocol.FRAME_END
        );
        if (!decodeOpcodes(frame).equals(expected)) {
            throw new AssertionError("Render pass encoded an unexpected command sequence");
        }

        expectIllegalState(() -> pass.draw(3, 1, 0, 0));
        vertexBuffer.close();
        pipeline.close();
        colorTarget.close();
    }

    private static List<Integer> decodeOpcodes(byte[] frame) {
        ByteBuffer bytes = ByteBuffer.wrap(frame).order(ByteOrder.LITTLE_ENDIAN);
        List<Integer> opcodes = new ArrayList<>();
        while (bytes.hasRemaining()) {
            int opcode = Short.toUnsignedInt(bytes.getShort());
            bytes.getShort();
            int packetSize = bytes.getInt();
            if (packetSize < RenderCommandProtocol.HEADER_BYTES
                    || packetSize % RenderCommandProtocol.PACKET_ALIGNMENT != 0) {
                throw new AssertionError("Invalid encoded packet size");
            }
            opcodes.add(opcode);
            bytes.position(bytes.position() - RenderCommandProtocol.HEADER_BYTES + packetSize);
        }
        return opcodes;
    }

    private static void expectIllegalState(Runnable action) {
        try {
            action.run();
        } catch (IllegalStateException expected) {
            return;
        }
        throw new AssertionError("Closed render pass accepted a draw");
    }
}
