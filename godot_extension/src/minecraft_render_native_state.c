#include "minecraft_render_native_state.h"

#include <stdlib.h>
#include <string.h>

#define MINECRAFT_RENDER_MAX_RESOURCE_BYTES (64u * 1024u * 1024u)

typedef struct MinecraftRenderBuffer {
    uint32_t id;
    uint32_t usage;
    uint64_t size;
    uint8_t *bytes;
    struct MinecraftRenderBuffer *next;
} MinecraftRenderBuffer;

typedef struct MinecraftRenderTexture {
    uint32_t id;
    uint32_t usage;
    uint32_t format;
    uint32_t width;
    uint32_t height;
    uint32_t depth_or_layers;
    uint32_t mip_levels;
    struct MinecraftRenderTexture *next;
} MinecraftRenderTexture;

struct MinecraftRenderNativeState {
    MinecraftRenderBuffer *buffers;
    MinecraftRenderTexture *textures;
    size_t buffer_count;
    size_t texture_count;
    uint32_t frame_width;
    uint32_t frame_height;
    uint32_t active_pipeline;
    bool frame_active;
    bool pass_active;
    int callback_status;
    int last_execution_status;
};

static bool fail(MinecraftRenderNativeState *state, int status) {
    state->callback_status = status;
    return false;
}

static MinecraftRenderBuffer *find_buffer(MinecraftRenderNativeState *state, uint32_t id) {
    for (MinecraftRenderBuffer *buffer = state->buffers; buffer != NULL; buffer = buffer->next) {
        if (buffer->id == id) {
            return buffer;
        }
    }
    return NULL;
}

static MinecraftRenderTexture *find_texture(MinecraftRenderNativeState *state, uint32_t id) {
    for (MinecraftRenderTexture *texture = state->textures; texture != NULL; texture = texture->next) {
        if (texture->id == id) {
            return texture;
        }
    }
    return NULL;
}

static bool frame_begin(void *user_data, uint64_t frame_id, uint32_t width, uint32_t height) {
    (void)frame_id;
    MinecraftRenderNativeState *state = user_data;
    if (width == 0 || height == 0 || state->frame_active || state->pass_active) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    state->frame_active = true;
    state->frame_width = width;
    state->frame_height = height;
    state->active_pipeline = 0;
    return true;
}

static bool frame_end(void *user_data) {
    MinecraftRenderNativeState *state = user_data;
    if (!state->frame_active || state->pass_active) {
        return fail(state, MINECRAFT_RENDER_BAD_FRAME_ORDER);
    }
    state->frame_active = false;
    return true;
}

static bool create_buffer(void *user_data, uint32_t buffer_id, uint32_t usage, uint64_t size) {
    MinecraftRenderNativeState *state = user_data;
    if (!state->frame_active || state->pass_active || buffer_id == 0 ||
            size > MINECRAFT_RENDER_MAX_RESOURCE_BYTES) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }

    MinecraftRenderBuffer *buffer = find_buffer(state, buffer_id);
    if (buffer == NULL) {
        buffer = calloc(1, sizeof(*buffer));
        if (buffer == NULL) {
            return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
        }
        buffer->id = buffer_id;
        buffer->next = state->buffers;
        state->buffers = buffer;
        state->buffer_count++;
    }

    uint8_t *bytes = size == 0 ? NULL : calloc(1, (size_t)size);
    if (size != 0 && bytes == NULL) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    free(buffer->bytes);
    buffer->bytes = bytes;
    buffer->usage = usage;
    buffer->size = size;
    return true;
}

static bool write_buffer(void *user_data, uint32_t buffer_id, uint64_t offset,
                         const uint8_t *data, uint32_t data_size) {
    MinecraftRenderNativeState *state = user_data;
    MinecraftRenderBuffer *buffer = find_buffer(state, buffer_id);
    if (!state->frame_active || state->pass_active || buffer == NULL ||
            offset > buffer->size || data_size > buffer->size - offset ||
            (data_size != 0 && data == NULL)) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    if (data_size != 0) {
        memcpy(buffer->bytes + (size_t)offset, data, data_size);
    }
    return true;
}

static bool create_texture(void *user_data, uint32_t texture_id, uint32_t usage,
                           uint32_t format, uint32_t width, uint32_t height,
                           uint32_t depth_or_layers, uint32_t mip_levels) {
    MinecraftRenderNativeState *state = user_data;
    if (!state->frame_active || state->pass_active || texture_id == 0 || width == 0 || height == 0 ||
            depth_or_layers == 0 || mip_levels == 0) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }

    MinecraftRenderTexture *texture = find_texture(state, texture_id);
    if (texture == NULL) {
        texture = calloc(1, sizeof(*texture));
        if (texture == NULL) {
            return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
        }
        texture->id = texture_id;
        texture->next = state->textures;
        state->textures = texture;
        state->texture_count++;
    }
    texture->usage = usage;
    texture->format = format;
    texture->width = width;
    texture->height = height;
    texture->depth_or_layers = depth_or_layers;
    texture->mip_levels = mip_levels;
    return true;
}

static bool begin_render_pass(void *user_data, uint32_t color_texture_id,
                              uint32_t depth_texture_id, float clear_red,
                              float clear_green, float clear_blue,
                              float clear_alpha, double clear_depth) {
    (void)clear_red;
    (void)clear_green;
    (void)clear_blue;
    (void)clear_alpha;
    (void)clear_depth;
    MinecraftRenderNativeState *state = user_data;
    if (!state->frame_active || state->pass_active || find_texture(state, color_texture_id) == NULL ||
            (depth_texture_id != 0 && find_texture(state, depth_texture_id) == NULL)) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    state->pass_active = true;
    state->active_pipeline = 0;
    return true;
}

static bool end_render_pass(void *user_data) {
    MinecraftRenderNativeState *state = user_data;
    if (!state->frame_active || !state->pass_active) {
        return fail(state, MINECRAFT_RENDER_BAD_FRAME_ORDER);
    }
    state->pass_active = false;
    state->active_pipeline = 0;
    return true;
}

static bool set_pipeline(void *user_data, uint32_t pipeline_id) {
    MinecraftRenderNativeState *state = user_data;
    if (!state->pass_active || pipeline_id == 0) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    /* Pipeline bytecode/state translation is the next backend slice. The
     * handle is retained now so draw ordering is checked without inventing a
     * Godot pipeline that does not exist. */
    state->active_pipeline = pipeline_id;
    return true;
}

static bool set_vertex_buffer(void *user_data, uint32_t slot, uint32_t buffer_id,
                              uint64_t offset, uint64_t length) {
    (void)slot;
    MinecraftRenderNativeState *state = user_data;
    MinecraftRenderBuffer *buffer = find_buffer(state, buffer_id);
    if (!state->pass_active || buffer == NULL || offset > buffer->size ||
            length > buffer->size - offset) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    return true;
}

static bool set_index_buffer(void *user_data, uint32_t buffer_id, uint32_t index_type,
                             uint64_t offset, uint64_t length) {
    (void)index_type;
    MinecraftRenderNativeState *state = user_data;
    MinecraftRenderBuffer *buffer = find_buffer(state, buffer_id);
    if (!state->pass_active || buffer == NULL || offset > buffer->size ||
            length > buffer->size - offset) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    return true;
}

static bool set_scissor(void *user_data, uint32_t x, uint32_t y,
                        uint32_t width, uint32_t height) {
    MinecraftRenderNativeState *state = user_data;
    if (!state->pass_active || x > state->frame_width || y > state->frame_height ||
            width > state->frame_width - x || height > state->frame_height - y) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    return true;
}

static bool draw(void *user_data, uint32_t vertex_count, uint32_t instance_count,
                 uint32_t first_vertex, uint32_t first_instance) {
    (void)vertex_count;
    (void)instance_count;
    (void)first_vertex;
    (void)first_instance;
    MinecraftRenderNativeState *state = user_data;
    return state->pass_active ? true : fail(state, MINECRAFT_RENDER_BAD_FRAME_ORDER);
}

static bool draw_indexed(void *user_data, uint32_t index_count, uint32_t instance_count,
                         uint32_t first_index, int32_t vertex_offset,
                         uint32_t first_instance) {
    (void)index_count;
    (void)instance_count;
    (void)first_index;
    (void)vertex_offset;
    (void)first_instance;
    MinecraftRenderNativeState *state = user_data;
    return state->pass_active ? true : fail(state, MINECRAFT_RENDER_BAD_FRAME_ORDER);
}

static const MinecraftRenderCommandSink NATIVE_STATE_SINK = {
    .frame_begin = frame_begin,
    .frame_end = frame_end,
    .create_buffer = create_buffer,
    .write_buffer = write_buffer,
    .create_texture = create_texture,
    .begin_render_pass = begin_render_pass,
    .end_render_pass = end_render_pass,
    .set_pipeline = set_pipeline,
    .set_vertex_buffer = set_vertex_buffer,
    .set_index_buffer = set_index_buffer,
    .set_scissor = set_scissor,
    .draw = draw,
    .draw_indexed = draw_indexed,
};

MinecraftRenderNativeState *minecraft_render_native_state_create(void) {
    MinecraftRenderNativeState *state = calloc(1, sizeof(*state));
    if (state != NULL) {
        state->last_execution_status = MINECRAFT_RENDER_NO_FRAME;
    }
    return state;
}

void minecraft_render_native_state_destroy(MinecraftRenderNativeState *state) {
    if (state == NULL) {
        return;
    }
    while (state->buffers != NULL) {
        MinecraftRenderBuffer *buffer = state->buffers;
        state->buffers = buffer->next;
        free(buffer->bytes);
        free(buffer);
    }
    while (state->textures != NULL) {
        MinecraftRenderTexture *texture = state->textures;
        state->textures = texture->next;
        free(texture);
    }
    free(state);
}

int minecraft_render_native_execute_latest(MinecraftRenderNativeState *state) {
    if (state == NULL) {
        return MINECRAFT_RENDER_INVALID_ARGUMENT;
    }
    MinecraftRenderFrame frame = {0};
    int result = minecraft_render_take_latest_frame(&frame);
    if (result < 0) {
        state->last_execution_status = result;
        return result;
    }

    state->callback_status = MINECRAFT_RENDER_VISITOR_REJECTED;
    result = minecraft_render_execute_frame(&frame, &NATIVE_STATE_SINK, state);
    minecraft_render_release_frame(&frame);
    if (result == MINECRAFT_RENDER_VISITOR_REJECTED) {
        result = state->callback_status;
    }
    if (result < 0) {
        /* A rejected detached frame must not poison the next submitted frame. */
        state->frame_active = false;
        state->pass_active = false;
        state->active_pipeline = 0;
    }
    state->last_execution_status = result;
    return result;
}

int minecraft_render_native_last_execution_status(const MinecraftRenderNativeState *state) {
    return state == NULL ? MINECRAFT_RENDER_INVALID_ARGUMENT : state->last_execution_status;
}

size_t minecraft_render_native_buffer_count(const MinecraftRenderNativeState *state) {
    return state == NULL ? 0 : state->buffer_count;
}

size_t minecraft_render_native_texture_count(const MinecraftRenderNativeState *state) {
    return state == NULL ? 0 : state->texture_count;
}
