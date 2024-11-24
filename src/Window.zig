//! Abstraction over GLFW and GLFW window usage with Vulkan.
const Window = @This();

const std = @import("std");
const c = @import("c.zig");

handle: *c.GLFWwindow,

/// Initialize GLFW and create a Window and its Vulkan Surface.
pub fn init(frame_buffer_did_resize: *bool) !Window {
    if (c.glfwInit() != c.GLFW_TRUE) {
        return error.GLFWInitFailed;
    }

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);

    const handle = c.glfwCreateWindow(1920, 1080, "Vulkan", null, null) orelse {
        return error.GLFWCreateWindowFailed;
    };

    c.glfwSetWindowUserPointer(handle, frame_buffer_did_resize);
    _ = c.glfwSetFramebufferSizeCallback(handle, &framebufferResizeCallback);

    var w: c_int = 0;
    var h: c_int = 0;
    c.glfwGetWindowSize(handle, &w, &h);
    std.log.info("init window size: {d} x {d}", .{ w, h });

    return .{
        .handle = handle,
    };
}

fn framebufferResizeCallback(handle: ?*c.GLFWwindow, _: c_int, _: c_int) callconv(.c) void {
    const frame_buffer_did_resize: *bool = @ptrCast(c.glfwGetWindowUserPointer(handle).?);
    frame_buffer_did_resize.* = true;
}

/// Destroy the Window and window Surface and terminate GLFW.
pub fn deinit(window: Window) void {
    c.glfwDestroyWindow(window.handle);
    c.glfwTerminate();
}

/// Creates a Vulkan window surface from the Window.
pub fn createSurface(window: Window, instance: c.VkInstance) !c.VkSurfaceKHR {
    var surface: c.VkSurfaceKHR = null;
    if (c.glfwCreateWindowSurface(instance, window.handle, null, &surface) != c.VK_SUCCESS) {
        return error.CreateWindowSurfaceFailed;
    }
    return surface;
}

/// Returns the windows resolution in pixels.
pub fn getFrameBufferExtent(window: Window) c.VkExtent2D {
    var extent: c.VkExtent2D = undefined;
    c.glfwGetFramebufferSize(window.handle, @ptrCast(&extent.width), @ptrCast(&extent.height));
    return extent;
}
