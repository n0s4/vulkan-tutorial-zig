const Buffer = @This();

const std = @import("std");
const c = @import("c.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");

handle: c.VkBuffer,
memory: c.VkDeviceMemory,

pub fn createOnDevice(
    T: type,
    data: []const T,
    usage: c.VkBufferUsageFlags,
    device_properties: c.VkPhysicalDeviceMemoryProperties,
    device: c.VkDevice,
    queue: c.VkQueue,
    command_pool: c.VkCommandPool,
) !Buffer {
    const size: c.VkDeviceSize = @sizeOf(T) * data.len;
    const staging_buffer = try create(
        size,
        c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        device,
        device_properties,
    );
    defer staging_buffer.destroy(device);

    var mapped_mem: [*]T = undefined;
    _ = c.vkMapMemory(device, staging_buffer.memory, 0, size, 0, @ptrCast(&mapped_mem));
    @memcpy(mapped_mem, data);

    const buffer = try create(
        size,
        usage | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        device,
        device_properties,
    );

    copy(staging_buffer.handle, buffer.handle, size, device, queue, command_pool);

    return buffer;
}

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
        .memoryTypeIndex = findMemoryType(device_properties, mem_requirements.memoryTypeBits, properties) orelse {
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

fn findMemoryType(
    device_properties: c.VkPhysicalDeviceMemoryProperties,
    type_filter: u32,
    properties: c.VkMemoryPropertyFlags,
) ?u32 {
    for (device_properties.memoryTypes[0..device_properties.memoryTypeCount], 0..) |mem_type, i| {
        if (((type_filter & (@as(u32, 1) << @intCast(i))) != 0) and
            (mem_type.propertyFlags & properties) == properties)
        {
            return @intCast(i);
        }
    }
    return null;
}

fn copy(
    src: c.VkBuffer,
    dst: c.VkBuffer,
    size: c.VkDeviceSize,
    device: c.VkDevice,
    queue: c.VkQueue,
    command_pool: c.VkCommandPool,
) void {
    const alloc_info = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };

    var command_buffer: c.VkCommandBuffer = undefined;
    _ = c.vkAllocateCommandBuffers(device, &alloc_info, &command_buffer);
    defer c.vkFreeCommandBuffers(device, command_pool, 1, &command_buffer);

    const begin_info = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };

    _ = c.vkBeginCommandBuffer(command_buffer, &begin_info);

    const copy_region = c.VkBufferCopy{
        .size = size,
        .srcOffset = 0,
        .dstOffset = 0,
    };

    c.vkCmdCopyBuffer(command_buffer, src, dst, 1, &copy_region);

    _ = c.vkEndCommandBuffer(command_buffer);

    const submit_info = c.VkSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &command_buffer,
    };

    _ = c.vkQueueSubmit(queue, 1, &submit_info, @ptrCast(c.VK_NULL_HANDLE));
    _ = c.vkQueueWaitIdle(queue);
}

pub fn destroy(buffer: Buffer, device: c.VkDevice) void {
    c.vkDestroyBuffer(device, buffer.handle, null);
    c.vkFreeMemory(device, buffer.memory, null);
}
