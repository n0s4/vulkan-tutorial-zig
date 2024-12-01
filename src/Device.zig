const Device = @This();

const std = @import("std");
const c = @import("c.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");

const Allocator = std.mem.Allocator;

handle: c.VkDevice,
graphics_queue: c.VkQueue,
present_queue: c.VkQueue,

pub fn create(
    physical_device: PhysicalDevice,
    validation_layers: []const [*:0]const u8,
    extensions: []const [*:0]const u8,
    allocator: Allocator,
) !Device {
    var unique_queue_families = std.ArrayList(u32).init(allocator);
    defer unique_queue_families.deinit();
    for ([_]u32{
        physical_device.queue_families.graphics_index,
        physical_device.queue_families.present_index,
    }) |family| {
        if (std.mem.containsAtLeast(u32, unique_queue_families.items, 1, &.{family}) == false) {
            try unique_queue_families.append(family);
        }
    }

    var queue_create_infos = std.ArrayList(c.VkDeviceQueueCreateInfo).init(allocator);
    defer queue_create_infos.deinit();

    for (unique_queue_families.items) |family| {
        try queue_create_infos.append(c.VkDeviceQueueCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = family,
            .queueCount = 1,
            .pQueuePriorities = &@as(f32, 1),
        });
    }

    const device_features = c.VkPhysicalDeviceFeatures{
        .samplerAnisotropy = c.VK_TRUE,
    };

    const create_info = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = @intCast(queue_create_infos.items.len),
        .pQueueCreateInfos = queue_create_infos.items.ptr,
        .pEnabledFeatures = &device_features,
        .enabledLayerCount = @intCast(validation_layers.len),
        .ppEnabledLayerNames = validation_layers.ptr,
        .enabledExtensionCount = @intCast(extensions.len),
        .ppEnabledExtensionNames = extensions.ptr,
    };

    var device: c.VkDevice = null;
    if (c.vkCreateDevice(physical_device.handle, &create_info, null, &device) != c.VK_SUCCESS) {
        return error.VKCreateDeviceFailed;
    }

    var graphics_queue: c.VkQueue = null;
    c.vkGetDeviceQueue(device, physical_device.queue_families.graphics_index, 0, &graphics_queue);

    var present_queue: c.VkQueue = null;
    c.vkGetDeviceQueue(device, physical_device.queue_families.present_index, 0, &present_queue);

    return Device{
        .handle = device,
        .graphics_queue = graphics_queue,
        .present_queue = present_queue,
    };
}

pub fn destroy(device: Device) void {
    c.vkDestroyDevice(device.handle, null);
}
