#pragma once
#include <string>
#include <functional>
#include <glm/glm.hpp>
#include "../core/Shader.h"

namespace Eaglercraft {

class Button {
public:
    Button() = default;
    Button(const std::string& text, float x, float y, float w, float h);

    void setText(const std::string& t) { text = t; }
    void setPosition(float x_, float y_) { x = x_; y = y_; }
    void setSize(float w_, float h_) { width = w_; height = h_; }
    void setCallback(std::function<void()> cb) { callback = cb; }

    void update(float mouseX, float mouseY);
    void render(Shader& shader);

    bool isHovered() const { return hovered; }
    bool isPressed() const { return pressed; }

    bool contains(float mx, float my) const {
        return mx >= x && mx <= x+width && my >= y && my <= y+height;
    }

    void onMouseButton(int button, int action, float mx, float my);

    std::string text;
    float x = 0, y = 0, width = 200, height = 20;
    bool hovered = false;
    bool pressed = false;
    bool enabled = true;

private:
    std::function<void()> callback;
    static uint32_t vao, vbo;
    static bool initialized;
    static void initGL();
};

}
