#pragma once
#include "Camera.h"
#include "../world/World.h"
#include "../utils/Math.h"
#include <glm/glm.hpp>

namespace Eaglercraft {

enum class GameMode {
    Survival,
    Creative,
    Spectator
};

class Player {
public:
    Player();

    void setWorld(World* w) { world = w; }
    void setPosition(const glm::vec3& pos) { position = pos; camera.setPosition(pos + glm::vec3(0, eyeHeight, 0)); }
    glm::vec3 getPosition() const { return position; }

    void update(float deltaTime);
    void handleInput(float deltaTime);

    Camera& getCamera() { return camera; }
    const Camera& getCamera() const { return camera; }

    void setGameMode(GameMode mode) { gameMode = mode; }
    GameMode getGameMode() const { return gameMode; }

    // Physics
    glm::vec3 velocity{0};
    bool onGround = false;
    bool isFlying = false;
    bool isSprinting = false;
    bool isSneaking = false;

    // Inventory (simple)
    static constexpr int HOTBAR_SIZE = 9;
    BlockType hotbar[HOTBAR_SIZE];
    int selectedSlot = 0;

    // Raycast
    World::RaycastResult getTargetBlock() const;

    AABB getAABB() const;

private:
    glm::vec3 position{0, 80, 0};
    Camera camera;
    World* world = nullptr;
    GameMode gameMode = GameMode::Creative;

    float eyeHeight = 1.62f;
    float height = 1.8f;
    float width = 0.6f;

    float moveSpeed = 4.3f; // m/s
    float flySpeed = 8.0f;
    float jumpVelocity = 8.5f;
    float gravity = 24.0f;

    void applyGravity(float dt);
    void checkCollisions();
    bool isColliding(const AABB& box) const;
};

}
