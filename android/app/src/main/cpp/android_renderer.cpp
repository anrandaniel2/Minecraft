#include "android_renderer.h"
#include "vulkan_context.h"
#include "shaders/triangle_vert_spv.h"
#include "shaders/triangle_frag_spv.h"
#include "shaders/uioverlay_vert_spv.h"
#include "shaders/uioverlay_frag_spv.h"
#include <android/log.h>
#include <array>

#define LOGI(...) ((void)__android_log_print(ANDROID_LOG_INFO, "Eaglercraft-VK", __VA_ARGS__))
#define LOGE(...) ((void)__android_log_print(ANDROID_LOG_ERROR, "Eaglercraft-VK", __VA_ARGS__))

namespace Eaglercraft {

AndroidRenderer::AndroidRenderer() = default;
AndroidRenderer::~AndroidRenderer() { shutdown(); }

VkShaderModule AndroidRenderer::createShaderModule(const uint32_t* code, size_t size) {
    auto& ctx = VulkanContext::get();
    VkDevice device = ctx.getDevice();
    VkShaderModuleCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    createInfo.codeSize = size;
    createInfo.pCode = code;
    VkShaderModule module;
    if (vkCreateShaderModule(device, &createInfo, nullptr, &module) != VK_SUCCESS) {
        LOGE("Failed to create shader module");
        return VK_NULL_HANDLE;
    }
    return module;
}

bool AndroidRenderer::init(int width, int height) {
    LOGI("AndroidRenderer Vulkan init %dx%d", width, height);
    screenWidth = width;
    screenHeight = height;

    if (!createDescriptorSetLayouts()) return false;
    if (!createPipelines()) return false;
    if (!createUniformBuffers()) return false;
    if (!createDescriptorPool()) return false;
    if (!createDescriptorSets()) return false;
    if (!createUIMesh()) return false;

    LOGI("AndroidRenderer Vulkan initialized");
    initialized = true;
    return true;
}

void AndroidRenderer::shutdown() {
    if (!initialized) return;
    LOGI("AndroidRenderer shutdown");
    auto& ctx = VulkanContext::get();
    VkDevice device = ctx.getDevice();
    if (device == VK_NULL_HANDLE) return;

    vkDeviceWaitIdle(device);

    chunkMeshes.clear();
    uiQuadMesh.reset();

    for (size_t i = 0; i < blockUniformBuffers.size(); i++) {
        if (blockUniformBuffers[i] != VK_NULL_HANDLE) vkDestroyBuffer(device, blockUniformBuffers[i], nullptr);
        if (blockUniformMemories[i] != VK_NULL_HANDLE) vkFreeMemory(device, blockUniformMemories[i], nullptr);
    }
    blockUniformBuffers.clear();
    blockUniformMemories.clear();
    blockUniformMapped.clear();

    for (size_t i = 0; i < uiUniformBuffers.size(); i++) {
        if (uiUniformBuffers[i] != VK_NULL_HANDLE) vkDestroyBuffer(device, uiUniformBuffers[i], nullptr);
        if (uiUniformMemories[i] != VK_NULL_HANDLE) vkFreeMemory(device, uiUniformMemories[i], nullptr);
    }
    uiUniformBuffers.clear();
    uiUniformMemories.clear();
    uiUniformMapped.clear();

    if (descriptorPool != VK_NULL_HANDLE) {
        vkDestroyDescriptorPool(device, descriptorPool, nullptr);
        descriptorPool = VK_NULL_HANDLE;
    }

    if (blockPipeline != VK_NULL_HANDLE) {
        vkDestroyPipeline(device, blockPipeline, nullptr);
        blockPipeline = VK_NULL_HANDLE;
    }
    if (uiPipeline != VK_NULL_HANDLE) {
        vkDestroyPipeline(device, uiPipeline, nullptr);
        uiPipeline = VK_NULL_HANDLE;
    }
    if (blockPipelineLayout != VK_NULL_HANDLE) {
        vkDestroyPipelineLayout(device, blockPipelineLayout, nullptr);
        blockPipelineLayout = VK_NULL_HANDLE;
    }
    if (uiPipelineLayout != VK_NULL_HANDLE) {
        vkDestroyPipelineLayout(device, uiPipelineLayout, nullptr);
        uiPipelineLayout = VK_NULL_HANDLE;
    }
    if (blockDescriptorSetLayout != VK_NULL_HANDLE) {
        vkDestroyDescriptorSetLayout(device, blockDescriptorSetLayout, nullptr);
        blockDescriptorSetLayout = VK_NULL_HANDLE;
    }
    if (uiDescriptorSetLayout != VK_NULL_HANDLE) {
        vkDestroyDescriptorSetLayout(device, uiDescriptorSetLayout, nullptr);
        uiDescriptorSetLayout = VK_NULL_HANDLE;
    }

    initialized = false;
}

bool AndroidRenderer::createDescriptorSetLayouts() {
    auto& ctx = VulkanContext::get();
    VkDevice device = ctx.getDevice();

    // Block descriptor set layout: UBO at binding 0
    VkDescriptorSetLayoutBinding uboLayoutBinding{};
    uboLayoutBinding.binding = 0;
    uboLayoutBinding.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    uboLayoutBinding.descriptorCount = 1;
    uboLayoutBinding.stageFlags = VK_SHADER_STAGE_VERTEX_BIT;
    uboLayoutBinding.pImmutableSamplers = nullptr;

    VkDescriptorSetLayoutCreateInfo layoutInfo{};
    layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    layoutInfo.bindingCount = 1;
    layoutInfo.pBindings = &uboLayoutBinding;

    if (vkCreateDescriptorSetLayout(device, &layoutInfo, nullptr, &blockDescriptorSetLayout) != VK_SUCCESS) {
        LOGE("Failed to create block descriptor set layout");
        return false;
    }

    // UI descriptor set layout: same
    if (vkCreateDescriptorSetLayout(device, &layoutInfo, nullptr, &uiDescriptorSetLayout) != VK_SUCCESS) {
        LOGE("Failed to create UI descriptor set layout");
        return false;
    }

    LOGI("Descriptor set layouts created");
    return true;
}

bool AndroidRenderer::createPipelines() {
    auto& ctx = VulkanContext::get();
    VkDevice device = ctx.getDevice();

    // Shader modules
    VkShaderModule vertBlockModule = createShaderModule(triangle_vert_spv, triangle_vert_spv_size);
    VkShaderModule fragBlockModule = createShaderModule(triangle_frag_spv, triangle_frag_spv_size);
    VkShaderModule vertUIModule = createShaderModule(uioverlay_vert_spv, uioverlay_vert_spv_size);
    VkShaderModule fragUIModule = createShaderModule(uioverlay_frag_spv, uioverlay_frag_spv_size);

    if (vertBlockModule == VK_NULL_HANDLE || fragBlockModule == VK_NULL_HANDLE ||
        vertUIModule == VK_NULL_HANDLE || fragUIModule == VK_NULL_HANDLE) {
        LOGE("Failed to create shader modules");
        return false;
    }

    // Pipeline layouts
    VkPipelineLayoutCreateInfo pipelineLayoutInfo{};
    pipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pipelineLayoutInfo.setLayoutCount = 1;
    pipelineLayoutInfo.pSetLayouts = &blockDescriptorSetLayout;

    if (vkCreatePipelineLayout(device, &pipelineLayoutInfo, nullptr, &blockPipelineLayout) != VK_SUCCESS) {
        LOGE("Failed to create block pipeline layout");
        return false;
    }

    pipelineLayoutInfo.pSetLayouts = &uiDescriptorSetLayout;
    if (vkCreatePipelineLayout(device, &pipelineLayoutInfo, nullptr, &uiPipelineLayout) != VK_SUCCESS) {
        LOGE("Failed to create UI pipeline layout");
        return false;
    }

    // Helper lambda to create pipeline
    auto createPipeline = [&](VkShaderModule vert, VkShaderModule frag, VkPipelineLayout layout,
                              const VkVertexInputBindingDescription& binding,
                              const std::vector<VkVertexInputAttributeDescription>& attribs,
                              VkPipeline& pipeline) -> bool {
        VkPipelineShaderStageCreateInfo vertStage{};
        vertStage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        vertStage.stage = VK_SHADER_STAGE_VERTEX_BIT;
        vertStage.module = vert;
        vertStage.pName = "main";

        VkPipelineShaderStageCreateInfo fragStage{};
        fragStage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        fragStage.stage = VK_SHADER_STAGE_FRAGMENT_BIT;
        fragStage.module = frag;
        fragStage.pName = "main";

        VkPipelineShaderStageCreateInfo stages[] = {vertStage, fragStage};

        VkPipelineVertexInputStateCreateInfo vertexInput{};
        vertexInput.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
        vertexInput.vertexBindingDescriptionCount = 1;
        vertexInput.pVertexBindingDescriptions = &binding;
        vertexInput.vertexAttributeDescriptionCount = static_cast<uint32_t>(attribs.size());
        vertexInput.pVertexAttributeDescriptions = attribs.data();

        VkPipelineInputAssemblyStateCreateInfo inputAssembly{};
        inputAssembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
        inputAssembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
        inputAssembly.primitiveRestartEnable = VK_FALSE;

        VkViewport viewport{};
        viewport.x = 0.0f;
        viewport.y = 0.0f;
        viewport.width = static_cast<float>(ctx.getSwapchainExtent().width);
        viewport.height = static_cast<float>(ctx.getSwapchainExtent().height);
        viewport.minDepth = 0.0f;
        viewport.maxDepth = 1.0f;

        VkRect2D scissor{};
        scissor.offset = {0,0};
        scissor.extent = ctx.getSwapchainExtent();

        VkPipelineViewportStateCreateInfo viewportState{};
        viewportState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
        viewportState.viewportCount = 1;
        viewportState.pViewports = &viewport;
        viewportState.scissorCount = 1;
        viewportState.pScissors = &scissor;

        VkPipelineRasterizationStateCreateInfo rasterizer{};
        rasterizer.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
        rasterizer.depthClampEnable = VK_FALSE;
        rasterizer.rasterizerDiscardEnable = VK_FALSE;
        rasterizer.polygonMode = VK_POLYGON_MODE_FILL;
        rasterizer.lineWidth = 1.0f;
        rasterizer.cullMode = VK_CULL_MODE_BACK_BIT;
        rasterizer.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;
        rasterizer.depthBiasEnable = VK_FALSE;

        VkPipelineMultisampleStateCreateInfo multisampling{};
        multisampling.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
        multisampling.sampleShadingEnable = VK_FALSE;
        multisampling.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

        VkPipelineColorBlendAttachmentState colorBlendAttachment{};
        colorBlendAttachment.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
        colorBlendAttachment.blendEnable = VK_TRUE;
        colorBlendAttachment.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA;
        colorBlendAttachment.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
        colorBlendAttachment.colorBlendOp = VK_BLEND_OP_ADD;
        colorBlendAttachment.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
        colorBlendAttachment.dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO;
        colorBlendAttachment.alphaBlendOp = VK_BLEND_OP_ADD;

        VkPipelineColorBlendStateCreateInfo colorBlending{};
        colorBlending.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
        colorBlending.logicOpEnable = VK_FALSE;
        colorBlending.attachmentCount = 1;
        colorBlending.pAttachments = &colorBlendAttachment;

        VkPipelineDepthStencilStateCreateInfo depthStencil{};
        depthStencil.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
        depthStencil.depthTestEnable = VK_TRUE;
        depthStencil.depthWriteEnable = VK_TRUE;
        depthStencil.depthCompareOp = VK_COMPARE_OP_LESS;
        depthStencil.depthBoundsTestEnable = VK_FALSE;
        depthStencil.stencilTestEnable = VK_FALSE;

        VkGraphicsPipelineCreateInfo pipelineInfo{};
        pipelineInfo.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
        pipelineInfo.stageCount = 2;
        pipelineInfo.pStages = stages;
        pipelineInfo.pVertexInputState = &vertexInput;
        pipelineInfo.pInputAssemblyState = &inputAssembly;
        pipelineInfo.pViewportState = &viewportState;
        pipelineInfo.pRasterizationState = &rasterizer;
        pipelineInfo.pMultisampleState = &multisampling;
        pipelineInfo.pDepthStencilState = &depthStencil;
        pipelineInfo.pColorBlendState = &colorBlending;
        pipelineInfo.layout = layout;
        pipelineInfo.renderPass = ctx.getRenderPass();
        pipelineInfo.subpass = 0;
        pipelineInfo.basePipelineHandle = VK_NULL_HANDLE;

        if (vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &pipeline) != VK_SUCCESS) {
            LOGE("Failed to create graphics pipeline");
            return false;
        }
        return true;
    };

    // Block pipeline: use SimpleVertex layout (pos + color) for now, but our mesh has more attributes
    // We'll use SimpleVertex for block rendering to match triangle shader (pos+color)
    auto simpleBinding = SimpleVertex::getBindingDescription();
    auto simpleAttribs = SimpleVertex::getAttributeDescriptions();

    if (!createPipeline(vertBlockModule, fragBlockModule, blockPipelineLayout, simpleBinding, simpleAttribs, blockPipeline)) {
        LOGE("Failed to create block pipeline");
        return false;
    }

    // UI pipeline: uses its own vertex format (pos, uv, color?) but uioverlay shader expects pos, uv, color
    // For simplicity, use same SimpleVertex for UI as well (will be adapted)
    // Actually uioverlay shader expects different layout, but we try with SimpleVertex for now
    auto uiBinding = SimpleVertex::getBindingDescription();
    auto uiAttribs = SimpleVertex::getAttributeDescriptions();

    // For UI, disable depth test
    // We'll create UI pipeline with depth test disabled via custom lambda, but for simplicity reuse same
    // Actually createPipeline uses depth test enabled, we need UI without depth test
    // We'll create UI pipeline manually with depthTest disabled
    {
        VkPipelineShaderStageCreateInfo vertStage{};
        vertStage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        vertStage.stage = VK_SHADER_STAGE_VERTEX_BIT;
        vertStage.module = vertUIModule;
        vertStage.pName = "main";

        VkPipelineShaderStageCreateInfo fragStage{};
        fragStage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        fragStage.stage = VK_SHADER_STAGE_FRAGMENT_BIT;
        fragStage.module = fragUIModule;
        fragStage.pName = "main";

        VkPipelineShaderStageCreateInfo stages[] = {vertStage, fragStage};

        VkPipelineVertexInputStateCreateInfo vertexInput{};
        vertexInput.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
        vertexInput.vertexBindingDescriptionCount = 1;
        vertexInput.pVertexBindingDescriptions = &uiBinding;
        vertexInput.vertexAttributeDescriptionCount = static_cast<uint32_t>(uiAttribs.size());
        vertexInput.pVertexAttributeDescriptions = uiAttribs.data();

        VkPipelineInputAssemblyStateCreateInfo inputAssembly{};
        inputAssembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
        inputAssembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
        inputAssembly.primitiveRestartEnable = VK_FALSE;

        VkViewport viewport{};
        viewport.x = 0.0f;
        viewport.y = 0.0f;
        viewport.width = static_cast<float>(ctx.getSwapchainExtent().width);
        viewport.height = static_cast<float>(ctx.getSwapchainExtent().height);
        viewport.minDepth = 0.0f;
        viewport.maxDepth = 1.0f;

        VkRect2D scissor{};
        scissor.offset = {0,0};
        scissor.extent = ctx.getSwapchainExtent();

        VkPipelineViewportStateCreateInfo viewportState{};
        viewportState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
        viewportState.viewportCount = 1;
        viewportState.pViewports = &viewport;
        viewportState.scissorCount = 1;
        viewportState.pScissors = &scissor;

        VkPipelineRasterizationStateCreateInfo rasterizer{};
        rasterizer.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
        rasterizer.depthClampEnable = VK_FALSE;
        rasterizer.rasterizerDiscardEnable = VK_FALSE;
        rasterizer.polygonMode = VK_POLYGON_MODE_FILL;
        rasterizer.lineWidth = 1.0f;
        rasterizer.cullMode = VK_CULL_MODE_NONE;
        rasterizer.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;

        VkPipelineMultisampleStateCreateInfo multisampling{};
        multisampling.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
        multisampling.sampleShadingEnable = VK_FALSE;
        multisampling.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

        VkPipelineColorBlendAttachmentState colorBlendAttachment{};
        colorBlendAttachment.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
        colorBlendAttachment.blendEnable = VK_TRUE;
        colorBlendAttachment.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA;
        colorBlendAttachment.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
        colorBlendAttachment.colorBlendOp = VK_BLEND_OP_ADD;
        colorBlendAttachment.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
        colorBlendAttachment.dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO;
        colorBlendAttachment.alphaBlendOp = VK_BLEND_OP_ADD;

        VkPipelineColorBlendStateCreateInfo colorBlending{};
        colorBlending.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
        colorBlending.logicOpEnable = VK_FALSE;
        colorBlending.attachmentCount = 1;
        colorBlending.pAttachments = &colorBlendAttachment;

        VkPipelineDepthStencilStateCreateInfo depthStencil{};
        depthStencil.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
        depthStencil.depthTestEnable = VK_FALSE;
        depthStencil.depthWriteEnable = VK_FALSE;
        depthStencil.depthCompareOp = VK_COMPARE_OP_ALWAYS;

        VkGraphicsPipelineCreateInfo pipelineInfo{};
        pipelineInfo.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
        pipelineInfo.stageCount = 2;
        pipelineInfo.pStages = stages;
        pipelineInfo.pVertexInputState = &vertexInput;
        pipelineInfo.pInputAssemblyState = &inputAssembly;
        pipelineInfo.pViewportState = &viewportState;
        pipelineInfo.pRasterizationState = &rasterizer;
        pipelineInfo.pMultisampleState = &multisampling;
        pipelineInfo.pDepthStencilState = &depthStencil;
        pipelineInfo.pColorBlendState = &colorBlending;
        pipelineInfo.layout = uiPipelineLayout;
        pipelineInfo.renderPass = ctx.getRenderPass();
        pipelineInfo.subpass = 0;

        if (vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &uiPipeline) != VK_SUCCESS) {
            LOGE("Failed to create UI pipeline");
            return false;
        }
    }

    vkDestroyShaderModule(device, vertBlockModule, nullptr);
    vkDestroyShaderModule(device, fragBlockModule, nullptr);
    vkDestroyShaderModule(device, vertUIModule, nullptr);
    vkDestroyShaderModule(device, fragUIModule, nullptr);

    LOGI("Pipelines created");
    return true;
}

bool AndroidRenderer::createUniformBuffers() {
    auto& ctx = VulkanContext::get();
    VkDevice device = ctx.getDevice();
    VkDeviceSize blockSize = sizeof(BlockUBO);
    VkDeviceSize uiSize = sizeof(UIUBO);

    size_t swapchainImages = ctx.getImageViews().size();
    // Use MAX_FRAMES_IN_FLIGHT for uniform buffers
    size_t count = 2; // MAX_FRAMES_IN_FLIGHT

    blockUniformBuffers.resize(count);
    blockUniformMemories.resize(count);
    blockUniformMapped.resize(count);

    uiUniformBuffers.resize(count);
    uiUniformMemories.resize(count);
    uiUniformMapped.resize(count);

    for (size_t i = 0; i < count; i++) {
        if (ctx.createBuffer(blockSize, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, blockUniformBuffers[i], blockUniformMemories[i]) != VK_SUCCESS) {
            LOGE("Failed to create block uniform buffer %zu", i);
            return false;
        }
        vkMapMemory(device, blockUniformMemories[i], 0, blockSize, 0, &blockUniformMapped[i]);

        if (ctx.createBuffer(uiSize, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, uiUniformBuffers[i], uiUniformMemories[i]) != VK_SUCCESS) {
            LOGE("Failed to create UI uniform buffer %zu", i);
            return false;
        }
        vkMapMemory(device, uiUniformMemories[i], 0, uiSize, 0, &uiUniformMapped[i]);
    }

    LOGI("Uniform buffers created");
    return true;
}

bool AndroidRenderer::createDescriptorPool() {
    auto& ctx = VulkanContext::get();
    VkDevice device = ctx.getDevice();

    std::array<VkDescriptorPoolSize, 1> poolSizes{};
    poolSizes[0].type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    poolSizes[0].descriptorCount = 4; // 2 frames * 2 sets

    VkDescriptorPoolCreateInfo poolInfo{};
    poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    poolInfo.poolSizeCount = static_cast<uint32_t>(poolSizes.size());
    poolInfo.pPoolSizes = poolSizes.data();
    poolInfo.maxSets = 4;

    if (vkCreateDescriptorPool(device, &poolInfo, nullptr, &descriptorPool) != VK_SUCCESS) {
        LOGE("Failed to create descriptor pool");
        return false;
    }
    LOGI("Descriptor pool created");
    return true;
}

bool AndroidRenderer::createDescriptorSets() {
    auto& ctx = VulkanContext::get();
    VkDevice device = ctx.getDevice();

    size_t count = 2;
    blockDescriptorSets.resize(count);
    uiDescriptorSets.resize(count);

    for (size_t i = 0; i < count; i++) {
        VkDescriptorSetLayout layouts[] = {blockDescriptorSetLayout};
        VkDescriptorSetAllocateInfo allocInfo{};
        allocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        allocInfo.descriptorPool = descriptorPool;
        allocInfo.descriptorSetCount = 1;
        allocInfo.pSetLayouts = layouts;

        if (vkAllocateDescriptorSets(device, &allocInfo, &blockDescriptorSets[i]) != VK_SUCCESS) {
            LOGE("Failed to allocate block descriptor set %zu", i);
            return false;
        }

        VkDescriptorBufferInfo bufferInfo{};
        bufferInfo.buffer = blockUniformBuffers[i];
        bufferInfo.offset = 0;
        bufferInfo.range = sizeof(BlockUBO);

        VkWriteDescriptorSet descriptorWrite{};
        descriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        descriptorWrite.dstSet = blockDescriptorSets[i];
        descriptorWrite.dstBinding = 0;
        descriptorWrite.dstArrayElement = 0;
        descriptorWrite.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        descriptorWrite.descriptorCount = 1;
        descriptorWrite.pBufferInfo = &bufferInfo;

        vkUpdateDescriptorSets(device, 1, &descriptorWrite, 0, nullptr);
    }

    for (size_t i = 0; i < count; i++) {
        VkDescriptorSetLayout layouts[] = {uiDescriptorSetLayout};
        VkDescriptorSetAllocateInfo allocInfo{};
        allocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        allocInfo.descriptorPool = descriptorPool;
        allocInfo.descriptorSetCount = 1;
        allocInfo.pSetLayouts = layouts;

        if (vkAllocateDescriptorSets(device, &allocInfo, &uiDescriptorSets[i]) != VK_SUCCESS) {
            LOGE("Failed to allocate UI descriptor set %zu", i);
            return false;
        }

        VkDescriptorBufferInfo bufferInfo{};
        bufferInfo.buffer = uiUniformBuffers[i];
        bufferInfo.offset = 0;
        bufferInfo.range = sizeof(UIUBO);

        VkWriteDescriptorSet descriptorWrite{};
        descriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        descriptorWrite.dstSet = uiDescriptorSets[i];
        descriptorWrite.dstBinding = 0;
        descriptorWrite.dstArrayElement = 0;
        descriptorWrite.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        descriptorWrite.descriptorCount = 1;
        descriptorWrite.pBufferInfo = &bufferInfo;

        vkUpdateDescriptorSets(device, 1, &descriptorWrite, 0, nullptr);
    }

    LOGI("Descriptor sets created");
    return true;
}

bool AndroidRenderer::createUIMesh() {
    // Create a simple quad for UI rendering (full screen quad)
    std::vector<SimpleVertex> vertices = {
        {{-1.0f, -1.0f, 0.0f}, {1.0f, 1.0f, 1.0f}},
        {{ 1.0f, -1.0f, 0.0f}, {1.0f, 1.0f, 1.0f}},
        {{ 1.0f,  1.0f, 0.0f}, {1.0f, 1.0f, 1.0f}},
        {{-1.0f,  1.0f, 0.0f}, {1.0f, 1.0f, 1.0f}}
    };
    std::vector<uint32_t> indices = {0,1,2, 2,3,0};
    uiQuadMesh = std::make_unique<VulkanMesh>();
    uiQuadMesh->setSimpleData(vertices, indices);
    return true;
}

void AndroidRenderer::updateBlockUBO(uint32_t currentImage, const glm::mat4& proj, const glm::mat4& view, const glm::mat4& model) {
    BlockUBO ubo{};
    ubo.projectionMatrix = proj;
    ubo.viewMatrix = view;
    ubo.modelMatrix = model;
    // Vulkan clip space has inverted Y and half Z
    ubo.projectionMatrix[1][1] *= -1;
    memcpy(blockUniformMapped[currentImage], &ubo, sizeof(ubo));
}

void AndroidRenderer::updateUIUBO(uint32_t currentImage, const glm::mat4& proj) {
    UIUBO ubo{};
    ubo.projection = proj;
    memcpy(uiUniformMapped[currentImage], &ubo, sizeof(ubo));
}

void AndroidRenderer::setViewport(int w, int h) {
    screenWidth = w;
    screenHeight = h;
}

void AndroidRenderer::beginFrame() {
    auto& ctx = VulkanContext::get();
    if (!ctx.beginFrame()) {
        LOGE("beginFrame failed");
    }
}

void AndroidRenderer::endFrame() {
    auto& ctx = VulkanContext::get();
    if (!ctx.endFrame()) {
        LOGE("endFrame failed");
    }
}

void AndroidRenderer::renderWorld(World& world, const Camera& camera) {
    auto& ctx = VulkanContext::get();
    VkCommandBuffer cmd = ctx.getCurrentCommandBuffer();
    uint32_t currentFrame = ctx.getCurrentFrame();

    // Update UBO with camera matrices
    glm::mat4 view = camera.getViewMatrix();
    glm::mat4 proj = camera.getProjectionMatrix();
    // For Vulkan, we already handle Y inversion in updateBlockUBO

    // Bind block pipeline
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, blockPipeline);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, blockPipelineLayout, 0, 1, &blockDescriptorSets[currentFrame], 0, nullptr);

    auto chunks = world.getLoadedChunks();
    for (auto* chunk : chunks) {
        if (!chunk) continue;
        const auto& meshData = chunk->getMesh();
        if (!meshData.hasData) continue;

        auto it = chunkMeshes.find(chunk);
        if (it == chunkMeshes.end() || chunk->isDirty()) {
            auto mesh = std::make_unique<VulkanMesh>();
            // Convert meshData.vertices (11 floats) to SimpleVertex (pos+color) for our simple shader
            std::vector<SimpleVertex> simpleVerts;
            size_t vertCount = meshData.vertices.size() / 11;
            simpleVerts.reserve(vertCount);
            for (size_t i = 0; i < vertCount; i++) {
                size_t base = i * 11;
                SimpleVertex v;
                v.pos = glm::vec3(meshData.vertices[base+0], meshData.vertices[base+1], meshData.vertices[base+2]);
                v.color = glm::vec3(meshData.vertices[base+8], meshData.vertices[base+9], meshData.vertices[base+10]);
                simpleVerts.push_back(v);
            }
            mesh->setSimpleData(simpleVerts, meshData.indices);
            chunkMeshes[chunk] = std::move(mesh);
        }

        auto& mesh = chunkMeshes[chunk];
        if (mesh && mesh->isValid()) {
            glm::mat4 model = glm::translate(glm::mat4(1.0f), glm::vec3(chunk->getX()*16, 0, chunk->getZ()*16));
            updateBlockUBO(currentFrame, proj, view, model);
            mesh->bind(cmd);
            mesh->draw(cmd);
        }
    }

    // For UI, we would render HUD here with uiPipeline, but for now we just clear
    // The actual UI rendering from MainMenu etc uses old GL code, so we skip for Vulkan minimal
}

}
