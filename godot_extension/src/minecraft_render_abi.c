#include "minecraft_render_abi.h"

#include <limits.h>
#include <string.h>

static bool is_known_opcode(uint16_t opcode) {
    return opcode >= MINECRAFT_RENDER_FRAME_BEGIN && opcode <= MINECRAFT_RENDER_DRAW_INDEXED;
}

static bool is_draw_opcode(uint16_t opcode) {
    return opcode == MINECRAFT_RENDER_DRAW || opcode == MINECRAFT_RENDER_DRAW_INDEXED;
}

static bool is_pass_command(uint16_t opcode) {
    return opcode == MINECRAFT_RENDER_SET_PIPELINE ||
           opcode == MINECRAFT_RENDER_SET_VERTEX_BUFFER ||
           opcode == MINECRAFT_RENDER_SET_INDEX_BUFFER ||
           opcode == MINECRAFT_RENDER_SET_UNIFORM_BUFFER ||
           opcode == MINECRAFT_RENDER_SET_TEXTURE_SAMPLER ||
           opcode == MINECRAFT_RENDER_SET_SCISSOR ||
           is_draw_opcode(opcode);
}

int minecraft_render_visit_frame(
    const uint8_t *frame_bytes,
    size_t frame_size,
    MinecraftRenderPacketVisitor visitor,
    void *user_data
) {
    if (frame_bytes == NULL || visitor == NULL || frame_size == 0) {
        return MINECRAFT_RENDER_INVALID_ARGUMENT;
    }

    size_t offset = 0;
    int packet_count = 0;
    bool frame_open = false;
    bool frame_closed = false;
    bool render_pass_open = false;

    while (offset < frame_size) {
        if (frame_size - offset < sizeof(MinecraftRenderPacketHeader)) {
            return MINECRAFT_RENDER_TRUNCATED_PACKET;
        }

        MinecraftRenderPacketHeader header;
        memcpy(&header, frame_bytes + offset, sizeof(header));
        if (header.packet_size < sizeof(header) ||
            (header.packet_size % MINECRAFT_RENDER_PACKET_ALIGNMENT) != 0) {
            return MINECRAFT_RENDER_BAD_ALIGNMENT;
        }
        if ((size_t)header.packet_size > frame_size - offset) {
            return MINECRAFT_RENDER_TRUNCATED_PACKET;
        }
        if (!is_known_opcode(header.opcode)) {
            return MINECRAFT_RENDER_UNKNOWN_OPCODE;
        }

        switch (header.opcode) {
            case MINECRAFT_RENDER_FRAME_BEGIN:
                if (frame_open || frame_closed || render_pass_open || offset != 0) {
                    return MINECRAFT_RENDER_BAD_FRAME_ORDER;
                }
                frame_open = true;
                break;
            case MINECRAFT_RENDER_FRAME_END:
                if (!frame_open || frame_closed || render_pass_open ||
                    offset + header.packet_size != frame_size) {
                    return MINECRAFT_RENDER_BAD_FRAME_ORDER;
                }
                frame_closed = true;
                break;
            case MINECRAFT_RENDER_BEGIN_RENDER_PASS:
                if (!frame_open || frame_closed || render_pass_open) {
                    return MINECRAFT_RENDER_BAD_FRAME_ORDER;
                }
                render_pass_open = true;
                break;
            case MINECRAFT_RENDER_END_RENDER_PASS:
                if (!frame_open || frame_closed || !render_pass_open) {
                    return MINECRAFT_RENDER_BAD_FRAME_ORDER;
                }
                render_pass_open = false;
                break;
            default:
                if (!frame_open || frame_closed) {
                    return MINECRAFT_RENDER_BAD_FRAME_ORDER;
                }
                if (is_pass_command(header.opcode) != render_pass_open) {
                    return MINECRAFT_RENDER_BAD_FRAME_ORDER;
                }
                break;
        }

        if (!visitor(&header, frame_bytes + offset, user_data)) {
            return MINECRAFT_RENDER_VISITOR_REJECTED;
        }
        if (packet_count == INT_MAX) {
            return MINECRAFT_RENDER_INVALID_ARGUMENT;
        }
        packet_count++;
        offset += header.packet_size;
    }

    if (!frame_open || !frame_closed || render_pass_open) {
        return MINECRAFT_RENDER_BAD_FRAME_ORDER;
    }
    return packet_count;
}
