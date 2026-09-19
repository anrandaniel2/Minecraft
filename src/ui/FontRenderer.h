#pragma once
#include <string>
#include <glm/glm.hpp>
#include "../core/Shader.h"
#include <unordered_map>

namespace Eaglercraft {

class FontRenderer {
public:
    FontRenderer();
    ~FontRenderer();

    bool init();
    void renderText(Shader& shader, const std::string& text, float x, float y, float scale, glm::vec4 color);

    // Minecraft style font - 8x8 bitmap, we generate texture procedurally
    static FontRenderer& get();

private:
    uint32_t vao = 0, vbo = 0;
    uint32_t texture = 0;
    bool initialized = false;

    // Simple bitmap font data (ASCII 32-126)
    static const unsigned char fontData[95][8];
};

}
