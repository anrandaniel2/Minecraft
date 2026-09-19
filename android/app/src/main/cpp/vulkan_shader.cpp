#include "vulkan_shader.h"
#include "vulkan_context.h"
#include <android/log.h>

#define LOGI(...) ((void)__android_log_print(ANDROID_LOG_INFO, "Eaglercraft-VK", __VA_ARGS__))
#define LOGE(...) ((void)__android_log_print(ANDROID_LOG_ERROR, "Eaglercraft-VK", __VA_ARGS__))

namespace Eaglercraft {

VulkanShader::~VulkanShader() { destroy(); }

void VulkanShader::destroy() {
    if (module != VK_NULL_HANDLE && device != VK_NULL_HANDLE) {
        vkDestroyShaderModule(device, module, nullptr);
        module = VK_NULL_HANDLE;
    }
}

bool VulkanShader::loadFromSPV(const uint32_t* code, size_t size) {
    destroy();
    device = VulkanContext::get().getDevice();
    if (device == VK_NULL_HANDLE) {
        LOGE("Vulkan device not initialized for shader");
        return false;
    }

    VkShaderModuleCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    createInfo.codeSize = size;
    createInfo.pCode = code;

    VkResult res = vkCreateShaderModule(device, &createInfo, nullptr, &module);
    if (res != VK_SUCCESS) {
        LOGE("Failed to create shader module %d size %zu", res, size);
        return false;
    }
    return true;
}

bool VulkanShader::loadFromSPV(const std::vector<uint32_t>& code) {
    return loadFromSPV(code.data(), code.size() * sizeof(uint32_t));
}

bool VulkanShader::loadFromFile(const std::string& path) {
    // TODO: Load from asset manager
    LOGE("loadFromFile not implemented for %s", path.c_str());
    return false;
}

}
