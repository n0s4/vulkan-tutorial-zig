const CommandPool = @This();

const std = @import("std");
const c = @import("c.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");

const Allocator = std.mem.Allocator;

handle: c.VkCommandPool,
buffers: []c.VkCommandBuffer,

pub fn create(
    device: c.VkDevice,
    queue_families: PhysicalDevice.QueueFamilyIndices,
    buffer_count: u32,
    allocator: Allocator,
) !CommandPool {
    const create_info = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = queue_families.graphics_index,
    };

    var command_pool: c.VkCommandPool = undefined;
    if (c.vkCreateCommandPool(device, &create_info, null, &command_pool) != c.VK_SUCCESS) {
        return error.VKCreateCommandPoolFailed;
    }

    const alloc_info = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = buffer_count,
    };

    const buffers = try allocator.alloc(c.VkCommandBuffer, buffer_count);

    if (c.vkAllocateCommandBuffers(device, &alloc_info, buffers.ptr) != c.VK_SUCCESS) {
        return error.VKAllocateCommandBuffersFailed;
    }

    return CommandPool{
        .handle = command_pool,
        .buffers = buffers,
    };
}

pub fn destroy(command_pool: CommandPool, device: c.VkDevice, allocator: std.mem.Allocator) void {
    c.vkDestroyCommandPool(device, command_pool.handle, null);
    allocator.free(command_pool.buffers);
}
