/*
 * Proves libminecraft_java.so starts the extracted client rather than the
 * sample touch surface. The process is expected to create an isolate, call
 * minecraft_bootstrap, and observe minecraft_client_running become 1.
 */
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
    status = graal_create_isolate(NULL, &isolate, &thread);
    if (status != 0 || thread == NULL) {
        fprintf(stderr, "graal_create_isolate failed: %d\n", status);
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
            fprintf(stderr, "extracted client failed to start\n");
            return 2;
        }
        usleep(500000);
    }
    fprintf(stderr, "extracted client did not start within 180 seconds\n");
    minecraft_client_stop(thread);
    return 3;
}
