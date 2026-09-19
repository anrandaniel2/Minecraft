#pragma once
#include <vector>
#include <cstdint>
#if defined(EAGLER_VULKAN)
 // Vulkan dummy - real mesh is VulkanMesh in android
#else
#ifdef EAGLER_ANDROID
#include <GLES3/gl3.h>
#else
#include <glad/gl.h>
#endif
#endif

namespace Eaglercraft {

class Mesh {
public:
    Mesh();
    ~Mesh();

    void setData(const std::vector<float>& vertices, const std::vector<uint32_t>& indices, bool hasColor = true);
    void draw() const;
    void clear();

#if defined(EAGLER_VULKAN)
    bool isValid() const { return indexCount != 0; }
#else
    bool isValid() const { return vao != 0; }
#endif
    size_t getIndexCount() const { return indexCount; }

private:
#if defined(EAGLER_VULKAN)
    size_t indexCount = 0;
    std::vector<float> storedVertices;
    std::vector<uint32_t> storedIndices;
#else
    uint32_t vao = 0, vbo = 0, ebo = 0;
    size_t indexCount = 0;
#endif
};

}
