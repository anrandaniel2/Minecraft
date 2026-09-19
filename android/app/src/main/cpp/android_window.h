#pragma once
#include <android/native_window.h>
#include <EGL/egl.h>
#include <GLES3/gl3.h>

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

    EGLDisplay getDisplay() const { return display; }
    EGLSurface getSurface() const { return surface; }
    EGLContext getContext() const { return context; }

private:
    ANativeWindow* nativeWindow = nullptr;
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLSurface surface = EGL_NO_SURFACE;
    EGLContext context = EGL_NO_CONTEXT;
    EGLConfig config = nullptr;
    int width = 0, height = 0;
    bool initialized = false;
};

}
