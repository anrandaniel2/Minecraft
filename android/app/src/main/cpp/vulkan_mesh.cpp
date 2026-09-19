#include "vulkan_mesh.h"
#include "vulkan_context.h"
#include <android/log.h>
#include <cstring>

#define LOGI(...) ((void)__android_log_print(ANDROID_LOG_INFO, "Eaglercraft-VK", __VA_ARGS__))
#define LOGE(...) ((void)__android_log_print(ANDROID_LOG_ERROR, "Eaglercraft-VK", __VA_ARGS__))

namespace Eaglercraft {

VulkanMesh::~VulkanMesh() { clear(); }

void VulkanMesh::clear() {
    auto& ctx = VulkanContext::get();
    VkDevice device = ctx.getDevice();
    if (device == VK_NULL_HANDLE) {
        vertexBuffer = VK_NULL_HANDLE;
        indexBuffer = VK_NULL_HANDLE;
        return;
    }
    if (vertexBuffer != VK_NULL_HANDLE) {
        vkDestroyBuffer(device, vertexBuffer, nullptr);
        vertexBuffer = VK_NULL_HANDLE;
    }
    if (vertexMemory != VK_NULL_HANDLE) {
        vkFreeMemory(device, vertexMemory, nullptr);
        vertexMemory = VK_NULL_HANDLE;
    }
    if (indexBuffer != VK_NULL_HANDLE) {
        vkDestroyBuffer(device, indexBuffer, nullptr);
        indexBuffer = VK_NULL_HANDLE;
    }
    if (indexMemory != VK_NULL_HANDLE) {
        vkFreeMemory(device, indexMemory, nullptr);
        indexMemory = VK_NULL_HANDLE;
    }
    indexCount = 0;
    vertexCount = 0;
}

void VulkanMesh::createVertexBuffer(const void* data, VkDeviceSize size) {
    auto& ctx = VulkanContext::get();
    VkDevice device = ctx.getDevice();

    VkBuffer stagingBuffer;
    VkDeviceMemory stagingMemory;
    ctx.createBuffer(size, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, stagingBuffer, stagingMemory);

    void* mapped;
    vkMapMemory(device, stagingMemory, 0, size, 0, &mapped);
    memcpy(mapped, data, static_cast<size_t>(size));
    vkUnmapMemory(device, stagingMemory);

    ctx.createBuffer(size, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, vertexBuffer, vertexMemory);
    ctx.copyBuffer(stagingBuffer, vertexBuffer, size);

    vkDestroyBuffer(device, stagingBuffer, nullptr);
    vkFreeMemory(device, stagingMemory, nullptr);
}

void VulkanMesh::createIndexBuffer(const void* data, VkDeviceSize size) {
    auto& ctx = VulkanContext::get();
    VkDevice device = ctx.getDevice();

    VkBuffer stagingBuffer;
    VkDeviceMemory stagingMemory;
    ctx.createBuffer(size, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, stagingBuffer, stagingMemory);

    void* mapped;
    vkMapMemory(device, stagingMemory, 0, size, 0, &mapped);
    memcpy(mapped, data, static_cast<size_t>(size));
    vkUnmapMemory(device, stagingMemory);

    ctx.createBuffer(size, VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, indexBuffer, indexMemory);
    ctx.copyBuffer(stagingBuffer, indexBuffer, size);

    vkDestroyBuffer(device, stagingBuffer, nullptr);
    vkFreeMemory(device, stagingMemory, nullptr);
}

void VulkanMesh::setData(const std::vector<float>& vertices, const std::vector<uint32_t>& indices) {
    if (vertices.empty() || indices.empty()) {
        clear();
        return;
    }
    clear();

    // Convert interleaved float array (11 floats per vertex) to VulkanVertex array
    size_t vertCount = vertices.size() / 11;
    std::vector<VulkanVertex> vulkanVerts;
    vulkanVerts.reserve(vertCount);
    for (size_t i = 0; i < vertCount; i++) {
        size_t base = i * 11;
        VulkanVertex v{};
        v.pos = glm::vec3(vertices[base+0], vertices[base+1], vertices[base+2]);
        v.normal = glm::vec3(vertices[base+3], vertices[base+4], vertices[base+5]);
        v.uv = glm::vec2(vertices[base+6], vertices[base+7]);
        v.color = glm::vec3(vertices[base+8], vertices[base+9], vertices[base+10]);
        vulkanVerts.push_back(v);
    }

    createVertexBuffer(vulkanVerts.data(), vulkanVerts.size() * sizeof(VulkanVertex));
    createIndexBuffer(indices.data(), indices.size() * sizeof(uint32_t));
    indexCount = indices.size();
    vertexCount = vertCount;
    isSimple = false;
}

void VulkanMesh::setSimpleData(const std::vector<SimpleVertex>& vertices, const std::vector<uint32_t>& indices) {
    if (vertices.empty() || indices.empty()) {
        clear();
        return;
    }
    clear();
    createVertexBuffer(vertices.data(), vertices.size() * sizeof(SimpleVertex));
    createIndexBuffer(indices.data(), indices.size() * sizeof(uint32_t));
    indexCount = indices.size();
    vertexCount = vertices.size();
    isSimple = true;
}

void VulkanMesh::bind(VkCommandBuffer cmd) const {
    if (!isValid()) return;
    VkBuffer buffers[] = {vertexBuffer};
    VkDeviceSize offsets[] = {0};
    vkCmdBindVertexBuffers(cmd, 0, 1, buffers, offsets);
    vkCmdBindIndexBuffer(cmd, indexBuffer, 0, VK_INDEX_TYPE_UINT32);
}

void VulkanMesh::draw(VkCommandBuffer cmd) const {
    if (!isValid()) return;
    vkCmdDrawIndexed(cmd, static_cast<uint32_t>(indexCount), 1, 0, 0, 0);
}

}
