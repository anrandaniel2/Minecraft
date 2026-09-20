#include "FontRenderer.h"
#ifdef EAGLER_ANDROID
#include <GLES3/gl3.h>
#else
#include <glad/gl.h>
#endif
#include <iostream>
#if defined(EAGLER_VULKAN)
// Vulkan dummy - UI rendering handled by VulkanRenderer
namespace Eaglercraft {
const unsigned char FontRenderer::fontData[95][8] = {};
FontRenderer::FontRenderer() {}
FontRenderer::~FontRenderer() {}
FontRenderer& FontRenderer::get() { static FontRenderer instance; return instance; }
bool FontRenderer::init() { initialized = true; return true; }
void FontRenderer::renderText(Shader& shader, const std::string& text, float x, float y, float scale, glm::vec4 color) {}
}
#else

namespace Eaglercraft {

const unsigned char FontRenderer::fontData[95][8] = {
    {0,0,0,0,0,0,0,0},
};

FontRenderer::FontRenderer() {}
FontRenderer::~FontRenderer() {
    if (vao) glDeleteVertexArrays(1, &vao);
    if (vbo) glDeleteBuffers(1, &vbo);
    if (texture) glDeleteTextures(1, &texture);
}

FontRenderer& FontRenderer::get() {
    static FontRenderer instance;
    return instance;
}

bool FontRenderer::init() {
    if (initialized) return true;
    glGenVertexArrays(1, &vao);
    glGenBuffers(1, &vbo);
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    unsigned char white[4] = {255,255,255,255};
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1,1,0, GL_RGBA, GL_UNSIGNED_BYTE, white);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glBindTexture(GL_TEXTURE_2D, 0);
    initialized = true;
    return true;
}

void FontRenderer::renderText(Shader& shader, const std::string& text, float x, float y, float scale, glm::vec4 color) {
    if (!initialized) init();
    shader.bind();
    shader.setUniform("uUseTex", false);
    glBindVertexArray(vao);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    float charWidth = 8 * scale;
    for (size_t i = 0; i < text.size(); ++i) {
        char c = text[i];
        if (c == ' ') continue;
        float cx = x + i * charWidth;
        float cy = y;
        float vertices[] = {
            cx, cy, 0,0, color.r, color.g, color.b, color.a,
            cx, cy+8*scale, 0,1, color.r, color.g, color.b, color.a,
            cx+8*scale, cy+8*scale, 1,1, color.r, color.g, color.b, color.a,
            cx, cy, 0,0, color.r, color.g, color.b, color.a,
            cx+8*scale, cy+8*scale, 1,1, color.r, color.g, color.b, color.a,
            cx+8*scale, cy, 1,0, color.r, color.g, color.b, color.a,
        };
        glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_DYNAMIC_DRAW);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 8*sizeof(float), (void*)0);
        glEnableVertexAttribArray(1);
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 8*sizeof(float), (void*)(2*sizeof(float)));
        glEnableVertexAttribArray(2);
        glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, 8*sizeof(float), (void*)(4*sizeof(float)));
        glDrawArrays(GL_TRIANGLES, 0, 6);
    }
    glBindVertexArray(0);
}

}

#endif
