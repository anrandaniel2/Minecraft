#include "MainMenu.h"
#include "FontRenderer.h"
#include <glm/gtc/matrix_transform.hpp>
#include <iostream>

namespace Eaglercraft {

MainMenu::MainMenu() : UIScreen(ScreenType::MainMenu) {}

void MainMenu::init(int w, int h) {
    width = w; height = h;
    buttons.clear();

    // Create buttons matching Eaglercraft 26.2 main menu
    // In original HTML, buttons are: Singleplayer, Multiplayer, Options, etc.

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

    // Additional buttons for 26.2
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
    // Update hover
    // Mouse pos handled in onMouseMove
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

    // Background - panorama or dirt
    // For 26.2, background is a blurred panorama - we simulate with gradient
    drawRect(uiShader, 0, 0, width, height, glm::vec4(0.2f, 0.3f, 0.5f, 1.0f));
    // Dirt overlay for bottom
    drawRect(uiShader, 0, height*0.6f, width, height*0.4f, glm::vec4(0.3f, 0.2f, 0.15f, 0.6f));

    // Logo - Eaglercraft 26.2
    float logoW = 400, logoH = 60;
    float logoX = (width - logoW)*0.5f;
    float logoY = height*0.15f;
    // Logo background
    // drawRect(uiShader, logoX, logoY, logoW, logoH, glm::vec4(0,0,0,0.3f));
    FontRenderer::get().renderText(uiShader, "EAGLER CRAFT", logoX+40, logoY, 3.0f, glm::vec4(1,1,1,1));
    FontRenderer::get().renderText(uiShader, "26.2 - 0.6 (Native C++ Port)", logoX+20, logoY+40, 1.2f, glm::vec4(1,1,0.3f,1));

    // Buttons
    for (auto& b : buttons) {
        b.render(uiShader);
        // Render button text centered
        float textX = b.x + (b.width - b.text.length()*8*1.0f)*0.5f;
        float textY = b.y + 6;
        FontRenderer::get().renderText(uiShader, b.text, textX, textY, 1.0f, glm::vec4(1,1,1,1));
    }

    // Bottom info
    FontRenderer::get().renderText(uiShader, "Minecraft 1.20.6 / 26.2 WASM -> C++ Native Port", 10, height-30, 0.9f, glm::vec4(1,1,1,0.8f));
    FontRenderer::get().renderText(uiShader, "Original by lax1dude, o_xer, ayunami | C++ Port: Eaglercraft Native", 10, height-15, 0.8f, glm::vec4(0.8f,0.8f,0.8f,1));

    // Version
    std::string ver = "Eaglercraft 26.2-0.6 Native (C++)";
    FontRenderer::get().renderText(uiShader, ver, width - ver.length()*8 - 10, height-15, 0.8f, glm::vec4(1,1,1,0.7f));
}

}
