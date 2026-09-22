package net.minecraft.godot.renderpearl;

/**
 * Numeric protocol shared with minecraft_render_abi.h.
 *
 * This package deliberately has no Godot dependency. A future implementation
 * of Minecraft's RenderPearl GpuDevice/CommandEncoder emits these operations;
 * the native GDExtension is the only layer allowed to translate them to Godot.
 */
public final class RenderCommandProtocol {
    public static final int ABI_VERSION = 1;
    public static final int PACKET_ALIGNMENT = 8;
    public static final int HEADER_BYTES = 8;

    public static final int FRAME_BEGIN = 1;
    public static final int FRAME_END = 2;
    public static final int CREATE_BUFFER = 3;
    public static final int DESTROY_BUFFER = 4;
    public static final int WRITE_BUFFER = 5;
    public static final int CREATE_TEXTURE = 6;
    public static final int DESTROY_TEXTURE = 7;
    public static final int WRITE_TEXTURE = 8;
    public static final int CREATE_SAMPLER = 9;
    public static final int DESTROY_SAMPLER = 10;
    public static final int COMPILE_PIPELINE = 11;
    public static final int DESTROY_PIPELINE = 12;
    public static final int BEGIN_RENDER_PASS = 13;
    public static final int END_RENDER_PASS = 14;
    public static final int SET_PIPELINE = 15;
    public static final int SET_VERTEX_BUFFER = 16;
    public static final int SET_INDEX_BUFFER = 17;
    public static final int SET_UNIFORM_BUFFER = 18;
    public static final int SET_TEXTURE_SAMPLER = 19;
    public static final int SET_SCISSOR = 20;
    public static final int DRAW = 21;
    public static final int DRAW_INDEXED = 22;

    private RenderCommandProtocol() {
    }

    public static int alignedPacketSize(int rawSize) {
        if (rawSize < HEADER_BYTES || rawSize > Integer.MAX_VALUE - (PACKET_ALIGNMENT - 1)) {
            throw new IllegalArgumentException("Invalid render packet size: " + rawSize);
        }
        return (rawSize + (PACKET_ALIGNMENT - 1)) & -PACKET_ALIGNMENT;
    }
}
