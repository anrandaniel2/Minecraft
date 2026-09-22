package net.minecraft.godot.renderpearl;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Objects;

/**
 * Encoder for the neutral RenderPearl-to-native command stream.
 *
 * The byte layout is little-endian and begins every packet with the ABI header:
 * unsigned short opcode, unsigned short reserved, unsigned int packet size.
 * Packet sizes include zero padding to an eight-byte boundary. This writer is
 * intentionally engine-neutral: Java renderer code uses it without importing
 * Godot; native code validates/executes the resulting byte array.
 */
public final class RenderCommandWriter {
    private static final int INITIAL_CAPACITY = 4096;

    private ByteBuffer bytes = ByteBuffer.allocate(INITIAL_CAPACITY).order(ByteOrder.LITTLE_ENDIAN);
    private boolean frameOpen;
    private boolean renderPassOpen;
    private boolean frameComplete;

    /** Starts one complete RenderPearl frame. */
    public void beginFrame(long frameId, int width, int height) {
        require(!frameOpen && !frameComplete, "A new writer is required after a completed frame");
        require(width > 0 && height > 0, "Frame dimensions must be positive");
        int start = beginPacket(RenderCommandProtocol.FRAME_BEGIN);
        bytes.putLong(frameId);
        bytes.putInt(width);
        bytes.putInt(height);
        finishPacket(start);
        frameOpen = true;
    }

    /** Allocates a RenderPearl buffer resource. */
    public void createBuffer(int bufferId, int usage, long size) {
        requireFrameOutsidePass();
        requireHandle(bufferId, "bufferId");
        require(size >= 0, "Buffer size must not be negative");
        int start = beginPacket(RenderCommandProtocol.CREATE_BUFFER);
        bytes.putInt(bufferId);
        bytes.putInt(usage);
        bytes.putLong(size);
        finishPacket(start);
    }

    /** Writes a byte range into an existing RenderPearl buffer. */
    public void writeBuffer(int bufferId, long offset, byte[] data) {
        requireFrameOutsidePass();
        requireHandle(bufferId, "bufferId");
        require(offset >= 0, "Buffer offset must not be negative");
        Objects.requireNonNull(data, "data");
        int start = beginPacket(RenderCommandProtocol.WRITE_BUFFER);
        bytes.putInt(bufferId);
        bytes.putLong(offset);
        bytes.putInt(data.length);
        putBytes(data);
        finishPacket(start);
    }

    /** Allocates a RenderPearl texture resource. */
    public void createTexture(
            int textureId,
            int usage,
            int format,
            int width,
            int height,
            int depthOrLayers,
            int mipLevels
    ) {
        requireFrameOutsidePass();
        requireHandle(textureId, "textureId");
        require(width > 0 && height > 0 && depthOrLayers > 0 && mipLevels > 0,
                "Texture dimensions and mip count must be positive");
        int start = beginPacket(RenderCommandProtocol.CREATE_TEXTURE);
        bytes.putInt(textureId);
        bytes.putInt(usage);
        bytes.putInt(format);
        bytes.putInt(width);
        bytes.putInt(height);
        bytes.putInt(depthOrLayers);
        bytes.putInt(mipLevels);
        finishPacket(start);
    }

    /** Begins a Godot-owned offscreen RenderPearl render pass. */
    public void beginRenderPass(
            int colorTextureId,
            int depthTextureId,
            float clearRed,
            float clearGreen,
            float clearBlue,
            float clearAlpha,
            double clearDepth
    ) {
        require(frameOpen && !frameComplete && !renderPassOpen, "Cannot nest render passes");
        requireHandle(colorTextureId, "colorTextureId");
        require(depthTextureId >= 0, "depthTextureId must be non-negative");
        int start = beginPacket(RenderCommandProtocol.BEGIN_RENDER_PASS);
        bytes.putInt(colorTextureId);
        bytes.putInt(depthTextureId);
        bytes.putFloat(clearRed);
        bytes.putFloat(clearGreen);
        bytes.putFloat(clearBlue);
        bytes.putFloat(clearAlpha);
        bytes.putDouble(clearDepth);
        finishPacket(start);
        renderPassOpen = true;
    }

    /** Binds a compiled RenderPearl pipeline within the active render pass. */
    public void setPipeline(int pipelineId) {
        requireRenderPass();
        requireHandle(pipelineId, "pipelineId");
        int start = beginPacket(RenderCommandProtocol.SET_PIPELINE);
        bytes.putInt(pipelineId);
        finishPacket(start);
    }

    /** Binds a vertex-buffer range within the active render pass. */
    public void setVertexBuffer(int slot, int bufferId, long offset, long length) {
        requireRenderPass();
        require(slot >= 0, "Vertex slot must not be negative");
        requireHandle(bufferId, "bufferId");
        requireRange(offset, length);
        int start = beginPacket(RenderCommandProtocol.SET_VERTEX_BUFFER);
        bytes.putInt(slot);
        bytes.putInt(bufferId);
        bytes.putLong(offset);
        bytes.putLong(length);
        finishPacket(start);
    }

    /** Binds an index-buffer range and its RenderPearl index type. */
    public void setIndexBuffer(int bufferId, int indexType, long offset, long length) {
        requireRenderPass();
        requireHandle(bufferId, "bufferId");
        requireRange(offset, length);
        int start = beginPacket(RenderCommandProtocol.SET_INDEX_BUFFER);
        bytes.putInt(bufferId);
        bytes.putInt(indexType);
        bytes.putLong(offset);
        bytes.putLong(length);
        finishPacket(start);
    }

    /** Emits a non-indexed draw operation. */
    public void draw(int vertexCount, int instanceCount, int firstVertex, int firstInstance) {
        requireRenderPass();
        require(vertexCount >= 0 && instanceCount >= 0 && firstVertex >= 0 && firstInstance >= 0,
                "Draw parameters must be non-negative");
        int start = beginPacket(RenderCommandProtocol.DRAW);
        bytes.putInt(vertexCount);
        bytes.putInt(instanceCount);
        bytes.putInt(firstVertex);
        bytes.putInt(firstInstance);
        finishPacket(start);
    }

    /** Emits an indexed draw operation. */
    public void drawIndexed(int indexCount, int instanceCount, int firstIndex, int vertexOffset, int firstInstance) {
        requireRenderPass();
        require(indexCount >= 0 && instanceCount >= 0 && firstIndex >= 0 && firstInstance >= 0,
                "Indexed draw parameters must be non-negative");
        int start = beginPacket(RenderCommandProtocol.DRAW_INDEXED);
        bytes.putInt(indexCount);
        bytes.putInt(instanceCount);
        bytes.putInt(firstIndex);
        bytes.putInt(vertexOffset);
        bytes.putInt(firstInstance);
        finishPacket(start);
    }

    /** Ends the current RenderPearl pass. */
    public void endRenderPass() {
        requireRenderPass();
        int start = beginPacket(RenderCommandProtocol.END_RENDER_PASS);
        finishPacket(start);
        renderPassOpen = false;
    }

    /** Finishes the frame and returns an immutable copy for the native adapter. */
    public byte[] finishFrame() {
        require(frameOpen && !frameComplete && !renderPassOpen, "Frame must end outside a render pass");
        int start = beginPacket(RenderCommandProtocol.FRAME_END);
        finishPacket(start);
        frameOpen = false;
        frameComplete = true;
        return Arrays.copyOf(bytes.array(), bytes.position());
    }

    private int beginPacket(int opcode) {
        ensureCapacity(RenderCommandProtocol.HEADER_BYTES);
        int start = bytes.position();
        bytes.putShort((short) opcode);
        bytes.putShort((short) 0);
        bytes.putInt(0);
        return start;
    }

    private void finishPacket(int start) {
        int rawSize = bytes.position() - start;
        int alignedSize = RenderCommandProtocol.alignedPacketSize(rawSize);
        ensureCapacity(alignedSize - rawSize);
        while (bytes.position() - start < alignedSize) {
            bytes.put((byte) 0);
        }
        bytes.putInt(start + 4, alignedSize);
    }

    private void putBytes(byte[] data) {
        ensureCapacity(data.length);
        bytes.put(data);
    }

    private void ensureCapacity(int additionalBytes) {
        require(additionalBytes >= 0, "additionalBytes must not be negative");
        if (bytes.remaining() >= additionalBytes) {
            return;
        }
        int required = bytes.position() + additionalBytes;
        int capacity = bytes.capacity();
        while (capacity < required) {
            if (capacity > Integer.MAX_VALUE / 2) {
                capacity = required;
                break;
            }
            capacity *= 2;
        }
        ByteBuffer expanded = ByteBuffer.allocate(capacity).order(ByteOrder.LITTLE_ENDIAN);
        bytes.flip();
        expanded.put(bytes);
        bytes = expanded;
    }

    private void requireFrameOutsidePass() {
        require(frameOpen && !frameComplete && !renderPassOpen, "Operation requires an open frame outside a render pass");
    }

    private void requireRenderPass() {
        require(frameOpen && !frameComplete && renderPassOpen, "Operation requires an active render pass");
    }

    private static void requireHandle(int handle, String name) {
        require(handle > 0, name + " must be positive");
    }

    private static void requireRange(long offset, long length) {
        require(offset >= 0 && length >= 0, "Resource range must be non-negative");
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new IllegalStateException(message);
        }
    }
}
