#ifndef MINECRAFT_RENDER_NATIVE_STATE_H
#define MINECRAFT_RENDER_NATIVE_STATE_H

/*
 * Native resource/lifecycle sink for decoded RenderPearl packets.
 *
 * This is the non-Godot half of the eventual RenderingDevice executor. It
 * owns validated buffer bytes plus the latest texture-upload regions on the
 * GDExtension side so command frames cannot reference unknown handles or
 * out-of-range resource data.
 * The later Godot sink will replace these CPU mirrors with RenderingDevice RIDs
 * while retaining the same lifetime and ordering checks.
 */

#include "minecraft_render_executor.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MinecraftRenderNativeState MinecraftRenderNativeState;

typedef enum MinecraftRenderBufferAttribute {
    MINECRAFT_RENDER_BUFFER_ATTRIBUTE_ID = 0,
    MINECRAFT_RENDER_BUFFER_ATTRIBUTE_SIZE = 1,
    /* Increments whenever retained contents or allocation changes. */
    MINECRAFT_RENDER_BUFFER_ATTRIBUTE_REVISION = 2,
    /* RenderPearl GpuBuffer usage bits retained with the allocation. */
    MINECRAFT_RENDER_BUFFER_ATTRIBUTE_USAGE = 3,
} MinecraftRenderBufferAttribute;

typedef enum MinecraftRenderTextureAttribute {
    MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_ID = 0,
    MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_USAGE = 1,
    MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_FORMAT = 2,
    MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_WIDTH = 3,
    MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_HEIGHT = 4,
    MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_DEPTH_OR_LAYERS = 5,
    MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_MIP_LEVELS = 6,
    /* Increments whenever retained pixels or allocation changes. */
    MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_REVISION = 7,
} MinecraftRenderTextureAttribute;

/* A bounded GDExtension-to-GDScript transfer request. */
#define MINECRAFT_RENDER_BRIDGE_MAX_CHUNK_BYTES (4u * 1024u * 1024u)

typedef enum MinecraftRenderPassAttribute {
    MINECRAFT_RENDER_PASS_ATTRIBUTE_COLOR_TEXTURE_ID = 0,
    MINECRAFT_RENDER_PASS_ATTRIBUTE_DEPTH_TEXTURE_ID = 1,
    MINECRAFT_RENDER_PASS_ATTRIBUTE_REVISION = 2,
    MINECRAFT_RENDER_PASS_ATTRIBUTE_DRAW_COUNT = 3,
    MINECRAFT_RENDER_PASS_ATTRIBUTE_CLEAR_RED_BITS = 4,
    MINECRAFT_RENDER_PASS_ATTRIBUTE_CLEAR_GREEN_BITS = 5,
    MINECRAFT_RENDER_PASS_ATTRIBUTE_CLEAR_BLUE_BITS = 6,
    MINECRAFT_RENDER_PASS_ATTRIBUTE_CLEAR_ALPHA_BITS = 7,
    /* Index of this pass's first retained draw. Valid for frame-pass queries. */
    MINECRAFT_RENDER_PASS_ATTRIBUTE_DRAW_START = 8,
} MinecraftRenderPassAttribute;

typedef enum MinecraftRenderDrawAttribute {
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_COLOR_TEXTURE_ID = 0,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_PIPELINE_ID = 1,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_FAMILY = 2,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_BLEND = 3,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_TOPOLOGY = 4,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_KIND = 5,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_COUNT = 6,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_INSTANCE_COUNT = 7,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_FIRST = 8,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_BASE_VERTEX = 9,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_FIRST_INSTANCE = 10,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_VERTEX_BUFFER_ID = 11,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_VERTEX_STRIDE = 12,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_VERTEX_OFFSET = 13,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_VERTEX_LENGTH = 14,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_INDEX_BUFFER_ID = 15,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_INDEX_TYPE = 16,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_INDEX_OFFSET = 17,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_INDEX_LENGTH = 18,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_SCISSOR_X = 19,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_SCISSOR_Y = 20,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_SCISSOR_WIDTH = 21,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_SCISSOR_HEIGHT = 22,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_DYNAMIC_BUFFER_ID = 23,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_DYNAMIC_OFFSET = 24,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_DYNAMIC_LENGTH = 25,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_PROJECTION_BUFFER_ID = 26,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_PROJECTION_OFFSET = 27,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_PROJECTION_LENGTH = 28,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_SAMPLER0_TEXTURE_ID = 29,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_SAMPLER0_BASE_MIP = 30,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_SAMPLER0_MIN_FILTER = 31,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_SAMPLER0_MAG_FILTER = 32,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_SAMPLER0_ADDRESS_U = 33,
    MINECRAFT_RENDER_DRAW_ATTRIBUTE_SAMPLER0_ADDRESS_V = 34,
} MinecraftRenderDrawAttribute;

typedef enum MinecraftRenderPipelineAttributeId {
    MINECRAFT_RENDER_PIPELINE_ATTRIBUTE_FAMILY = 0,
    MINECRAFT_RENDER_PIPELINE_ATTRIBUTE_BLEND = 1,
    MINECRAFT_RENDER_PIPELINE_ATTRIBUTE_TOPOLOGY = 2,
    MINECRAFT_RENDER_PIPELINE_ATTRIBUTE_VERTEX_STRIDE = 3,
    MINECRAFT_RENDER_PIPELINE_ATTRIBUTE_ATTRIBUTE_COUNT = 4,
    /* Bit 0 is set when the pipeline identifier selects the grayscale text shader. */
    MINECRAFT_RENDER_PIPELINE_ATTRIBUTE_FLAGS = 5,
} MinecraftRenderPipelineAttributeId;

typedef enum MinecraftRenderVertexAttributeField {
    MINECRAFT_RENDER_VERTEX_ATTRIBUTE_LOCATION = 0,
    MINECRAFT_RENDER_VERTEX_ATTRIBUTE_OFFSET = 1,
    MINECRAFT_RENDER_VERTEX_ATTRIBUTE_FORMAT = 2,
} MinecraftRenderVertexAttributeField;

MinecraftRenderNativeState *minecraft_render_native_state_create(void);
void minecraft_render_native_state_destroy(MinecraftRenderNativeState *state);

/*
 * Atomically takes and executes one mailbox frame through the checked native
 * resource sink. Returns MINECRAFT_RENDER_NO_FRAME when idle, packet count on
 * success, or a negative MinecraftRenderValidationResult on rejection.
 */
int minecraft_render_native_execute_latest(MinecraftRenderNativeState *state);

int minecraft_render_native_last_execution_status(const MinecraftRenderNativeState *state);
size_t minecraft_render_native_buffer_count(const MinecraftRenderNativeState *state);
size_t minecraft_render_native_texture_count(const MinecraftRenderNativeState *state);
/* Enumerate metadata needed by the Godot RenderingDevice allocator/uploader. */
uint64_t minecraft_render_native_buffer_attribute_at(
    const MinecraftRenderNativeState *state,
    size_t index,
    uint32_t attribute
);
uint32_t minecraft_render_native_texture_attribute_at(
    const MinecraftRenderNativeState *state,
    size_t index,
    uint32_t attribute
);
/* Latest completed render pass. Revision 0 means no pass has completed. */
uint32_t minecraft_render_native_pass_attribute(
    const MinecraftRenderNativeState *state,
    uint32_t attribute
);

/*
 * Copies an exact retained buffer range into caller-owned memory. An invalid
 * request returns zero. Callers must request no more than
 * MINECRAFT_RENDER_BRIDGE_MAX_CHUNK_BYTES per call.
 */
size_t minecraft_render_native_copy_buffer_bytes(
    const MinecraftRenderNativeState *state,
    uint32_t buffer_id,
    uint64_t offset,
    uint8_t *destination,
    size_t byte_count
);

/*
 * Returns/copies a resolved RGBA8 mip/layer image. Upload regions are composited
 * in original submission order, so later overlapping writes win. The byte
 * layout is tightly packed rows, four bytes per pixel. Unsupported texture
 * formats and invalid requests return zero.
 */
uint64_t minecraft_render_native_texture_mip_layer_size(
    const MinecraftRenderNativeState *state,
    uint32_t texture_id,
    uint32_t mip_level,
    uint32_t layer
);
size_t minecraft_render_native_copy_texture_mip_layer_bytes(
    const MinecraftRenderNativeState *state,
    uint32_t texture_id,
    uint32_t mip_level,
    uint32_t layer,
    uint64_t offset,
    uint8_t *destination,
    size_t byte_count
);

/* Retained latest upload regions/bytes for one native texture handle. */
size_t minecraft_render_native_texture_upload_count(
    const MinecraftRenderNativeState *state,
    uint32_t texture_id
);
uint64_t minecraft_render_native_texture_uploaded_bytes(
    const MinecraftRenderNativeState *state,
    uint32_t texture_id
);

/* Passes and draws retained from the latest successfully executed frame. */
size_t minecraft_render_native_frame_pass_count(const MinecraftRenderNativeState *state);
uint32_t minecraft_render_native_frame_pass_attribute(
    const MinecraftRenderNativeState *state,
    size_t pass_index,
    uint32_t attribute
);
size_t minecraft_render_native_draw_count(const MinecraftRenderNativeState *state);
int64_t minecraft_render_native_draw_attribute(
    const MinecraftRenderNativeState *state,
    size_t draw_index,
    uint32_t attribute
);
int64_t minecraft_render_native_pipeline_attribute(
    const MinecraftRenderNativeState *state,
    uint32_t pipeline_id,
    uint32_t attribute
);
int64_t minecraft_render_native_pipeline_vertex_attribute(
    const MinecraftRenderNativeState *state,
    uint32_t pipeline_id,
    uint32_t attribute_index,
    uint32_t field
);

#ifdef __cplusplus
}
#endif

#endif
