#ifndef MINECRAFT_RENDER_EXECUTOR_H
#define MINECRAFT_RENDER_EXECUTOR_H

/*
 * Typed decoder from the neutral RenderPearl wire ABI to a native backend.
 *
 * This layer intentionally has no Godot dependency. The GDExtension's future
 * RenderingDevice implementation supplies a command sink; Java only ever
 * submits bytes to minecraft_render_submit_frame(). Keeping packet decoding
 * here gives the Godot-facing code validated native values rather than raw
 * Java-owned byte pointers.
 */

#include "minecraft_render_abi.h"

#ifdef __cplusplus
extern "C" {
#endif

#define MINECRAFT_RENDER_MAX_PIPELINE_ATTRIBUTES 16u
#define MINECRAFT_RENDER_MAX_SHADER_IDENTIFIER_BYTES 256u
#define MINECRAFT_RENDER_MAX_UNIFORM_NAME_BYTES 128u

/* Families the Godot executor can translate from extracted Minecraft shaders. */
#define MINECRAFT_RENDER_PIPELINE_FAMILY_UNKNOWN 0u
#define MINECRAFT_RENDER_PIPELINE_FAMILY_GUI_COLOR 1u
#define MINECRAFT_RENDER_PIPELINE_FAMILY_GUI_TEXTURED 2u
#define MINECRAFT_RENDER_PIPELINE_FAMILY_GUI_TEXT 3u
#define MINECRAFT_RENDER_PIPELINE_FAMILY_WORLD_TERRAIN 4u
#define MINECRAFT_RENDER_PIPELINE_FAMILY_WORLD_ENTITY 5u
#define MINECRAFT_RENDER_PIPELINE_FAMILY_WORLD_SKY 6u
#define MINECRAFT_RENDER_PIPELINE_FAMILY_WORLD_PARTICLE 7u

typedef struct MinecraftRenderPipelineAttribute {
    uint32_t location;
    uint32_t offset;
    uint32_t format;
} MinecraftRenderPipelineAttribute;

typedef struct MinecraftRenderCompiledPipeline {
    uint32_t pipeline_id;
    uint32_t family;
    uint32_t topology;
    uint32_t blend;
    uint32_t vertex_stride;
    uint32_t attribute_count;
    const MinecraftRenderPipelineAttribute *attributes;
    const uint8_t *location;
    uint32_t location_length;
    const uint8_t *vertex_shader;
    uint32_t vertex_shader_length;
    const uint8_t *fragment_shader;
    uint32_t fragment_shader_length;
} MinecraftRenderCompiledPipeline;

typedef struct MinecraftRenderUniformBufferBinding {
    const uint8_t *name;
    uint32_t name_length;
    uint32_t buffer_id;
    uint64_t offset;
    uint64_t length;
} MinecraftRenderUniformBufferBinding;

typedef struct MinecraftRenderTextureSamplerBinding {
    const uint8_t *name;
    uint32_t name_length;
    uint32_t texture_id;
    uint32_t sampler_id;
    uint32_t base_mip;
    uint32_t min_filter;
    uint32_t mag_filter;
    uint32_t address_u;
    uint32_t address_v;
} MinecraftRenderTextureSamplerBinding;

typedef struct MinecraftRenderCommandSink {
    bool (*frame_begin)(void *user_data, uint64_t frame_id, uint32_t width, uint32_t height);
    bool (*frame_end)(void *user_data);
    bool (*create_buffer)(void *user_data, uint32_t buffer_id, uint32_t usage, uint64_t size);
    bool (*write_buffer)(void *user_data, uint32_t buffer_id, uint64_t offset,
                         const uint8_t *data, uint32_t data_size);
    bool (*create_texture)(void *user_data, uint32_t texture_id, uint32_t usage,
                           uint32_t format, uint32_t width, uint32_t height,
                           uint32_t depth_or_layers, uint32_t mip_levels);
    bool (*write_texture)(void *user_data, uint32_t texture_id, uint32_t width,
                          uint32_t height, uint32_t depth_or_layers,
                          uint32_t dest_x, uint32_t dest_y, uint32_t mip_level,
                          const uint8_t *data, uint32_t data_size);
    bool (*begin_render_pass)(void *user_data, uint32_t color_texture_id,
                              uint32_t depth_texture_id, float clear_red,
                              float clear_green, float clear_blue,
                              float clear_alpha, double clear_depth);
    bool (*end_render_pass)(void *user_data);
    bool (*set_pipeline)(void *user_data, uint32_t pipeline_id);
    bool (*set_vertex_buffer)(void *user_data, uint32_t slot, uint32_t buffer_id,
                              uint64_t offset, uint64_t length);
    bool (*set_index_buffer)(void *user_data, uint32_t buffer_id, uint32_t index_type,
                             uint64_t offset, uint64_t length);
    /*
     * Pointers inside these descriptors alias the packet being decoded and are
     * valid only for the duration of the callback. Sinks must copy anything
     * they retain.
     */
    bool (*compile_pipeline)(void *user_data, const MinecraftRenderCompiledPipeline *pipeline);
    bool (*set_uniform_buffer)(void *user_data, const MinecraftRenderUniformBufferBinding *binding);
    bool (*set_texture_sampler)(void *user_data, const MinecraftRenderTextureSamplerBinding *binding);
    bool (*set_scissor)(void *user_data, uint32_t x, uint32_t y,
                        uint32_t width, uint32_t height);
    bool (*draw)(void *user_data, uint32_t vertex_count, uint32_t instance_count,
                 uint32_t first_vertex, uint32_t first_instance);
    bool (*draw_indexed)(void *user_data, uint32_t index_count, uint32_t instance_count,
                         uint32_t first_index, int32_t vertex_offset,
                         uint32_t first_instance);
} MinecraftRenderCommandSink;

/*
 * Decodes and dispatches a detached mailbox frame. Payload lengths are checked
 * before every field is read; missing sink callbacks are rejected explicitly.
 * Returns the dispatched packet count, a MinecraftRenderValidationResult, or
 * MINECRAFT_RENDER_UNSUPPORTED_COMMAND for a valid ABI opcode that has no
 * decoder yet.
 */
int minecraft_render_execute_frame(
    const MinecraftRenderFrame *frame,
    const MinecraftRenderCommandSink *sink,
    void *user_data
);

#ifdef __cplusplus
}
#endif

#endif
