const Instance = @This();

const std = @import("std");
const c = @import("c.zig");
const DebugMessenger = @import("DebugMessenger.zig");

const Allocator = std.mem.Allocator;

handle: c.VkInstance,

pub fn create(
    validation_layers: []const [*:0]const u8,
    allocator: Allocator,
) !Instance {
    try checkValidationLayerSupport(validation_layers, allocator);

    const app_info = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "Vulkan Triangle",
        .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "No Engine",
        .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = c.VK_API_VERSION_1_0,
    };

    const extensions = try getRequiredExtensions(validation_layers.len > 0, allocator);
    defer extensions.deinit();

    const create_info = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = if (validation_layers.len > 0) &DebugMessenger.create_info else null,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = @intCast(extensions.names.len),
        .ppEnabledExtensionNames = extensions.names.ptr,
        .enabledLayerCount = @intCast(validation_layers.len),
        .ppEnabledLayerNames = validation_layers.ptr,
    };

    var instance: c.VkInstance = null;
    if (c.vkCreateInstance(&create_info, null, &instance) != c.VK_SUCCESS) {
        return error.VKCreateInstanceFailed;
    }

    return Instance{ .handle = instance };
}

pub fn destroy(instance: Instance) void {
    c.vkDestroyInstance(instance.handle, null);
}

fn checkValidationLayerSupport(required_layers: []const [*:0]const u8, allocator: Allocator) !void {
    var layer_count: u32 = 0;
    _ = c.vkEnumerateInstanceLayerProperties(&layer_count, null);

    const available_layers = try allocator.alloc(c.VkLayerProperties, layer_count);
    defer allocator.free(available_layers);
    _ = c.vkEnumerateInstanceLayerProperties(&layer_count, available_layers.ptr);

    for (available_layers) |layer| {
        std.log.info(
            "found available layer: {s}",
            .{@as([*:0]const u8, @ptrCast(&layer.layerName))},
        );
    }

    next_layer: for (required_layers) |required_layer| {
        for (available_layers) |available_layer| {
            if (std.mem.orderZ(u8, required_layer, @ptrCast(&available_layer.layerName)) == .eq) {
                continue :next_layer;
            }
        }
        std.log.err("required validation layer not available: {s}", .{required_layer});
        return error.ValidationLayerNotAvailable;
    }
}

const ExtensionList = struct {
    names: [][*:0]const u8,
    allocator: ?Allocator,

    pub fn deinit(exts: ExtensionList) void {
        if (exts.allocator) |allocator| {
            allocator.free(exts.names);
        }
    }
};

fn getRequiredExtensions(validation_layers_enabled: bool, allocator: Allocator) !ExtensionList {
    var glfw_ext_count: u32 = 0;
    const glfw_exts_ptr = c.glfwGetRequiredInstanceExtensions(&glfw_ext_count);
    const glfw_exts: [][*:0]const u8 = @ptrCast(glfw_exts_ptr[0..glfw_ext_count]);

    if (!validation_layers_enabled) {
        return ExtensionList{
            .names = glfw_exts,
            .allocator = null,
        };
    }

    const exts = try allocator.alloc([*:0]const u8, glfw_ext_count + 1);
    std.mem.copyForwards([*:0]const u8, exts, glfw_exts);
    exts[exts.len - 1] = c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME;

    return ExtensionList{
        .names = exts,
        .allocator = allocator,
    };
}
