#pragma once
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>
#include <cmath>

namespace Eaglercraft {

using Vec2 = glm::vec2;
using Vec3 = glm::vec3;
using Vec4 = glm::vec4;
using Mat4 = glm::mat4;
using IVec3 = glm::ivec3;

constexpr float PI = 3.14159265359f;

inline float lerp(float a, float b, float t) {
    return a + (b - a) * t;
}

struct AABB {
    Vec3 min;
    Vec3 max;
    AABB() : min(0), max(0) {}
    AABB(Vec3 min_, Vec3 max_) : min(min_), max(max_) {}
    bool intersects(const AABB& other) const {
        return (min.x <= other.max.x && max.x >= other.min.x) &&
               (min.y <= other.max.y && max.y >= other.min.y) &&
               (min.z <= other.max.z && max.z >= other.min.z);
    }
    Vec3 getCenter() const { return (min + max) * 0.5f; }
    Vec3 getSize() const { return max - min; }
};

}
