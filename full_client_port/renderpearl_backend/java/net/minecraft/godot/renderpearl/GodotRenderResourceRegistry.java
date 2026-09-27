package net.minecraft.godot.renderpearl;

import java.util.HashMap;
import java.util.Map;

/**
 * Engine-neutral ownership and handle registry for Godot-backed RenderPearl
 * resources. The native executor receives only numeric handles; Java retains
 * lifecycle checks so stale/cross-device resources cannot produce commands.
 */
final class GodotRenderResourceRegistry {
    enum Kind {
        BUFFER,
        TEXTURE,
        TEXTURE_VIEW,
        SAMPLER,
        PIPELINE,
    }

    static final class Handle {
        private final GodotRenderResourceRegistry owner;
        private final Kind kind;
        private final int id;
        private boolean closed;

        private Handle(GodotRenderResourceRegistry owner, Kind kind, int id) {
            this.owner = owner;
            this.kind = kind;
            this.id = id;
        }

        int id() {
            owner.requireOpen(this, kind);
            return id;
        }

        /** Identifier retained after close so a view can still name its source texture. */
        int rawId() {
            return id;
        }

        Kind kind() {
            return kind;
        }

        boolean isClosed() {
            return closed;
        }
    }

    private final Map<Integer, Handle> liveHandles = new HashMap<>();
    private int nextId = 1;

    synchronized Handle allocate(Kind kind) {
        if (nextId <= 0) {
            throw new IllegalStateException("Render resource handle space exhausted");
        }
        Handle handle = new Handle(this, kind, nextId++);
        liveHandles.put(handle.id, handle);
        return handle;
    }

    synchronized void close(Handle handle) {
        requireOwned(handle);
        if (handle.closed) {
            return;
        }
        Handle removed = liveHandles.remove(handle.id);
        if (removed != handle) {
            throw new IllegalStateException("Render resource registry lost handle " + handle.id);
        }
        handle.closed = true;
    }

    synchronized void requireOpen(Handle handle, Kind expectedKind) {
        requireOwned(handle);
        if (handle.kind != expectedKind) {
            throw new IllegalArgumentException(
                    "Expected " + expectedKind + " handle, received " + handle.kind
            );
        }
        if (handle.closed || liveHandles.get(handle.id) != handle) {
            throw new IllegalStateException("Render resource handle " + handle.id + " is closed");
        }
    }

    synchronized int liveCount() {
        return liveHandles.size();
    }

    private void requireOwned(Handle handle) {
        if (handle == null || handle.owner != this) {
            throw new IllegalArgumentException("Render resource belongs to a different device");
        }
    }
}
