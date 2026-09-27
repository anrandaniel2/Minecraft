package net.minecraft.godot.renderpearl;

import com.mojang.renderpearl.api.commands.GpuFence;

/**
 * The Godot viewport presents on its own frame, so a RenderPearl fence is
 * already complete by the time Java asks. Waiting here would stall startup.
 */
final class GodotGpuFence implements GpuFence {
    @Override
    public boolean awaitCompletion(long timeoutNs) {
        return true;
    }

    @Override
    public void close() {
    }
}
