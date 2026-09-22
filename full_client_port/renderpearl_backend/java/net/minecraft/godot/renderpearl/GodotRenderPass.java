package net.minecraft.godot.renderpearl;

import com.mojang.renderpearl.api.buffers.GpuBuffer;
import com.mojang.renderpearl.api.buffers.GpuBufferSlice;
import com.mojang.renderpearl.api.commands.GpuQueryPool;
import com.mojang.renderpearl.api.commands.RenderPass;
import com.mojang.renderpearl.api.pipeline.CompiledRenderPipeline;
import com.mojang.renderpearl.api.pipeline.IndexType;
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
 * It covers pipeline/buffer binding, scissor state and direct draw operations.
 * Timestamp, texture-sampler uniforms, push constants and indirect draw forms
 * remain explicit unsupported work rather than silently being discarded.
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
        throw unsupported("timestamp queries");
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
        throw unsupported("texture/sampler uniforms");
    }

    @Override
    public void setUniform(String name, GpuBuffer buffer) {
        throw unsupported("uniform-buffer bindings");
    }

    @Override
    public void setUniform(String name, GpuBufferSlice bufferSlice) {
        throw unsupported("uniform-buffer slice bindings");
    }

    @Override
    public void pushConstants(ByteBuffer data) {
        throw unsupported("push constants");
    }

    @Override
    public void enableScissor(int x, int y, int width, int height) {
        requireOpen();
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
        GodotGpuBuffer buffer = requireBuffer(vertexBuffer);
        writer.setVertexBuffer(slot, buffer.nativeHandle(), vertexBuffer.offset(), vertexBuffer.length());
    }

    @Override
    public void setIndexBuffer(GpuBuffer indexBuffer, IndexType indexType) {
        requireOpen();
        if (!(indexBuffer instanceof GodotGpuBuffer buffer)) {
            throw new IllegalArgumentException("Index buffer was not created by GodotRenderPearlBackend");
        }
        writer.setIndexBuffer(buffer.nativeHandle(), indexType.ordinal(), 0L, buffer.size());
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
        throw unsupported("dynamic-uniform indexed multi-draw");
    }

    @Override
    public void drawIndexedIndirect(GpuBufferSlice commands, int drawCount) {
        throw unsupported("indexed indirect draws");
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
        throw unsupported("indirect draws");
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
