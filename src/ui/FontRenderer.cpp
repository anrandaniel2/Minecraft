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
FontRenderer::FontRenderer() = default;
FontRenderer::~FontRenderer() {}
FontRenderer& FontRenderer::get() { static FontRenderer instance; return instance; }
bool FontRenderer::init() { initialized = true; return true; }
void FontRenderer::renderText(Shader& shader, const std::string& text, float x, float y, float scale, glm::vec4 color) {}
}
#else

namespace Eaglercraft {

// Very simple 8x8 font - placeholder, using a basic pattern
// For real Minecraft font, we'd need to load from texture, but we generate a simple one
const unsigned char FontRenderer::fontData[95][8] = {
    // Space and basic characters - simplified
    {0,0,0,0,0,0,0,0}, // space
    // For brevity, we use same pattern for all - in real implementation would have full font
};

FontRenderer::FontRenderer() = default;
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

    // Create a simple white texture for font (placeholder)
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
    // For this native port, we will render text as colored quads for each character
    // In a full implementation, we'd use a texture atlas with Minecraft font
    // Here we render simple rectangles with the text string in mind - we don't actually draw glyphs,
    // but we provide the infrastructure

    // For debugging, we draw a small indicator that text rendering is called
    // Real implementation would sample from font texture

    // We'll draw each character as a quad with color, and we store the text for debugging
    // Since we don't have actual font texture, we will draw nothing but we keep the method

    // Placeholder: draw a background for text length
    // This helps visualize where text should be
    float charWidth = 8 * scale;
    float charHeight = 8 * scale;
    // float totalWidth = text.length() * charWidth;

    // For now, we render using simple GL lines for each char as a placeholder
    // To actually see text, we would need a font atlas - we skip for brevity but keep API

    // In a real port of Eaglercraft 26.2, the UI text is rendered via HTML/CSS originally,
    // but we replicate with this font renderer

    // We'll render a simple quad per character with slightly different alpha to indicate text
    shader.bind();
    shader.setUniform("uUseTex", false);

    glBindVertexArray(vao);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);

    // For each character, draw a quad
    for (size_t i = 0; i < text.size(); ++i) {
        char c = text[i];
        if (c == ' ') continue;
        float cx = x + i * charWidth;
        float cy = y;

        // Simple colored quad for char
        float vertices[] = {
            cx, cy, 0,0, color.r, color.g, color.b, color.a,
            cx, cy+charHeight, 0,1, color.r, color.g, color.b, color.a,
            cx+charWidth, cy+charHeight, 1,1, color.r, color.g, color.b, color.a,
            cx, cy, 0,0, color.r, color.g, color.b, color.a,
            cx+charWidth, cy+charHeight, 1,1, color.r, color.g, color.b, color.a,
            cx+charWidth, cy, 1,0, color.r, color.g, color.b, color.a,
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

#endif // EAGLER_VULKAN