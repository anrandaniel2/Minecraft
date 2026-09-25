package net.minecraft.godot.renderpearl;

import com.mojang.blaze3d.platform.NativeImage;
import com.mojang.renderpearl.api.buffers.GpuBufferSlice;
import com.mojang.renderpearl.api.buffers.TransientMemory;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

/**
 * CPU staging memory for texture and sprite uploads.
 *
 * Minecraft 26.3 calls {@code transientMemory()} while reloading resources,
 * then copies the returned slices into textures. The bytes stay in the
 * {@link GodotGpuBuffer} so a later encoder can read them without a GPU heap.
 */
final class GodotTransientMemory implements TransientMemory {
    private final GodotGpuDevice device;

    GodotTransientMemory(GodotGpuDevice device) {
        this.device = Objects.requireNonNull(device, "device");
    }

    @Override
    public ByteBuffer allocateCpu(long size, long alignment) {
        int bytes = alignedSize(size, alignment);
        ByteBuffer buffer = ByteBuffer.allocateDirect(bytes).order(ByteOrder.LITTLE_ENDIAN);
        buffer.limit((int) size);
        return buffer;
    }

    @Override
    public ByteBuffer allocateCpu(long size, long alignment, long ignoredOffset, long ignoredLength) {
        return allocateCpu(size, alignment);
    }

    @Override
    public GpuBufferSlice.MappedView allocateStaging(long size, long alignment, int usage) {
        GodotGpuBuffer buffer = device.createTransientBuffer(usage, alignedSize(size, alignment));
        return buffer.map(0L, size, true, true);
    }

    @Override
    public GpuBufferSlice.MappedView allocateStaging(
            long size, long alignment, int usage, long ignoredOffset, long ignoredLength) {
        return allocateStaging(size, alignment, usage);
    }

    @Override
    public GpuBufferSlice allocateGpu(long size, long alignment, int usage) {
        GodotGpuBuffer buffer = device.createTransientBuffer(usage, alignedSize(size, alignment));
        return new GpuBufferSlice(buffer, 0L, size);
    }

    @Override
    public GpuBufferSlice allocateGpu(
            long size, long alignment, int usage, long ignoredOffset, long ignoredLength) {
        return allocateGpu(size, alignment, usage);
    }

    @Override
    public GpuBufferSlice.MappedView allocateGpuMapped(long size, long alignment, int usage) {
        return allocateStaging(size, alignment, usage);
    }

    @Override
    public GpuBufferSlice.MappedView allocateGpuMapped(
            long size, long alignment, int usage, long ignoredOffset, long ignoredLength) {
        return allocateStaging(size, alignment, usage);
    }

    @Override
    public GpuBufferSlice uploadStaging(ByteBuffer data, long alignment, int usage) {
        return upload(data, alignment, usage);
    }

    @Override
    public GpuBufferSlice uploadStaging(
            ByteBuffer data, long alignment, int usage, long sourceOffset, long sourceLength) {
        return upload(window(data, sourceOffset, sourceLength), alignment, usage);
    }

    @Override
    public GpuBufferSlice uploadStaging(List<ByteBuffer> sources, long alignment, int usage) {
        return upload(concatenate(sources), alignment, usage);
    }

    @Override
    public GpuBufferSlice uploadStaging(
            List<ByteBuffer> sources, long alignment, int usage, long sourceOffset, long sourceLength) {
        return upload(window(concatenate(sources), sourceOffset, sourceLength), alignment, usage);
    }

    @Override
    public GpuBufferSlice uploadGpu(ByteBuffer data, long alignment, int usage) {
        return upload(data, alignment, usage);
    }

    @Override
    public GpuBufferSlice uploadGpu(
            ByteBuffer data, long alignment, int usage, long sourceOffset, long sourceLength) {
        return upload(window(data, sourceOffset, sourceLength), alignment, usage);
    }

    @Override
    public GpuBufferSlice uploadGpu(List<ByteBuffer> sources, long alignment, int usage) {
        return upload(concatenate(sources), alignment, usage);
    }

    @Override
    public GpuBufferSlice uploadGpu(
            List<ByteBuffer> sources, long alignment, int usage, long sourceOffset, long sourceLength) {
        return upload(window(concatenate(sources), sourceOffset, sourceLength), alignment, usage);
    }

    @Override
    public List<GpuBufferSlice> multiUploadStaging(List<ByteBuffer> sources, long alignment, int usage) {
        return uploadEach(sources, alignment, usage);
    }

    @Override
    public List<GpuBufferSlice> multiUploadGpu(List<ByteBuffer> sources, long alignment, int usage) {
        return uploadEach(sources, alignment, usage);
    }

    private GpuBufferSlice upload(ByteBuffer data, long alignment, int usage) {
        Objects.requireNonNull(data, "data");
        int pixelBytes = data.remaining();
        ByteBuffer source = data.duplicate().order(ByteOrder.LITTLE_ENDIAN);
        int size = alignedSize(pixelBytes, alignment);
        ByteBuffer padded = ByteBuffer.allocate(size).order(ByteOrder.LITTLE_ENDIAN);
        padded.put(source);
        padded.position(0);
        padded.limit(size);
        GodotGpuBuffer buffer = device.createTransientBuffer(usage, padded);
        return new GpuBufferSlice(buffer, 0L, pixelBytes);
    }

    private List<GpuBufferSlice> uploadEach(List<ByteBuffer> sources, long alignment, int usage) {
        Objects.requireNonNull(sources, "sources");
        List<GpuBufferSlice> slices = new ArrayList<>(sources.size());
        for (Object source : sources) {
            slices.add(upload(bytesOf(source), alignment, usage));
        }
        return slices;
    }

    private static ByteBuffer concatenate(List<ByteBuffer> sources) {
        Objects.requireNonNull(sources, "sources");
        int total = 0;
        List<ByteBuffer> parts = new ArrayList<>(sources.size());
        for (Object source : sources) {
            ByteBuffer part = bytesOf(source).duplicate();
            total += part.remaining();
            parts.add(part);
        }
        ByteBuffer packed = ByteBuffer.allocate(total).order(ByteOrder.LITTLE_ENDIAN);
        for (ByteBuffer part : parts) {
            packed.put(part);
        }
        packed.flip();
        return packed;
    }

    private static ByteBuffer bytesOf(Object source) {
        if (source instanceof ByteBuffer buffer) {
            return buffer;
        }
        if (source instanceof NativeImage image) {
            return image.getPixelBytes();
        }
        throw new IllegalArgumentException("Transient upload expected pixel bytes, got " + source);
    }

    private static ByteBuffer window(ByteBuffer data, long sourceOffset, long sourceLength) {
        Objects.requireNonNull(data, "data");
        if (sourceLength <= 0) {
            return data;
        }
        if (sourceOffset < 0 || sourceOffset > data.remaining() - sourceLength) {
            throw new IllegalArgumentException("Transient upload window lies outside the source");
        }
        ByteBuffer window = data.duplicate();
        window.position(window.position() + (int) sourceOffset);
        window.limit(window.position() + (int) sourceLength);
        return window.slice();
    }

    private static int alignedSize(long size, long alignment) {
        if (size < 0 || size > Integer.MAX_VALUE) {
            throw new IllegalArgumentException("Transient allocation size is unsupported: " + size);
        }
        long align = alignment <= 1 ? 1 : alignment;
        long padded = (size + align - 1) / align * align;
        if (padded > Integer.MAX_VALUE) {
            throw new IllegalArgumentException("Transient allocation alignment overflowed");
        }
        return (int) Math.max(padded, 1);
    }
}
