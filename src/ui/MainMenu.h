#pragma once
#include "UIScreen.h"
#include "Button.h"
#include <vector>
#include <functional>

namespace Eaglercraft {

class MainMenu : public UIScreen {
public:
    MainMenu();
    void init(int width, int height) override;
    void render(Shader& uiShader, int width, int height) override;
    void onMouseButton(int button, int action, int mods, float x, float y) override;
    void onMouseMove(float x, float y) override;
    void update(float deltaTime) override;

    // Callbacks
    std::function<void()> onSingleplayer;
    std::function<void()> onMultiplayer;
    std::function<void()> onOptions;
    std::function<void()> onQuit;

private:
    std::vector<Button> buttons;
    float time = 0.0f;
    void layoutButtons();
};

}
