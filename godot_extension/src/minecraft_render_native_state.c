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

#define MINECRAFT_RENDER_MAX_PIPELINES 1024u
#define MINECRAFT_RENDER_MAX_DRAWS 16384u
#define MINECRAFT_RENDER_MAX_PASSES 256u

typedef struct MinecraftRenderPipelineRecord {
    uint32_t id;
    uint32_t family;
    uint32_t topology;
    uint32_t blend;
    uint32_t vertex_stride;
    uint32_t attribute_count;
    uint32_t flags;
    MinecraftRenderPipelineAttribute attributes[MINECRAFT_RENDER_MAX_PIPELINE_ATTRIBUTES];
} MinecraftRenderPipelineRecord;

typedef struct MinecraftRenderRangeBinding {
    uint32_t buffer_id;
    uint64_t offset;
    uint64_t length;
    bool bound;
} MinecraftRenderRangeBinding;

typedef struct MinecraftRenderSamplerBinding {
    uint32_t texture_id;
    uint32_t base_mip;
    uint32_t min_filter;
    uint32_t mag_filter;
    uint32_t address_u;
    uint32_t address_v;
    bool bound;
} MinecraftRenderSamplerBinding;

typedef struct MinecraftRenderDrawRecord {
    uint32_t color_texture_id;
    uint32_t pipeline_id;
    uint32_t family;
    uint32_t blend;
    uint32_t topology;
    uint32_t kind;
    uint32_t count;
    uint32_t instance_count;
    uint32_t first;
    int32_t base_vertex;
    uint32_t first_instance;
    uint32_t vertex_buffer_id;
    uint32_t vertex_stride;
    uint64_t vertex_offset;
    uint64_t vertex_length;
    uint32_t index_buffer_id;
    uint32_t index_type;
    uint64_t index_offset;
    uint64_t index_length;
    uint32_t scissor_x;
    uint32_t scissor_y;
    uint32_t scissor_width;
    uint32_t scissor_height;
    uint32_t dynamic_buffer_id;
    uint64_t dynamic_offset;
    uint64_t dynamic_length;
    uint32_t projection_buffer_id;
    uint64_t projection_offset;
    uint64_t projection_length;
    uint32_t sampler0_texture_id;
    uint32_t sampler0_base_mip;
    uint32_t sampler0_min_filter;
    uint32_t sampler0_mag_filter;
    uint32_t sampler0_address_u;
    uint32_t sampler0_address_v;
} MinecraftRenderDrawRecord;

typedef struct MinecraftRenderPassRecord {
    uint32_t color_texture;
    uint32_t depth_texture;
    uint32_t draw_start;
    uint32_t draw_count;
    float clear_red;
    float clear_green;
    float clear_blue;
    float clear_alpha;
} MinecraftRenderPassRecord;

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
    uint32_t completed_draw_start;
    uint32_t completed_pass_revision;
    float completed_clear_red;
    float completed_clear_green;
    float completed_clear_blue;
    float completed_clear_alpha;
    bool frame_active;
    bool pass_active;
    bool vertex_bound;
    bool index_bound;
    int callback_status;
    int last_execution_status;
    MinecraftRenderPipelineRecord *pipelines;
    MinecraftRenderDrawRecord *draws;
    MinecraftRenderPassRecord *passes;
    size_t pipeline_count;
    size_t draw_count;
    size_t pass_count;
    uint32_t bound_vertex_buffer;
    uint64_t bound_vertex_offset;
    uint64_t bound_vertex_length;
    uint32_t bound_index_buffer;
    uint32_t bound_index_type;
    uint64_t bound_index_offset;
    uint64_t bound_index_length;
    uint32_t scissor_x;
    uint32_t scissor_y;
    uint32_t scissor_width;
    uint32_t scissor_height;
    MinecraftRenderRangeBinding dynamic_uniform;
    MinecraftRenderRangeBinding projection_uniform;
    MinecraftRenderSamplerBinding sampler0;
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
    state->draw_count = 0;
    state->pass_count = 0;
    state->completed_color_texture = 0;
    state->completed_depth_texture = 0;
    state->completed_draw_count = 0;
    state->completed_draw_start = 0;
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
    if (state->pass_count >= MINECRAFT_RENDER_MAX_PASSES) {
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
    state->vertex_bound = false;
    state->index_bound = false;
    state->bound_vertex_buffer = 0;
    state->bound_index_buffer = 0;
    state->scissor_x = 0;
    state->scissor_y = 0;
    state->scissor_width = state->frame_width;
    state->scissor_height = state->frame_height;
    memset(&state->dynamic_uniform, 0, sizeof(state->dynamic_uniform));
    memset(&state->projection_uniform, 0, sizeof(state->projection_uniform));
    memset(&state->sampler0, 0, sizeof(state->sampler0));
    return true;
}

static bool end_render_pass(void *user_data) {
    MinecraftRenderNativeState *state = user_data;
    if (!state->frame_active || !state->pass_active) {
        return fail(state, MINECRAFT_RENDER_BAD_FRAME_ORDER);
    }
    MinecraftRenderPassRecord *pass = &state->passes[state->pass_count++];
    pass->color_texture = state->pending_color_texture;
    pass->depth_texture = state->pending_depth_texture;
    pass->draw_start = (uint32_t)(state->draw_count - state->pending_draw_count);
    pass->draw_count = state->pending_draw_count;
    pass->clear_red = state->pending_clear_red;
    pass->clear_green = state->pending_clear_green;
    pass->clear_blue = state->pending_clear_blue;
    pass->clear_alpha = state->pending_clear_alpha;
    state->completed_color_texture = state->pending_color_texture;
    state->completed_depth_texture = state->pending_depth_texture;
    state->completed_draw_count = state->pending_draw_count;
    state->completed_draw_start = pass->draw_start;
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
    state->active_pipeline = pipeline_id;
    return true;
}

static bool set_vertex_buffer(void *user_data, uint32_t slot, uint32_t buffer_id,
                              uint64_t offset, uint64_t length) {
    MinecraftRenderNativeState *state = user_data;
    MinecraftRenderBuffer *buffer = find_buffer(state, buffer_id);
    if (!state->pass_active || buffer == NULL || offset > buffer->size ||
            length > buffer->size - offset) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    if (slot == 0) {
        state->vertex_bound = true;
        state->bound_vertex_buffer = buffer_id;
        state->bound_vertex_offset = offset;
        state->bound_vertex_length = length;
    }
    return true;
}

static bool set_index_buffer(void *user_data, uint32_t buffer_id, uint32_t index_type,
                             uint64_t offset, uint64_t length) {
    MinecraftRenderNativeState *state = user_data;
    MinecraftRenderBuffer *buffer = find_buffer(state, buffer_id);
    if (!state->pass_active || buffer == NULL || offset > buffer->size ||
            length > buffer->size - offset || index_type > 1u) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    state->index_bound = true;
    state->bound_index_buffer = buffer_id;
    state->bound_index_type = index_type;
    state->bound_index_offset = offset;
    state->bound_index_length = length;
    return true;
}

static bool set_scissor(void *user_data, uint32_t x, uint32_t y,
                        uint32_t width, uint32_t height) {
    MinecraftRenderNativeState *state = user_data;
    if (!state->pass_active || x > state->frame_width || y > state->frame_height ||
            width > state->frame_width - x || height > state->frame_height - y) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    state->scissor_x = x;
    state->scissor_y = y;
    state->scissor_width = width;
    state->scissor_height = height;
    return true;
}

static bool bytes_contain(const uint8_t *bytes, uint32_t length, const char *needle) {
    size_t needle_length = strlen(needle);
    if (bytes == NULL || needle_length == 0 || length < needle_length) {
        return false;
    }
    for (uint32_t index = 0; index + needle_length <= length; index++) {
        if (memcmp(bytes + index, needle, needle_length) == 0) {
            return true;
        }
    }
    return false;
}

static bool name_is(const uint8_t *name, uint32_t length, const char *expected) {
    size_t expected_length = strlen(expected);
    return name != NULL && length == expected_length && memcmp(name, expected, length) == 0;
}

static MinecraftRenderPipelineRecord *find_pipeline(MinecraftRenderNativeState *state, uint32_t id) {
    for (size_t index = 0; index < state->pipeline_count; index++) {
        if (state->pipelines[index].id == id) {
            return &state->pipelines[index];
        }
    }
    return NULL;
}

static bool range_in_buffer(const MinecraftRenderBuffer *buffer, uint64_t offset, uint64_t length) {
    return buffer != NULL && offset <= buffer->size && length <= buffer->size - offset;
}

static bool compile_pipeline(void *user_data, const MinecraftRenderCompiledPipeline *pipeline) {
    MinecraftRenderNativeState *state = user_data;
    if (!state->frame_active || state->pass_active || pipeline == NULL || pipeline->pipeline_id == 0 ||
            pipeline->family > MINECRAFT_RENDER_PIPELINE_FAMILY_GUI_TEXT ||
            pipeline->attribute_count > MINECRAFT_RENDER_MAX_PIPELINE_ATTRIBUTES ||
            pipeline->vertex_stride > 4096u ||
            (pipeline->attribute_count != 0 && pipeline->attributes == NULL)) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    for (uint32_t index = 0; index < pipeline->attribute_count; index++) {
        if (pipeline->attributes[index].location > 255u ||
                (pipeline->vertex_stride != 0 &&
                        pipeline->attributes[index].offset > pipeline->vertex_stride)) {
            return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
        }
    }
    MinecraftRenderPipelineRecord *record = find_pipeline(state, pipeline->pipeline_id);
    if (record == NULL) {
        if (state->pipeline_count >= MINECRAFT_RENDER_MAX_PIPELINES) {
            return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
        }
        record = &state->pipelines[state->pipeline_count++];
        memset(record, 0, sizeof(*record));
        record->id = pipeline->pipeline_id;
    }
    record->family = pipeline->family;
    record->topology = pipeline->topology;
    record->blend = pipeline->blend;
    record->vertex_stride = pipeline->vertex_stride;
    record->attribute_count = pipeline->attribute_count;
    record->flags = 0;
    if (bytes_contain(pipeline->location, pipeline->location_length, "grayscale") ||
            bytes_contain(pipeline->vertex_shader, pipeline->vertex_shader_length, "grayscale") ||
            bytes_contain(pipeline->fragment_shader, pipeline->fragment_shader_length, "grayscale")) {
        record->flags |= 1u;
    }
    if (pipeline->attribute_count != 0) {
        memcpy(record->attributes, pipeline->attributes,
                pipeline->attribute_count * sizeof(*pipeline->attributes));
    }
    return true;
}

static bool set_uniform_buffer(void *user_data, const MinecraftRenderUniformBufferBinding *binding) {
    MinecraftRenderNativeState *state = user_data;
    if (!state->pass_active || binding == NULL || binding->name == NULL) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    MinecraftRenderBuffer *buffer = find_buffer(state, binding->buffer_id);
    if (!range_in_buffer(buffer, binding->offset, binding->length)) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    MinecraftRenderRangeBinding stored = {
        .buffer_id = binding->buffer_id,
        .offset = binding->offset,
        .length = binding->length,
        .bound = true,
    };
    if (name_is(binding->name, binding->name_length, "DynamicTransforms") ||
            name_is(binding->name, binding->name_length, "dynamicTransforms")) {
        state->dynamic_uniform = stored;
    } else if (name_is(binding->name, binding->name_length, "Projection") ||
            name_is(binding->name, binding->name_length, "projection")) {
        state->projection_uniform = stored;
    }
    return true;
}

static bool set_texture_sampler(void *user_data, const MinecraftRenderTextureSamplerBinding *binding) {
    MinecraftRenderNativeState *state = user_data;
    MinecraftRenderTexture *texture = binding == NULL ? NULL : find_texture(state, binding->texture_id);
    if (!state->pass_active || binding == NULL || binding->name == NULL || binding->sampler_id == 0 ||
            texture == NULL || binding->base_mip >= texture->mip_levels) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    if (name_is(binding->name, binding->name_length, "Sampler0") ||
            name_is(binding->name, binding->name_length, "sampler0")) {
        state->sampler0.texture_id = binding->texture_id;
        state->sampler0.base_mip = binding->base_mip;
        state->sampler0.min_filter = binding->min_filter;
        state->sampler0.mag_filter = binding->mag_filter;
        state->sampler0.address_u = binding->address_u;
        state->sampler0.address_v = binding->address_v;
        state->sampler0.bound = true;
    }
    return true;
}

static bool retain_draw(MinecraftRenderNativeState *state, uint32_t kind, uint32_t count,
                        uint32_t instance_count, uint32_t first, int32_t base_vertex,
                        uint32_t first_instance) {
    if (!state->pass_active) {
        return fail(state, MINECRAFT_RENDER_BAD_FRAME_ORDER);
    }
    if (state->draw_count >= MINECRAFT_RENDER_MAX_DRAWS) {
        return fail(state, MINECRAFT_RENDER_INVALID_ARGUMENT);
    }
    const MinecraftRenderPipelineRecord *pipeline = find_pipeline(state, state->active_pipeline);
    MinecraftRenderDrawRecord *draw = &state->draws[state->draw_count++];
    memset(draw, 0, sizeof(*draw));
    draw->color_texture_id = state->pending_color_texture;
    draw->pipeline_id = state->active_pipeline;
    draw->family = pipeline == NULL ? MINECRAFT_RENDER_PIPELINE_FAMILY_UNKNOWN : pipeline->family;
    draw->blend = pipeline == NULL ? 0 : pipeline->blend;
    draw->topology = pipeline == NULL ? 0 : pipeline->topology;
    draw->kind = kind;
    draw->count = count;
    draw->instance_count = instance_count;
    draw->first = first;
    draw->base_vertex = base_vertex;
    draw->first_instance = first_instance;
    draw->vertex_buffer_id = state->vertex_bound ? state->bound_vertex_buffer : 0;
    draw->vertex_stride = pipeline == NULL ? 0 : pipeline->vertex_stride;
    draw->vertex_offset = state->vertex_bound ? state->bound_vertex_offset : 0;
    draw->vertex_length = state->vertex_bound ? state->bound_vertex_length : 0;
    draw->index_buffer_id = state->index_bound ? state->bound_index_buffer : 0;
    draw->index_type = state->index_bound ? state->bound_index_type : 0;
    draw->index_offset = state->index_bound ? state->bound_index_offset : 0;
    draw->index_length = state->index_bound ? state->bound_index_length : 0;
    draw->scissor_x = state->scissor_x;
    draw->scissor_y = state->scissor_y;
    draw->scissor_width = state->scissor_width;
    draw->scissor_height = state->scissor_height;
    if (state->dynamic_uniform.bound) {
        draw->dynamic_buffer_id = state->dynamic_uniform.buffer_id;
        draw->dynamic_offset = state->dynamic_uniform.offset;
        draw->dynamic_length = state->dynamic_uniform.length;
    }
    if (state->projection_uniform.bound) {
        draw->projection_buffer_id = state->projection_uniform.buffer_id;
        draw->projection_offset = state->projection_uniform.offset;
        draw->projection_length = state->projection_uniform.length;
    }
    if (state->sampler0.bound) {
        draw->sampler0_texture_id = state->sampler0.texture_id;
        draw->sampler0_base_mip = state->sampler0.base_mip;
        draw->sampler0_min_filter = state->sampler0.min_filter;
        draw->sampler0_mag_filter = state->sampler0.mag_filter;
        draw->sampler0_address_u = state->sampler0.address_u;
        draw->sampler0_address_v = state->sampler0.address_v;
    }
    state->pending_draw_count++;
    return true;
}

static bool draw(void *user_data, uint32_t vertex_count, uint32_t instance_count,
                 uint32_t first_vertex, uint32_t first_instance) {
    return retain_draw(user_data, 1u, vertex_count, instance_count, first_vertex, 0, first_instance);
}

static bool draw_indexed(void *user_data, uint32_t index_count, uint32_t instance_count,
                         uint32_t first_index, int32_t vertex_offset,
                         uint32_t first_instance) {
    return retain_draw(user_data, 2u, index_count, instance_count, first_index, vertex_offset,
            first_instance);
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
    .compile_pipeline = compile_pipeline,
    .set_uniform_buffer = set_uniform_buffer,
    .set_texture_sampler = set_texture_sampler,
    .set_scissor = set_scissor,
    .draw = draw,
    .draw_indexed = draw_indexed,
};

MinecraftRenderNativeState *minecraft_render_native_state_create(void) {
    MinecraftRenderNativeState *state = calloc(1, sizeof(*state));
    if (state == NULL) {
        return NULL;
    }
    state->pipelines = calloc(MINECRAFT_RENDER_MAX_PIPELINES, sizeof(*state->pipelines));
    state->draws = calloc(MINECRAFT_RENDER_MAX_DRAWS, sizeof(*state->draws));
    state->passes = calloc(MINECRAFT_RENDER_MAX_PASSES, sizeof(*state->passes));
    if (state->pipelines == NULL || state->draws == NULL || state->passes == NULL) {
        free(state->pipelines);
        free(state->draws);
        free(state->passes);
        free(state);
        return NULL;
    }
    state->last_execution_status = MINECRAFT_RENDER_NO_FRAME;
    return state;
}

void minecraft_render_native_state_destroy(MinecraftRenderNativeState *state) {
    if (state == NULL) {
        return;
    }
    free(state->pipelines);
    free(state->draws);
    free(state->passes);
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
            case MINECRAFT_RENDER_BUFFER_ATTRIBUTE_USAGE:
                return buffer->usage;
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
        case MINECRAFT_RENDER_PASS_ATTRIBUTE_DRAW_START:
            return state->completed_draw_start;
        default:
            return 0;
    }
}

size_t minecraft_render_native_frame_pass_count(const MinecraftRenderNativeState *state) {
    return state == NULL ? 0 : state->pass_count;
}

uint32_t minecraft_render_native_frame_pass_attribute(
        const MinecraftRenderNativeState *state,
        size_t pass_index,
        uint32_t attribute
) {
    if (state == NULL || pass_index >= state->pass_count) {
        return 0;
    }
    const MinecraftRenderPassRecord *pass = &state->passes[pass_index];
    switch (attribute) {
        case MINECRAFT_RENDER_PASS_ATTRIBUTE_COLOR_TEXTURE_ID:
            return pass->color_texture;
        case MINECRAFT_RENDER_PASS_ATTRIBUTE_DEPTH_TEXTURE_ID:
            return pass->depth_texture;
        case MINECRAFT_RENDER_PASS_ATTRIBUTE_DRAW_COUNT:
            return pass->draw_count;
        case MINECRAFT_RENDER_PASS_ATTRIBUTE_CLEAR_RED_BITS:
            return float_bits(pass->clear_red);
        case MINECRAFT_RENDER_PASS_ATTRIBUTE_CLEAR_GREEN_BITS:
            return float_bits(pass->clear_green);
        case MINECRAFT_RENDER_PASS_ATTRIBUTE_CLEAR_BLUE_BITS:
            return float_bits(pass->clear_blue);
        case MINECRAFT_RENDER_PASS_ATTRIBUTE_CLEAR_ALPHA_BITS:
            return float_bits(pass->clear_alpha);
        case MINECRAFT_RENDER_PASS_ATTRIBUTE_DRAW_START:
            return pass->draw_start;
        default:
            return 0;
    }
}

size_t minecraft_render_native_draw_count(const MinecraftRenderNativeState *state) {
    return state == NULL ? 0 : state->draw_count;
}

int64_t minecraft_render_native_draw_attribute(
        const MinecraftRenderNativeState *state,
        size_t draw_index,
        uint32_t attribute
) {
    if (state == NULL || draw_index >= state->draw_count) {
        return 0;
    }
    const MinecraftRenderDrawRecord *draw = &state->draws[draw_index];
    switch (attribute) {
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_COLOR_TEXTURE_ID:
            return draw->color_texture_id;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_PIPELINE_ID:
            return draw->pipeline_id;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_FAMILY:
            return draw->family;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_BLEND:
            return draw->blend;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_TOPOLOGY:
            return draw->topology;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_KIND:
            return draw->kind;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_COUNT:
            return draw->count;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_INSTANCE_COUNT:
            return draw->instance_count;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_FIRST:
            return draw->first;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_BASE_VERTEX:
            return draw->base_vertex;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_FIRST_INSTANCE:
            return draw->first_instance;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_VERTEX_BUFFER_ID:
            return draw->vertex_buffer_id;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_VERTEX_STRIDE:
            return draw->vertex_stride;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_VERTEX_OFFSET:
            return (int64_t)draw->vertex_offset;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_VERTEX_LENGTH:
            return (int64_t)draw->vertex_length;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_INDEX_BUFFER_ID:
            return draw->index_buffer_id;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_INDEX_TYPE:
            return draw->index_type;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_INDEX_OFFSET:
            return (int64_t)draw->index_offset;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_INDEX_LENGTH:
            return (int64_t)draw->index_length;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_SCISSOR_X:
            return draw->scissor_x;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_SCISSOR_Y:
            return draw->scissor_y;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_SCISSOR_WIDTH:
            return draw->scissor_width;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_SCISSOR_HEIGHT:
            return draw->scissor_height;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_DYNAMIC_BUFFER_ID:
            return draw->dynamic_buffer_id;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_DYNAMIC_OFFSET:
            return (int64_t)draw->dynamic_offset;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_DYNAMIC_LENGTH:
            return (int64_t)draw->dynamic_length;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_PROJECTION_BUFFER_ID:
            return draw->projection_buffer_id;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_PROJECTION_OFFSET:
            return (int64_t)draw->projection_offset;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_PROJECTION_LENGTH:
            return (int64_t)draw->projection_length;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_SAMPLER0_TEXTURE_ID:
            return draw->sampler0_texture_id;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_SAMPLER0_BASE_MIP:
            return draw->sampler0_base_mip;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_SAMPLER0_MIN_FILTER:
            return draw->sampler0_min_filter;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_SAMPLER0_MAG_FILTER:
            return draw->sampler0_mag_filter;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_SAMPLER0_ADDRESS_U:
            return draw->sampler0_address_u;
        case MINECRAFT_RENDER_DRAW_ATTRIBUTE_SAMPLER0_ADDRESS_V:
            return draw->sampler0_address_v;
        default:
            return 0;
    }
}

static const MinecraftRenderPipelineRecord *find_pipeline_const(
        const MinecraftRenderNativeState *state,
        uint32_t pipeline_id
) {
    if (state == NULL) {
        return NULL;
    }
    for (size_t index = 0; index < state->pipeline_count; index++) {
        if (state->pipelines[index].id == pipeline_id) {
            return &state->pipelines[index];
        }
    }
    return NULL;
}

int64_t minecraft_render_native_pipeline_attribute(
        const MinecraftRenderNativeState *state,
        uint32_t pipeline_id,
        uint32_t attribute
) {
    const MinecraftRenderPipelineRecord *pipeline = find_pipeline_const(state, pipeline_id);
    if (pipeline == NULL) {
        return 0;
    }
    switch (attribute) {
        case MINECRAFT_RENDER_PIPELINE_ATTRIBUTE_FAMILY:
            return pipeline->family;
        case MINECRAFT_RENDER_PIPELINE_ATTRIBUTE_BLEND:
            return pipeline->blend;
        case MINECRAFT_RENDER_PIPELINE_ATTRIBUTE_TOPOLOGY:
            return pipeline->topology;
        case MINECRAFT_RENDER_PIPELINE_ATTRIBUTE_VERTEX_STRIDE:
            return pipeline->vertex_stride;
        case MINECRAFT_RENDER_PIPELINE_ATTRIBUTE_ATTRIBUTE_COUNT:
            return pipeline->attribute_count;
        case MINECRAFT_RENDER_PIPELINE_ATTRIBUTE_FLAGS:
            return pipeline->flags;
        default:
            return 0;
    }
}

int64_t minecraft_render_native_pipeline_vertex_attribute(
        const MinecraftRenderNativeState *state,
        uint32_t pipeline_id,
        uint32_t attribute_index,
        uint32_t field
) {
    const MinecraftRenderPipelineRecord *pipeline = find_pipeline_const(state, pipeline_id);
    if (pipeline == NULL || attribute_index >= pipeline->attribute_count) {
        return 0;
    }
    const MinecraftRenderPipelineAttribute *attribute = &pipeline->attributes[attribute_index];
    switch (field) {
        case MINECRAFT_RENDER_VERTEX_ATTRIBUTE_LOCATION:
            return attribute->location;
        case MINECRAFT_RENDER_VERTEX_ATTRIBUTE_OFFSET:
            return attribute->offset;
        case MINECRAFT_RENDER_VERTEX_ATTRIBUTE_FORMAT:
            return attribute->format;
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
