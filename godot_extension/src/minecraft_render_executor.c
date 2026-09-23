#include "minecraft_render_executor.h"

#include <limits.h>
#include <string.h>

typedef struct MinecraftRenderExecutionState {
    const MinecraftRenderCommandSink *sink;
    void *user_data;
    int result;
} MinecraftRenderExecutionState;

static uint32_t read_u32_le(const uint8_t *bytes) {
    return (uint32_t)bytes[0] |
           ((uint32_t)bytes[1] << 8) |
           ((uint32_t)bytes[2] << 16) |
           ((uint32_t)bytes[3] << 24);
}

static uint64_t read_u64_le(const uint8_t *bytes) {
    return (uint64_t)read_u32_le(bytes) |
           ((uint64_t)read_u32_le(bytes + 4) << 32);
}

static float read_f32_le(const uint8_t *bytes) {
    uint32_t bits = read_u32_le(bytes);
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

static double read_f64_le(const uint8_t *bytes) {
    uint64_t bits = read_u64_le(bytes);
    double value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

static bool has_exact_size(const MinecraftRenderPacketHeader *header, uint32_t size) {
    return header->packet_size == size;
}

static bool has_inline_data_size(const MinecraftRenderPacketHeader *header,
                                 const uint8_t *packet_bytes,
                                 uint32_t minimum_size,
                                 uint32_t data_size_offset) {
    if (header->packet_size < minimum_size) {
        return false;
    }
    uint32_t data_size = read_u32_le(packet_bytes + data_size_offset);
    if (data_size > UINT32_MAX - minimum_size - (MINECRAFT_RENDER_PACKET_ALIGNMENT - 1u)) {
        return false;
    }
    uint32_t raw_size = minimum_size + data_size;
    uint32_t aligned_size = (raw_size + (MINECRAFT_RENDER_PACKET_ALIGNMENT - 1u)) &
                            ~(MINECRAFT_RENDER_PACKET_ALIGNMENT - 1u);
    return header->packet_size == aligned_size;
}

static bool has_write_buffer_size(const MinecraftRenderPacketHeader *header,
                                  const uint8_t *packet_bytes) {
    /* Header + buffer id + byte offset + byte count. */
    return has_inline_data_size(header, packet_bytes, 24u, 20u);
}

static bool has_write_texture_size(const MinecraftRenderPacketHeader *header,
                                   const uint8_t *packet_bytes) {
    /* Header + eight 32-bit fields, ending in byte count. */
    return has_inline_data_size(header, packet_bytes, 40u, 36u);
}

static bool reject(MinecraftRenderExecutionState *state, int result) {
    state->result = result;
    return false;
}

static bool dispatch_packet(const MinecraftRenderPacketHeader *header,
                            const uint8_t *packet_bytes,
                            void *user_data) {
    MinecraftRenderExecutionState *state = user_data;
    const MinecraftRenderCommandSink *sink = state->sink;
    const uint8_t *payload = packet_bytes + MINECRAFT_RENDER_PACKET_HEADER_BYTES;

    switch (header->opcode) {
        case MINECRAFT_RENDER_FRAME_BEGIN:
            if (!has_exact_size(header, 24u)) {
                return reject(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
            }
            if (sink->frame_begin == NULL) {
                return reject(state, MINECRAFT_RENDER_UNSUPPORTED_COMMAND);
            }
            return sink->frame_begin(state->user_data, read_u64_le(payload),
                                     read_u32_le(payload + 8), read_u32_le(payload + 12)) ||
                   reject(state, MINECRAFT_RENDER_VISITOR_REJECTED);

        case MINECRAFT_RENDER_FRAME_END:
            if (!has_exact_size(header, 8u)) {
                return reject(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
            }
            if (sink->frame_end == NULL) {
                return reject(state, MINECRAFT_RENDER_UNSUPPORTED_COMMAND);
            }
            return sink->frame_end(state->user_data) ||
                   reject(state, MINECRAFT_RENDER_VISITOR_REJECTED);

        case MINECRAFT_RENDER_CREATE_BUFFER:
            if (!has_exact_size(header, 24u)) {
                return reject(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
            }
            if (sink->create_buffer == NULL) {
                return reject(state, MINECRAFT_RENDER_UNSUPPORTED_COMMAND);
            }
            return sink->create_buffer(state->user_data, read_u32_le(payload),
                                       read_u32_le(payload + 4), read_u64_le(payload + 8)) ||
                   reject(state, MINECRAFT_RENDER_VISITOR_REJECTED);

        case MINECRAFT_RENDER_WRITE_BUFFER:
            if (!has_write_buffer_size(header, packet_bytes)) {
                return reject(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
            }
            if (sink->write_buffer == NULL) {
                return reject(state, MINECRAFT_RENDER_UNSUPPORTED_COMMAND);
            }
            return sink->write_buffer(state->user_data, read_u32_le(payload),
                                      read_u64_le(payload + 4), payload + 16,
                                      read_u32_le(payload + 12)) ||
                   reject(state, MINECRAFT_RENDER_VISITOR_REJECTED);

        case MINECRAFT_RENDER_CREATE_TEXTURE:
            if (!has_exact_size(header, 40u)) {
                return reject(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
            }
            if (sink->create_texture == NULL) {
                return reject(state, MINECRAFT_RENDER_UNSUPPORTED_COMMAND);
            }
            return sink->create_texture(state->user_data, read_u32_le(payload),
                                        read_u32_le(payload + 4), read_u32_le(payload + 8),
                                        read_u32_le(payload + 12), read_u32_le(payload + 16),
                                        read_u32_le(payload + 20), read_u32_le(payload + 24)) ||
                   reject(state, MINECRAFT_RENDER_VISITOR_REJECTED);

        case MINECRAFT_RENDER_WRITE_TEXTURE:
            if (!has_write_texture_size(header, packet_bytes)) {
                return reject(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
            }
            if (sink->write_texture == NULL) {
                return reject(state, MINECRAFT_RENDER_UNSUPPORTED_COMMAND);
            }
            return sink->write_texture(
                    state->user_data,
                    read_u32_le(payload), read_u32_le(payload + 4), read_u32_le(payload + 8),
                    read_u32_le(payload + 12), read_u32_le(payload + 16),
                    read_u32_le(payload + 20), read_u32_le(payload + 24),
                    payload + 32, read_u32_le(payload + 28)
            ) || reject(state, MINECRAFT_RENDER_VISITOR_REJECTED);

        case MINECRAFT_RENDER_BEGIN_RENDER_PASS:
            if (!has_exact_size(header, 40u)) {
                return reject(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
            }
            if (sink->begin_render_pass == NULL) {
                return reject(state, MINECRAFT_RENDER_UNSUPPORTED_COMMAND);
            }
            return sink->begin_render_pass(state->user_data, read_u32_le(payload),
                                           read_u32_le(payload + 4), read_f32_le(payload + 8),
                                           read_f32_le(payload + 12), read_f32_le(payload + 16),
                                           read_f32_le(payload + 20), read_f64_le(payload + 24)) ||
                   reject(state, MINECRAFT_RENDER_VISITOR_REJECTED);

        case MINECRAFT_RENDER_END_RENDER_PASS:
            if (!has_exact_size(header, 8u)) {
                return reject(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
            }
            if (sink->end_render_pass == NULL) {
                return reject(state, MINECRAFT_RENDER_UNSUPPORTED_COMMAND);
            }
            return sink->end_render_pass(state->user_data) ||
                   reject(state, MINECRAFT_RENDER_VISITOR_REJECTED);

        case MINECRAFT_RENDER_SET_PIPELINE:
            if (!has_exact_size(header, 16u)) {
                return reject(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
            }
            if (sink->set_pipeline == NULL) {
                return reject(state, MINECRAFT_RENDER_UNSUPPORTED_COMMAND);
            }
            return sink->set_pipeline(state->user_data, read_u32_le(payload)) ||
                   reject(state, MINECRAFT_RENDER_VISITOR_REJECTED);

        case MINECRAFT_RENDER_SET_VERTEX_BUFFER:
            if (!has_exact_size(header, 32u)) {
                return reject(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
            }
            if (sink->set_vertex_buffer == NULL) {
                return reject(state, MINECRAFT_RENDER_UNSUPPORTED_COMMAND);
            }
            return sink->set_vertex_buffer(state->user_data, read_u32_le(payload),
                                           read_u32_le(payload + 4), read_u64_le(payload + 8),
                                           read_u64_le(payload + 16)) ||
                   reject(state, MINECRAFT_RENDER_VISITOR_REJECTED);

        case MINECRAFT_RENDER_SET_INDEX_BUFFER:
            if (!has_exact_size(header, 32u)) {
                return reject(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
            }
            if (sink->set_index_buffer == NULL) {
                return reject(state, MINECRAFT_RENDER_UNSUPPORTED_COMMAND);
            }
            return sink->set_index_buffer(state->user_data, read_u32_le(payload),
                                          read_u32_le(payload + 4), read_u64_le(payload + 8),
                                          read_u64_le(payload + 16)) ||
                   reject(state, MINECRAFT_RENDER_VISITOR_REJECTED);

        case MINECRAFT_RENDER_SET_SCISSOR:
            if (!has_exact_size(header, 24u)) {
                return reject(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
            }
            if (sink->set_scissor == NULL) {
                return reject(state, MINECRAFT_RENDER_UNSUPPORTED_COMMAND);
            }
            return sink->set_scissor(state->user_data, read_u32_le(payload),
                                     read_u32_le(payload + 4), read_u32_le(payload + 8),
                                     read_u32_le(payload + 12)) ||
                   reject(state, MINECRAFT_RENDER_VISITOR_REJECTED);

        case MINECRAFT_RENDER_DRAW:
            if (!has_exact_size(header, 24u)) {
                return reject(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
            }
            if (sink->draw == NULL) {
                return reject(state, MINECRAFT_RENDER_UNSUPPORTED_COMMAND);
            }
            return sink->draw(state->user_data, read_u32_le(payload), read_u32_le(payload + 4),
                              read_u32_le(payload + 8), read_u32_le(payload + 12)) ||
                   reject(state, MINECRAFT_RENDER_VISITOR_REJECTED);

        case MINECRAFT_RENDER_DRAW_INDEXED:
            if (!has_exact_size(header, 32u)) {
                return reject(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
            }
            if (sink->draw_indexed == NULL) {
                return reject(state, MINECRAFT_RENDER_UNSUPPORTED_COMMAND);
            }
            return sink->draw_indexed(state->user_data, read_u32_le(payload),
                                      read_u32_le(payload + 4), read_u32_le(payload + 8),
                                      (int32_t)read_u32_le(payload + 12),
                                      read_u32_le(payload + 16)) ||
                   reject(state, MINECRAFT_RENDER_VISITOR_REJECTED);

        default:
            return reject(state, MINECRAFT_RENDER_UNSUPPORTED_COMMAND);
    }
}

int minecraft_render_execute_frame(const MinecraftRenderFrame *frame,
                                   const MinecraftRenderCommandSink *sink,
                                   void *user_data) {
    if (frame == NULL || frame->bytes == NULL || frame->size == 0 || sink == NULL) {
        return MINECRAFT_RENDER_INVALID_ARGUMENT;
    }

    MinecraftRenderExecutionState state = {
        .sink = sink,
        .user_data = user_data,
        .result = MINECRAFT_RENDER_VISITOR_REJECTED,
    };
    int result = minecraft_render_visit_frame(frame->bytes, frame->size, dispatch_packet, &state);
    if (result == MINECRAFT_RENDER_VISITOR_REJECTED) {
        return state.result;
    }
    return result;
}
