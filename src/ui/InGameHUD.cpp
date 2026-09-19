#include "InGameHUD.h"
#include "../player/Player.h"
#include "../world/World.h"
#include "FontRenderer.h"
#include <glm/gtc/matrix_transform.hpp>

namespace Eaglercraft {

InGameHUD::InGameHUD() : UIScreen(ScreenType::InGame) {}

void InGameHUD::init(int w, int h) {
    width = w; height = h;
}

void InGameHUD::render(Shader& uiShader, int w, int h) {
    // Base render without player - just debug
    width = w; height = h;
    glm::mat4 proj = glm::ortho(0.0f, float(width), float(height), 0.0f, -1.0f, 1.0f);
    uiShader.bind();
    uiShader.setUniform("uProj", proj);
    renderDebug(uiShader);
}

void InGameHUD::render(Shader& uiShader, int w, int h, Player& player, World& world) {
    width = w; height = h;
    glm::mat4 proj = glm::ortho(0.0f, float(width), float(height), 0.0f, -1.0f, 1.0f);
    uiShader.bind();
    uiShader.setUniform("uProj", proj);

    renderCrosshair(uiShader);
    renderHotbar(uiShader, player);
    renderHealth(uiShader);
    renderDebug(uiShader);

    // Selected block info
    auto target = player.getTargetBlock();
    if (target.hit) {
        std::string info = "Target: " + std::to_string(target.blockPos.x) + "," + std::to_string(target.blockPos.y) + "," + std::to_string(target.blockPos.z);
        FontRenderer::get().renderText(uiShader, info, 10, 50, 0.9f, glm::vec4(1,1,1,1));
    }

    // Position
    auto pos = player.getPosition();
    std::string posStr = "XYZ: " + std::to_string(int(pos.x)) + " / " + std::to_string(int(pos.y)) + " / " + std::to_string(int(pos.z));
    FontRenderer::get().renderText(uiShader, posStr, 10, 10, 0.9f, glm::vec4(1,1,1,1));

    // FPS etc from debugInfo
    FontRenderer::get().renderText(uiShader, debugInfo, 10, 25, 0.8f, glm::vec4(1,1,1,0.8f));
}

void InGameHUD::renderHotbar(Shader& shader, Player& player) {
    float hotbarW = 182*2;
    float hotbarH = 22*2;
    float x = (width - hotbarW)*0.5f;
    float y = height - hotbarH - 5;

    // Background
    drawRect(shader, x, y, hotbarW, hotbarH, glm::vec4(0.2f,0.2f,0.2f,0.8f));

    // Slots
    for (int i = 0; i < 9; ++i) {
        float sx = x + 3 + i*20*2;
        float sy = y + 3;
        float sw = 16*2;
        float sh = 16*2;
        bool selected = (i == player.selectedSlot);
        glm::vec4 col = selected ? glm::vec4(1,1,1,1) : glm::vec4(0.4f,0.4f,0.4f,1);
        drawRect(shader, sx-1, sy-1, sw+2, sh+2, col);
        // Block color
        auto blockType = player.hotbar[i];
        auto& reg = BlockRegistry::get();
        auto info = reg.getInfo(blockType);
        drawRect(shader, sx, sy, sw, sh, glm::vec4(info.color, 1.0f));

        // Selection highlight
        if (selected) {
            drawRect(shader, sx-2, sy-2, sw+4, 2, glm::vec4(1,1,1,1));
            drawRect(shader, sx-2, sy+sh, sw+4, 2, glm::vec4(1,1,1,1));
            drawRect(shader, sx-2, sy-2, 2, sh+4, glm::vec4(1,1,1,1));
            drawRect(shader, sx+sw, sy-2, 2, sh+4, glm::vec4(1,1,1,1));
        }
    }
}

void InGameHUD::renderCrosshair(Shader& shader) {
    float cx = width*0.5f;
    float cy = height*0.5f;
    float size = 10;
    float thickness = 2;
    // Horizontal
    drawRect(shader, cx - size, cy - thickness*0.5f, size*2, thickness, glm::vec4(1,1,1,1));
    // Vertical
    drawRect(shader, cx - thickness*0.5f, cy - size, thickness, size*2, glm::vec4(1,1,1,1));
    // Outline
    drawRect(shader, cx - size -1, cy - thickness*0.5f -1, size*2+2, thickness+2, glm::vec4(0,0,0,0.8f));
    drawRect(shader, cx - thickness*0.5f -1, cy - size -1, thickness+2, size*2+2, glm::vec4(0,0,0,0.8f));
    // Recenter white
    drawRect(shader, cx - size, cy - thickness*0.5f, size*2, thickness, glm::vec4(1,1,1,1));
    drawRect(shader, cx - thickness*0.5f, cy - size, thickness, size*2, glm::vec4(1,1,1,1));
}

void InGameHUD::renderHealth(Shader& shader) {
    // Simple health bar - 10 hearts
    float x = width*0.5f - 91*2;
    float y = height - 22*2 - 5 - 10 - 10;
    for (int i = 0; i < 10; ++i) {
        float hx = x + i*8*2;
        drawRect(shader, hx, y, 7*2, 7*2, glm::vec4(1,0,0,1));
        drawRect(shader, hx+2, y+2, 3*2, 3*2, glm::vec4(0.6f,0,0,1));
    }
}

void InGameHUD::renderDebug(Shader& shader) {
    if (!debugInfo.empty()) {
        // Already rendered elsewhere
    }
}

}
