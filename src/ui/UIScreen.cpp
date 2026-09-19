#include "UIScreen.h"
#include "Button.h"
#ifdef EAGLER_ANDROID
#include <GLES3/gl3.h>
#else
#include <glad/gl.h>
#endif
#include <iostream>

namespace Eaglercraft {

void UIScreen::drawRect(Shader& shader, float x, float y, float w, float h, glm::vec4 color) {
    // Simple immediate mode quad rendering
    // Convert to NDC? We'll use ortho projection already set in shader
    // Vertices: pos(2) uv(2) color(4)
    float vertices[] = {
        x, y, 0,0, color.r, color.g, color.b, color.a,
        x, y+h, 0,1, color.r, color.g, color.b, color.a,
        x+w, y+h, 1,1, color.r, color.g, color.b, color.a,
        x, y, 0,0, color.r, color.g, color.b, color.a,
        x+w, y+h, 1,1, color.r, color.g, color.b, color.a,
        x+w, y, 1,0, color.r, color.g, color.b, color.a,
    };

    static uint32_t vao = 0, vbo = 0;
    if (vao == 0) {
        glGenVertexArrays(1, &vao);
        glGenBuffers(1, &vbo);
    }
    glBindVertexArray(vao);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_DYNAMIC_DRAW);
    // pos
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 8*sizeof(float), (void*)0);
    // uv
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 8*sizeof(float), (void*)(2*sizeof(float)));
    // color
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, 8*sizeof(float), (void*)(4*sizeof(float)));

    shader.bind();
    shader.setUniform("uUseTex", false);
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glBindVertexArray(0);
}

void UIScreen::drawText(Shader& shader, const std::string& text, float x, float y, float scale, glm::vec4 color) {
    // Placeholder: draw rects for each char as simple blocks - in real implementation would use font atlas
    // For now, we just draw a background rect for text to indicate where text would be
    // This is a stub; FontRenderer will handle real text
    // We'll not implement bitmap font here, but we can draw small rects
    // To keep UI functional, we will draw nothing or just use drawRect for debug
    // The real text rendering is done via FontRenderer class
}

void UIScreen::drawButton(Shader& shader, Button& button) {
    button.render(shader);
}

}
