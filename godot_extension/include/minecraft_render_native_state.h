#ifndef MINECRAFT_RENDER_NATIVE_STATE_H
#define MINECRAFT_RENDER_NATIVE_STATE_H

/*
 * Native resource/lifecycle sink for decoded RenderPearl packets.
 *
 * This is the non-Godot half of the eventual RenderingDevice executor. It
 * owns validated buffer bytes and texture metadata on the GDExtension side so
 * command frames cannot reference unknown handles or out-of-range buffer data.
 * The later Godot sink will replace these CPU mirrors with RenderingDevice RIDs
 * while retaining the same lifetime and ordering checks.
 */

#include "minecraft_render_executor.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MinecraftRenderNativeState MinecraftRenderNativeState;

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

#ifdef __cplusplus
}
#endif

#endif
