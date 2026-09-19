#pragma once
#include <vulkan/vulkan.h>
#include <android/native_window.h>
#include <android/log.h>
#include <vector>
#include <optional>
#include <string>

#define LOGI(...) ((void)__android_log_print(ANDROID_LOG_INFO, "Eaglercraft-VK", __VA_ARGS__))
#define LOGE(...) ((void)__android_log_print(ANDROID_LOG_ERROR, "Eaglercraft-VK", __VA_ARGS__))

namespace Eaglercraft {

struct QueueFamilyIndices {
    std::optional<uint32_t> graphicsFamily;
    std::optional<uint32_t> presentFamily;
    bool isComplete() const { return graphicsFamily.has_value() && presentFamily.has_value(); }
};

struct SwapChainSupportDetails {
    VkSurfaceCapabilitiesKHR capabilities{};
    std::vector<VkSurfaceFormatKHR> formats;
    std::vector<VkPresentModeKHR> presentModes;
};

class VulkanContext {
public:
    static VulkanContext& get() {
        static VulkanContext instance;
        return instance;
    }

    bool init(ANativeWindow* window);
    void cleanup();
    void cleanupSwapchain();

    bool recreateSwapchain();
    bool createFramebuffers();

    VkInstance getInstance() const { return instance; }
    VkPhysicalDevice getPhysicalDevice() const { return physicalDevice; }
    VkDevice getDevice() const { return device; }
    VkQueue getGraphicsQueue() const { return graphicsQueue; }
    VkQueue getPresentQueue() const { return presentQueue; }
    VkSurfaceKHR getSurface() const { return surface; }
    VkSwapchainKHR getSwapchain() const { return swapChain; }
    VkRenderPass getRenderPass() const { return renderPass; }
    VkExtent2D getSwapchainExtent() const { return swapChainExtent; }
    VkFormat getSwapchainImageFormat() const { return swapChainImageFormat; }
    const std::vector<VkFramebuffer>& getFramebuffers() const { return swapChainFramebuffers; }
    const std::vector<VkImageView>& getImageViews() const { return swapChainImageViews; }
    VkCommandPool getCommandPool() const { return commandPool; }
    VkCommandBuffer getCurrentCommandBuffer() const { return commandBuffers[currentFrame]; }
    uint32_t getCurrentImageIndex() const { return currentImageIndex; }
    uint32_t getCurrentFrame() const { return currentFrame; }
    VkDeviceSize getMinUniformBufferOffsetAlignment() const { return minUboAlignment; }

    bool beginFrame();
    bool endFrame();

    VkResult createBuffer(VkDeviceSize size, VkBufferUsageFlags usage, VkMemoryPropertyFlags properties, VkBuffer& buffer, VkDeviceMemory& bufferMemory);
    uint32_t findMemoryType(uint32_t typeFilter, VkMemoryPropertyFlags properties);
    void copyBuffer(VkBuffer src, VkBuffer dst, VkDeviceSize size);

    bool isInitialized() const { return initialized; }

private:
    VulkanContext() = default;
    ~VulkanContext() { cleanup(); }

    bool createInstance();
    bool createSurface(ANativeWindow* window);
    bool pickPhysicalDevice();
    bool createLogicalDevice();
    bool createSwapchain();
    bool createImageViews();
    bool createRenderPass();
    bool createCommandPool();
    bool createCommandBuffers();
    bool createSyncObjects();
    bool isDeviceSuitable(VkPhysicalDevice device);
    QueueFamilyIndices findQueueFamilies(VkPhysicalDevice device);
    SwapChainSupportDetails querySwapChainSupport(VkPhysicalDevice device);
    VkSurfaceFormatKHR chooseSwapSurfaceFormat(const std::vector<VkSurfaceFormatKHR>& availableFormats);
    VkPresentModeKHR chooseSwapPresentMode(const std::vector<VkPresentModeKHR>& availablePresentModes);
    VkExtent2D chooseSwapExtent(const VkSurfaceCapabilitiesKHR& capabilities);

    // Members
    bool initialized = false;
    ANativeWindow* nativeWindow = nullptr;

    VkInstance instance = VK_NULL_HANDLE;
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue graphicsQueue = VK_NULL_HANDLE;
    VkQueue presentQueue = VK_NULL_HANDLE;

    VkSwapchainKHR swapChain = VK_NULL_HANDLE;
    std::vector<VkImage> swapChainImages;
    VkFormat swapChainImageFormat = VK_FORMAT_UNDEFINED;
    VkExtent2D swapChainExtent{};
    std::vector<VkImageView> swapChainImageViews;
    std::vector<VkFramebuffer> swapChainFramebuffers;

    VkRenderPass renderPass = VK_NULL_HANDLE;
    VkCommandPool commandPool = VK_NULL_HANDLE;
    std::vector<VkCommandBuffer> commandBuffers;

    std::vector<VkSemaphore> imageAvailableSemaphores;
    std::vector<VkSemaphore> renderFinishedSemaphores;
    std::vector<VkFence> inFlightFences;

    uint32_t currentFrame = 0;
    uint32_t currentImageIndex = 0;
    static const int MAX_FRAMES_IN_FLIGHT = 2;

    VkDeviceSize minUboAlignment = 256;

    const std::vector<const char*> deviceExtensions = {
        VK_KHR_SWAPCHAIN_EXTENSION_NAME
    };
};

}
