#include "minecraft_render_abi.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

_Static_assert(sizeof(MinecraftRenderPacketHeader) == 8, "render ABI packet header must remain 8 bytes");

static void write_u16_le(uint8_t *bytes, uint16_t value) {
    bytes[0] = (uint8_t)value;
    bytes[1] = (uint8_t)(value >> 8);
}

static void write_u32_le(uint8_t *bytes, uint32_t value) {
    bytes[0] = (uint8_t)value;
    bytes[1] = (uint8_t)(value >> 8);
    bytes[2] = (uint8_t)(value >> 16);
    bytes[3] = (uint8_t)(value >> 24);
}

static void append_packet(uint8_t *bytes, size_t *offset, uint16_t opcode) {
    write_u16_le(bytes + *offset, opcode);
    write_u16_le(bytes + *offset + 2, 0);
    write_u32_le(bytes + *offset + 4, sizeof(MinecraftRenderPacketHeader));
    *offset += sizeof(MinecraftRenderPacketHeader);
}

static bool count_packet(
    const MinecraftRenderPacketHeader *header,
    const uint8_t *packet_bytes,
    void *user_data
) {
    int *count = user_data;
    if (header == NULL || packet_bytes == NULL) {
        return false;
    }
    (*count)++;
    return true;
}

int main(void) {
    uint8_t frame[7 * sizeof(MinecraftRenderPacketHeader)] = {0};
    size_t size = 0;
    append_packet(frame, &size, MINECRAFT_RENDER_FRAME_BEGIN);
    append_packet(frame, &size, MINECRAFT_RENDER_CREATE_BUFFER);
    append_packet(frame, &size, MINECRAFT_RENDER_BEGIN_RENDER_PASS);
    append_packet(frame, &size, MINECRAFT_RENDER_SET_PIPELINE);
    append_packet(frame, &size, MINECRAFT_RENDER_DRAW_INDEXED);
    append_packet(frame, &size, MINECRAFT_RENDER_END_RENDER_PASS);
    append_packet(frame, &size, MINECRAFT_RENDER_FRAME_END);

    int visitor_count = 0;
    int result = minecraft_render_visit_frame(frame, size, count_packet, &visitor_count);
    if (result != 7 || visitor_count != 7) {
        fprintf(stderr, "valid frame was rejected: result=%d, visited=%d\n", result, visitor_count);
        return 1;
    }

    /* The Java producer can submit a complete frame from another thread; the
     * native mailbox keeps an owned, stable copy for a Godot render thread. */
    result = minecraft_render_submit_frame(frame, size);
    if (result != 7 || minecraft_render_last_submission_status() != 7 ||
            minecraft_render_latest_frame_size() != size) {
        fprintf(stderr, "valid frame was not stored in mailbox\n");
        return 1;
    }
    uint8_t copied_frame[sizeof(frame)] = {0};
    if (minecraft_render_copy_latest_frame(copied_frame, sizeof(copied_frame)) != size ||
            memcmp(frame, copied_frame, size) != 0) {
        fprintf(stderr, "mailbox changed the submitted frame\n");
        return 1;
    }

    /* Draw commands must be emitted only inside a render pass. */
    uint8_t invalid_draw[sizeof(MinecraftRenderPacketHeader)] = {0};
    size_t invalid_draw_size = 0;
    append_packet(invalid_draw, &invalid_draw_size, MINECRAFT_RENDER_DRAW);
    result = minecraft_render_visit_frame(
        invalid_draw,
        invalid_draw_size,
        count_packet,
        &visitor_count
    );
    if (result != MINECRAFT_RENDER_BAD_FRAME_ORDER) {
        fprintf(stderr, "out-of-pass draw returned %d\n", result);
        return 1;
    }
    result = minecraft_render_submit_frame(invalid_draw, invalid_draw_size);
    if (result != MINECRAFT_RENDER_BAD_FRAME_ORDER ||
            minecraft_render_last_submission_status() != MINECRAFT_RENDER_BAD_FRAME_ORDER ||
            minecraft_render_latest_frame_size() != size) {
        fprintf(stderr, "invalid mailbox submission overwrote valid frame\n");
        return 1;
    }

    /* The render thread detaches ownership before executing the packets. This
     * prevents a concurrent Java submission from mutating the frame being
     * consumed by the Godot-side executor. */
    MinecraftRenderFrame owned_frame = {0};
    result = minecraft_render_take_latest_frame(&owned_frame);
    if (result != 7 || owned_frame.size != size || owned_frame.bytes == NULL ||
            memcmp(owned_frame.bytes, frame, size) != 0 ||
            minecraft_render_latest_frame_size() != 0) {
        fprintf(stderr, "mailbox did not atomically detach the valid frame\n");
        minecraft_render_release_frame(&owned_frame);
        return 1;
    }
    minecraft_render_release_frame(&owned_frame);
    if (owned_frame.bytes != NULL || owned_frame.size != 0 ||
            minecraft_render_take_latest_frame(&owned_frame) != MINECRAFT_RENDER_NO_FRAME ||
            minecraft_render_take_latest_frame(NULL) != MINECRAFT_RENDER_INVALID_ARGUMENT) {
        fprintf(stderr, "mailbox frame ownership/release contract failed\n");
        return 1;
    }

    /* Packet payloads have to preserve the ABI's eight-byte alignment. */
    uint8_t invalid_alignment[sizeof(MinecraftRenderPacketHeader)] = {0};
    size_t invalid_alignment_size = 0;
    append_packet(invalid_alignment, &invalid_alignment_size, MINECRAFT_RENDER_FRAME_BEGIN);
    write_u32_le(invalid_alignment + 4, sizeof(MinecraftRenderPacketHeader) + 1);
    result = minecraft_render_visit_frame(
        invalid_alignment,
        invalid_alignment_size,
        count_packet,
        &visitor_count
    );
    if (result != MINECRAFT_RENDER_BAD_ALIGNMENT) {
        fprintf(stderr, "misaligned packet returned %d\n", result);
        return 1;
    }

    minecraft_render_clear_latest_frame();
    if (minecraft_render_latest_frame_size() != 0) {
        fprintf(stderr, "mailbox clear left frame data behind\n");
        return 1;
    }
    return 0;
}
