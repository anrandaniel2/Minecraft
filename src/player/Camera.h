#pragma once
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

namespace Eaglercraft {

class Camera {
public:
    Camera();

    void setPosition(const glm::vec3& pos) { position = pos; dirty = true; }
    void setRotation(float yaw_, float pitch_) { yaw = yaw_; pitch = pitch_; clampPitch(); dirty = true; }
    void move(const glm::vec3& delta) { position += delta; dirty = true; }
    void rotate(float dyaw, float dpitch) { yaw += dyaw; pitch += dpitch; clampPitch(); dirty = true; }

    glm::vec3 getPosition() const { return position; }
    float getYaw() const { return yaw; }
    float getPitch() const { return pitch; }

    glm::vec3 getForward() const;
    glm::vec3 getRight() const;
    glm::vec3 getUp() const;

    void setPerspective(float fovDeg, float aspect, float nearPlane, float farPlane);
    glm::mat4 getViewMatrix() const;
    glm::mat4 getProjectionMatrix() const;
    glm::mat4 getViewProjection() const;

    // Frustum
    bool isBoxInFrustum(const glm::vec3& min, const glm::vec3& max) const;

private:
    glm::vec3 position = glm::vec3(0, 80, 0);
    float yaw = -90.0f; // looking towards -Z
    float pitch = 0.0f;
    float fov = 70.0f;
    float aspect = 16.0f/9.0f;
    float nearPlane = 0.1f;
    float farPlane = 500.0f;

    mutable glm::mat4 view{1.0f}, proj{1.0f}, viewProj{1.0f};
    mutable bool dirty = true;

    void clampPitch();
    void updateMatrices() const;
};

}
