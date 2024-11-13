const VertexBuffer = @This();

const std = @import("std");
const c = @import("c.zig");
const Vertex = @import("Vertex.zig");

handle: c.VkBuffer,
memory: c.VkDeviceMemory,

pub fn create(
    size: u64,
    device: c.VkDevice,
    device_mem_properties: c.VkPhysicalDeviceMemoryProperties,
    usage: c.VkBufferUsageFlags,
    properties: c.VkMemoryPropertyFlags,
) !VertexBuffer {
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

    var chosen_memory_type: u32 = 0;
    for (device_mem_properties.memoryTypes[0..device_mem_properties.memoryTypeCount], 0..) |mem_type, i| {
        if (((mem_requirements.memoryTypeBits & (@as(u32, 1) << @intCast(i))) != 0) and
            (mem_type.propertyFlags & properties) == properties)
        {
            chosen_memory_type = @intCast(i);
            break;
        }
    } else {
        return error.NoSuitableMemoryType;
    }

    const alloc_info = c.VkMemoryAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = mem_requirements.size,
        .memoryTypeIndex = chosen_memory_type,
    };

    var memory: c.VkDeviceMemory = undefined;

    if (c.vkAllocateMemory(device, &alloc_info, null, &memory) != c.VK_SUCCESS) {
        return error.VKAllocateMemoryFailed;
    }

    _ = c.vkBindBufferMemory(device, buffer, memory, 0);

    // var data: [*]Vertex = undefined;
    // _ = c.vkMapMemory(device, memory, 0, buffer_info.size, 0, @ptrCast(&data));
    // @memcpy(data, vertices);
    // c.vkUnmapMemory(device, memory);

    return VertexBuffer{
        .handle = buffer,
        .memory = memory,
    };
}

pub fn destroy(buffer: VertexBuffer, device: c.VkDevice) void {
    c.vkDestroyBuffer(device, buffer.handle, null);
    c.vkFreeMemory(device, buffer.memory, null);
}

fn findMemoryType(
    device_properties: c.VkPhysicalDeviceMemoryProperties,
    type_filter: u32,
    required_properties: c.VkMemoryPropertyFlags,
) ?u32 {
    for (0..device_properties.memoryTypeCount) |i| {
        if (((type_filter & (1 << i)) != 0) and
            (device_properties.memoryTypes[i].propertyFlags & required_properties) == required_properties)
        {
            return i;
        }
    }
    return null;
}
