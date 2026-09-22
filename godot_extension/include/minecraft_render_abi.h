#ifndef MINECRAFT_RENDER_ABI_H
#define MINECRAFT_RENDER_ABI_H

/*
 * Neutral command stream between a Java RenderPearl backend and the native
 * Godot platform adapter.  This header intentionally has no Godot dependency:
 * the Java side emits RenderPearl operations and only the C GDExtension layer
 * maps them to Godot rendering commands.
 *
 * All packets begin at an 8-byte boundary. packet_size includes the header and
 * padding, which makes a frame safe to validate before touching GPU resources.
 */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MINECRAFT_RENDER_ABI_VERSION 1u
#define MINECRAFT_RENDER_PACKET_ALIGNMENT 8u

typedef enum MinecraftRenderOpcode {
    MINECRAFT_RENDER_FRAME_BEGIN = 1,
    MINECRAFT_RENDER_FRAME_END = 2,
    MINECRAFT_RENDER_CREATE_BUFFER = 3,
    MINECRAFT_RENDER_DESTROY_BUFFER = 4,
    MINECRAFT_RENDER_WRITE_BUFFER = 5,
    MINECRAFT_RENDER_CREATE_TEXTURE = 6,
    MINECRAFT_RENDER_DESTROY_TEXTURE = 7,
    MINECRAFT_RENDER_WRITE_TEXTURE = 8,
    MINECRAFT_RENDER_CREATE_SAMPLER = 9,
    MINECRAFT_RENDER_DESTROY_SAMPLER = 10,
    MINECRAFT_RENDER_COMPILE_PIPELINE = 11,
    MINECRAFT_RENDER_DESTROY_PIPELINE = 12,
    MINECRAFT_RENDER_BEGIN_RENDER_PASS = 13,
    MINECRAFT_RENDER_END_RENDER_PASS = 14,
    MINECRAFT_RENDER_SET_PIPELINE = 15,
    MINECRAFT_RENDER_SET_VERTEX_BUFFER = 16,
    MINECRAFT_RENDER_SET_INDEX_BUFFER = 17,
    MINECRAFT_RENDER_SET_UNIFORM_BUFFER = 18,
    MINECRAFT_RENDER_SET_TEXTURE_SAMPLER = 19,
    MINECRAFT_RENDER_SET_SCISSOR = 20,
    MINECRAFT_RENDER_DRAW = 21,
    MINECRAFT_RENDER_DRAW_INDEXED = 22,
} MinecraftRenderOpcode;

typedef struct MinecraftRenderPacketHeader {
    uint16_t opcode;
    uint16_t reserved;
    uint32_t packet_size;
} MinecraftRenderPacketHeader;

typedef enum MinecraftRenderValidationResult {
    MINECRAFT_RENDER_VALID = 0,
    MINECRAFT_RENDER_INVALID_ARGUMENT = -1,
    MINECRAFT_RENDER_TRUNCATED_PACKET = -2,
    MINECRAFT_RENDER_BAD_ALIGNMENT = -3,
    MINECRAFT_RENDER_UNKNOWN_OPCODE = -4,
    MINECRAFT_RENDER_BAD_FRAME_ORDER = -5,
    MINECRAFT_RENDER_VISITOR_REJECTED = -6,
} MinecraftRenderValidationResult;

/* Return false to stop processing with MINECRAFT_RENDER_VISITOR_REJECTED. */
typedef bool (*MinecraftRenderPacketVisitor)(
    const MinecraftRenderPacketHeader *header,
    const uint8_t *packet_bytes,
    void *user_data
);

/*
 * Validates RenderPearl operations and visits each complete packet in order.
 * A frame must have exactly one FRAME_BEGIN and FRAME_END, and render-pass
 * commands must be properly nested. Returns packet count, or a negative
 * MinecraftRenderValidationResult.
 */
int minecraft_render_visit_frame(
    const uint8_t *frame_bytes,
    size_t frame_size,
    MinecraftRenderPacketVisitor visitor,
    void *user_data
);

/*
 * Thread-safe native mailbox used by the future Java RenderPearl backend.
 * minecraft_render_submit_frame() validates a frame, copies it atomically and
 * returns its packet count. The Godot render thread can then take a stable
 * snapshot through copy_latest_frame() without Java code knowing about Godot.
 */
int minecraft_render_submit_frame(const uint8_t *frame_bytes, size_t frame_size);
int minecraft_render_last_submission_status(void);
size_t minecraft_render_latest_frame_size(void);
/* Returns zero when destination is NULL or smaller than the current frame. */
size_t minecraft_render_copy_latest_frame(uint8_t *destination, size_t destination_size);
void minecraft_render_clear_latest_frame(void);

#ifdef __cplusplus
}
#endif

#endif
