#include "MainMenu.h"
#include "FontRenderer.h"
#include <glm/gtc/matrix_transform.hpp>
#include <iostream>
#if defined(EAGLER_VULKAN)
// Vulkan dummy - UI rendering handled by VulkanRenderer
namespace Eaglercraft {

MainMenu::MainMenu() : UIScreen(ScreenType::MainMenu) {}

void MainMenu::init(int w, int h) { width=w; height=h; buttons.clear(); }

void MainMenu::layoutButtons() {
    float centerX = width * 0.5f;
    float startY = height * 0.45f;
    float spacing = 24;
    for (size_t i = 0; i < buttons.size(); ++i) {
        if (i < 4) {
            buttons[i].setPosition(centerX - buttons[i].width*0.5f, startY + i*spacing);
        } else if (i == 4) {
            buttons[i].setPosition(centerX - 100 - 2, startY + 4*spacing);
        } else if (i == 5) {
            buttons[i].setPosition(centerX + 2, startY + 4*spacing);
        }
    }
}

void MainMenu::update(float dt) { time += dt; }

void MainMenu::onMouseMove(float x, float y) {
    for (auto& b : buttons) b.update(x,y);
}

void MainMenu::onMouseButton(int button, int action, int mods, float x, float y) {
    for (auto& b : buttons) b.onMouseButton(button, action, x, y);
}

void MainMenu::render(Shader& shader, int w, int h) { width=w; height=h; }

}

#else

namespace Eaglercraft {

MainMenu::MainMenu() : UIScreen(ScreenType::MainMenu) {}

void MainMenu::init(int w, int h) {
    width = w; height = h;
    buttons.clear();

    Button single("Singleplayer", 0,0,200,20);
    single.setCallback([this](){ if(onSingleplayer) onSingleplayer(); });
    buttons.push_back(single);

    Button multi("Multiplayer", 0,0,200,20);
    multi.setCallback([this](){ if(onMultiplayer) onMultiplayer(); });
    buttons.push_back(multi);

    Button options("Options...", 0,0,200,20);
    options.setCallback([this](){ if(onOptions) onOptions(); });
    buttons.push_back(options);

    Button quit("Quit Game", 0,0,200,20);
    quit.setCallback([this](){ if(onQuit) onQuit(); });
    buttons.push_back(quit);

    Button skins("Skins...", 0,0,98,20);
    buttons.push_back(skins);

    Button servers("Servers", 0,0,98,20);
    buttons.push_back(servers);

    layoutButtons();
}

void MainMenu::layoutButtons() {
    float centerX = width * 0.5f;
    float startY = height * 0.45f;
    float spacing = 24;

    for (size_t i = 0; i < buttons.size(); ++i) {
        if (i < 4) {
            buttons[i].setPosition(centerX - buttons[i].width*0.5f, startY + i*spacing);
        } else if (i == 4) {
            buttons[i].setPosition(centerX - 100 - 2, startY + 4*spacing);
        } else if (i == 5) {
            buttons[i].setPosition(centerX + 2, startY + 4*spacing);
        }
    }
}

void MainMenu::update(float dt) {
    time += dt;
}

void MainMenu::onMouseMove(float x, float y) {
    for (auto& b : buttons) {
        b.update(x,y);
    }
}

void MainMenu::onMouseButton(int button, int action, int mods, float x, float y) {
    for (auto& b : buttons) {
        b.onMouseButton(button, action, x, y);
    }
}

void MainMenu::render(Shader& uiShader, int w, int h) {
    width = w; height = h;
    layoutButtons();

    glm::mat4 proj = glm::ortho(0.0f, float(width), float(height), 0.0f, -1.0f, 1.0f);
    uiShader.bind();
    uiShader.setUniform("uProj", proj);

    drawRect(uiShader, 0, 0, width, height, glm::vec4(0.2f, 0.3f, 0.5f, 1.0f));
    drawRect(uiShader, 0, height*0.6f, width, height*0.4f, glm::vec4(0.3f, 0.2f, 0.15f, 0.6f));

    float logoW = 400, logoH = 60;
    float logoX = (width - logoW)*0.5f;
    float logoY = height*0.15f;
    FontRenderer::get().renderText(uiShader, "EAGLER CRAFT", logoX+40, logoY, 3.0f, glm::vec4(1,1,1,1));
    FontRenderer::get().renderText(uiShader, "26.2 - 0.6 (Native C++ Port)", logoX+20, logoY+40, 1.2f, glm::vec4(1,1,0.3f,1));

    for (auto& b : buttons) {
        b.render(uiShader);
        float textX = b.x + (b.width - b.text.length()*8*1.0f)*0.5f;
        float textY = b.y + 6;
        FontRenderer::get().renderText(uiShader, b.text, textX, textY, 1.0f, glm::vec4(1,1,1,1));
    }

    FontRenderer::get().renderText(uiShader, "Minecraft 1.20.6 / 26.2 WASM -> C++ Native Port", 10, height-30, 0.9f, glm::vec4(1,1,1,0.8f));
    FontRenderer::get().renderText(uiShader, "Original by lax1dude, o_xer, ayunami | C++ Port: Eaglercraft Native", 10, height-15, 0.8f, glm::vec4(0.8f,0.8f,0.8f,1));

    std::string ver = "Eaglercraft 26.2-0.6 Native (C++)";
    FontRenderer::get().renderText(uiShader, ver, width - ver.length()*8 - 10, height-15, 0.8f, glm::vec4(1,1,1,0.7f));
}

}

#endif
