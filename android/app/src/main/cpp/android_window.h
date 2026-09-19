#pragma once
#include <android/native_window.h>
#include "vulkan_context.h"

namespace Eaglercraft {

class AndroidWindow {
public:
    AndroidWindow(ANativeWindow* nativeWindow);
    ~AndroidWindow();

    bool init();
    void shutdown();
    void swapBuffers();

    int getWidth() const { return width; }
    int getHeight() const { return height; }

    bool isInitialized() const { return initialized; }

private:
    ANativeWindow* nativeWindow = nullptr;
    int width = 0, height = 0;
    bool initialized = false;
};

}
