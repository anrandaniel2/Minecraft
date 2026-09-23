package net.minecraft.godot.renderpearl;

import com.mojang.renderpearl.api.buffers.GpuBuffer;
import com.mojang.renderpearl.api.buffers.GpuBufferSlice;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

/**
 * Godot-backed RenderPearl buffer metadata plus an explicit CPU staging store.
 *
 * The backing bytes make map()/slice semantics deterministic before the native
 * command executor uploads changed ranges to Godot. The first implementation
 * deliberately limits one resource to Java ByteBuffer addressability; larger
 * buffers must be segmented by the future device implementation.
 */
final class GodotGpuBuffer implements GpuBuffer {
    private final GodotRenderResourceRegistry registry;
    private final GodotRenderResourceRegistry.Handle handle;
    private final int usage;
    private final long size;
    private final ByteBuffer staging;
    private byte[] initialContents;
    private final List<long[]> dirtyRanges = new ArrayList<>();

    GodotGpuBuffer(GodotRenderResourceRegistry registry, int usage, long size) {
        this.registry = Objects.requireNonNull(registry, "registry");
        if (size < 0 || size > Integer.MAX_VALUE) {
            throw new IllegalArgumentException("Godot staging buffer size is unsupported: " + size);
        }
        this.usage = usage;
        this.size = size;
        this.staging = ByteBuffer.allocateDirect((int) size).order(ByteOrder.LITTLE_ENDIAN);
        this.initialContents = null;
        this.handle = registry.allocate(GodotRenderResourceRegistry.Kind.BUFFER);
    }

    GodotGpuBuffer(GodotRenderResourceRegistry registry, int usage, ByteBuffer initialData) {
        this(registry, usage, Objects.requireNonNull(initialData, "initialData").remaining());
        ByteBuffer source = initialData.duplicate();
        this.initialContents = new byte[source.remaining()];
        source.get(this.initialContents);
        ByteBuffer destination = staging.duplicate();
        destination.put(this.initialContents);
    }

    int nativeHandle() {
        requireOpen();
        return handle.id();
    }

    /** Emits the complete native allocation descriptor at the start of a frame. */
    void recordCreate(RenderCommandWriter writer) {
        requireOpen();
        RenderCommandWriter commandWriter = Objects.requireNonNull(writer, "writer");
        commandWriter.createBuffer(nativeHandle(), usage, size);
        if (initialContents != null && initialContents.length != 0) {
            commandWriter.writeBuffer(nativeHandle(), 0L, initialContents);
        }
        // Mapped GUI/world uploads often never submit their own encoder.
        // The next submitted frame's prelude is what actually reaches native code.
        flushDirty(commandWriter);
    }

    byte[] copyRange(long offset, int length) {
        requireOpen();
        if (offset < 0 || length < 0 || offset > size - length) {
            throw new IllegalArgumentException("Read range lies outside buffer bounds");
        }
        ByteBuffer source = staging.duplicate().order(ByteOrder.LITTLE_ENDIAN);
        source.position((int) offset);
        byte[] bytes = new byte[length];
        source.get(bytes);
        return bytes;
    }

    void clearDirty(long offset, long length) {
        dirtyRanges.removeIf(range -> range[0] == offset && range[1] == length);
    }

    private void markDirty(long offset, long length) {
        if (length > 0) {
            dirtyRanges.add(new long[] {offset, length});
        }
    }

    private void flushDirty(RenderCommandWriter writer) {
        if (dirtyRanges.isEmpty()) {
            return;
        }
        List<long[]> pending = List.copyOf(dirtyRanges);
        dirtyRanges.clear();
        for (long[] range : pending) {
            writer.writeBuffer(nativeHandle(), range[0], copyRange(range[0], (int) range[1]));
        }
    }

    void writeFrom(long offset, ByteBuffer source) {
        requireOpen();
        Objects.requireNonNull(source, "source");
        ByteBuffer input = source.duplicate();
        int length = input.remaining();
        if (offset < 0 || offset > size - length) {
            throw new IllegalArgumentException("Write range lies outside buffer bounds");
        }
        ByteBuffer destination = staging.duplicate().order(ByteOrder.LITTLE_ENDIAN);
        destination.position((int) offset);
        destination.put(input);
        markDirty(offset, length);
    }

    @Override
    public long size() {
        requireOpen();
        return size;
    }

    @Override
    public int usage() {
        requireOpen();
        return usage;
    }

    @Override
    public boolean isClosed() {
        return handle.isClosed();
    }

    @Override
    public GpuBufferSlice.MappedView map(long offset, long length, boolean read, boolean write) {
        requireOpen();
        if (!read && !write) {
            throw new IllegalArgumentException("A mapped range must be readable, writable, or both");
        }
        if (offset < 0 || length < 0 || offset > size - length) {
            throw new IllegalArgumentException("Mapped range lies outside buffer bounds");
        }
        ByteBuffer mapped = staging.duplicate().order(ByteOrder.LITTLE_ENDIAN);
        mapped.position((int) offset);
        mapped.limit((int) (offset + length));
        ByteBuffer range = mapped.slice().order(ByteOrder.LITTLE_ENDIAN);
        GpuBufferSlice slice = new GpuBufferSlice(this, offset, length);
        return new GpuBufferSlice.MappedView(slice, range, () -> { });
    }

    @Override
    public void close() {
        registry.close(handle);
    }

    private void requireOpen() {
        registry.requireOpen(handle, GodotRenderResourceRegistry.Kind.BUFFER);
    }
}
