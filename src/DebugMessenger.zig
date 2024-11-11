const DebugMessenger = @This();

const std = @import("std");
const c = @import("c.zig");

handle: c.VkDebugUtilsMessengerEXT,

/// This is public so that it can be used at instance creation time to debug any issues in
/// vkCreateInstance or vkDestroyInstance.
pub const create_info = c.VkDebugUtilsMessengerCreateInfoEXT{
    .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
    .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
    .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
    .pUserData = null,
    .pfnUserCallback = &debugCallBack,
};

pub fn create(instance: c.VkInstance) !DebugMessenger {
    const getCreateMessenger: c.PFN_vkCreateDebugUtilsMessengerEXT =
        @ptrCast(c.vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"));

    const createMessenger = getCreateMessenger orelse {
        return error.VKDebugUtilsExtNotPresent;
    };

    var debug_messenger: c.VkDebugUtilsMessengerEXT = null;
    if (createMessenger(instance, &create_info, null, &debug_messenger) != c.VK_SUCCESS) {
        return error.VKCreateDebugUtilsMessengerExtFailed;
    }

    return DebugMessenger{ .handle = debug_messenger };
}

pub fn destroy(debug_messenger: DebugMessenger, instance: c.VkInstance) void {
    const getDestroyMessenger: c.PFN_vkDestroyDebugUtilsMessengerEXT =
        @ptrCast(c.vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT"));
    if (getDestroyMessenger) |destroyMessenger| {
        destroyMessenger(instance, debug_messenger.handle, null);
    }
}

fn debugCallBack(
    severity: c.VkDebugUtilsMessageSeverityFlagBitsEXT,
    msg_type: c.VkDebugUtilsMessageTypeFlagsEXT,
    callback_data: [*c]const c.VkDebugUtilsMessengerCallbackDataEXT,
    user_data: ?*anyopaque,
) callconv(.c) c.VkBool32 {
    _ = msg_type;
    _ = user_data;
    _ = severity;

    std.debug.print("validation layer: {s}\n", .{callback_data.*.pMessage});

    return c.VK_FALSE;
}
