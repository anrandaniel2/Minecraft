#include "Player.h"
#include "../core/Input.h"
#include <GLFW/glfw3.h>
#include <glm/gtc/matrix_transform.hpp>
#include <iostream>

namespace Eaglercraft {

Player::Player() {
    for (int i = 0; i < HOTBAR_SIZE; ++i) {
        hotbar[i] = BlockType::Grass;
    }
    hotbar[0] = BlockType::Grass;
    hotbar[1] = BlockType::Dirt;
    hotbar[2] = BlockType::Stone;
    hotbar[3] = BlockType::Wood;
    hotbar[4] = BlockType::Planks;
    hotbar[5] = BlockType::Glass;
    hotbar[6] = BlockType::Cobblestone;
    hotbar[7] = BlockType::Sand;
    hotbar[8] = BlockType::CherryWood;
}

AABB Player::getAABB() const {
    glm::vec3 min = position + glm::vec3(-width/2, 0, -width/2);
    glm::vec3 max = position + glm::vec3(width/2, height, width/2);
    return {min, max};
}

bool Player::isColliding(const AABB& box) const {
    if (!world) return false;
    int minX = (int)floor(box.min.x);
    int maxX = (int)floor(box.max.x);
    int minY = (int)floor(box.min.y);
    int maxY = (int)floor(box.max.y);
    int minZ = (int)floor(box.min.z);
    int maxZ = (int)floor(box.max.z);
    for (int x = minX; x <= maxX; ++x) {
        for (int y = minY; y <= maxY; ++y) {
            for (int z = minZ; z <= maxZ; ++z) {
                Block b = world->getBlock(x,y,z);
                if (b.isSolid()) {
                    AABB blockBox(glm::vec3(x,y,z), glm::vec3(x+1,y+1,z+1));
                    if (box.intersects(blockBox)) return true;
                }
            }
        }
    }
    return false;
}

void Player::applyGravity(float dt) {
    if (gameMode == GameMode::Creative && isFlying) return;
    if (gameMode == GameMode::Spectator) return;
    velocity.y -= gravity * dt;
}

void Player::checkCollisions() {
    if (!world) return;
    if (gameMode == GameMode::Spectator) return;
    if (gameMode == GameMode::Creative && isFlying) return;

    // Simple axis-separated collision
    glm::vec3 newPos = position;

    // Y
    newPos.y += velocity.y * 0.05f; // scaled
    AABB boxY(glm::vec3(newPos.x - width/2, newPos.y, newPos.z - width/2),
              glm::vec3(newPos.x + width/2, newPos.y + height, newPos.z + width/2));
    if (isColliding(boxY)) {
        if (velocity.y < 0) onGround = true;
        velocity.y = 0;
        newPos.y = position.y;
    } else {
        onGround = false;
    }

    // X
    newPos.x += velocity.x * 0.05f;
    AABB boxX(glm::vec3(newPos.x - width/2, newPos.y, newPos.z - width/2),
              glm::vec3(newPos.x + width/2, newPos.y + height, newPos.z + width/2));
    if (isColliding(boxX)) {
        velocity.x = 0;
        newPos.x = position.x;
    }

    // Z
    newPos.z += velocity.z * 0.05f;
    AABB boxZ(glm::vec3(newPos.x - width/2, newPos.y, newPos.z - width/2),
              glm::vec3(newPos.x + width/2, newPos.y + height, newPos.z + width/2));
    if (isColliding(boxZ)) {
        velocity.z = 0;
        newPos.z = position.z;
    }

    position = newPos;
}

void Player::handleInput(float deltaTime) {
    // Mouse look
    glm::vec2 delta = Input::getMouseDelta();
    float sensitivity = 0.15f;
    camera.rotate(delta.x * sensitivity, -delta.y * sensitivity);

    // Movement
    glm::vec3 forward = camera.getForward();
    glm::vec3 right = camera.getRight();
    forward.y = 0; forward = glm::normalize(forward);
    right.y = 0; right = glm::normalize(right);

    glm::vec3 moveDir(0);
    if (Input::isKeyDown(GLFW_KEY_W)) moveDir += forward;
    if (Input::isKeyDown(GLFW_KEY_S)) moveDir -= forward;
    if (Input::isKeyDown(GLFW_KEY_A)) moveDir -= right;
    if (Input::isKeyDown(GLFW_KEY_D)) moveDir += right;

    if (glm::length(moveDir) > 0) moveDir = glm::normalize(moveDir);

    float speed = (gameMode == GameMode::Creative && isFlying) ? flySpeed : moveSpeed;
    if (Input::isKeyDown(GLFW_KEY_LEFT_CONTROL) || Input::isKeyDown(GLFW_KEY_LEFT_SHIFT)) {
        if (gameMode == GameMode::Creative && isFlying) speed *= 2.5f;
        else isSprinting = true;
    } else {
        isSprinting = false;
    }
    if (isSprinting) speed *= 1.3f;

    if (gameMode == GameMode::Creative && isFlying) {
        if (Input::isKeyDown(GLFW_KEY_SPACE)) moveDir.y += 1;
        if (Input::isKeyDown(GLFW_KEY_LEFT_SHIFT) || Input::isKeyDown(GLFW_KEY_LEFT_CONTROL)) {
            // Actually shift for down in flying? We use shift as sprint, use C for down
        }
        if (Input::isKeyDown(GLFW_KEY_C) || Input::isKeyDown(GLFW_KEY_LEFT_SHIFT)) {
            if (Input::isKeyDown(GLFW_KEY_SPACE)) {
                // both pressed, don't move
            } else {
                moveDir.y -= 1;
            }
        }
        // When flying, we directly set velocity
        velocity.x = moveDir.x * speed;
        velocity.z = moveDir.z * speed;
        velocity.y = moveDir.y * speed;
    } else {
        velocity.x = moveDir.x * speed;
        velocity.z = moveDir.z * speed;
        if (Input::isKeyPressed(GLFW_KEY_SPACE) && onGround) {
            velocity.y = jumpVelocity;
            onGround = false;
        }
    }

    // Toggle flying
    if (Input::isKeyPressed(GLFW_KEY_F) && gameMode == GameMode::Creative) {
        isFlying = !isFlying;
        std::cout << "Flying: " << isFlying << "\n";
    }

    // Hotbar selection
    for (int i = 0; i < 9; ++i) {
        if (Input::isKeyPressed(GLFW_KEY_1 + i)) {
            selectedSlot = i;
        }
    }
    float scroll = Input::getScrollDelta().y;
    if (scroll != 0) {
        selectedSlot -= (int)scroll;
        if (selectedSlot < 0) selectedSlot = 8;
        if (selectedSlot > 8) selectedSlot = 0;
    }
}

void Player::update(float deltaTime) {
    if (!world) return;

    applyGravity(deltaTime);
    checkCollisions();

    // Apply friction
    if (onGround) {
        velocity.x *= 0.8f;
        velocity.z *= 0.8f;
    } else {
        velocity.x *= 0.95f;
        velocity.z *= 0.95f;
    }

    // Update camera
    camera.setPosition(position + glm::vec3(0, eyeHeight, 0));
}

World::RaycastResult Player::getTargetBlock() const {
    if (!world) return {};
    glm::vec3 eye = position + glm::vec3(0, eyeHeight, 0);
    glm::vec3 dir = camera.getForward();
    return world->raycast(eye, dir, 6.0f);
}

}
