/*
 * Proves libminecraft_java.so starts the extracted client rather than the
 * sample touch surface. The process is expected to create an isolate, call
 * minecraft_bootstrap, and observe minecraft_client_running become 1.
 */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "minecraft_java.h"

int main(int argc, char **argv) {
    const char *native_dir = argc > 1 ? argv[1] : "godot_extension/bin/natives";
    graal_isolate_t *isolate = NULL;
    graal_isolatethread_t *thread = NULL;
    int status;
    int ticks;

    setenv("MINECRAFT_GODOT_NATIVE_DIR", native_dir, 1);
    fprintf(stderr, "BOOT creating isolate\n");
    status = graal_create_isolate(NULL, &isolate, &thread);
    fprintf(stderr, "BOOT graal_create_isolate(NULL) status=%d thread=%p\n", status, (void *)thread);
    if (status != 0 || thread == NULL) {
        graal_create_isolate_params_t params;
        char arg0[] = "minecraft";
        char *isolate_argv[] = {arg0, NULL};
        memset(&params, 0, sizeof(params));
        params.version = __graal_create_isolate_params_version;
        params.reserved_address_space_size = (unsigned long)16 * 1024 * 1024 * 1024;
        params.argc = 1;
        params.argv = isolate_argv;
        params.ignore_unrecognized_args = 1;
        status = graal_create_isolate(&params, &isolate, &thread);
        fprintf(stderr, "BOOT graal_create_isolate(params) status=%d thread=%p\n", status, (void *)thread);
    }
    if (status != 0 || thread == NULL) {
        fprintf(stderr, "BOOT graal_create_isolate failed: %d\n", status);
        return 1;
    }
    minecraft_bootstrap(thread);
    for (ticks = 0; ticks < 360; ticks++) {
        int running = minecraft_client_running(thread);
        if (running == 1) {
            printf("extracted client is running\n");
            minecraft_client_stop(thread);
            return 0;
        }
        if (running < 0) {
            char message[1024];
            message[0] = '\0';
            minecraft_client_failure(thread, message, (int)sizeof(message));
            fprintf(stderr, "BOOT extracted client failed to start: %s\n", message);
            return 2;
        }
        usleep(500000);
    }
    fprintf(stderr, "extracted client did not start within 180 seconds\n");
    minecraft_client_stop(thread);
    return 3;
}
