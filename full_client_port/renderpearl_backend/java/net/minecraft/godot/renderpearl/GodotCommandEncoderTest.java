package net.minecraft.godot.renderpearl;

import com.mojang.renderpearl.api.GpuFormat;
import com.mojang.renderpearl.api.buffers.GpuBufferSlice;
import com.mojang.renderpearl.api.commands.RenderPass;
import com.mojang.renderpearl.api.commands.RenderPassDescriptor;
import org.joml.Vector4f;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/** Records a descriptor-backed pass and verifies the frame submitted to native code. */
public final class GodotCommandEncoderTest {
    private GodotCommandEncoderTest() {
    }

    public static void main(String[] args) {
        GodotRenderResourceRegistry registry = new GodotRenderResourceRegistry();
        GodotGpuTexture target = new GodotGpuTexture(
                registry, "target", 0x08, GpuFormat.RGBA8_UNORM, 64, 64, 1, 1
        );
        GodotGpuTextureView targetView = new GodotGpuTextureView(registry, target, 0, 1);
        GodotGpuBuffer vertexBuffer = new GodotGpuBuffer(registry, 0x10, 64L);
        GodotCompiledRenderPipeline pipeline = new GodotCompiledRenderPipeline(registry);
        List<byte[]> submittedFrames = new ArrayList<>();

        GodotCommandEncoder encoder = new GodotCommandEncoder(99L, 64, 64, frame -> {
            submittedFrames.add(frame);
            return countPackets(frame);
        });
        encoder.writeToBuffer(new GpuBufferSlice(vertexBuffer, 0, 4), ByteBuffer.wrap(new byte[] {1, 2, 3, 4}));
        encoder.writeToTexture(target, ByteBuffer.wrap(new byte[] {9, 8, 7, 6}), 0, 1, 0, 0, 1, 1);
        RenderPassDescriptor descriptor = RenderPassDescriptor.builder(() -> "test")
                .withColorAttachment(targetView, Optional.of(new Vector4f(0.1f, 0.2f, 0.3f, 1.0f)))
                .build();
        try (RenderPass pass = encoder.createRenderPass(descriptor)) {
            pass.setPipeline(pipeline);
            pass.setVertexBuffer(0, new GpuBufferSlice(vertexBuffer, 0, 4));
            pass.draw(3, 1, 0, 0);
        }
        encoder.submit();

        if (submittedFrames.size() != 1) {
            throw new AssertionError("Command frame was not submitted exactly once");
        }
        List<Integer> expected = List.of(
                RenderCommandProtocol.FRAME_BEGIN,
                RenderCommandProtocol.WRITE_BUFFER,
                RenderCommandProtocol.WRITE_TEXTURE,
                RenderCommandProtocol.BEGIN_RENDER_PASS,
                RenderCommandProtocol.SET_SCISSOR,
                RenderCommandProtocol.SET_PIPELINE,
                RenderCommandProtocol.SET_VERTEX_BUFFER,
                RenderCommandProtocol.DRAW,
                RenderCommandProtocol.END_RENDER_PASS,
                RenderCommandProtocol.FRAME_END
        );
        if (!decodeOpcodes(submittedFrames.getFirst()).equals(expected)) {
            throw new AssertionError("Descriptor-backed encoder emitted an unexpected frame");
        }
        expectIllegalState(encoder::submit);

        pipeline.close();
        vertexBuffer.close();
        targetView.close();
        target.close();
    }

    private static int countPackets(byte[] frame) {
        return decodeOpcodes(frame).size();
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
        throw new AssertionError("Submitted encoder accepted another submission");
    }
}
