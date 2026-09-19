#include "android_window.h"
#include "vulkan_context.h"
#include <android/log.h>

#define LOGI(...) ((void)__android_log_print(ANDROID_LOG_INFO, "Eaglercraft-VK", __VA_ARGS__))
#define LOGE(...) ((void)__android_log_print(ANDROID_LOG_ERROR, "Eaglercraft-VK", __VA_ARGS__))

namespace Eaglercraft {

AndroidWindow::AndroidWindow(ANativeWindow* win) : nativeWindow(win) {}

AndroidWindow::~AndroidWindow() { shutdown(); }

bool AndroidWindow::init() {
    LOGI("AndroidWindow Vulkan init with window %p", nativeWindow);
    if (!nativeWindow) {
        LOGE("nativeWindow is null");
        return false;
    }

    width = ANativeWindow_getWidth(nativeWindow);
    height = ANativeWindow_getHeight(nativeWindow);
    LOGI("Native window size %dx%d", width, height);

    auto& ctx = VulkanContext::get();
    if (!ctx.init(nativeWindow)) {
        LOGE("VulkanContext init failed");
        return false;
    }

    width = ctx.getSwapchainExtent().width;
    height = ctx.getSwapchainExtent().height;

    LOGI("AndroidWindow Vulkan initialized %dx%d", width, height);
    initialized = true;
    return true;
}

void AndroidWindow::shutdown() {
    if (!initialized) return;
    LOGI("AndroidWindow shutdown");
    VulkanContext::get().cleanup();
    initialized = false;
}

void AndroidWindow::swapBuffers() {
    // Vulkan handles present in endFrame, so swapBuffers is no-op here
    // But we keep it for compatibility
}

}
