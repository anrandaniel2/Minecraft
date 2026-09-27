package net.minecraft.godot.renderpearl;

import com.mojang.renderpearl.api.commands.GpuQueryPool;

import java.util.Arrays;
import java.util.OptionalLong;

/**
 * Timestamp queries are profiling only. The viewport does not read GPU time,
 * so this pool stays empty and never aborts frame submission.
 */
final class GodotGpuQueryPool implements GpuQueryPool {
    private final int size;

    GodotGpuQueryPool(int size) {
        if (size <= 0) {
            throw new IllegalArgumentException("Timestamp query pool size must be positive");
        }
        this.size = size;
    }

    @Override
    public int size() {
        return size;
    }

    @Override
    public OptionalLong getValue(int index) {
        if (index < 0 || index >= size) {
            throw new IndexOutOfBoundsException("Timestamp query index " + index + " is outside 0.." + (size - 1));
        }
        return OptionalLong.empty();
    }

    @Override
    public OptionalLong[] getValues(int index, int count) {
        if (index < 0 || count < 0 || index > size - count) {
            throw new IndexOutOfBoundsException("Timestamp query range " + index + "+" + count + " is outside " + size);
        }
        OptionalLong[] values = new OptionalLong[count];
        Arrays.fill(values, OptionalLong.empty());
        return values;
    }

    @Override
    public void close() {
    }
}
