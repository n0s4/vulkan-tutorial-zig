const Image = @This();

const std = @import("std");
const c = @import("c.zig");

const PhysicalDevice = @import("PhysicalDevice.zig");

handle: c.VkImage,
memory: c.VkDeviceMemory,

pub fn create(
    width: u32,
    height: u32,
    format: c.VkFormat,
    tiling: c.VkImageTiling,
    usage: c.VkImageUsageFlags,
    properties: c.VkMemoryPropertyFlags,
    device: c.VkDevice,
    device_mem_props: c.VkPhysicalDeviceMemoryProperties,
) !Image {
    const image_info = c.VkImageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .extent = c.VkExtent3D{
            .width = width,
            .height = height,
            .depth = 1,
        },
        .mipLevels = 1,
        .arrayLayers = 1,
        .format = format,
        .tiling = tiling,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .usage = usage,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
    };

    var image: c.VkImage = undefined;
    if (c.vkCreateImage(device, &image_info, null, &image) != c.VK_SUCCESS) {
        return error.VKCreateImageFailed;
    }

    var mem_requirements: c.VkMemoryRequirements = undefined;
    c.vkGetImageMemoryRequirements(device, image, &mem_requirements);

    const alloc_info = c.VkMemoryAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = mem_requirements.size,
        .memoryTypeIndex = PhysicalDevice.findMemoryType(device_mem_props, mem_requirements.memoryTypeBits, properties) orelse {
            return error.NoSuitableMemoryType;
        },
    };

    var memory: c.VkDeviceMemory = undefined;
    if (c.vkAllocateMemory(device, &alloc_info, null, &memory) != c.VK_SUCCESS) {
        return error.VKAllocateMemoryFailed;
    }

    _ = c.vkBindImageMemory(device, image, memory, 0);

    return Image{
        .handle = image,
        .memory = memory,
    };
}

pub fn destroy(image: Image, device: c.VkDevice) void {
    c.vkDestroyImage(device, image.handle, null);
    c.vkFreeMemory(device, image.memory, null);
}
