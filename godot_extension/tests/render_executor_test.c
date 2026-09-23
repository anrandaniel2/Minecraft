#include "minecraft_render_executor.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

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

static void write_u64_le(uint8_t *bytes, uint64_t value) {
    write_u32_le(bytes, (uint32_t)value);
    write_u32_le(bytes + 4, (uint32_t)(value >> 32));
}

static void write_f32_le(uint8_t *bytes, float value) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    write_u32_le(bytes, bits);
}

static void write_f64_le(uint8_t *bytes, double value) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof(bits));
    write_u64_le(bytes, bits);
}

static uint8_t *append_packet(uint8_t *frame, size_t *offset, uint16_t opcode, uint32_t size) {
    uint8_t *packet = frame + *offset;
    memset(packet, 0, size);
    write_u16_le(packet, opcode);
    write_u16_le(packet + 2, 0);
    write_u32_le(packet + 4, size);
    *offset += size;
    return packet + MINECRAFT_RENDER_PACKET_HEADER_BYTES;
}

typedef struct Recorder {
    int calls;
    uint64_t frame_id;
    uint32_t width;
    uint32_t height;
    uint32_t buffer_id;
    uint64_t write_offset;
    uint32_t texture_id;
    uint32_t draw_index_count;
    int32_t vertex_offset;
} Recorder;

static bool frame_begin(void *data, uint64_t frame_id, uint32_t width, uint32_t height) {
    Recorder *recorder = data;
    recorder->calls++;
    recorder->frame_id = frame_id;
    recorder->width = width;
    recorder->height = height;
    return true;
}

static bool frame_end(void *data) {
    ((Recorder *)data)->calls++;
    return true;
}

static bool create_buffer(void *data, uint32_t buffer_id, uint32_t usage, uint64_t size) {
    Recorder *recorder = data;
    recorder->calls++;
    recorder->buffer_id = buffer_id;
    return usage == 0x10u && size == 128u;
}

static bool write_buffer(void *data, uint32_t buffer_id, uint64_t offset,
                         const uint8_t *bytes, uint32_t size) {
    Recorder *recorder = data;
    recorder->calls++;
    recorder->write_offset = offset;
    return buffer_id == 7u && size == 4u &&
           bytes[0] == 1u && bytes[1] == 2u && bytes[2] == 3u && bytes[3] == 4u;
}

static bool create_texture(void *data, uint32_t texture_id, uint32_t usage, uint32_t format,
                           uint32_t width, uint32_t height, uint32_t depth, uint32_t mip_levels) {
    Recorder *recorder = data;
    recorder->calls++;
    recorder->texture_id = texture_id;
    return usage == 8u && format == 6u && width == 640u && height == 360u &&
           depth == 1u && mip_levels == 1u;
}

static bool begin_render_pass(void *data, uint32_t color_id, uint32_t depth_id,
                              float red, float green, float blue, float alpha, double depth) {
    Recorder *recorder = data;
    recorder->calls++;
    return color_id == 8u && depth_id == 0u && red == 0.25f && green == 0.5f &&
           blue == 0.75f && alpha == 1.0f && depth == 0.0;
}

static bool end_render_pass(void *data) {
    ((Recorder *)data)->calls++;
    return true;
}

static bool set_vertex_buffer(void *data, uint32_t slot, uint32_t buffer_id,
                              uint64_t offset, uint64_t length) {
    Recorder *recorder = data;
    recorder->calls++;
    return slot == 0u && buffer_id == 7u && offset == 4u && length == 32u;
}

static bool set_scissor(void *data, uint32_t x, uint32_t y, uint32_t width, uint32_t height) {
    Recorder *recorder = data;
    recorder->calls++;
    return x == 2u && y == 3u && width == 600u && height == 300u;
}

static bool draw_indexed(void *data, uint32_t index_count, uint32_t instance_count,
                         uint32_t first_index, int32_t vertex_offset, uint32_t first_instance) {
    Recorder *recorder = data;
    recorder->calls++;
    recorder->draw_index_count = index_count;
    recorder->vertex_offset = vertex_offset;
    return index_count == 36u && instance_count == 1u && first_index == 0u &&
           vertex_offset == -2 && first_instance == 0u;
}

int main(void) {
    uint8_t bytes[256] = {0};
    size_t size = 0;
    uint8_t *payload = append_packet(bytes, &size, MINECRAFT_RENDER_FRAME_BEGIN, 24u);
    write_u64_le(payload, 91u);
    write_u32_le(payload + 8, 640u);
    write_u32_le(payload + 12, 360u);

    payload = append_packet(bytes, &size, MINECRAFT_RENDER_CREATE_BUFFER, 24u);
    write_u32_le(payload, 7u);
    write_u32_le(payload + 4, 0x10u);
    write_u64_le(payload + 8, 128u);

    payload = append_packet(bytes, &size, MINECRAFT_RENDER_WRITE_BUFFER, 32u);
    write_u32_le(payload, 7u);
    write_u64_le(payload + 4, 4u);
    write_u32_le(payload + 12, 4u);
    payload[16] = 1u;
    payload[17] = 2u;
    payload[18] = 3u;
    payload[19] = 4u;

    payload = append_packet(bytes, &size, MINECRAFT_RENDER_CREATE_TEXTURE, 40u);
    write_u32_le(payload, 8u);
    write_u32_le(payload + 4, 8u);
    write_u32_le(payload + 8, 6u);
    write_u32_le(payload + 12, 640u);
    write_u32_le(payload + 16, 360u);
    write_u32_le(payload + 20, 1u);
    write_u32_le(payload + 24, 1u);

    payload = append_packet(bytes, &size, MINECRAFT_RENDER_BEGIN_RENDER_PASS, 40u);
    write_u32_le(payload, 8u);
    write_u32_le(payload + 4, 0u);
    write_f32_le(payload + 8, 0.25f);
    write_f32_le(payload + 12, 0.5f);
    write_f32_le(payload + 16, 0.75f);
    write_f32_le(payload + 20, 1.0f);
    write_f64_le(payload + 24, 0.0);

    payload = append_packet(bytes, &size, MINECRAFT_RENDER_SET_VERTEX_BUFFER, 32u);
    write_u32_le(payload, 0u);
    write_u32_le(payload + 4, 7u);
    write_u64_le(payload + 8, 4u);
    write_u64_le(payload + 16, 32u);

    payload = append_packet(bytes, &size, MINECRAFT_RENDER_SET_SCISSOR, 24u);
    write_u32_le(payload, 2u);
    write_u32_le(payload + 4, 3u);
    write_u32_le(payload + 8, 600u);
    write_u32_le(payload + 12, 300u);

    payload = append_packet(bytes, &size, MINECRAFT_RENDER_DRAW_INDEXED, 32u);
    write_u32_le(payload, 36u);
    write_u32_le(payload + 4, 1u);
    write_u32_le(payload + 8, 0u);
    write_u32_le(payload + 12, UINT32_MAX - 1u);
    write_u32_le(payload + 16, 0u);

    append_packet(bytes, &size, MINECRAFT_RENDER_END_RENDER_PASS, 8u);
    append_packet(bytes, &size, MINECRAFT_RENDER_FRAME_END, 8u);

    MinecraftRenderFrame frame = {.bytes = bytes, .size = size};
    MinecraftRenderCommandSink sink = {
        .frame_begin = frame_begin,
        .frame_end = frame_end,
        .create_buffer = create_buffer,
        .write_buffer = write_buffer,
        .create_texture = create_texture,
        .begin_render_pass = begin_render_pass,
        .end_render_pass = end_render_pass,
        .set_vertex_buffer = set_vertex_buffer,
        .set_scissor = set_scissor,
        .draw_indexed = draw_indexed,
    };
    Recorder recorder = {0};
    int result = minecraft_render_execute_frame(&frame, &sink, &recorder);
    if (result != 10 || recorder.calls != 10 || recorder.frame_id != 91u ||
            recorder.width != 640u || recorder.height != 360u || recorder.buffer_id != 7u ||
            recorder.write_offset != 4u || recorder.texture_id != 8u ||
            recorder.draw_index_count != 36u || recorder.vertex_offset != -2) {
        fprintf(stderr, "typed RenderPearl command dispatch failed: result=%d calls=%d\n",
                result, recorder.calls);
        return 1;
    }

    MinecraftRenderCommandSink incomplete_sink = {0};
    result = minecraft_render_execute_frame(&frame, &incomplete_sink, &recorder);
    if (result != MINECRAFT_RENDER_UNSUPPORTED_COMMAND) {
        fprintf(stderr, "missing command callback returned %d\n", result);
        return 1;
    }

    if (minecraft_render_execute_frame(NULL, &sink, &recorder) != MINECRAFT_RENDER_INVALID_ARGUMENT ||
            minecraft_render_execute_frame(&frame, NULL, &recorder) != MINECRAFT_RENDER_INVALID_ARGUMENT) {
        fprintf(stderr, "invalid executor arguments were accepted\n");
        return 1;
    }
    return 0;
}
