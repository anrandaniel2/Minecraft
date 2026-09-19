#pragma once
#include "vulkan_context.h"
#include "vulkan_mesh.h"
#include "vulkan_shader.h"
#include "world/World.h"
#include "player/Camera.h"
#include "core/Shader.h" // keep for compatibility but will not use GL
#include <unordered_map>
#include <memory>
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

namespace Eaglercraft {

// Uniform buffer object for block shader (matches triangle.vert from Sascha Willems)
struct BlockUBO {
    glm::mat4 projectionMatrix;
    glm::mat4 modelMatrix;
    glm::mat4 viewMatrix;
};

// For UI, we need ortho projection
struct UIUBO {
    glm::mat4 projection;
};

class AndroidRenderer {
public:
    AndroidRenderer();
    ~AndroidRenderer();

    bool init(int width, int height);
    void shutdown();
    void beginFrame();
    void endFrame();
    void setViewport(int w, int h);

    void renderWorld(World& world, const Camera& camera);

    // Compatibility: return dummy shaders for old code that expects Shader&
    // We'll provide Vulkan equivalents but keep interface
    Shader& getBlockShader() { return dummyBlockShader; }
    Shader& getUIShader() { return dummyUIShader; }

    // Vulkan-specific
    VkPipeline getBlockPipeline() const { return blockPipeline; }
    VkPipeline getUIPipeline() const { return uiPipeline; }
    VkPipelineLayout getBlockPipelineLayout() const { return blockPipelineLayout; }
    VkPipelineLayout getUIPipelineLayout() const { return uiPipelineLayout; }

private:
    // Dummy GL shaders for compatibility (not used in Vulkan path)
    Shader dummyBlockShader;
    Shader dummyUIShader;

    // Vulkan resources
    VkDescriptorSetLayout blockDescriptorSetLayout = VK_NULL_HANDLE;
    VkDescriptorSetLayout uiDescriptorSetLayout = VK_NULL_HANDLE;
    VkPipelineLayout blockPipelineLayout = VK_NULL_HANDLE;
    VkPipelineLayout uiPipelineLayout = VK_NULL_HANDLE;
    VkPipeline blockPipeline = VK_NULL_HANDLE;
    VkPipeline uiPipeline = VK_NULL_HANDLE;

    VkDescriptorPool descriptorPool = VK_NULL_HANDLE;
    std::vector<VkDescriptorSet> blockDescriptorSets;
    std::vector<VkDescriptorSet> uiDescriptorSets;

    std::vector<VkBuffer> blockUniformBuffers;
    std::vector<VkDeviceMemory> blockUniformMemories;
    std::vector<void*> blockUniformMapped;

    std::vector<VkBuffer> uiUniformBuffers;
    std::vector<VkDeviceMemory> uiUniformMemories;
    std::vector<void*> uiUniformMapped;

    std::unordered_map<Chunk*, std::unique_ptr<VulkanMesh>> chunkMeshes;

    // UI quad
    std::unique_ptr<VulkanMesh> uiQuadMesh;

    int screenWidth = 0, screenHeight = 0;
    bool initialized = false;

    bool createDescriptorSetLayouts();
    bool createPipelines();
    bool createUniformBuffers();
    bool createDescriptorPool();
    bool createDescriptorSets();
    bool createUIMesh();

    void updateBlockUBO(uint32_t currentImage, const glm::mat4& proj, const glm::mat4& view, const glm::mat4& model);
    void updateUIUBO(uint32_t currentImage, const glm::mat4& proj);

    VkShaderModule createShaderModule(const uint32_t* code, size_t size);
};

}
