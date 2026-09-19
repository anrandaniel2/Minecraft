#pragma once
#include <string>
#include <vector>
#include <glm/glm.hpp>
#include <memory>
#include "../core/Shader.h"

namespace Eaglercraft {

class Button;

enum class ScreenType {
    None,
    Loading,
    MainMenu,
    Singleplayer,
    Multiplayer,
    Options,
    InGame,
    Pause
};

class UIScreen {
public:
    UIScreen(ScreenType type) : screenType(type) {}
    virtual ~UIScreen() = default;

    virtual void init(int width, int height) = 0;
    virtual void update(float deltaTime) {}
    virtual void render(Shader& uiShader, int width, int height) = 0;
    virtual void onResize(int w, int h) { width = w; height = h; }
    virtual void onKey(int key, int scancode, int action, int mods) {}
    virtual void onMouseButton(int button, int action, int mods, float x, float y) {}
    virtual void onMouseMove(float x, float y) {}
    virtual void onChar(unsigned int c) {}

    ScreenType getType() const { return screenType; }

protected:
    ScreenType screenType;
    int width = 1280, height = 720;

    // Helper for rendering rects - to be implemented in cpp
    void drawRect(Shader& shader, float x, float y, float w, float h, glm::vec4 color);
    void drawText(Shader& shader, const std::string& text, float x, float y, float scale, glm::vec4 color);
    void drawButton(Shader& shader, Button& button);
};

}
