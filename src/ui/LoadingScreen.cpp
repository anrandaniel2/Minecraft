#include "LoadingScreen.h"
#include "FontRenderer.h"
#include <glm/gtc/matrix_transform.hpp>
#if defined(EAGLER_VULKAN)
// Vulkan dummy - UI rendering handled by VulkanRenderer
namespace Eaglercraft {

LoadingScreen::LoadingScreen() : UIScreen(ScreenType::Loading) {}

void LoadingScreen::init(int w, int h) { width=w; height=h; progress=0.0f; status="Loading Eaglercraft 26.2..."; }

void LoadingScreen::update(float deltaTime) { time += deltaTime; }

void LoadingScreen::render(Shader& shader, int width, int height) {}

}

#else

namespace Eaglercraft {

LoadingScreen::LoadingScreen() : UIScreen(ScreenType::Loading) {}

void LoadingScreen::init(int w, int h) {
    width = w; height = h;
    progress = 0.0f;
    status = "Loading Eaglercraft 26.2...";
}

void LoadingScreen::update(float deltaTime) {
    time += deltaTime;
}

void LoadingScreen::render(Shader& uiShader, int w, int h) {
    width = w; height = h;
    glm::mat4 proj = glm::ortho(0.0f, float(width), float(height), 0.0f, -1.0f, 1.0f);
    uiShader.bind();
    uiShader.setUniform("uProj", proj);

    drawRect(uiShader, 0, 0, width, height, glm::vec4(0.15f, 0.15f, 0.15f, 1.0f));

    float logoW = 400, logoH = 80;
    float logoX = (width - logoW) * 0.5f;
    float logoY = height * 0.3f;
    drawRect(uiShader, logoX, logoY, logoW, logoH, glm::vec4(0.2f, 0.2f, 0.2f, 1.0f));
    FontRenderer::get().renderText(uiShader, "Eaglercraft 26.2", logoX+20, logoY+20, 2.0f, glm::vec4(1,1,1,1));
    FontRenderer::get().renderText(uiShader, "0.6 - Native C++ Port", logoX+20, logoY+50, 1.0f, glm::vec4(0.8f,0.8f,0.8f,1));

    float barW = 400, barH = 20;
    float barX = (width - barW) * 0.5f;
    float barY = height * 0.6f;
    drawRect(uiShader, barX, barY, barW, barH, glm::vec4(0.3f,0.3f,0.3f,1.0f));
    drawRect(uiShader, barX, barY, barW * progress, barH, glm::vec4(0.2f, 0.8f, 0.2f, 1.0f));

    FontRenderer::get().renderText(uiShader, status, barX, barY+30, 1.0f, glm::vec4(1,1,1,1));

    FontRenderer::get().renderText(uiShader, "Minecraft 1.20.6+ (26.2) - WASM Port -> C++ Native", 10, height-30, 1.0f, glm::vec4(0.6f,0.6f,0.6f,1));
    FontRenderer::get().renderText(uiShader, "Original: https://eymenwsmc.site/262/ | Ported by C++ Engine", 10, height-15, 0.8f, glm::vec4(0.5f,0.5f,0.5f,1));
}

}

#endif
