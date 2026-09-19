#pragma once
#include "UIScreen.h"
#include <string>

namespace Eaglercraft {

class LoadingScreen : public UIScreen {
public:
    LoadingScreen();
    void init(int width, int height) override;
    void render(Shader& uiShader, int width, int height) override;
    void update(float deltaTime) override;

    void setProgress(float p) { progress = p; }
    void setStatus(const std::string& s) { status = s; }

private:
    float progress = 0.0f;
    std::string status = "Loading...";
    float time = 0.0f;
};

}
