#pragma once
#include <vulkan/vulkan.h>
#include <vector>
#include <string>
#include <cstdint>

namespace Eaglercraft {

class VulkanShader {
public:
    VulkanShader() = default;
    ~VulkanShader();

    bool loadFromSPV(const uint32_t* code, size_t size);
    bool loadFromSPV(const std::vector<uint32_t>& code);
    bool loadFromFile(const std::string& path); // for future use with assets

    VkShaderModule getModule() const { return module; }
    bool isValid() const { return module != VK_NULL_HANDLE; }

    void destroy();

private:
    VkShaderModule module = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
};

}
