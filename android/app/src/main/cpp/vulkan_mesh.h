#pragma once
#include <vulkan/vulkan.h>
#include <vector>
#include <cstdint>
#include <glm/glm.hpp>

namespace Eaglercraft {

struct VulkanVertex {
    glm::vec3 pos;
    glm::vec3 normal;
    glm::vec2 uv;
    glm::vec3 color;

    static VkVertexInputBindingDescription getBindingDescription() {
        VkVertexInputBindingDescription binding{};
        binding.binding = 0;
        binding.stride = sizeof(VulkanVertex);
        binding.inputRate = VK_VERTEX_INPUT_RATE_VERTEX;
        return binding;
    }

    static std::vector<VkVertexInputAttributeDescription> getAttributeDescriptions() {
        std::vector<VkVertexInputAttributeDescription> attribs(4);
        attribs[0].binding = 0;
        attribs[0].location = 0;
        attribs[0].format = VK_FORMAT_R32G32B32_SFLOAT;
        attribs[0].offset = offsetof(VulkanVertex, pos);

        attribs[1].binding = 0;
        attribs[1].location = 1;
        attribs[1].format = VK_FORMAT_R32G32B32_SFLOAT;
        attribs[1].offset = offsetof(VulkanVertex, normal);

        attribs[2].binding = 0;
        attribs[2].location = 2;
        attribs[2].format = VK_FORMAT_R32G32_SFLOAT;
        attribs[2].offset = offsetof(VulkanVertex, uv);

        attribs[3].binding = 0;
        attribs[3].location = 3;
        attribs[3].format = VK_FORMAT_R32G32B32_SFLOAT;
        attribs[3].offset = offsetof(VulkanVertex, color);

        return attribs;
    }
};

struct SimpleVertex {
    glm::vec3 pos;
    glm::vec3 color;
    static VkVertexInputBindingDescription getBindingDescription() {
        VkVertexInputBindingDescription binding{};
        binding.binding = 0;
        binding.stride = sizeof(SimpleVertex);
        binding.inputRate = VK_VERTEX_INPUT_RATE_VERTEX;
        return binding;
    }
    static std::vector<VkVertexInputAttributeDescription> getAttributeDescriptions() {
        std::vector<VkVertexInputAttributeDescription> attribs(2);
        attribs[0].binding = 0;
        attribs[0].location = 0;
        attribs[0].format = VK_FORMAT_R32G32B32_SFLOAT;
        attribs[0].offset = offsetof(SimpleVertex, pos);
        attribs[1].binding = 0;
        attribs[1].location = 1;
        attribs[1].format = VK_FORMAT_R32G32B32_SFLOAT;
        attribs[1].offset = offsetof(SimpleVertex, color);
        return attribs;
    }
};

class VulkanMesh {
public:
    VulkanMesh() = default;
    ~VulkanMesh();

    // For world chunks: vertices as interleaved float array [pos(3), normal(3), uv(2), color(3)] = 11 floats
    void setData(const std::vector<float>& vertices, const std::vector<uint32_t>& indices);
    void setSimpleData(const std::vector<SimpleVertex>& vertices, const std::vector<uint32_t>& indices);

    void bind(VkCommandBuffer cmd) const;
    void draw(VkCommandBuffer cmd) const;
    void clear();

    bool isValid() const { return indexCount > 0 && vertexBuffer != VK_NULL_HANDLE; }
    size_t getIndexCount() const { return indexCount; }

private:
    VkBuffer vertexBuffer = VK_NULL_HANDLE;
    VkDeviceMemory vertexMemory = VK_NULL_HANDLE;
    VkBuffer indexBuffer = VK_NULL_HANDLE;
    VkDeviceMemory indexMemory = VK_NULL_HANDLE;
    size_t indexCount = 0;
    size_t vertexCount = 0;
    bool isSimple = false;

    void createVertexBuffer(const void* data, VkDeviceSize size);
    void createIndexBuffer(const void* data, VkDeviceSize size);
};

}
