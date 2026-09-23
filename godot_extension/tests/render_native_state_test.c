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
            minecraft_render_native_texture_count(state) != 1 ||
            minecraft_render_native_buffer_attribute_at(
                    state, 0, MINECRAFT_RENDER_BUFFER_ATTRIBUTE_ID
            ) != 7u ||
            minecraft_render_native_buffer_attribute_at(
                    state, 0, MINECRAFT_RENDER_BUFFER_ATTRIBUTE_SIZE
            ) != 64u ||
            minecraft_render_native_buffer_attribute_at(
                    state, 0, MINECRAFT_RENDER_BUFFER_ATTRIBUTE_REVISION
            ) == 0 ||
            minecraft_render_native_texture_attribute_at(
                    state, 0, MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_ID
            ) != 3u ||
            minecraft_render_native_texture_attribute_at(
                    state, 0, MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_WIDTH
            ) != 64u ||
            minecraft_render_native_texture_upload_count(state, 3u) != 1 ||
            minecraft_render_native_texture_uploaded_bytes(state, 3u) != 4u ||
            minecraft_render_native_pass_attribute(
                    state, MINECRAFT_RENDER_PASS_ATTRIBUTE_COLOR_TEXTURE_ID
            ) != 3u ||
            minecraft_render_native_pass_attribute(
                    state, MINECRAFT_RENDER_PASS_ATTRIBUTE_DRAW_COUNT
            ) != 1u ||
            minecraft_render_native_pass_attribute(
                    state, MINECRAFT_RENDER_PASS_ATTRIBUTE_REVISION
            ) == 0u ||
            minecraft_render_native_pass_attribute(
                    state, MINECRAFT_RENDER_PASS_ATTRIBUTE_CLEAR_ALPHA_BITS
            ) != 0x3f800000u) {
        fprintf(stderr, "native state rejected a valid resource-backed frame\n");
        minecraft_render_native_state_destroy(state);
        return 1;
    }

    /* Device declaration preludes repeat each frame. Matching descriptors
     * must preserve CPU mirrors instead of silently clearing prior writes. */
    uint8_t declarations[192] = {0};
    size_t declarations_size = 0;
    begin_frame(declarations, &declarations_size, 2u);
    p = packet(declarations, &declarations_size, MINECRAFT_RENDER_CREATE_BUFFER, 24u);
    u32(p, 7u);
    u32(p + 4, 0x10u);
    u64(p + 8, 64u);
    p = packet(declarations, &declarations_size, MINECRAFT_RENDER_CREATE_TEXTURE, 40u);
    u32(p, 3u);
    u32(p + 4, 8u);
    u32(p + 8, 6u);
    u32(p + 12, 64u);
    u32(p + 16, 64u);
    u32(p + 20, 1u);
    u32(p + 24, 1u);
    begin_pass(declarations, &declarations_size, 3u);
    p = packet(declarations, &declarations_size, MINECRAFT_RENDER_DRAW, 24u);
    u32(p, 3u);
    u32(p + 4, 1u);
    end_frame(declarations, &declarations_size);
    if (minecraft_render_submit_frame(declarations, declarations_size) != 7 ||
            minecraft_render_native_execute_latest(state) != 7) {
        fprintf(stderr, "native state rejected a repeated resource declaration\n");
        minecraft_render_native_state_destroy(state);
        return 1;
    }

    uint8_t retained_buffer[4] = {0};
    uint8_t retained_texture[4] = {0};
    if (minecraft_render_native_copy_buffer_bytes(state, 7u, 0u, retained_buffer,
            sizeof(retained_buffer)) != sizeof(retained_buffer) ||
            memcmp(retained_buffer, (uint8_t[]) {9u, 8u, 7u, 6u}, sizeof(retained_buffer)) != 0 ||
            minecraft_render_native_texture_mip_layer_size(state, 3u, 0u, 0u) != 64u * 64u * 4u ||
            minecraft_render_native_copy_texture_mip_layer_bytes(state, 3u, 0u, 0u, 0u,
                    retained_texture, sizeof(retained_texture)) != sizeof(retained_texture) ||
            memcmp(retained_texture, (uint8_t[]) {1u, 2u, 3u, 4u}, sizeof(retained_texture)) != 0) {
        fprintf(stderr, "native state did not expose retained buffer/texture bytes\n");
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

    uint8_t recovery[192] = {0};
    size_t recovery_size = 0;
    begin_frame(recovery, &recovery_size, 3u);
    p = packet(recovery, &recovery_size, MINECRAFT_RENDER_WRITE_TEXTURE, 48u);
    u32(p, 3u);
    u32(p + 4, 1u);
    u32(p + 8, 1u);
    u32(p + 12, 1u);
    u32(p + 28, 4u);
    p[32] = 5u;
    p[33] = 6u;
    p[34] = 7u;
    p[35] = 8u;
    begin_pass(recovery, &recovery_size, 3u);
    packet(recovery, &recovery_size, MINECRAFT_RENDER_DRAW, 24u);
    end_frame(recovery, &recovery_size);
    if (minecraft_render_submit_frame(recovery, recovery_size) != 6 ||
            minecraft_render_native_execute_latest(state) != 6 ||
            minecraft_render_native_texture_upload_count(state, 3u) != 1 ||
            minecraft_render_native_texture_uploaded_bytes(state, 3u) != 4u) {
        fprintf(stderr, "native state did not recover after rejecting a frame\n");
        minecraft_render_native_state_destroy(state);
        return 1;
    }

    /* The Godot texture bridge receives full mip/layer bytes. Verify that it
     * composites retained upload regions in packet order when they overlap. */
    uint8_t overlap[256] = {0};
    size_t overlap_size = 0;
    begin_frame(overlap, &overlap_size, 4u);
    p = packet(overlap, &overlap_size, MINECRAFT_RENDER_WRITE_TEXTURE, 48u);
    u32(p, 3u);
    u32(p + 4, 2u);
    u32(p + 8, 1u);
    u32(p + 12, 1u);
    u32(p + 16, 1u);
    u32(p + 28, 8u);
    memcpy(p + 32, (uint8_t[]) {10u, 11u, 12u, 13u, 14u, 15u, 16u, 17u}, 8u);
    p = packet(overlap, &overlap_size, MINECRAFT_RENDER_WRITE_TEXTURE, 48u);
    u32(p, 3u);
    u32(p + 4, 1u);
    u32(p + 8, 1u);
    u32(p + 12, 1u);
    u32(p + 16, 2u);
    u32(p + 28, 4u);
    memcpy(p + 32, (uint8_t[]) {21u, 22u, 23u, 24u}, 4u);
    begin_pass(overlap, &overlap_size, 3u);
    p = packet(overlap, &overlap_size, MINECRAFT_RENDER_DRAW, 24u);
    u32(p, 3u);
    u32(p + 4, 1u);
    end_frame(overlap, &overlap_size);
    uint8_t composited[12] = {0};
    if (minecraft_render_submit_frame(overlap, overlap_size) != 7 ||
            minecraft_render_native_execute_latest(state) != 7 ||
            minecraft_render_native_copy_texture_mip_layer_bytes(state, 3u, 0u, 0u, 0u,
                    composited, sizeof(composited)) != sizeof(composited) ||
            memcmp(composited,
                    (uint8_t[]) {5u, 6u, 7u, 8u, 10u, 11u, 12u, 13u, 21u, 22u, 23u, 24u},
                    sizeof(composited)) != 0) {
        fprintf(stderr, "native texture bridge did not preserve upload ordering\n");
        minecraft_render_native_state_destroy(state);
        return 1;
    }

    uint8_t mip_frame[192] = {0};
    size_t mip_frame_size = 0;
    begin_frame(mip_frame, &mip_frame_size, 5u);
    p = packet(mip_frame, &mip_frame_size, MINECRAFT_RENDER_CREATE_TEXTURE, 40u);
    u32(p, 4u);
    u32(p + 4, 8u);
    u32(p + 8, 6u);
    u32(p + 12, 4u);
    u32(p + 16, 4u);
    u32(p + 20, 1u);
    u32(p + 24, 2u);
    p = packet(mip_frame, &mip_frame_size, MINECRAFT_RENDER_WRITE_TEXTURE, 48u);
    u32(p, 4u);
    u32(p + 4, 1u);
    u32(p + 8, 1u);
    u32(p + 12, 1u);
    u32(p + 24, 1u);
    u32(p + 28, 4u);
    memcpy(p + 32, (uint8_t[]) {9u, 8u, 7u, 6u}, 4u);
    begin_pass(mip_frame, &mip_frame_size, 4u);
    p = packet(mip_frame, &mip_frame_size, MINECRAFT_RENDER_DRAW, 24u);
    u32(p, 3u);
    u32(p + 4, 1u);
    end_frame(mip_frame, &mip_frame_size);
    uint8_t mip0[4] = {0};
    uint8_t mip1[8] = {0};
    if (minecraft_render_submit_frame(mip_frame, mip_frame_size) != 7 ||
            minecraft_render_native_execute_latest(state) != 7 ||
            minecraft_render_native_texture_mip_layer_size(state, 4u, 0u, 0u) != 64u ||
            minecraft_render_native_texture_mip_layer_size(state, 4u, 1u, 0u) != 16u ||
            minecraft_render_native_copy_texture_mip_layer_bytes(state, 4u, 0u, 0u, 0u,
                    mip0, sizeof(mip0)) != sizeof(mip0) ||
            memcmp(mip0, (uint8_t[]) {0u, 0u, 0u, 0u}, sizeof(mip0)) != 0 ||
            minecraft_render_native_copy_texture_mip_layer_bytes(state, 4u, 1u, 0u, 0u,
                    mip1, sizeof(mip1)) != sizeof(mip1) ||
            memcmp(mip1, (uint8_t[]) {9u, 8u, 7u, 6u, 0u, 0u, 0u, 0u}, sizeof(mip1)) != 0) {
        fprintf(stderr, "native texture bridge mixed mip levels\n");
        minecraft_render_native_state_destroy(state);
        return 1;
    }

    minecraft_render_native_state_destroy(state);
    return 0;
}
