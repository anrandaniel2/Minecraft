#pragma once
#include <string>
#include <functional>
#include <glm/glm.hpp>

#ifdef EAGLER_ANDROID
// On Android, Window is replaced by AndroidWindow
namespace Eaglercraft {
struct WindowConfig {
    int width = 1280;
    int height = 720;
    std::string title = "Eaglercraft 26.2 - 0.6 Native (C++ Port)";
    bool resizable = true;
    bool vsync = true;
    bool fullscreen = false;
};
class Window {
public:
    Window(const WindowConfig&) {}
    ~Window() {}
    bool shouldClose() const { return false; }
    void pollEvents() {}
    void swapBuffers() {}
    void close() {}
    int getWidth() const { return 1280; }
    int getHeight() const { return 720; }
    float getAspect() const { return 16.0f/9.0f; }
    void* getHandle() const { return nullptr; }
    void setTitle(const std::string&) {}
    void setCursorMode(int) {}
    glm::vec2 getCursorPos() const { return glm::vec2(0); }
    static void initGLFW() {}
    static void terminateGLFW() {}
};
}
#else

struct GLFWwindow;

namespace Eaglercraft {

struct WindowConfig {
    int width = 1280;
    int height = 720;
    std::string title = "Eaglercraft 26.2 - 0.6 Native (C++ Port)";
    bool resizable = true;
    bool vsync = true;
    bool fullscreen = false;
};

class Window {
public:
    Window(const WindowConfig& config);
    ~Window();

    bool shouldClose() const;
    void pollEvents();
    void swapBuffers();
    void close();

    int getWidth() const { return width; }
    int getHeight() const { return height; }
    float getAspect() const { return width / float(height ? height : 1); }
    GLFWwindow* getHandle() const { return handle; }

    void setTitle(const std::string& title);

    // Callbacks
    using ResizeCallback = std::function<void(int,int)>;
    using KeyCallback = std::function<void(int,int,int,int)>;
    using MouseButtonCallback = std::function<void(int,int,int)>;
    using CursorPosCallback = std::function<void(double,double)>;
    using ScrollCallback = std::function<void(double,double)>;
    using CharCallback = std::function<void(unsigned int)>;

    void setResizeCallback(ResizeCallback cb) { resizeCallback = cb; }
    void setKeyCallback(KeyCallback cb) { keyCallback = cb; }
    void setMouseButtonCallback(MouseButtonCallback cb) { mouseButtonCallback = cb; }
    void setCursorPosCallback(CursorPosCallback cb) { cursorPosCallback = cb; }
    void setScrollCallback(ScrollCallback cb) { scrollCallback = cb; }
    void setCharCallback(CharCallback cb) { charCallback = cb; }

    void setCursorMode(int mode); // GLFW_CURSOR_NORMAL, DISABLED, etc
    glm::vec2 getCursorPos() const;

    static void initGLFW();
    static void terminateGLFW();

private:
    GLFWwindow* handle = nullptr;
    int width, height;
    std::string title;

    ResizeCallback resizeCallback;
    KeyCallback keyCallback;
    MouseButtonCallback mouseButtonCallback;
    CursorPosCallback cursorPosCallback;
    ScrollCallback scrollCallback;
    CharCallback charCallback;

    static void glfwErrorCallback(int error, const char* description);
    void setupCallbacks();
};

}

#endif // EAGLER_ANDROID
