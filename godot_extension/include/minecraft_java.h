#ifndef MINECRAFT_JAVA_H
#define MINECRAFT_JAVA_H

/*
 * Fallback declarations for the GraalVM Native Image library.
 *
 * build.sh generates a richer header next to minecraft_java.so. This stub
 * exists so the Godot adapter can be relinked against an already-built
 * libminecraft_java.so when native-image is not available. The generated
 * header must stay ahead of this directory on the compiler include path.
 */

typedef struct graal_isolate_t graal_isolate_t;
typedef struct graal_isolatethread_t graal_isolatethread_t;

/* Matches GraalVM's graal_isolate.h so callers can reserve a large heap
 * without requiring the generated header. A newer generated header, when
 * present, supplies the same field names. */
typedef unsigned long __graal_uword;
enum { __graal_create_isolate_params_version = 5 };
struct __graal_create_isolate_params_t {
    int version;
    __graal_uword reserved_address_space_size;
    const char *auxiliary_image_path;
    __graal_uword auxiliary_image_reserved_space_size;
    int argc;
    char **argv;
    int pkey;
    char ignore_unrecognized_args;
    char _reserved_4;
    char _reserved_5;
};
typedef struct __graal_create_isolate_params_t graal_create_isolate_params_t;

int graal_create_isolate(
    graal_create_isolate_params_t *params,
    graal_isolate_t **isolate,
    graal_isolatethread_t **thread
);
graal_isolatethread_t *graal_get_current_thread(graal_isolate_t *isolate);
int graal_attach_thread(graal_isolate_t *isolate, graal_isolatethread_t **thread);
int graal_tear_down_isolate(graal_isolatethread_t *thread);

void minecraft_bootstrap(graal_isolatethread_t *thread);
void minecraft_touch_down(
    graal_isolatethread_t *thread, int pointer_id, int x, int y, int width, int height
);
void minecraft_touch_move(
    graal_isolatethread_t *thread, int pointer_id, int x, int y, int width, int height
);
void minecraft_touch_up(graal_isolatethread_t *thread, int pointer_id);
void minecraft_touch_reset(graal_isolatethread_t *thread);
void minecraft_set_virtual_joystick_mask(graal_isolatethread_t *thread, int action_mask);
void minecraft_add_camera_drag(graal_isolatethread_t *thread, int delta_x, int delta_y);
int minecraft_render_submit_protocol_smoke_frame(graal_isolatethread_t *thread);
int minecraft_touch_mask(graal_isolatethread_t *thread);
int minecraft_active_touch_count(graal_isolatethread_t *thread);
int minecraft_client_running(graal_isolatethread_t *thread);
void minecraft_client_stop(graal_isolatethread_t *thread);
int minecraft_client_failure(graal_isolatethread_t *thread, char *buffer, int capacity);

#endif
