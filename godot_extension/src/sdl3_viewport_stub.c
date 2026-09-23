/*
 * SDL3 stand-in for the extracted client's stock Window/RenderSystem boot.
 *
 * Minecraft 26.3 calls SDL before it creates a GpuDevice, and Window then
 * queries that SDL window. This library answers those calls without opening a
 * display. GodotGpuBackend.createWindow returns WINDOW_HANDLE (1); presentation
 * stays on the Godot viewport. Load this as libSDL3 ahead of any real SDL.
 *
 * The viewport size can be set with godot_sdl_stub_set_framebuffer or the
 * GODOT_VIEWPORT_WIDTH / GODOT_VIEWPORT_HEIGHT environment variables.
 */

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifdef _WIN32
#define STUB_EXPORT __declspec(dllexport)
#else
#define STUB_EXPORT __attribute__((visibility("default")))
#endif

static int g_width = 1280;
static int g_height = 720;
static int g_size_ready = 0;
static const char *g_error = "";

static void ensure_size(void) {
    const char *width;
    const char *height;
    if (g_size_ready) {
        return;
    }
    width = getenv("GODOT_VIEWPORT_WIDTH");
    height = getenv("GODOT_VIEWPORT_HEIGHT");
    if (width != NULL && height != NULL) {
        int parsed_width = atoi(width);
        int parsed_height = atoi(height);
        if (parsed_width > 0 && parsed_height > 0) {
            g_width = parsed_width;
            g_height = parsed_height;
        }
    }
    g_size_ready = 1;
}

STUB_EXPORT void godot_sdl_stub_set_framebuffer(int width, int height) {
    if (width > 0 && height > 0) {
        g_width = width;
        g_height = height;
        g_size_ready = 1;
    }
}

STUB_EXPORT bool SDL_Init(uint32_t flags) {
    (void)flags;
    ensure_size();
    g_error = "";
    return true;
}

STUB_EXPORT void SDL_Quit(void) {}

STUB_EXPORT const char *SDL_GetError(void) {
    return g_error == NULL ? "" : g_error;
}

STUB_EXPORT bool SDL_SetHint(const char *name, const char *value) {
    (void)name;
    (void)value;
    return true;
}

STUB_EXPORT const char *SDL_GetHint(const char *name) {
    (void)name;
    return "";
}

STUB_EXPORT bool SDL_SetAppMetadataProperty(const char *name, const char *value) {
    (void)name;
    (void)value;
    return true;
}

STUB_EXPORT uint64_t SDL_GetTicksNS(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
        return 0;
    }
    return (uint64_t)now.tv_sec * 1000000000ull + (uint64_t)now.tv_nsec;
}

STUB_EXPORT bool SDL_OpenURL(const char *url) {
    (void)url;
    return false;
}

STUB_EXPORT void *SDL_CreateWindow(const char *title, int width, int height, uint64_t flags) {
    (void)title;
    (void)flags;
    ensure_size();
    if (width > 0 && height > 0) {
        g_width = width;
        g_height = height;
    }
    return (void *)(uintptr_t)1;
}

STUB_EXPORT void SDL_DestroyWindow(void *window) {
    (void)window;
}

STUB_EXPORT bool SDL_SetWindowMinimumSize(void *window, int min_w, int min_h) {
    (void)window;
    (void)min_w;
    (void)min_h;
    return true;
}

STUB_EXPORT bool SDL_SetWindowMaximumSize(void *window, int max_w, int max_h) {
    (void)window;
    (void)max_w;
    (void)max_h;
    return true;
}

STUB_EXPORT bool SDL_SetWindowSize(void *window, int width, int height) {
    (void)window;
    if (width > 0 && height > 0) {
        g_width = width;
        g_height = height;
    }
    return true;
}

STUB_EXPORT bool SDL_GetWindowSize(void *window, int *width, int *height) {
    (void)window;
    ensure_size();
    if (width != NULL) {
        *width = g_width;
    }
    if (height != NULL) {
        *height = g_height;
    }
    return true;
}

STUB_EXPORT bool SDL_GetWindowSizeInPixels(void *window, int *width, int *height) {
    return SDL_GetWindowSize(window, width, height);
}

STUB_EXPORT bool SDL_GetWindowPosition(void *window, int *x, int *y) {
    (void)window;
    if (x != NULL) {
        *x = 0;
    }
    if (y != NULL) {
        *y = 0;
    }
    return true;
}

STUB_EXPORT bool SDL_SetWindowPosition(void *window, int x, int y) {
    (void)window;
    (void)x;
    (void)y;
    return true;
}

STUB_EXPORT bool SDL_SetWindowTitle(void *window, const char *title) {
    (void)window;
    (void)title;
    return true;
}

STUB_EXPORT bool SDL_SetWindowBordered(void *window, bool bordered) {
    (void)window;
    (void)bordered;
    return true;
}

STUB_EXPORT bool SDL_SetWindowFullscreen(void *window, bool fullscreen) {
    (void)window;
    (void)fullscreen;
    return true;
}

STUB_EXPORT bool SDL_SetWindowFullscreenMode(void *window, const void *mode) {
    (void)window;
    (void)mode;
    return true;
}

STUB_EXPORT const void *SDL_GetWindowFullscreenMode(void *window) {
    (void)window;
    return NULL;
}

STUB_EXPORT bool SDL_SyncWindow(void *window) {
    (void)window;
    return true;
}

STUB_EXPORT bool SDL_RestoreWindow(void *window) {
    (void)window;
    return true;
}

STUB_EXPORT uint64_t SDL_GetWindowFlags(void *window) {
    (void)window;
    return 0;
}

STUB_EXPORT float SDL_GetWindowPixelDensity(void *window) {
    (void)window;
    return 1.0f;
}

STUB_EXPORT bool SDL_SetWindowIcon(void *window, void *surface) {
    (void)window;
    (void)surface;
    return true;
}

STUB_EXPORT bool SDL_SetWindowMouseGrab(void *window, bool grabbed) {
    (void)window;
    (void)grabbed;
    return true;
}

STUB_EXPORT bool SDL_SetWindowRelativeMouseMode(void *window, bool enabled) {
    (void)window;
    (void)enabled;
    return true;
}

STUB_EXPORT void SDL_WarpMouseInWindow(void *window, float x, float y) {
    (void)window;
    (void)x;
    (void)y;
}

STUB_EXPORT uint32_t SDL_GetPrimaryDisplay(void) {
    return 1;
}

STUB_EXPORT uint32_t SDL_GetDisplayForWindow(void *window) {
    (void)window;
    return 1;
}

STUB_EXPORT const char *SDL_GetCurrentVideoDriver(void) {
    return "godot";
}

STUB_EXPORT const char *SDL_GetPlatform(void) {
    return "Godot";
}

STUB_EXPORT uint32_t *SDL_GetDisplays(int *count) {
    uint32_t *ids = (uint32_t *)malloc(sizeof(uint32_t) * 2);
    if (ids == NULL) {
        if (count != NULL) {
            *count = 0;
        }
        return NULL;
    }
    ids[0] = 1;
    ids[1] = 0;
    if (count != NULL) {
        *count = 1;
    }
    return ids;
}

STUB_EXPORT const char *SDL_GetDisplayName(uint32_t display) {
    (void)display;
    return "Godot viewport";
}

STUB_EXPORT bool SDL_GetDisplayBounds(uint32_t display, void *rect) {
    (void)display;
    (void)rect;
    /* LWJGL owns the SDL_Rect layout. Decline so Monitor.tryCreate uses its
     * logged fallback instead of reading a struct this stub does not define. */
    return false;
}

STUB_EXPORT void *SDL_GetDesktopDisplayMode(uint32_t display) {
    (void)display;
    return NULL;
}

STUB_EXPORT void *SDL_GetFullscreenDisplayModes(uint32_t display, int *count) {
    (void)display;
    if (count != NULL) {
        *count = 0;
    }
    return NULL;
}

STUB_EXPORT void *SDL_GetCurrentDisplayMode(uint32_t display) {
    (void)display;
    return NULL;
}

STUB_EXPORT void *SDL_GetClosestFullscreenDisplayMode(uint32_t display, int width, int height, float refresh, bool include_high_density) {
    (void)display;
    (void)width;
    (void)height;
    (void)refresh;
    (void)include_high_density;
    return NULL;
}

STUB_EXPORT const void *SDL_GetPixelFormatDetails(uint32_t format) {
    (void)format;
    return NULL;
}

STUB_EXPORT void SDL_free(void *memory) {
    free(memory);
}

STUB_EXPORT bool SDL_PollEvent(void *event) {
    (void)event;
    return false;
}

STUB_EXPORT void SDL_PumpEvents(void) {}

STUB_EXPORT void SDL_FlushEvents(uint32_t min_type, uint32_t max_type) {
    (void)min_type;
    (void)max_type;
}

STUB_EXPORT uint32_t SDL_GetWindowFromEvent(const void *event) {
    (void)event;
    return 0;
}

STUB_EXPORT uint16_t SDL_GetModState(void) {
    return 0;
}

STUB_EXPORT const bool *SDL_GetKeyboardState(int *numkeys) {
    static bool keys[512];
    if (numkeys != NULL) {
        *numkeys = 512;
    }
    return keys;
}

STUB_EXPORT uint32_t SDL_GetKeyFromScancode(uint32_t scancode, uint16_t modstate, bool key_event) {
    (void)modstate;
    (void)key_event;
    return scancode;
}

STUB_EXPORT const char *SDL_GetKeyName(uint32_t key) {
    (void)key;
    return "";
}

STUB_EXPORT bool SDL_StartTextInput(void *window) {
    (void)window;
    return true;
}

STUB_EXPORT bool SDL_StopTextInput(void *window) {
    (void)window;
    return true;
}

STUB_EXPORT bool SDL_ClearComposition(void *window) {
    (void)window;
    return true;
}

STUB_EXPORT bool SDL_SetTextInputArea(void *window, const void *rect, int cursor) {
    (void)window;
    (void)rect;
    (void)cursor;
    return true;
}

STUB_EXPORT void *SDL_CreateSurfaceFrom(int width, int height, uint32_t format, void *pixels, int pitch) {
    (void)width;
    (void)height;
    (void)format;
    (void)pixels;
    (void)pitch;
    return NULL;
}

STUB_EXPORT void SDL_DestroySurface(void *surface) {
    (void)surface;
}

STUB_EXPORT bool SDL_AddSurfaceAlternateImage(void *surface, void *image) {
    (void)surface;
    (void)image;
    return false;
}

STUB_EXPORT void *SDL_CreateSystemCursor(int id) {
    (void)id;
    return NULL;
}

STUB_EXPORT void *SDL_GetDefaultCursor(void) {
    return NULL;
}

STUB_EXPORT bool SDL_SetCursor(void *cursor) {
    (void)cursor;
    return true;
}

STUB_EXPORT bool SDL_ShowSimpleMessageBox(uint32_t flags, const char *title, const char *message, void *window) {
    (void)flags;
    (void)title;
    (void)message;
    (void)window;
    return true;
}

STUB_EXPORT bool SDL_ShowMessageBox(const void *data, int *button) {
    (void)data;
    if (button != NULL) {
        *button = 0;
    }
    return true;
}

STUB_EXPORT void *SDL_Vulkan_LoadLibrary(const char *path) {
    (void)path;
    g_error = "Vulkan is not the Godot viewport backend";
    return NULL;
}

STUB_EXPORT void *SDL_Vulkan_GetVkGetInstanceProcAddr(void) {
    return NULL;
}

STUB_EXPORT void SDL_Vulkan_UnloadLibrary(void) {}

STUB_EXPORT bool SDL_SetLogPriorities(int priority) {
    (void)priority;
    return true;
}

STUB_EXPORT void SDL_SetLogOutputFunction(void *callback, void *userdata) {
    (void)callback;
    (void)userdata;
}
