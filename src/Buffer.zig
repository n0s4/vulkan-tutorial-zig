const Buffer = @This();

const std = @import("std");
const c = @import("c.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");

handle: c.VkBuffer,
memory: c.VkDeviceMemory,

pub fn create(
    size: c.VkDeviceSize,
    usage: c.VkBufferUsageFlags,
    properties: c.VkMemoryPropertyFlags,
    device: c.VkDevice,
    device_properties: c.VkPhysicalDeviceMemoryProperties,
) !Buffer {
    const buffer_info = c.VkBufferCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = usage,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
    };

    var buffer: c.VkBuffer = undefined;
    if (c.vkCreateBuffer(device, &buffer_info, null, &buffer) != c.VK_SUCCESS) {
        return error.VKCreateBufferFailed;
    }

    var mem_requirements: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(device, buffer, &mem_requirements);

    const alloc_info = c.VkMemoryAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = mem_requirements.size,
        .memoryTypeIndex = PhysicalDevice.findMemoryType(device_properties, mem_requirements.memoryTypeBits, properties) orelse {
            return error.NoSuitableMemoryType;
        },
    };

    var memory: c.VkDeviceMemory = undefined;
    if (c.vkAllocateMemory(device, &alloc_info, null, &memory) != c.VK_SUCCESS) {
        return error.VKAllocateMemoryFailed;
    }

    _ = c.vkBindBufferMemory(device, buffer, memory, 0);

    return Buffer{
        .handle = buffer,
        .memory = memory,
    };
}

pub fn destroy(buffer: Buffer, device: c.VkDevice) void {
    c.vkDestroyBuffer(device, buffer.handle, null);
    c.vkFreeMemory(device, buffer.memory, null);
}
