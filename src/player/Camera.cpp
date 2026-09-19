#include "Camera.h"
#include <glm/gtc/matrix_transform.hpp>

namespace Eaglercraft {

Camera::Camera() {
    updateMatrices();
}

void Camera::clampPitch() {
    if (pitch > 89.0f) pitch = 89.0f;
    if (pitch < -89.0f) pitch = -89.0f;
}

glm::vec3 Camera::getForward() const {
    glm::vec3 forward;
    forward.x = cos(glm::radians(yaw)) * cos(glm::radians(pitch));
    forward.y = sin(glm::radians(pitch));
    forward.z = sin(glm::radians(yaw)) * cos(glm::radians(pitch));
    return glm::normalize(forward);
}

glm::vec3 Camera::getRight() const {
    return glm::normalize(glm::cross(getForward(), glm::vec3(0,1,0)));
}

glm::vec3 Camera::getUp() const {
    return glm::normalize(glm::cross(getRight(), getForward()));
}

void Camera::setPerspective(float fovDeg, float aspect_, float nearP, float farP) {
    fov = fovDeg;
    aspect = aspect_;
    nearPlane = nearP;
    farPlane = farP;
    dirty = true;
}

glm::mat4 Camera::getViewMatrix() const {
    if (dirty) updateMatrices();
    return view;
}

glm::mat4 Camera::getProjectionMatrix() const {
    if (dirty) updateMatrices();
    return proj;
}

glm::mat4 Camera::getViewProjection() const {
    if (dirty) updateMatrices();
    return viewProj;
}

void Camera::updateMatrices() const {
    view = glm::lookAt(position, position + getForward(), glm::vec3(0,1,0));
    proj = glm::perspective(glm::radians(fov), aspect, nearPlane, farPlane);
    viewProj = proj * view;
    dirty = false;
}

bool Camera::isBoxInFrustum(const glm::vec3& min, const glm::vec3& max) const {
    // Simplified: always true for now, could implement proper frustum culling
    return true;
}

}
