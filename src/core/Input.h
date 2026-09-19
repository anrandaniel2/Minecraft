#pragma once
#include <glm/glm.hpp>
#include <array>

namespace Eaglercraft {

class Input {
public:
    static void init();
    static void update();

    static bool isKeyDown(int key);
    static bool isKeyPressed(int key); // just pressed this frame
    static bool isKeyReleased(int key);

    static bool isMouseDown(int button);
    static bool isMousePressed(int button);
    static bool isMouseReleased(int button);

    static glm::vec2 getMousePos();
    static glm::vec2 getMouseDelta();
    static glm::vec2 getScrollDelta();

    // To be called from Window callbacks
    static void setKey(int key, int action);
    static void setMouseButton(int button, int action);
    static void setMousePos(double x, double y);
    static void setScroll(double x, double y);

private:
    static std::array<bool, 512> keys;
    static std::array<bool, 512> keysPrev;
    static std::array<bool, 8> mouseButtons;
    static std::array<bool, 8> mouseButtonsPrev;
    static glm::vec2 mousePos;
    static glm::vec2 mousePosPrev;
    static glm::vec2 mouseDelta;
    static glm::vec2 scrollDelta;
    static glm::vec2 scrollAccum;
};

}
