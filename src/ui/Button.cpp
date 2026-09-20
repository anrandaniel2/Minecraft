#include "Button.h"
#ifdef EAGLER_ANDROID
#include <GLES3/gl3.h>
#else
#include <glad/gl.h>
#endif
#include <iostream>
#if defined(EAGLER_VULKAN)
// Vulkan dummy - UI rendering handled by VulkanRenderer
namespace Eaglercraft {

uint32_t Button::vao = 0;
uint32_t Button::vbo = 0;
bool Button::initialized = false;

void Button::initGL() {}

Button::Button(const std::string& txt, float x_, float y_, float w_, float h_) : text(txt), x(x_), y(y_), width(w_), height(h_) {}

void Button::update(float mouseX, float mouseY) {
    hovered = contains(mouseX, mouseY);
}

void Button::onMouseButton(int button, int action, float mx, float my) {
    if (!enabled) return;
    if (button == 0) {
        if (action == 1) {
            if (contains(mx, my)) pressed = true;
        } else if (action == 0) {
            if (pressed && contains(mx, my)) {
                if (callback) callback();
            }
            pressed = false;
        }
    }
}

void Button::render(Shader& shader) {}

}

#else

namespace Eaglercraft {

uint32_t Button::vao = 0;
uint32_t Button::vbo = 0;
bool Button::initialized = false;

void Button::initGL() {
    if (initialized) return;
    glGenVertexArrays(1, &vao);
    glGenBuffers(1, &vbo);
    initialized = true;
}

Button::Button(const std::string& txt, float x_, float y_, float w_, float h_) : text(txt), x(x_), y(y_), width(w_), height(h_) {
    initGL();
}

void Button::update(float mouseX, float mouseY) {
    hovered = contains(mouseX, mouseY);
}

void Button::onMouseButton(int button, int action, float mx, float my) {
    if (!enabled) return;
    if (button == 0) {
        if (action == 1) {
            if (contains(mx, my)) {
                pressed = true;
            }
        } else if (action == 0) {
            if (pressed && contains(mx, my)) {
                if (callback) callback();
            }
            pressed = false;
        }
    }
}

void Button::render(Shader& shader) {
    initGL();
    glm::vec4 bgColor = hovered ? glm::vec4(0.6f, 0.6f, 0.85f, 1.0f) : glm::vec4(0.5f, 0.5f, 0.5f, 1.0f);
    glm::vec4 borderColor = glm::vec4(0.1f, 0.1f, 0.1f, 1.0f);
    if (!enabled) bgColor = glm::vec4(0.3f, 0.3f, 0.3f, 1.0f);

    float verticesBorder[] = {
        x-1, y-1, 0,0, borderColor.r, borderColor.g, borderColor.b, borderColor.a,
        x-1, y+height+1, 0,1, borderColor.r, borderColor.g, borderColor.b, borderColor.a,
        x+width+1, y+height+1, 1,1, borderColor.r, borderColor.g, borderColor.b, borderColor.a,
        x-1, y-1, 0,0, borderColor.r, borderColor.g, borderColor.b, borderColor.a,
        x+width+1, y+height+1, 1,1, borderColor.r, borderColor.g, borderColor.b, borderColor.a,
        x+width+1, y-1, 1,0, borderColor.r, borderColor.g, borderColor.b, borderColor.a,
    };
    float verticesBg[] = {
        x, y, 0,0, bgColor.r, bgColor.g, bgColor.b, bgColor.a,
        x, y+height, 0,1, bgColor.r, bgColor.g, bgColor.b, bgColor.a,
        x+width, y+height, 1,1, bgColor.r, bgColor.g, bgColor.b, bgColor.a,
        x, y, 0,0, bgColor.r, bgColor.g, bgColor.b, bgColor.a,
        x+width, y+height, 1,1, bgColor.r, bgColor.g, bgColor.b, bgColor.a,
        x+width, y, 1,0, bgColor.r, bgColor.g, bgColor.b, bgColor.a,
    };

    shader.bind();
    shader.setUniform("uUseTex", false);

    glBindVertexArray(vao);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);

    glBufferData(GL_ARRAY_BUFFER, sizeof(verticesBorder), verticesBorder, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 8*sizeof(float), (void*)0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 8*sizeof(float), (void*)(2*sizeof(float)));
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, 8*sizeof(float), (void*)(4*sizeof(float)));
    glDrawArrays(GL_TRIANGLES, 0, 6);

    glBufferData(GL_ARRAY_BUFFER, sizeof(verticesBg), verticesBg, GL_DYNAMIC_DRAW);
    glDrawArrays(GL_TRIANGLES, 0, 6);

    glBindVertexArray(0);
}

}

#endif
