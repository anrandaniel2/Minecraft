#include "Window.h"
#ifdef EAGLER_ANDROID
// Dummy implementation for Android - real window is AndroidWindow
#else
#include <glad/gl.h>
#include <GLFW/glfw3.h>
#include <iostream>
#if defined(EAGLER_VULKAN)
// Vulkan dummy - UI rendering handled by VulkanRenderer
namespace Eaglercraft {}
#else

namespace Eaglercraft {

void Window::glfwErrorCallback(int error, const char* description) {
    std::cerr << "GLFW Error " << error << ": " << description << "\n";
}

void Window::initGLFW() {
    glfwSetErrorCallback(glfwErrorCallback);
    if (!glfwInit()) {
        std::cerr << "Failed to init GLFW\n";
        throw std::runtime_error("GLFW init failed");
    }
}

void Window::terminateGLFW() {
    glfwTerminate();
}

Window::Window(const WindowConfig& config) : width(config.width), height(config.height), title(config.title) {
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_RESIZABLE, config.resizable ? GLFW_TRUE : GLFW_FALSE);
#ifdef __APPLE__
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
#endif

    GLFWmonitor* monitor = nullptr;
    if (config.fullscreen) {
        monitor = glfwGetPrimaryMonitor();
    }

    handle = glfwCreateWindow(width, height, title.c_str(), monitor, nullptr);
    if (!handle) {
        std::cerr << "Failed to create GLFW window\n";
        throw std::runtime_error("Window creation failed");
    }

    glfwMakeContextCurrent(handle);

    // Load GL via glad
    int version = gladLoadGL(glfwGetProcAddress);
    if (version == 0) {
        std::cerr << "Failed to load OpenGL via glad\n";
        throw std::runtime_error("GLAD load failed");
    }
    std::cout << "OpenGL loaded: " << GLAD_VERSION_MAJOR(version) << "." << GLAD_VERSION_MINOR(version) << "\n";
    std::cout << "Renderer: " << glGetString(GL_RENDERER) << "\n";
    std::cout << "Version: " << glGetString(GL_VERSION) << "\n";

    if (config.vsync) {
        glfwSwapInterval(1);
    } else {
        glfwSwapInterval(0);
    }

    glEnable(GL_DEPTH_TEST);
    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);
    glFrontFace(GL_CCW);

    setupCallbacks();

    // Store this pointer for callbacks
    glfwSetWindowUserPointer(handle, this);
}

Window::~Window() {
    if (handle) {
        glfwDestroyWindow(handle);
        handle = nullptr;
    }
}

void Window::setupCallbacks() {
    glfwSetFramebufferSizeCallback(handle, [](GLFWwindow* win, int w, int h) {
        auto* self = static_cast<Window*>(glfwGetWindowUserPointer(win));
        if (!self) return;
        self->width = w;
        self->height = h;
        glViewport(0,0,w,h);
        if (self->resizeCallback) self->resizeCallback(w,h);
    });

    glfwSetKeyCallback(handle, [](GLFWwindow* win, int key, int scancode, int action, int mods) {
        auto* self = static_cast<Window*>(glfwGetWindowUserPointer(win));
        if (!self) return;
        if (self->keyCallback) self->keyCallback(key, scancode, action, mods);
    });

    glfwSetMouseButtonCallback(handle, [](GLFWwindow* win, int button, int action, int mods) {
        auto* self = static_cast<Window*>(glfwGetWindowUserPointer(win));
        if (!self) return;
        if (self->mouseButtonCallback) self->mouseButtonCallback(button, action, mods);
    });

    glfwSetCursorPosCallback(handle, [](GLFWwindow* win, double x, double y) {
        auto* self = static_cast<Window*>(glfwGetWindowUserPointer(win));
        if (!self) return;
        if (self->cursorPosCallback) self->cursorPosCallback(x,y);
    });

    glfwSetScrollCallback(handle, [](GLFWwindow* win, double x, double y) {
        auto* self = static_cast<Window*>(glfwGetWindowUserPointer(win));
        if (!self) return;
        if (self->scrollCallback) self->scrollCallback(x,y);
    });

    glfwSetCharCallback(handle, [](GLFWwindow* win, unsigned int c) {
        auto* self = static_cast<Window*>(glfwGetWindowUserPointer(win));
        if (!self) return;
        if (self->charCallback) self->charCallback(c);
    });
}

bool Window::shouldClose() const {
    return glfwWindowShouldClose(handle);
}

void Window::pollEvents() {
    glfwPollEvents();
}

void Window::swapBuffers() {
    glfwSwapBuffers(handle);
}

void Window::close() {
    glfwSetWindowShouldClose(handle, true);
}

void Window::setTitle(const std::string& t) {
    title = t;
    glfwSetWindowTitle(handle, t.c_str());
}

void Window::setCursorMode(int mode) {
    glfwSetInputMode(handle, GLFW_CURSOR, mode);
}

glm::vec2 Window::getCursorPos() const {
    double x,y;
    glfwGetCursorPos(handle, &x, &y);
    return {float(x), float(y)};
}

}

#endif // EAGLER_ANDROID

#endif // EAGLER_VULKAN