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

static bool has_trailing_name(const MinecraftRenderPacketHeader *header,
                              const uint8_t *packet_bytes,
                              uint32_t minimum_size,
                              uint32_t max_name_length) {
    if (!has_inline_data_size(header, packet_bytes, minimum_size, MINECRAFT_RENDER_PACKET_HEADER_BYTES)) {
        return false;
    }
    uint32_t name_length = read_u32_le(packet_bytes + MINECRAFT_RENDER_PACKET_HEADER_BYTES);
    return name_length <= max_name_length;
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

        case MINECRAFT_RENDER_COMPILE_PIPELINE: {
            if (header->packet_size < 44u) {
                return reject(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
            }
            uint32_t attribute_count = read_u32_le(payload + 20);
            uint32_t location_length = read_u32_le(payload + 24);
            uint32_t vertex_shader_length = read_u32_le(payload + 28);
            uint32_t fragment_shader_length = read_u32_le(payload + 32);
            if (attribute_count > MINECRAFT_RENDER_MAX_PIPELINE_ATTRIBUTES ||
                    location_length > MINECRAFT_RENDER_MAX_SHADER_IDENTIFIER_BYTES ||
                    vertex_shader_length > MINECRAFT_RENDER_MAX_SHADER_IDENTIFIER_BYTES ||
                    fragment_shader_length > MINECRAFT_RENDER_MAX_SHADER_IDENTIFIER_BYTES) {
                return reject(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
            }
            uint64_t raw_size = 44ull + (uint64_t)attribute_count * 12ull + location_length +
                    vertex_shader_length + fragment_shader_length;
            uint64_t aligned_size = (raw_size + (MINECRAFT_RENDER_PACKET_ALIGNMENT - 1u)) &
                    ~(uint64_t)(MINECRAFT_RENDER_PACKET_ALIGNMENT - 1u);
            if (aligned_size != header->packet_size) {
                return reject(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
            }
            if (sink->compile_pipeline == NULL) {
                return reject(state, MINECRAFT_RENDER_UNSUPPORTED_COMMAND);
            }
            MinecraftRenderPipelineAttribute attributes[MINECRAFT_RENDER_MAX_PIPELINE_ATTRIBUTES];
            const uint8_t *attribute_bytes = payload + 36;
            for (uint32_t index = 0; index < attribute_count; index++) {
                const uint8_t *attribute = attribute_bytes + index * 12u;
                attributes[index].location = read_u32_le(attribute);
                attributes[index].offset = read_u32_le(attribute + 4);
                attributes[index].format = read_u32_le(attribute + 8);
            }
            const uint8_t *strings = attribute_bytes + attribute_count * 12u;
            MinecraftRenderCompiledPipeline pipeline = {
                .pipeline_id = read_u32_le(payload),
                .family = read_u32_le(payload + 4),
                .topology = read_u32_le(payload + 8),
                .blend = read_u32_le(payload + 12),
                .vertex_stride = read_u32_le(payload + 16),
                .attribute_count = attribute_count,
                .attributes = attributes,
                .location = strings,
                .location_length = location_length,
                .vertex_shader = strings + location_length,
                .vertex_shader_length = vertex_shader_length,
                .fragment_shader = strings + location_length + vertex_shader_length,
                .fragment_shader_length = fragment_shader_length,
            };
            return sink->compile_pipeline(state->user_data, &pipeline) ||
                   reject(state, MINECRAFT_RENDER_VISITOR_REJECTED);
        }

        case MINECRAFT_RENDER_SET_UNIFORM_BUFFER: {
            if (!has_trailing_name(header, packet_bytes, 32u, MINECRAFT_RENDER_MAX_UNIFORM_NAME_BYTES)) {
                return reject(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
            }
            if (sink->set_uniform_buffer == NULL) {
                return reject(state, MINECRAFT_RENDER_UNSUPPORTED_COMMAND);
            }
            uint32_t name_length = read_u32_le(payload);
            MinecraftRenderUniformBufferBinding binding = {
                .name = payload + 24,
                .name_length = name_length,
                .buffer_id = read_u32_le(payload + 4),
                .offset = read_u64_le(payload + 8),
                .length = read_u64_le(payload + 16),
            };
            return sink->set_uniform_buffer(state->user_data, &binding) ||
                   reject(state, MINECRAFT_RENDER_VISITOR_REJECTED);
        }

        case MINECRAFT_RENDER_SET_TEXTURE_SAMPLER: {
            if (!has_trailing_name(header, packet_bytes, 40u, MINECRAFT_RENDER_MAX_UNIFORM_NAME_BYTES)) {
                return reject(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
            }
            if (sink->set_texture_sampler == NULL) {
                return reject(state, MINECRAFT_RENDER_UNSUPPORTED_COMMAND);
            }
            uint32_t name_length = read_u32_le(payload);
            MinecraftRenderTextureSamplerBinding binding = {
                .name = payload + 32,
                .name_length = name_length,
                .texture_id = read_u32_le(payload + 4),
                .sampler_id = read_u32_le(payload + 8),
                .base_mip = read_u32_le(payload + 12),
                .min_filter = read_u32_le(payload + 16),
                .mag_filter = read_u32_le(payload + 20),
                .address_u = read_u32_le(payload + 24),
                .address_v = read_u32_le(payload + 28),
            };
            return sink->set_texture_sampler(state->user_data, &binding) ||
                   reject(state, MINECRAFT_RENDER_VISITOR_REJECTED);
        }

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
