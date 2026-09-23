#include "minecraft_render_native_state.h"

#include <stdlib.h>
#include <string.h>

#define MINECRAFT_RENDER_MAX_RESOURCE_BYTES (64u * 1024u * 1024u)
/* Extracted 26.3 GpuFormat.RGBA8_UNORM ordinal. */
#define MINECRAFT_RENDER_RGBA8_UNORM 6u
#define MINECRAFT_RENDER_RGBA8_BYTES_PER_PIXEL 4u

static uint32_t next_revision(uint32_t revision) {
    /* Zero means "not initialized" to the Godot-side synchronizer. */
    return revision == UINT32_MAX ? 1u : revision + 1u;
}

typedef struct MinecraftRenderBuffer {
    uint32_t id;
    uint32_t usage;
    uint32_t revision;
    uint64_t size;
    uint8_t *bytes;
    struct MinecraftRenderBuffer *next;
} MinecraftRenderBuffer;

typedef struct MinecraftRenderTextureUpload {
    uint32_t width;
    uint32_t height;
    uint32_t depth_or_layers;
    uint32_t dest_x;
    uint32_t dest_y;
    uint32_t mip_level;
    uint32_t data_size;
    uint8_t *bytes;
    struct MinecraftRenderTextureUpload *next;
} MinecraftRenderTextureUpload;

typedef struct MinecraftRenderTexture {
    uint32_t id;
    uint32_t usage;
    uint32_t format;
    uint32_t width;
    uint32_t height;
    uint32_t depth_or_layers;
    uint32_t mip_levels;
    uint64_t uploaded_bytes;
    uint32_t upload_count;
    uint32_t revision;
    MinecraftRenderTextureUpload *uploads;
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
    uint32_t pending_color_texture;
    uint32_t pending_depth_texture;
    uint32_t pending_draw_count;
    float pending_clear_red;
    float pending_clear_green;
    float pending_clear_blue;
    float pending_clear_alpha;
    uint32_t completed_color_texture;
    uint32_t completed_depth_texture;
    uint32_t completed_draw_count;
    uint32_t completed_pass_revision;
    float completed_clear_red;
    float completed_clear_green;
    float completed_clear_blue;
    float completed_clear_alpha;
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

static void free_texture_uploads(MinecraftRenderTexture *texture) {
    while (texture->uploads != NULL) {
        MinecraftRenderTextureUpload *upload = texture->uploads;
        texture->uploads = upload->next;
        free(upload->bytes);
        free(upload);
    }
    texture->uploaded_bytes = 0;
    texture->upload_count = 0;
}

static MinecraftRenderTextureUpload *find_texture_upload(
        MinecraftRenderTexture *texture,
        uint32_t width,
        uint32_t height,
        uint32_t depth_or_layers,
        uint32_t dest_x,
        uint32_t dest_y,
        uint32_t mip_level
) {
    for (MinecraftRenderTextureUpload *upload = texture->uploads;
            upload != NULL; upload = upload->next) {
        if (upload->width == width && upload->height == height &&
                upload->depth_or_layers == depth_or_layers && upload->dest_x == dest_x &&
                upload->dest_y == dest_y && upload->mip_level == mip_level) {
            return upload;
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
    bool allocation_changed = false;
    if (buffer == NULL) {
        buffer = calloc(1, sizeof(*buffer));
        if (buffer == NULL) {
            return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
        }
        buffer->id = buffer_id;
        buffer->next = state->buffers;
        state->buffers = buffer;
        state->buffer_count++;
        allocation_changed = true;
    } else if (buffer->usage != usage || buffer->size != size) {
        allocation_changed = true;
    }
    if (!allocation_changed) {
        /* Device-owned declaration preludes repeat before every frame. They
         * describe a live allocation; they must not erase retained contents. */
        return true;
    }

    uint8_t *bytes = size == 0 ? NULL : calloc(1, (size_t)size);
    if (size != 0 && bytes == NULL) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    free(buffer->bytes);
    buffer->bytes = bytes;
    buffer->usage = usage;
    buffer->size = size;
    buffer->revision = next_revision(buffer->revision);
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
        buffer->revision = next_revision(buffer->revision);
    }
    return true;
}

static bool create_texture(void *user_data, uint32_t texture_id, uint32_t usage,
                           uint32_t format, uint32_t width, uint32_t height,
                           uint32_t depth_or_layers, uint32_t mip_levels) {
    MinecraftRenderNativeState *state = user_data;
    if (!state->frame_active || state->pass_active || texture_id == 0 || width == 0 || height == 0 ||
            depth_or_layers == 0 || mip_levels == 0 || mip_levels > 32u) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }

    MinecraftRenderTexture *texture = find_texture(state, texture_id);
    bool allocation_changed = false;
    if (texture == NULL) {
        texture = calloc(1, sizeof(*texture));
        if (texture == NULL) {
            return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
        }
        texture->id = texture_id;
        texture->next = state->textures;
        state->textures = texture;
        state->texture_count++;
        allocation_changed = true;
    } else if (texture->usage != usage || texture->format != format || texture->width != width ||
            texture->height != height || texture->depth_or_layers != depth_or_layers ||
            texture->mip_levels != mip_levels) {
        /* Reusing a handle with different allocation metadata invalidates all
         * CPU upload regions retained for the old native texture. */
        free_texture_uploads(texture);
        allocation_changed = true;
    }
    texture->usage = usage;
    texture->format = format;
    texture->width = width;
    texture->height = height;
    texture->depth_or_layers = depth_or_layers;
    texture->mip_levels = mip_levels;
    if (allocation_changed) {
        texture->revision = next_revision(texture->revision);
    }
    return true;
}

static bool write_texture(void *user_data, uint32_t texture_id, uint32_t width,
                          uint32_t height, uint32_t depth_or_layers,
                          uint32_t dest_x, uint32_t dest_y, uint32_t mip_level,
                          const uint8_t *data, uint32_t data_size) {
    MinecraftRenderNativeState *state = user_data;
    MinecraftRenderTexture *texture = find_texture(state, texture_id);
    if (!state->frame_active || state->pass_active || texture == NULL || width == 0 || height == 0 ||
            depth_or_layers == 0 || depth_or_layers > texture->depth_or_layers ||
            mip_level >= texture->mip_levels || (data == NULL && data_size != 0)) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    uint32_t mip_width = texture->width >> mip_level;
    uint32_t mip_height = texture->height >> mip_level;
    if (mip_width == 0) {
        mip_width = 1;
    }
    if (mip_height == 0) {
        mip_height = 1;
    }
    if (dest_x > mip_width || dest_y > mip_height ||
            width > mip_width - dest_x || height > mip_height - dest_y) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }

    MinecraftRenderTextureUpload *upload = find_texture_upload(
            texture, width, height, depth_or_layers, dest_x, dest_y, mip_level
    );
    uint64_t retained_without_previous = texture->uploaded_bytes;
    if (upload != NULL) {
        retained_without_previous -= upload->data_size;
    }
    if (data_size > MINECRAFT_RENDER_MAX_RESOURCE_BYTES ||
            retained_without_previous > MINECRAFT_RENDER_MAX_RESOURCE_BYTES - data_size) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }

    uint8_t *copy = data_size == 0 ? NULL : malloc(data_size);
    if (data_size != 0 && copy == NULL) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    if (data_size != 0) {
        memcpy(copy, data, data_size);
    }
    if (upload == NULL) {
        upload = calloc(1, sizeof(*upload));
        if (upload == NULL) {
            free(copy);
            return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
        }
        upload->width = width;
        upload->height = height;
        upload->depth_or_layers = depth_or_layers;
        upload->dest_x = dest_x;
        upload->dest_y = dest_y;
        upload->mip_level = mip_level;
        upload->next = texture->uploads;
        texture->uploads = upload;
        texture->upload_count++;
    } else {
        texture->uploaded_bytes -= upload->data_size;
        free(upload->bytes);
    }
    upload->bytes = copy;
    upload->data_size = data_size;
    texture->uploaded_bytes += data_size;
    texture->revision = next_revision(texture->revision);
    return true;
}

static bool begin_render_pass(void *user_data, uint32_t color_texture_id,
                              uint32_t depth_texture_id, float clear_red,
                              float clear_green, float clear_blue,
                              float clear_alpha, double clear_depth) {
    (void)clear_depth;
    MinecraftRenderNativeState *state = user_data;
    if (!state->frame_active || state->pass_active || find_texture(state, color_texture_id) == NULL ||
            (depth_texture_id != 0 && find_texture(state, depth_texture_id) == NULL)) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    state->pass_active = true;
    state->active_pipeline = 0;
    state->pending_color_texture = color_texture_id;
    state->pending_depth_texture = depth_texture_id;
    state->pending_draw_count = 0;
    state->pending_clear_red = clear_red;
    state->pending_clear_green = clear_green;
    state->pending_clear_blue = clear_blue;
    state->pending_clear_alpha = clear_alpha;
    return true;
}

static bool end_render_pass(void *user_data) {
    MinecraftRenderNativeState *state = user_data;
    if (!state->frame_active || !state->pass_active) {
        return fail(state, MINECRAFT_RENDER_BAD_FRAME_ORDER);
    }
    state->completed_color_texture = state->pending_color_texture;
    state->completed_depth_texture = state->pending_depth_texture;
    state->completed_draw_count = state->pending_draw_count;
    state->completed_clear_red = state->pending_clear_red;
    state->completed_clear_green = state->pending_clear_green;
    state->completed_clear_blue = state->pending_clear_blue;
    state->completed_clear_alpha = state->pending_clear_alpha;
    state->completed_pass_revision = next_revision(state->completed_pass_revision);
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
    if (!state->pass_active) {
        return fail(state, MINECRAFT_RENDER_BAD_FRAME_ORDER);
    }
    state->pending_draw_count++;
    return true;
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
    if (!state->pass_active) {
        return fail(state, MINECRAFT_RENDER_BAD_FRAME_ORDER);
    }
    state->pending_draw_count++;
    return true;
}

static const MinecraftRenderCommandSink NATIVE_STATE_SINK = {
    .frame_begin = frame_begin,
    .frame_end = frame_end,
    .create_buffer = create_buffer,
    .write_buffer = write_buffer,
    .create_texture = create_texture,
    .write_texture = write_texture,
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
        free_texture_uploads(texture);
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

uint64_t minecraft_render_native_buffer_attribute_at(
        const MinecraftRenderNativeState *state,
        size_t index,
        uint32_t attribute
) {
    if (state == NULL) {
        return 0;
    }
    for (const MinecraftRenderBuffer *buffer = state->buffers; buffer != NULL; buffer = buffer->next) {
        if (index-- != 0) {
            continue;
        }
        switch (attribute) {
            case MINECRAFT_RENDER_BUFFER_ATTRIBUTE_ID:
                return buffer->id;
            case MINECRAFT_RENDER_BUFFER_ATTRIBUTE_SIZE:
                return buffer->size;
            case MINECRAFT_RENDER_BUFFER_ATTRIBUTE_REVISION:
                return buffer->revision;
            default:
                return 0;
        }
    }
    return 0;
}

static uint32_t float_bits(float value) {
    uint32_t bits = 0;
    memcpy(&bits, &value, sizeof(bits));
    return bits;
}

uint32_t minecraft_render_native_pass_attribute(
        const MinecraftRenderNativeState *state,
        uint32_t attribute
) {
    if (state == NULL || state->completed_pass_revision == 0) {
        return 0;
    }
    switch (attribute) {
        case MINECRAFT_RENDER_PASS_ATTRIBUTE_COLOR_TEXTURE_ID:
            return state->completed_color_texture;
        case MINECRAFT_RENDER_PASS_ATTRIBUTE_DEPTH_TEXTURE_ID:
            return state->completed_depth_texture;
        case MINECRAFT_RENDER_PASS_ATTRIBUTE_REVISION:
            return state->completed_pass_revision;
        case MINECRAFT_RENDER_PASS_ATTRIBUTE_DRAW_COUNT:
            return state->completed_draw_count;
        case MINECRAFT_RENDER_PASS_ATTRIBUTE_CLEAR_RED_BITS:
            return float_bits(state->completed_clear_red);
        case MINECRAFT_RENDER_PASS_ATTRIBUTE_CLEAR_GREEN_BITS:
            return float_bits(state->completed_clear_green);
        case MINECRAFT_RENDER_PASS_ATTRIBUTE_CLEAR_BLUE_BITS:
            return float_bits(state->completed_clear_blue);
        case MINECRAFT_RENDER_PASS_ATTRIBUTE_CLEAR_ALPHA_BITS:
            return float_bits(state->completed_clear_alpha);
        default:
            return 0;
    }
}

uint32_t minecraft_render_native_texture_attribute_at(
        const MinecraftRenderNativeState *state,
        size_t index,
        uint32_t attribute
) {
    if (state == NULL) {
        return 0;
    }
    for (const MinecraftRenderTexture *texture = state->textures;
            texture != NULL; texture = texture->next) {
        if (index-- != 0) {
            continue;
        }
        switch (attribute) {
            case MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_ID:
                return texture->id;
            case MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_USAGE:
                return texture->usage;
            case MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_FORMAT:
                return texture->format;
            case MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_WIDTH:
                return texture->width;
            case MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_HEIGHT:
                return texture->height;
            case MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_DEPTH_OR_LAYERS:
                return texture->depth_or_layers;
            case MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_MIP_LEVELS:
                return texture->mip_levels;
            case MINECRAFT_RENDER_TEXTURE_ATTRIBUTE_REVISION:
                return texture->revision;
            default:
                return 0;
        }
    }
    return 0;
}

size_t minecraft_render_native_copy_buffer_bytes(
        const MinecraftRenderNativeState *state,
        uint32_t buffer_id,
        uint64_t offset,
        uint8_t *destination,
        size_t byte_count
) {
    if (state == NULL || destination == NULL || byte_count == 0 ||
            byte_count > MINECRAFT_RENDER_BRIDGE_MAX_CHUNK_BYTES) {
        return 0;
    }
    for (const MinecraftRenderBuffer *buffer = state->buffers;
            buffer != NULL; buffer = buffer->next) {
        if (buffer->id != buffer_id) {
            continue;
        }
        if (offset > buffer->size || byte_count > buffer->size - offset || buffer->bytes == NULL) {
            return 0;
        }
        memcpy(destination, buffer->bytes + (size_t)offset, byte_count);
        return byte_count;
    }
    return 0;
}

static bool texture_mip_layer_layout(
        const MinecraftRenderTexture *texture,
        uint32_t mip_level,
        uint32_t layer,
        uint32_t *mip_width,
        uint32_t *mip_height,
        uint64_t *byte_count
) {
    if (texture == NULL || texture->format != MINECRAFT_RENDER_RGBA8_UNORM ||
            mip_level >= texture->mip_levels || layer >= texture->depth_or_layers) {
        return false;
    }
    uint32_t width = texture->width >> mip_level;
    uint32_t height = texture->height >> mip_level;
    if (width == 0) {
        width = 1;
    }
    if (height == 0) {
        height = 1;
    }
    uint64_t size = (uint64_t)width * (uint64_t)height * MINECRAFT_RENDER_RGBA8_BYTES_PER_PIXEL;
    if (size > MINECRAFT_RENDER_MAX_RESOURCE_BYTES) {
        return false;
    }
    *mip_width = width;
    *mip_height = height;
    *byte_count = size;
    return true;
}

uint64_t minecraft_render_native_texture_mip_layer_size(
        const MinecraftRenderNativeState *state,
        uint32_t texture_id,
        uint32_t mip_level,
        uint32_t layer
) {
    if (state == NULL) {
        return 0;
    }
    for (const MinecraftRenderTexture *texture = state->textures;
            texture != NULL; texture = texture->next) {
        if (texture->id != texture_id) {
            continue;
        }
        uint32_t mip_width;
        uint32_t mip_height;
        uint64_t byte_count;
        return texture_mip_layer_layout(texture, mip_level, layer, &mip_width, &mip_height, &byte_count)
                ? byte_count : 0;
    }
    return 0;
}

static size_t texture_upload_count(const MinecraftRenderTexture *texture) {
    size_t count = 0;
    for (const MinecraftRenderTextureUpload *upload = texture->uploads;
            upload != NULL; upload = upload->next) {
        count++;
    }
    return count;
}

static void composite_texture_upload(
        const MinecraftRenderTextureUpload *upload,
        uint32_t mip_level,
        uint32_t mip_width,
        uint32_t mip_height,
        uint32_t layer,
        uint64_t range_offset,
        uint8_t *destination,
        size_t byte_count
) {
    /* Regions are retained per mip. Applying another mip's region here would
     * paint it into the wrong Godot mip-chain slice. */
    if (upload->mip_level != mip_level || upload->bytes == NULL ||
            layer >= upload->depth_or_layers ||
            upload->dest_x >= mip_width || upload->dest_y >= mip_height ||
            upload->width > mip_width - upload->dest_x ||
            upload->height > mip_height - upload->dest_y) {
        return;
    }
    uint64_t source_layer_stride = (uint64_t)upload->width * upload->height *
            MINECRAFT_RENDER_RGBA8_BYTES_PER_PIXEL;
    if (source_layer_stride == 0 || source_layer_stride > upload->data_size ||
            layer > (UINT64_MAX / source_layer_stride) ||
            (uint64_t)layer * source_layer_stride >= upload->data_size) {
        return;
    }
    uint64_t range_end = range_offset + byte_count;
    for (uint32_t row = 0; row < upload->height; row++) {
        uint64_t source_offset = (uint64_t)layer * source_layer_stride +
                (uint64_t)row * upload->width * MINECRAFT_RENDER_RGBA8_BYTES_PER_PIXEL;
        uint64_t row_bytes = (uint64_t)upload->width * MINECRAFT_RENDER_RGBA8_BYTES_PER_PIXEL;
        if (source_offset > upload->data_size || row_bytes > upload->data_size - source_offset) {
            return;
        }
        uint64_t target_offset = ((uint64_t)(upload->dest_y + row) * mip_width + upload->dest_x) *
                MINECRAFT_RENDER_RGBA8_BYTES_PER_PIXEL;
        uint64_t target_end = target_offset + row_bytes;
        uint64_t copy_start = target_offset > range_offset ? target_offset : range_offset;
        uint64_t copy_end = target_end < range_end ? target_end : range_end;
        if (copy_start < copy_end) {
            memcpy(destination + (size_t)(copy_start - range_offset),
                    upload->bytes + (size_t)(source_offset + copy_start - target_offset),
                    (size_t)(copy_end - copy_start));
        }
    }
}

size_t minecraft_render_native_copy_texture_mip_layer_bytes(
        const MinecraftRenderNativeState *state,
        uint32_t texture_id,
        uint32_t mip_level,
        uint32_t layer,
        uint64_t offset,
        uint8_t *destination,
        size_t byte_count
) {
    if (state == NULL || destination == NULL || byte_count == 0 ||
            byte_count > MINECRAFT_RENDER_BRIDGE_MAX_CHUNK_BYTES) {
        return 0;
    }
    for (const MinecraftRenderTexture *texture = state->textures;
            texture != NULL; texture = texture->next) {
        if (texture->id != texture_id) {
            continue;
        }
        uint32_t mip_width;
        uint32_t mip_height;
        uint64_t image_size;
        if (!texture_mip_layer_layout(texture, mip_level, layer, &mip_width, &mip_height, &image_size) ||
                offset > image_size || byte_count > image_size - offset) {
            return 0;
        }
        memset(destination, 0, byte_count);
        size_t upload_count = texture_upload_count(texture);
        if (upload_count == 0) {
            return byte_count;
        }
        const MinecraftRenderTextureUpload **uploads = calloc(upload_count, sizeof(*uploads));
        if (uploads == NULL) {
            return 0;
        }
        size_t index = 0;
        for (const MinecraftRenderTextureUpload *upload = texture->uploads;
                upload != NULL; upload = upload->next) {
            uploads[index++] = upload;
        }
        /* The linked list is newest-first; compose oldest-to-newest. */
        while (index != 0) {
            composite_texture_upload(uploads[--index], mip_level, mip_width, mip_height, layer,
                    offset, destination, byte_count);
        }
        free(uploads);
        return byte_count;
    }
    return 0;
}

size_t minecraft_render_native_texture_upload_count(
        const MinecraftRenderNativeState *state,
        uint32_t texture_id
) {
    if (state == NULL) {
        return 0;
    }
    for (const MinecraftRenderTexture *texture = state->textures;
            texture != NULL; texture = texture->next) {
        if (texture->id == texture_id) {
            return texture->upload_count;
        }
    }
    return 0;
}

uint64_t minecraft_render_native_texture_uploaded_bytes(
        const MinecraftRenderNativeState *state,
        uint32_t texture_id
) {
    if (state == NULL) {
        return 0;
    }
    for (const MinecraftRenderTexture *texture = state->textures;
            texture != NULL; texture = texture->next) {
        if (texture->id == texture_id) {
            return texture->uploaded_bytes;
        }
    }
    return 0;
}
