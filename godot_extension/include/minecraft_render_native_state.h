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

typedef enum MinecraftRenderTextureAttribute {
    MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_ID = 0,
    MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_USAGE = 1,
    MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_FORMAT = 2,
    MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_WIDTH = 3,
    MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_HEIGHT = 4,
    MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_DEPTH_OR_LAYERS = 5,
    MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_MIP_LEVELS = 6,
} MinecraftRenderTextureAttribute;

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
/* Enumerate immutable metadata needed by the Godot RenderingDevice allocator. */
uint32_t minecraft_render_native_buffer_id_at(const MinecraftRenderNativeState *state, size_t index);
uint64_t minecraft_render_native_buffer_size_at(const MinecraftRenderNativeState *state, size_t index);
uint32_t minecraft_render_native_texture_attribute_at(
    const MinecraftRenderNativeState *state,
    size_t index,
    uint32_t attribute
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

#ifdef __cplusplus
}
#endif

#endif
