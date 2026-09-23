package net.minecraft.godot.renderpearl;

import com.mojang.renderpearl.api.GpuFormat;
import com.mojang.renderpearl.api.buffers.GpuBuffer;
import com.mojang.renderpearl.api.buffers.GpuBufferSlice;
import com.mojang.renderpearl.api.commands.CommandEncoder;
import com.mojang.renderpearl.api.commands.RenderPass;
import com.mojang.renderpearl.api.commands.RenderPassDescriptor;
import com.mojang.renderpearl.api.device.GpuSurface;
import com.mojang.renderpearl.api.textures.GpuTexture;
import com.mojang.renderpearl.api.textures.GpuTextureView;
import org.joml.Vector4f;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/** Runtime smoke test for the extracted GpuDevice/GpuSurface adapter seam. */
public final class GodotGpuDeviceTest {
    private GodotGpuDeviceTest() {
    }

    public static void main(String[] args) throws Exception {
        List<byte[]> submittedFrames = new ArrayList<>();
        GodotGpuDevice device = new GodotGpuDevice(16, 16, frame -> {
            submittedFrames.add(frame);
            return decodeOpcodes(frame).size();
        });

        GodotGpuSurface surface = (GodotGpuSurface) device.createSurface(0L, () -> true);
        if (!surface.supportedPresentModes().equals(List.of(GpuSurface.PresentMode.FIFO))) {
            throw new AssertionError("Godot surface must expose FIFO presentation");
        }
        surface.configure(new GpuSurface.Configuration(320, 180, GpuSurface.PresentMode.FIFO));
        if (surface.currentConfiguration().isEmpty() || surface.currentConfiguration().get().width() != 320) {
            throw new AssertionError("Godot surface did not retain its configuration");
        }
        surface.acquireNextTexture();
        if (!surface.isAcquired()) {
            throw new AssertionError("Godot surface did not track acquisition");
        }

        GpuTexture texture = device.createTexture("target", 0x08, GpuFormat.RGBA8_UNORM, 320, 180, 1, 1);
        GpuTextureView view = device.createTextureView(texture);
        GpuBuffer vertexBuffer = device.createBuffer(() -> "vertices", 0x10, 64L);
        GpuBuffer initialBuffer = device.createBuffer(
                () -> "initial", 0x20, ByteBuffer.wrap(new byte[] {9, 8, 7, 6})
        );
        CommandEncoder encoder = device.createCommandEncoder();
        encoder.writeToBuffer(new GpuBufferSlice(vertexBuffer, 0, 4), ByteBuffer.wrap(new byte[] {1, 2, 3, 4}));
        RenderPassDescriptor descriptor = RenderPassDescriptor.builder(() -> "device-test")
                .withColorAttachment(view, Optional.of(new Vector4f(0.2f, 0.3f, 0.4f, 1.0f)))
                .build();
        try (RenderPass pass = encoder.createRenderPass(descriptor)) {
            pass.setVertexBuffer(0, new GpuBufferSlice(vertexBuffer, 0, 4));
            pass.draw(3, 1, 0, 0);
        }
        encoder.submit();

        if (submittedFrames.size() != 1) {
            throw new AssertionError("Device command encoder did not submit a frame");
        }
        ByteBuffer frame = ByteBuffer.wrap(submittedFrames.getFirst()).order(ByteOrder.LITTLE_ENDIAN);
        if (Short.toUnsignedInt(frame.getShort()) != RenderCommandProtocol.FRAME_BEGIN) {
            throw new AssertionError("Submitted frame does not start with FRAME_BEGIN");
        }
        frame.position(RenderCommandProtocol.HEADER_BYTES + Long.BYTES);
        if (frame.getInt() != 320 || frame.getInt() != 180) {
            throw new AssertionError("Surface configuration was not used by the command encoder");
        }
        List<Integer> expected = List.of(
                RenderCommandProtocol.FRAME_BEGIN,
                RenderCommandProtocol.CREATE_BUFFER,
                RenderCommandProtocol.CREATE_BUFFER,
                RenderCommandProtocol.WRITE_BUFFER,
                RenderCommandProtocol.CREATE_TEXTURE,
                RenderCommandProtocol.WRITE_BUFFER,
                RenderCommandProtocol.BEGIN_RENDER_PASS,
                RenderCommandProtocol.SET_SCISSOR,
                RenderCommandProtocol.SET_VERTEX_BUFFER,
                RenderCommandProtocol.DRAW,
                RenderCommandProtocol.END_RENDER_PASS,
                RenderCommandProtocol.FRAME_END
        );
        if (!decodeOpcodes(submittedFrames.getFirst()).equals(expected)) {
            throw new AssertionError("Device did not declare resources before using them");
        }

        expectUnsupported(() -> surface.blitFromTexture(encoder, view));
        surface.present();
        if (surface.isAcquired()) {
            throw new AssertionError("Godot surface remained acquired after present");
        }

        initialBuffer.close();
        vertexBuffer.close();
        view.close();
        texture.close();
        surface.close();
        device.close();
        expectIllegalState(device::createCommandEncoder);
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
                throw new AssertionError("Invalid packet size");
            }
            opcodes.add(opcode);
            bytes.position(bytes.position() - RenderCommandProtocol.HEADER_BYTES + packetSize);
        }
        return opcodes;
    }

    private static void expectUnsupported(Runnable action) {
        try {
            action.run();
        } catch (UnsupportedOperationException expected) {
            return;
        }
        throw new AssertionError("Expected UnsupportedOperationException");
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
