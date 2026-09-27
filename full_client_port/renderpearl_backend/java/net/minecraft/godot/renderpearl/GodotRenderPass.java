package net.minecraft.godot.renderpearl;

import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.renderpearl.api.buffers.GpuBuffer;
import com.mojang.renderpearl.api.buffers.GpuBufferSlice;
import com.mojang.renderpearl.api.commands.GpuQueryPool;
import com.mojang.renderpearl.api.commands.RenderPass;
import com.mojang.renderpearl.api.pipeline.CompiledRenderPipeline;
import com.mojang.renderpearl.api.pipeline.IndexType;
import com.mojang.renderpearl.api.pipeline.PrimitiveTopology;
import com.mojang.renderpearl.api.textures.GpuSampler;
import com.mojang.renderpearl.api.textures.GpuTextureView;
import org.lwjgl.PointerBuffer;

import java.nio.ByteBuffer;
import java.nio.IntBuffer;
import java.util.Collection;
import java.util.Objects;
import java.util.function.Supplier;

/**
 * Initial RenderPearl RenderPass implementation backed by RenderCommandWriter.
 *
 * It covers pipeline/buffer binding, named GUI uniforms, scissor state and
 * direct draw operations. Timestamp queries, push constants and indirect draw
 * forms remain explicit unsupported work rather than silently being discarded.
 */
final class GodotRenderPass implements RenderPass {
    private final RenderCommandWriter writer;
    private final int targetWidth;
    private final int targetHeight;
    private final Runnable onClose;
    private boolean closed;

    GodotRenderPass(RenderCommandWriter writer, int targetWidth, int targetHeight) {
        this(writer, targetWidth, targetHeight, () -> { });
    }

    GodotRenderPass(RenderCommandWriter writer, int targetWidth, int targetHeight, Runnable onClose) {
        this.writer = Objects.requireNonNull(writer, "writer");
        this.targetWidth = targetWidth;
        this.targetHeight = targetHeight;
        this.onClose = Objects.requireNonNull(onClose, "onClose");
    }

    @Override
    public void pushDebugGroup(Supplier<String> label) {
        Objects.requireNonNull(label, "label");
        requireOpen();
        // Debug labels are retained by the future native executor; they have no
        // GPU state effect in this first command-stream slice.
    }

    @Override
    public void popDebugGroup() {
        requireOpen();
    }

    @Override
    public void writeTimestamp(GpuQueryPool pool, int index) {
        requireOpen();
        if (pool != null && (index < 0 || index >= pool.size())) {
            throw new IndexOutOfBoundsException("Timestamp query index " + index);
        }
    }

    @Override
    public void setPipeline(CompiledRenderPipeline pipeline) {
        requireOpen();
        if (!(pipeline instanceof GodotCompiledRenderPipeline godotPipeline)) {
            throw new IllegalArgumentException("Pipeline was not created by GodotRenderPearlBackend");
        }
        writer.setPipeline(godotPipeline.nativeHandle());
    }

    @Override
    public void setUniform(String name, GpuTextureView textureView, GpuSampler sampler) {
        requireOpen();
        if (!(textureView instanceof GodotGpuTextureView view) || !(view.texture() instanceof GodotGpuTexture texture)) {
            throw new IllegalArgumentException("Texture view was not created by GodotRenderPearlBackend");
        }
        if (!(sampler instanceof GodotGpuSampler godotSampler)) {
            throw new IllegalArgumentException("Sampler was not created by GodotRenderPearlBackend");
        }
        writer.setTextureSampler(
                name,
                texture.nativeHandle(),
                godotSampler.nativeHandle(),
                view.baseMipLevel(),
                godotSampler.getMinFilter().ordinal(),
                godotSampler.getMagFilter().ordinal(),
                godotSampler.getAddressModeU().ordinal(),
                godotSampler.getAddressModeV().ordinal()
        );
    }

    @Override
    public void setUniform(String name, GpuBuffer buffer) {
        requireOpen();
        if (!(buffer instanceof GodotGpuBuffer godotBuffer)) {
            throw new IllegalArgumentException("Uniform buffer was not created by GodotRenderPearlBackend");
        }
        writer.setUniformBuffer(name, godotBuffer.nativeHandle(), 0L, godotBuffer.size());
    }

    @Override
    public void setUniform(String name, GpuBufferSlice bufferSlice) {
        requireOpen();
        if (bufferSlice == null) {
            return;
        }
        GodotGpuBuffer buffer = requireBuffer(bufferSlice);
        writer.setUniformBuffer(name, buffer.nativeHandle(), bufferSlice.offset(), bufferSlice.length());
    }

    @Override
    public void pushConstants(ByteBuffer data) {
        throw unsupported("push constants");
    }

    @Override
    public void enableScissor(int x, int y, int width, int height) {
        requireOpen();
        if (x < 0) {
            width += x;
            x = 0;
        }
        if (y < 0) {
            height += y;
            y = 0;
        }
        if (width < 0) {
            width = 0;
        }
        if (height < 0) {
            height = 0;
        }
        if (x > targetWidth) {
            x = targetWidth;
        }
        if (y > targetHeight) {
            y = targetHeight;
        }
        if (width > targetWidth - x) {
            width = targetWidth - x;
        }
        if (height > targetHeight - y) {
            height = targetHeight - y;
        }
        writer.setScissor(x, y, width, height);
    }

    @Override
    public void disableScissor() {
        requireOpen();
        writer.setScissor(0, 0, targetWidth, targetHeight);
    }

    @Override
    public void setVertexBuffer(int slot, GpuBufferSlice vertexBuffer) {
        requireOpen();
        // VulkanRenderPass returns when the slice is null. World passes use that
        // to skip an empty slot; throwing aborted the first world frame.
        if (vertexBuffer == null) {
            return;
        }
        GodotGpuBuffer buffer = requireBuffer(vertexBuffer);
        writer.setVertexBuffer(slot, buffer.nativeHandle(), vertexBuffer.offset(), vertexBuffer.length());
    }

    @Override
    public void setIndexBuffer(GpuBuffer indexBuffer, IndexType indexType) {
        requireOpen();
        if (indexBuffer == null) {
            // GuiRenderer's non-sorted draws pass a null index buffer and expect
            // the shared sequential quad buffer that upload() already warmed.
            indexBuffer = sequentialIndexBuffer();
        }
        if (!(indexBuffer instanceof GodotGpuBuffer buffer)) {
            return;
        }
        int type = indexType == null ? 0 : indexType.ordinal();
        writer.setIndexBuffer(buffer.nativeHandle(), type, 0L, buffer.size());
    }

    private static GpuBuffer sequentialIndexBuffer() {
        try {
            GpuBuffer quads = RenderSystem.getSequentialBuffer(PrimitiveTopology.QUADS).getBuffer(6);
            if (quads != null) {
                return quads;
            }
        } catch (RuntimeException ignored) {
            // A missing sequential buffer must not abort the GUI pass.
        }
        try {
            return RenderSystem.getSequentialBuffer(PrimitiveTopology.TRIANGLES).getBuffer(6);
        } catch (RuntimeException ignored) {
            return null;
        }
    }

    @Override
    public void drawIndexed(int indexCount, int instanceCount, int firstIndex, int vertexOffset, int firstInstance) {
        requireOpen();
        writer.drawIndexed(indexCount, instanceCount, firstIndex, vertexOffset, firstInstance);
    }

    @Override
    public void multiDrawIndexed(IntBuffer drawParameters, int drawCount, int indexOffset, int vertexOffset) {
        requireOpen();
        IntBuffer values = drawParameters.duplicate();
        if (drawCount < 0 || values.remaining() < drawCount * 2) {
            throw new IllegalArgumentException("Invalid indexed multi-draw parameter buffer");
        }
        for (int draw = 0; draw < drawCount; draw++) {
            int indexCount = values.get();
            int firstIndex = values.get();
            writer.drawIndexed(indexCount, 1, firstIndex + indexOffset, vertexOffset, 0);
        }
    }

    @Override
    public void multiDrawIndexed(PointerBuffer firstIndexOffsets, IntBuffer indexCounts, IntBuffer vertexOffsets, int drawCount) {
        throw unsupported("pointer-buffer multi-draw indexed");
    }

    @Override
    public <T> void drawMultipleIndexed(
            Collection<RenderPass.Draw<T>> draws,
            GpuBuffer defaultIndexBuffer,
            IndexType defaultIndexType,
            Collection<String> dynamicUniforms,
            T uniformArgument
    ) {
        requireOpen();
        if (draws == null || draws.isEmpty()) {
            return;
        }
        RenderPass.UniformUploader uploader = new RenderPass.UniformUploader() {
            @Override
            public void setUniform(String name, GpuBufferSlice slice) {
                GodotRenderPass.this.setUniform(name, slice);
            }

            @Override
            public void pushConstants(ByteBuffer data) {
                // Chunk and entity draws bind uniforms by name. Push constants are unused here.
            }
        };
        for (RenderPass.Draw<T> draw : draws) {
            if (draw == null || draw.indexCount() <= 0) {
                continue;
            }
            if (draw.uniformUploaderConsumer() != null) {
                draw.uniformUploaderConsumer().accept(uniformArgument, uploader);
            }
            GpuBuffer vertices = draw.vertexBuffer();
            if (vertices != null) {
                setVertexBuffer(draw.slot(), vertices.slice());
            }
            GpuBuffer indices = draw.indexBuffer() != null ? draw.indexBuffer() : defaultIndexBuffer;
            IndexType indexType = draw.indexType() != null ? draw.indexType() : defaultIndexType;
            if (indices != null) {
                setIndexBuffer(indices, indexType);
            }
            writer.drawIndexed(draw.indexCount(), 1, draw.firstIndex(), draw.baseVertex(), 0);
        }
    }

    @Override
    public void drawIndexedIndirect(GpuBufferSlice commands, int drawCount) {
        requireOpen();
        expandIndirect(commands, drawCount, true);
    }

    @Override
    public void draw(int vertexCount, int instanceCount, int firstVertex, int firstInstance) {
        requireOpen();
        writer.draw(vertexCount, instanceCount, firstVertex, firstInstance);
    }

    @Override
    public void multiDraw(IntBuffer drawParameters, int drawCount, int vertexOffset, int firstInstance) {
        requireOpen();
        IntBuffer values = drawParameters.duplicate();
        if (drawCount < 0 || values.remaining() < drawCount * 2) {
            throw new IllegalArgumentException("Invalid interleaved multi-draw parameter buffer");
        }
        for (int draw = 0; draw < drawCount; draw++) {
            int vertexCount = values.get();
            int firstVertex = values.get();
            writer.draw(vertexCount, 1, firstVertex + vertexOffset, firstInstance);
        }
    }

    @Override
    public void multiDraw(IntBuffer firstVertices, IntBuffer vertexCounts, int drawCount) {
        requireOpen();
        IntBuffer starts = firstVertices.duplicate();
        IntBuffer counts = vertexCounts.duplicate();
        if (drawCount < 0 || starts.remaining() < drawCount || counts.remaining() < drawCount) {
            throw new IllegalArgumentException("Invalid multi-draw parameter buffers");
        }
        for (int draw = 0; draw < drawCount; draw++) {
            writer.draw(counts.get(), 1, starts.get(), 0);
        }
    }


    @Override
    public void drawIndirect(GpuBufferSlice commands, int drawCount) {
        requireOpen();
        expandIndirect(commands, drawCount, false);
    }

    /** Expands CPU-staged indirect commands into the direct draws this executor records. */
    private void expandIndirect(GpuBufferSlice commands, int drawCount, boolean indexed) {
        if (commands == null || drawCount <= 0 || !(commands.buffer() instanceof GodotGpuBuffer buffer)) {
            return;
        }
        int stride = indexed ? 20 : 16;
        long offset = commands.offset();
        for (int draw = 0; draw < drawCount; draw++) {
            byte[] raw;
            try {
                raw = buffer.copyRange(offset + (long) draw * stride, stride);
            } catch (RuntimeException ignored) {
                return;
            }
            ByteBuffer view = ByteBuffer.wrap(raw).order(java.nio.ByteOrder.LITTLE_ENDIAN);
            if (indexed) {
                int indexCount = view.getInt();
                int instanceCount = view.getInt();
                int firstIndex = view.getInt();
                int vertexOffset = view.getInt();
                int firstInstance = view.getInt();
                if (indexCount > 0 && instanceCount > 0) {
                    writer.drawIndexed(indexCount, instanceCount, firstIndex, vertexOffset, firstInstance);
                }
            } else {
                int vertexCount = view.getInt();
                int instanceCount = view.getInt();
                int firstVertex = view.getInt();
                view.getInt();
                if (vertexCount > 0 && instanceCount > 0) {
                    writer.draw(vertexCount, instanceCount, firstVertex, 0);
                }
            }
        }
    }

    @Override
    public void close() {
        if (!closed) {
            writer.endRenderPass();
            closed = true;
            onClose.run();
        }
    }

    private GodotGpuBuffer requireBuffer(GpuBufferSlice slice) {
        Objects.requireNonNull(slice, "vertexBuffer");
        if (!(slice.buffer() instanceof GodotGpuBuffer buffer)) {
            throw new IllegalArgumentException("Buffer slice was not created by GodotRenderPearlBackend");
        }
        return buffer;
    }

    private void requireOpen() {
        if (closed) {
            throw new IllegalStateException("Render pass is closed");
        }
    }

    private static UnsupportedOperationException unsupported(String feature) {
        return new UnsupportedOperationException("Godot RenderPearl backend has not implemented " + feature);
    }
}
