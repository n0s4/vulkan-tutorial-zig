const PhysicalDevice = @This();

const std = @import("std");
const c = @import("c.zig");

const Allocator = std.mem.Allocator;

handle: c.VkPhysicalDevice,

// TODO: extract short-lived metadata into separate struct.
queue_families: QueueFamilyIndices,
swapchain_support: SwapChainSupport,
mem_props: c.VkPhysicalDeviceMemoryProperties,
properties: c.VkPhysicalDeviceProperties,

pub const QueueFamilyIndices = struct {
    graphics_index: u32,
    present_index: u32,
};

pub const SwapChainSupport = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR,
    formats: []c.VkSurfaceFormatKHR,
    present_modes: []c.VkPresentModeKHR,

    pub fn deinit(details: *const SwapChainSupport, allocator: Allocator) void {
        allocator.free(details.formats);
        allocator.free(details.present_modes);
    }
};

pub fn selectAndCreate(
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,
    extensions: []const [*:0]const u8,
    allocator: Allocator,
) !PhysicalDevice {
    var device_count: u32 = 0;
    _ = c.vkEnumeratePhysicalDevices(instance, &device_count, null);

    if (device_count == 0) {
        return error.NoVulkanSupportedGPUs;
    }

    const devices = try allocator.alloc(c.VkPhysicalDevice, device_count);
    defer allocator.free(devices);
    _ = c.vkEnumeratePhysicalDevices(instance, &device_count, devices.ptr);

    for (devices) |device| {
        if (try hasDeviceExtensionSupport(device, extensions, allocator) == false) continue;

        const swapchain_support = try querySwapChainSupport(device, surface, allocator);
        if (swapchain_support.formats.len == 0 or swapchain_support.present_modes.len == 0) continue;

        const indices = try findQueueFamilies(device, surface, allocator) orelse continue;

        var features: c.VkPhysicalDeviceFeatures = undefined;
        c.vkGetPhysicalDeviceFeatures(device, &features);
        if (features.samplerAnisotropy == c.VK_FALSE) continue;

        var mem_props: c.VkPhysicalDeviceMemoryProperties = undefined;
        c.vkGetPhysicalDeviceMemoryProperties(device, &mem_props);

        var properties: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(device, &properties);

        return PhysicalDevice{
            .handle = device,
            .queue_families = indices,
            .swapchain_support = swapchain_support,
            .properties = properties,
            .mem_props = mem_props,
        };
    }

    return error.NoSuitableGPUs;
}

pub fn findMemoryType(
    mem_props: c.VkPhysicalDeviceMemoryProperties,
    type_filter: u32,
    properties: c.VkMemoryPropertyFlags,
) ?u32 {
    for (mem_props.memoryTypes[0..mem_props.memoryTypeCount], 0..) |mem_type, i| {
        if (((type_filter & (@as(u32, 1) << @intCast(i))) != 0) and
            (mem_type.propertyFlags & properties) == properties)
        {
            return @intCast(i);
        }
    }
    return null;
}

pub fn findSupportedFormat(
    device: c.VkPhysicalDevice,
    candidates: []const c.VkFormat,
    tiling: c.VkImageTiling,
    features: c.VkFormatFeatureFlags,
) ?c.VkFormat {
    for (candidates) |format| {
        var props: c.VkFormatProperties = undefined;
        c.vkGetPhysicalDeviceFormatProperties(device, format, &props);
        if (tiling == c.VK_IMAGE_TILING_LINEAR and props.linearTilingFeatures & features == features or
            tiling == c.VK_IMAGE_TILING_OPTIMAL and props.optimalTilingFeatures & features == features)
        {
            return format;
        }
    }

    return null;
}

pub fn deinit(device: PhysicalDevice, allocator: Allocator) void {
    device.swapchain_support.deinit(allocator);
}

const QueueFamilySearch = struct {
    graphics_index: ?u32,
    present_index: ?u32,

    pub fn complete(search: QueueFamilySearch) ?QueueFamilyIndices {
        return QueueFamilyIndices{
            .graphics_index = search.graphics_index orelse return null,
            .present_index = search.present_index orelse return null,
        };
    }
};

/// Return null if one or more of the queue families are unsupported.
fn findQueueFamilies(device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, allocator: Allocator) !?QueueFamilyIndices {
    var search: QueueFamilySearch = undefined;

    var queue_family_count: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);

    const queue_families = try allocator.alloc(c.VkQueueFamilyProperties, queue_family_count);
    defer allocator.free(queue_families);
    c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

    for (queue_families, 0..) |family, i| {
        if (family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
            search.graphics_index = @intCast(i);
        }

        var present_support: c.VkBool32 = c.VK_FALSE;
        _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), surface, &present_support);
        if (present_support == c.VK_TRUE) {
            search.present_index = @intCast(i);
        }

        if (search.complete()) |indices| {
            return indices;
        }
    }

    return null;
}

fn hasDeviceExtensionSupport(
    device: c.VkPhysicalDevice,
    extensions: []const [*:0]const u8,
    allocator: std.mem.Allocator,
) !bool {
    var ext_count: u32 = 0;
    _ = c.vkEnumerateDeviceExtensionProperties(device, null, &ext_count, null);

    const available_extensions = try allocator.alloc(c.VkExtensionProperties, ext_count);
    defer allocator.free(available_extensions);
    _ = c.vkEnumerateDeviceExtensionProperties(device, null, &ext_count, available_extensions.ptr);

    next_extension: for (extensions) |extension_name| {
        for (available_extensions) |available_extension| {
            if (.eq ==
                std.mem.orderZ(u8, @ptrCast(&available_extension.extensionName), extension_name))
            {
                continue :next_extension;
            }
        }

        return false;
    }

    return true;
}

fn querySwapChainSupport(
    device: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
    allocator: Allocator,
) !SwapChainSupport {
    var capabilities = c.VkSurfaceCapabilitiesKHR{};
    _ = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &capabilities);

    var format_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, null);
    const formats = try allocator.alloc(c.VkSurfaceFormatKHR, format_count);
    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, formats.ptr);

    var present_mode_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, null);
    const present_modes = try allocator.alloc(c.VkPresentModeKHR, present_mode_count);
    _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, present_modes.ptr);

    return SwapChainSupport{
        .capabilities = capabilities,
        .formats = formats,
        .present_modes = present_modes,
    };
}
