#include "Input.h"
#ifndef EAGLER_ANDROID
#include <GLFW/glfw3.h>
#if defined(EAGLER_VULKAN)
// Vulkan dummy desktop - no GLFW needed, but we still need Input logic? For desktop Vulkan, Input would be via GLFW still, but we provide empty
namespace Eaglercraft {
std::array<bool, 512> Input::keys{};
std::array<bool, 512> Input::keysPrev{};
std::array<bool, 8> Input::mouseButtons{};
std::array<bool, 8> Input::mouseButtonsPrev{};
glm::vec2 Input::mousePos{0};
glm::vec2 Input::mousePosPrev{0};
glm::vec2 Input::mouseDelta{0};
glm::vec2 Input::scrollDelta{0};
glm::vec2 Input::scrollAccum{0};
void Input::init() { keys.fill(false); keysPrev.fill(false); mouseButtons.fill(false); mouseButtonsPrev.fill(false); }
void Input::update() { keysPrev = keys; mouseButtonsPrev = mouseButtons; mousePosPrev = mousePos; mouseDelta = mousePos - mousePosPrev; scrollDelta = scrollAccum; scrollAccum = glm::vec2(0); }
bool Input::isKeyDown(int key) { if (key < 0 || key >= 512) return false; return keys[key]; }
bool Input::isKeyPressed(int key) { if (key < 0 || key >= 512) return false; return keys[key] && !keysPrev[key]; }
bool Input::isKeyReleased(int key) { if (key < 0 || key >= 512) return false; return !keys[key] && keysPrev[key]; }
bool Input::isMouseDown(int button) { if (button < 0 || button >= 8) return false; return mouseButtons[button]; }
bool Input::isMousePressed(int button) { if (button < 0 || button >= 8) return false; return mouseButtons[button] && !mouseButtonsPrev[button]; }
bool Input::isMouseReleased(int button) { if (button < 0 || button >= 8) return false; return !mouseButtons[button] && mouseButtonsPrev[button]; }
glm::vec2 Input::getMousePos() { return mousePos; }
glm::vec2 Input::getMouseDelta() { return mouseDelta; }
glm::vec2 Input::getScrollDelta() { return scrollDelta; }
void Input::setKey(int key, int action) { if (key < 0 || key >= 512) return; if (action == GLFW_PRESS) keys[key] = true; else if (action == GLFW_RELEASE) keys[key] = false; }
void Input::setMouseButton(int button, int action) { if (button < 0 || button >= 8) return; if (action == GLFW_PRESS) mouseButtons[button] = true; else if (action == GLFW_RELEASE) mouseButtons[button] = false; }
void Input::setMousePos(double x, double y) { mousePos = glm::vec2(float(x), float(y)); }
void Input::setScroll(double x, double y) { scrollAccum += glm::vec2(float(x), float(y)); }
}
#else
namespace Eaglercraft {

std::array<bool, 512> Input::keys{};
std::array<bool, 512> Input::keysPrev{};
std::array<bool, 8> Input::mouseButtons{};
std::array<bool, 8> Input::mouseButtonsPrev{};
glm::vec2 Input::mousePos{0};
glm::vec2 Input::mousePosPrev{0};
glm::vec2 Input::mouseDelta{0};
glm::vec2 Input::scrollDelta{0};
glm::vec2 Input::scrollAccum{0};

void Input::init() {
    keys.fill(false);
    keysPrev.fill(false);
    mouseButtons.fill(false);
    mouseButtonsPrev.fill(false);
}

void Input::update() {
    keysPrev = keys;
    mouseButtonsPrev = mouseButtons;
    mousePosPrev = mousePos;
    mouseDelta = mousePos - mousePosPrev;
    scrollDelta = scrollAccum;
    scrollAccum = glm::vec2(0);
}

bool Input::isKeyDown(int key) {
    if (key < 0 || key >= 512) return false;
    return keys[key];
}
bool Input::isKeyPressed(int key) {
    if (key < 0 || key >= 512) return false;
    return keys[key] && !keysPrev[key];
}
bool Input::isKeyReleased(int key) {
    if (key < 0 || key >= 512) return false;
    return !keys[key] && keysPrev[key];
}
bool Input::isMouseDown(int button) {
    if (button < 0 || button >= 8) return false;
    return mouseButtons[button];
}
bool Input::isMousePressed(int button) {
    if (button < 0 || button >= 8) return false;
    return mouseButtons[button] && !mouseButtonsPrev[button];
}
bool Input::isMouseReleased(int button) {
    if (button < 0 || button >= 8) return false;
    return !mouseButtons[button] && mouseButtonsPrev[button];
}
glm::vec2 Input::getMousePos() { return mousePos; }
glm::vec2 Input::getMouseDelta() { return mouseDelta; }
glm::vec2 Input::getScrollDelta() { return scrollDelta; }

void Input::setKey(int key, int action) {
    if (key < 0 || key >= 512) return;
    if (action == GLFW_PRESS) keys[key] = true;
    else if (action == GLFW_RELEASE) keys[key] = false;
}
void Input::setMouseButton(int button, int action) {
    if (button < 0 || button >= 8) return;
    if (action == GLFW_PRESS) mouseButtons[button] = true;
    else if (action == GLFW_RELEASE) mouseButtons[button] = false;
}
void Input::setMousePos(double x, double y) {
    mousePos = glm::vec2(float(x), float(y));
}
void Input::setScroll(double x, double y) {
    scrollAccum += glm::vec2(float(x), float(y));
}

}

#endif
#else
#define GLFW_PRESS 1
#define GLFW_RELEASE 0
namespace Eaglercraft {

std::array<bool, 512> Input::keys{};
std::array<bool, 512> Input::keysPrev{};
std::array<bool, 8> Input::mouseButtons{};
std::array<bool, 8> Input::mouseButtonsPrev{};
glm::vec2 Input::mousePos{0};
glm::vec2 Input::mousePosPrev{0};
glm::vec2 Input::mouseDelta{0};
glm::vec2 Input::scrollDelta{0};
glm::vec2 Input::scrollAccum{0};

void Input::init() {
    keys.fill(false);
    keysPrev.fill(false);
    mouseButtons.fill(false);
    mouseButtonsPrev.fill(false);
}

void Input::update() {
    keysPrev = keys;
    mouseButtonsPrev = mouseButtons;
    mousePosPrev = mousePos;
    mouseDelta = mousePos - mousePosPrev;
    scrollDelta = scrollAccum;
    scrollAccum = glm::vec2(0);
}

bool Input::isKeyDown(int key) {
    if (key < 0 || key >= 512) return false;
    return keys[key];
}
bool Input::isKeyPressed(int key) {
    if (key < 0 || key >= 512) return false;
    return keys[key] && !keysPrev[key];
}
bool Input::isKeyReleased(int key) {
    if (key < 0 || key >= 512) return false;
    return !keys[key] && keysPrev[key];
}
bool Input::isMouseDown(int button) {
    if (button < 0 || button >= 8) return false;
    return mouseButtons[button];
}
bool Input::isMousePressed(int button) {
    if (button < 0 || button >= 8) return false;
    return mouseButtons[button] && !mouseButtonsPrev[button];
}
bool Input::isMouseReleased(int button) {
    if (button < 0 || button >= 8) return false;
    return !mouseButtons[button] && mouseButtonsPrev[button];
}
glm::vec2 Input::getMousePos() { return mousePos; }
glm::vec2 Input::getMouseDelta() { return mouseDelta; }
glm::vec2 Input::getScrollDelta() { return scrollDelta; }

void Input::setKey(int key, int action) {
    if (key < 0 || key >= 512) return;
    if (action == GLFW_PRESS) keys[key] = true;
    else if (action == GLFW_RELEASE) keys[key] = false;
}
void Input::setMouseButton(int button, int action) {
    if (button < 0 || button >= 8) return;
    if (action == GLFW_PRESS) mouseButtons[button] = true;
    else if (action == GLFW_RELEASE) mouseButtons[button] = false;
}
void Input::setMousePos(double x, double y) {
    mousePos = glm::vec2(float(x), float(y));
}
void Input::setScroll(double x, double y) {
    scrollAccum += glm::vec2(float(x), float(y));
}

}
#endif
