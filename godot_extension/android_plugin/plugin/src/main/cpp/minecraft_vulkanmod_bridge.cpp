#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <android/log.h>
#include <dlfcn.h>
#include <jni.h>
#include <mutex>

namespace {
constexpr char kTag[] = "MinecraftVulkanOverlay";
std::mutex g_mutex;
ANativeWindow *g_window = nullptr;
int g_width = 0;
int g_height = 0;

using SurfaceCallback = void (*)(ANativeWindow *, int, int);
using SurfaceDestroyedCallback = void (*)();

void notify_client(ANativeWindow *window, int width, int height) {
    // The callback is deliberately optional. A VulkanMod/Pojav-side bridge can
    // export it without making this Godot plugin link against the client.
    auto callback = reinterpret_cast<SurfaceCallback>(
            dlsym(RTLD_DEFAULT, "minecraft_vulkanmod_surface_available"));
    if (callback != nullptr) {
        callback(window, width, height);
    }
}

void notify_client_destroyed() {
    auto callback = reinterpret_cast<SurfaceDestroyedCallback>(
            dlsym(RTLD_DEFAULT, "minecraft_vulkanmod_surface_destroyed"));
    if (callback != nullptr) {
        callback();
    }
}
}

extern "C" JNIEXPORT jboolean JNICALL
Java_org_anrandaniel_minecraft_vulkanoverlay_MinecraftVulkanOverlayPlugin_nativeSurfaceAvailable(
        JNIEnv *env, jobject /* self */, jobject surface, jint width, jint height) {
    if (surface == nullptr) {
        return JNI_FALSE;
    }

    ANativeWindow *window = ANativeWindow_fromSurface(env, surface);
    if (window == nullptr) {
        __android_log_print(ANDROID_LOG_ERROR, kTag, "ANativeWindow_fromSurface failed");
        return JNI_FALSE;
    }

    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_window != nullptr) {
        ANativeWindow_release(g_window);
    }
    g_window = window;
    g_width = width;
    g_height = height;
    notify_client(g_window, g_width, g_height);
    __android_log_print(ANDROID_LOG_INFO, kTag, "Vulkan surface attached %dx%d", width, height);
    return JNI_TRUE;
}

extern "C" JNIEXPORT void JNICALL
Java_org_anrandaniel_minecraft_vulkanoverlay_MinecraftVulkanOverlayPlugin_nativeSurfaceSizeChanged(
        JNIEnv * /* env */, jobject /* self */, jint width, jint height) {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_width = width;
    g_height = height;
    if (g_window != nullptr) {
        notify_client(g_window, g_width, g_height);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_org_anrandaniel_minecraft_vulkanoverlay_MinecraftVulkanOverlayPlugin_nativeSurfaceDestroyed(
        JNIEnv * /* env */, jobject /* self */) {
    std::lock_guard<std::mutex> lock(g_mutex);
    notify_client_destroyed();
    if (g_window != nullptr) {
        ANativeWindow_release(g_window);
        g_window = nullptr;
    }
    g_width = 0;
    g_height = 0;
    __android_log_print(ANDROID_LOG_INFO, kTag, "Vulkan surface detached");
}

// C ABI for an in-process VulkanMod bridge. The returned pointer is borrowed
// until the next surface callback; callers must not release it.
extern "C" ANativeWindow *minecraft_vulkanmod_get_native_window() {
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_window;
}

extern "C" int minecraft_vulkanmod_get_surface_width() {
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_width;
}

extern "C" int minecraft_vulkanmod_get_surface_height() {
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_height;
}
