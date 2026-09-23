#include "minecraft_render_abi.h"

#include <limits.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#define MINECRAFT_RENDER_MAX_FRAME_BYTES (64u * 1024u * 1024u)

_Static_assert(sizeof(MinecraftRenderPacketHeader) == MINECRAFT_RENDER_PACKET_HEADER_BYTES,
               "Minecraft render packet header must match the wire format");

static pthread_mutex_t latest_frame_mutex = PTHREAD_MUTEX_INITIALIZER;
static uint8_t *latest_frame_bytes;
static size_t latest_frame_size;
static int latest_frame_packet_count;
static int latest_submission_status = MINECRAFT_RENDER_INVALID_ARGUMENT;

static uint16_t read_u16_le(const uint8_t *bytes) {
    return (uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8);
}

static uint32_t read_u32_le(const uint8_t *bytes) {
    return (uint32_t)bytes[0] |
           ((uint32_t)bytes[1] << 8) |
           ((uint32_t)bytes[2] << 16) |
           ((uint32_t)bytes[3] << 24);
}

static bool is_known_opcode(uint16_t opcode) {
    return opcode >= MINECRAFT_RENDER_FRAME_BEGIN && opcode <= MINECRAFT_RENDER_DRAW_INDEXED;
}

static bool is_draw_opcode(uint16_t opcode) {
    return opcode == MINECRAFT_RENDER_DRAW || opcode == MINECRAFT_RENDER_DRAW_INDEXED;
}

static bool is_pass_command(uint16_t opcode) {
    return opcode == MINECRAFT_RENDER_SET_PIPELINE ||
           opcode == MINECRAFT_RENDER_SET_VERTEX_BUFFER ||
           opcode == MINECRAFT_RENDER_SET_INDEX_BUFFER ||
           opcode == MINECRAFT_RENDER_SET_UNIFORM_BUFFER ||
           opcode == MINECRAFT_RENDER_SET_TEXTURE_SAMPLER ||
           opcode == MINECRAFT_RENDER_SET_SCISSOR ||
           is_draw_opcode(opcode);
}

int minecraft_render_visit_frame(
    const uint8_t *frame_bytes,
    size_t frame_size,
    MinecraftRenderPacketVisitor visitor,
    void *user_data
) {
    if (frame_bytes == NULL || visitor == NULL || frame_size == 0) {
        return MINECRAFT_RENDER_INVALID_ARGUMENT;
    }

    size_t offset = 0;
    int packet_count = 0;
    bool frame_open = false;
    bool frame_closed = false;
    bool render_pass_open = false;

    while (offset < frame_size) {
        if (frame_size - offset < sizeof(MinecraftRenderPacketHeader)) {
            return MINECRAFT_RENDER_TRUNCATED_PACKET;
        }

        const uint8_t *packet_bytes = frame_bytes + offset;
        MinecraftRenderPacketHeader header = {
            .opcode = read_u16_le(packet_bytes),
            .reserved = read_u16_le(packet_bytes + 2),
            .packet_size = read_u32_le(packet_bytes + 4),
        };
        if (header.reserved != 0 || header.packet_size < sizeof(header) ||
            (header.packet_size % MINECRAFT_RENDER_PACKET_ALIGNMENT) != 0) {
            return MINECRAFT_RENDER_BAD_ALIGNMENT;
        }
        if ((size_t)header.packet_size > frame_size - offset) {
            return MINECRAFT_RENDER_TRUNCATED_PACKET;
        }
        if (!is_known_opcode(header.opcode)) {
            return MINECRAFT_RENDER_UNKNOWN_OPCODE;
        }

        switch (header.opcode) {
            case MINECRAFT_RENDER_FRAME_BEGIN:
                if (frame_open || frame_closed || render_pass_open || offset != 0) {
                    return MINECRAFT_RENDER_BAD_FRAME_ORDER;
                }
                frame_open = true;
                break;
            case MINECRAFT_RENDER_FRAME_END:
                if (!frame_open || frame_closed || render_pass_open ||
                    offset + header.packet_size != frame_size) {
                    return MINECRAFT_RENDER_BAD_FRAME_ORDER;
                }
                frame_closed = true;
                break;
            case MINECRAFT_RENDER_BEGIN_RENDER_PASS:
                if (!frame_open || frame_closed || render_pass_open) {
                    return MINECRAFT_RENDER_BAD_FRAME_ORDER;
                }
                render_pass_open = true;
                break;
            case MINECRAFT_RENDER_END_RENDER_PASS:
                if (!frame_open || frame_closed || !render_pass_open) {
                    return MINECRAFT_RENDER_BAD_FRAME_ORDER;
                }
                render_pass_open = false;
                break;
            default:
                if (!frame_open || frame_closed) {
                    return MINECRAFT_RENDER_BAD_FRAME_ORDER;
                }
                if (is_pass_command(header.opcode) != render_pass_open) {
                    return MINECRAFT_RENDER_BAD_FRAME_ORDER;
                }
                break;
        }

        if (!visitor(&header, packet_bytes, user_data)) {
            return MINECRAFT_RENDER_VISITOR_REJECTED;
        }
        if (packet_count == INT_MAX) {
            return MINECRAFT_RENDER_INVALID_ARGUMENT;
        }
        packet_count++;
        offset += header.packet_size;
    }

    if (!frame_open || !frame_closed || render_pass_open) {
        return MINECRAFT_RENDER_BAD_FRAME_ORDER;
    }
    return packet_count;
}

static bool accept_packet(const MinecraftRenderPacketHeader *header,
                          const uint8_t *packet_bytes,
                          void *user_data) {
    (void)header;
    (void)packet_bytes;
    (void)user_data;
    return true;
}

int minecraft_render_submit_frame(const uint8_t *frame_bytes, size_t frame_size) {
    if (frame_size > MINECRAFT_RENDER_MAX_FRAME_BYTES) {
        pthread_mutex_lock(&latest_frame_mutex);
        latest_submission_status = MINECRAFT_RENDER_INVALID_ARGUMENT;
        pthread_mutex_unlock(&latest_frame_mutex);
        return MINECRAFT_RENDER_INVALID_ARGUMENT;
    }

    int validation = minecraft_render_visit_frame(frame_bytes, frame_size, accept_packet, NULL);
    if (validation < 0) {
        pthread_mutex_lock(&latest_frame_mutex);
        latest_submission_status = validation;
        pthread_mutex_unlock(&latest_frame_mutex);
        return validation;
    }

    uint8_t *copy = malloc(frame_size);
    if (copy == NULL) {
        pthread_mutex_lock(&latest_frame_mutex);
        latest_submission_status = MINECRAFT_RENDER_INVALID_ARGUMENT;
        pthread_mutex_unlock(&latest_frame_mutex);
        return MINECRAFT_RENDER_INVALID_ARGUMENT;
    }
    memcpy(copy, frame_bytes, frame_size);

    pthread_mutex_lock(&latest_frame_mutex);
    free(latest_frame_bytes);
    latest_frame_bytes = copy;
    latest_frame_size = frame_size;
    latest_frame_packet_count = validation;
    latest_submission_status = validation;
    pthread_mutex_unlock(&latest_frame_mutex);
    return validation;
}

int minecraft_render_last_submission_status(void) {
    pthread_mutex_lock(&latest_frame_mutex);
    int status = latest_submission_status;
    pthread_mutex_unlock(&latest_frame_mutex);
    return status;
}

size_t minecraft_render_latest_frame_size(void) {
    pthread_mutex_lock(&latest_frame_mutex);
    size_t size = latest_frame_size;
    pthread_mutex_unlock(&latest_frame_mutex);
    return size;
}

size_t minecraft_render_copy_latest_frame(uint8_t *destination, size_t destination_size) {
    pthread_mutex_lock(&latest_frame_mutex);
    if (destination == NULL || destination_size < latest_frame_size) {
        pthread_mutex_unlock(&latest_frame_mutex);
        return 0;
    }
    if (latest_frame_size != 0) {
        memcpy(destination, latest_frame_bytes, latest_frame_size);
    }
    size_t copied_size = latest_frame_size;
    pthread_mutex_unlock(&latest_frame_mutex);
    return copied_size;
}

int minecraft_render_take_latest_frame(MinecraftRenderFrame *frame) {
    if (frame == NULL) {
        return MINECRAFT_RENDER_INVALID_ARGUMENT;
    }
    frame->bytes = NULL;
    frame->size = 0;

    pthread_mutex_lock(&latest_frame_mutex);
    if (latest_frame_bytes == NULL) {
        pthread_mutex_unlock(&latest_frame_mutex);
        return MINECRAFT_RENDER_NO_FRAME;
    }

    frame->bytes = latest_frame_bytes;
    frame->size = latest_frame_size;
    int packet_count = latest_frame_packet_count;
    latest_frame_bytes = NULL;
    latest_frame_size = 0;
    latest_frame_packet_count = 0;
    pthread_mutex_unlock(&latest_frame_mutex);
    return packet_count;
}

void minecraft_render_release_frame(MinecraftRenderFrame *frame) {
    if (frame == NULL) {
        return;
    }
    free(frame->bytes);
    frame->bytes = NULL;
    frame->size = 0;
}

void minecraft_render_clear_latest_frame(void) {
    pthread_mutex_lock(&latest_frame_mutex);
    free(latest_frame_bytes);
    latest_frame_bytes = NULL;
    latest_frame_size = 0;
    latest_frame_packet_count = 0;
    latest_submission_status = MINECRAFT_RENDER_INVALID_ARGUMENT;
    pthread_mutex_unlock(&latest_frame_mutex);
}
