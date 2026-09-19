#pragma once
#include "UIScreen.h"
#include "../world/Block.h"
#include <glm/glm.hpp>

namespace Eaglercraft {

class Player;
class World;

class InGameHUD : public UIScreen {
public:
    InGameHUD();
    void init(int width, int height) override;
    void render(Shader& uiShader, int width, int height) override;
    void render(Shader& uiShader, int width, int height, Player& player, World& world);

    void setDebugInfo(const std::string& info) { debugInfo = info; }

private:
    std::string debugInfo;
    void renderHotbar(Shader& shader, Player& player);
    void renderCrosshair(Shader& shader);
    void renderHealth(Shader& shader);
    void renderDebug(Shader& shader);
};

}
