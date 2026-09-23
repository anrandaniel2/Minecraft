#include "minecraft_render_native_state.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

static void u16(uint8_t *p, uint16_t value) {
    p[0] = (uint8_t)value;
    p[1] = (uint8_t)(value >> 8);
}

static void u32(uint8_t *p, uint32_t value) {
    p[0] = (uint8_t)value;
    p[1] = (uint8_t)(value >> 8);
    p[2] = (uint8_t)(value >> 16);
    p[3] = (uint8_t)(value >> 24);
}

static void u64(uint8_t *p, uint64_t value) {
    u32(p, (uint32_t)value);
    u32(p + 4, (uint32_t)(value >> 32));
}

static void f32(uint8_t *p, float value) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    u32(p, bits);
}

static void f64(uint8_t *p, double value) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof(bits));
    u64(p, bits);
}

static uint8_t *packet(uint8_t *frame, size_t *offset, uint16_t opcode, uint32_t size) {
    uint8_t *result = frame + *offset;
    memset(result, 0, size);
    u16(result, opcode);
    u32(result + 4, size);
    *offset += size;
    return result + MINECRAFT_RENDER_PACKET_HEADER_BYTES;
}

static void begin_frame(uint8_t *frame, size_t *size, uint64_t id) {
    uint8_t *p = packet(frame, size, MINECRAFT_RENDER_FRAME_BEGIN, 24u);
    u64(p, id);
    u32(p + 8, 64u);
    u32(p + 12, 64u);
}

static void begin_pass(uint8_t *frame, size_t *size, uint32_t texture_id) {
    uint8_t *p = packet(frame, size, MINECRAFT_RENDER_BEGIN_RENDER_PASS, 40u);
    u32(p, texture_id);
    f32(p + 8, 0.0f);
    f32(p + 12, 0.0f);
    f32(p + 16, 0.0f);
    f32(p + 20, 1.0f);
    f64(p + 24, 0.0);
}

static void end_frame(uint8_t *frame, size_t *size) {
    packet(frame, size, MINECRAFT_RENDER_END_RENDER_PASS, 8u);
    packet(frame, size, MINECRAFT_RENDER_FRAME_END, 8u);
}

int main(void) {
    MinecraftRenderNativeState *state = minecraft_render_native_state_create();
    if (state == NULL || minecraft_render_native_execute_latest(state) != MINECRAFT_RENDER_NO_FRAME) {
        fprintf(stderr, "native state did not initialize as an idle mailbox consumer\n");
        minecraft_render_native_state_destroy(state);
        return 1;
    }

    uint8_t valid[320] = {0};
    size_t valid_size = 0;
    begin_frame(valid, &valid_size, 1u);
    uint8_t *p = packet(valid, &valid_size, MINECRAFT_RENDER_CREATE_BUFFER, 24u);
    u32(p, 7u);
    u32(p + 4, 0x10u);
    u64(p + 8, 64u);
    p = packet(valid, &valid_size, MINECRAFT_RENDER_WRITE_BUFFER, 32u);
    u32(p, 7u);
    u32(p + 12, 4u);
    p[16] = 9u;
    p[17] = 8u;
    p[18] = 7u;
    p[19] = 6u;
    p = packet(valid, &valid_size, MINECRAFT_RENDER_CREATE_TEXTURE, 40u);
    u32(p, 3u);
    u32(p + 4, 8u);
    u32(p + 8, 6u);
    u32(p + 12, 64u);
    u32(p + 16, 64u);
    u32(p + 20, 1u);
    u32(p + 24, 1u);
    p = packet(valid, &valid_size, MINECRAFT_RENDER_WRITE_TEXTURE, 48u);
    u32(p, 3u);
    u32(p + 4, 1u);
    u32(p + 8, 1u);
    u32(p + 12, 1u);
    u32(p + 28, 4u);
    p[32] = 1u;
    p[33] = 2u;
    p[34] = 3u;
    p[35] = 4u;
    begin_pass(valid, &valid_size, 3u);
    p = packet(valid, &valid_size, MINECRAFT_RENDER_SET_VERTEX_BUFFER, 32u);
    u32(p + 4, 7u);
    u64(p + 16, 4u);
    p = packet(valid, &valid_size, MINECRAFT_RENDER_DRAW, 24u);
    u32(p, 3u);
    u32(p + 4, 1u);
    end_frame(valid, &valid_size);

    int result = minecraft_render_submit_frame(valid, valid_size);
    if (result != 10 || minecraft_render_native_execute_latest(state) != 10 ||
            minecraft_render_native_buffer_count(state) != 1 ||
            minecraft_render_native_texture_count(state) != 1) {
        fprintf(stderr, "native state rejected a valid resource-backed frame\n");
        minecraft_render_native_state_destroy(state);
        return 1;
    }

    uint8_t invalid[128] = {0};
    size_t invalid_size = 0;
    begin_frame(invalid, &invalid_size, 2u);
    begin_pass(invalid, &invalid_size, 99u); /* Unknown color attachment. */
    end_frame(invalid, &invalid_size);
    if (minecraft_render_submit_frame(invalid, invalid_size) != 4 ||
            minecraft_render_native_execute_latest(state) != MINECRAFT_RENDER_INVALID_ARGUMENT ||
            minecraft_render_native_last_execution_status(state) != MINECRAFT_RENDER_INVALID_ARGUMENT) {
        fprintf(stderr, "native state accepted an unknown render-pass attachment\n");
        minecraft_render_native_state_destroy(state);
        return 1;
    }

    uint8_t recovery[128] = {0};
    size_t recovery_size = 0;
    begin_frame(recovery, &recovery_size, 3u);
    begin_pass(recovery, &recovery_size, 3u);
    packet(recovery, &recovery_size, MINECRAFT_RENDER_DRAW, 24u);
    end_frame(recovery, &recovery_size);
    if (minecraft_render_submit_frame(recovery, recovery_size) != 5 ||
            minecraft_render_native_execute_latest(state) != 5) {
        fprintf(stderr, "native state did not recover after rejecting a frame\n");
        minecraft_render_native_state_destroy(state);
        return 1;
    }

    minecraft_render_native_state_destroy(state);
    return 0;
}
