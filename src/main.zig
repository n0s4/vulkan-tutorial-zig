const std = @import("std");
const c = @import("c.zig");

const Window = @import("Window.zig");

var gpa: std.mem.Allocator = undefined;

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    gpa = gpa_state.allocator();

    window = try Window.init(&frame_buffer_did_resize);
    defer window.deinit();

    try initVulkan();
    try mainLoop();
    deinitVulkan();
}

fn mainLoop() !void {
    while (c.glfwWindowShouldClose(window.handle) == c.GLFW_FALSE) {
        c.glfwPollEvents();
        try drawFrame();
    }
    _ = c.vkDeviceWaitIdle(device);
}

fn drawFrame() !void {
    _ = c.vkWaitForFences(device, 1, &in_flight_fences[current_frame], c.VK_TRUE, std.math.maxInt(u64));

    var image_index: u32 = 0;
    var result = c.vkAcquireNextImageKHR(
        device,
        swapchain,
        std.math.maxInt(u64),
        image_available_semaphores[current_frame],
        @ptrCast(c.VK_NULL_HANDLE),
        &image_index,
    );

    if (result == c.VK_ERROR_OUT_OF_DATE_KHR) {
        try recreateSwapChain();
        return;
    } else if (result != c.VK_SUCCESS and result != c.VK_SUBOPTIMAL_KHR) {
        return error.VkAcquireNextImageFailed;
    }

    // Only reset the fence if we know we are submitting work.
    _ = c.vkResetFences(device, 1, &in_flight_fences[current_frame]);

    _ = c.vkResetCommandBuffer(command_buffers[current_frame], 0);
    try recordCommandBuffer(command_buffers[current_frame], image_index);

    const submit_info = c.VkSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &image_available_semaphores[current_frame],
        .pWaitDstStageMask = &@intCast(c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
        .commandBufferCount = 1,
        .pCommandBuffers = &command_buffers[current_frame],
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &render_finished_semaphores[current_frame],
    };

    if (c.vkQueueSubmit(graphics_queue, 1, &submit_info, in_flight_fences[current_frame]) != c.VK_SUCCESS) {
        return error.VKQueueSubmitFailed;
    }

    const present_info = c.VkPresentInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &render_finished_semaphores[current_frame],
        .swapchainCount = 1,
        .pSwapchains = &swapchain,
        .pImageIndices = &image_index,
        .pResults = null,
    };

    result = c.vkQueuePresentKHR(graphics_queue, &present_info);

    if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR or frame_buffer_did_resize) {
        frame_buffer_did_resize = false;
        try recreateSwapChain();
    } else if (result != c.VK_SUCCESS) {
        return error.VKQueuePresentFailed;
    }

    current_frame = (current_frame + 1) % max_frames_in_flight;
}

var window: Window = undefined;

const max_frames_in_flight = 2;
var current_frame: usize = 0;

const enable_validation_layers =
    @import("builtin").mode == .Debug;

const validation_layers = [_][*c]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const device_extensions = [_][*c]const u8{
    c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

const default_debug_messenger_create_info = c.VkDebugUtilsMessengerCreateInfoEXT{
    .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
    .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
    .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
    .pfnUserCallback = &debugCallback,
};

var vk_instance: c.VkInstance = null;
var debug_messenger: c.VkDebugUtilsMessengerEXT = null;
var physical_device: c.VkPhysicalDevice = null;
var device: c.VkDevice = null;
var graphics_queue: c.VkQueue = null;
var present_queue: c.VkQueue = null;
var surface: c.VkSurfaceKHR = null;
var swapchain: c.VkSwapchainKHR = null;
var swapchain_images: std.ArrayListUnmanaged(c.VkImage) = .empty;
var swapchain_image_format: c.VkFormat = c.VK_FORMAT_UNDEFINED;
var swapchain_extent: c.VkExtent2D = .{};
var swapchain_image_views: std.ArrayListUnmanaged(c.VkImageView) = .empty;
var render_pass: c.VkRenderPass = null;
var pipeline_layout: c.VkPipelineLayout = null;
var graphics_pipeline: c.VkPipeline = null;
var swapchain_frame_buffers: std.ArrayListUnmanaged(c.VkFramebuffer) = .empty;
var command_pool: c.VkCommandPool = null;
var command_buffers: [max_frames_in_flight]c.VkCommandBuffer = undefined;
var image_available_semaphores: [max_frames_in_flight]c.VkSemaphore = undefined;
var render_finished_semaphores: [max_frames_in_flight]c.VkSemaphore = undefined;
var in_flight_fences: [max_frames_in_flight]c.VkFence = undefined;
var frame_buffer_did_resize = false;

fn initVulkan() !void {
    try createInstance();
    try setupDebugMessenger();
    try window.createSurface(vk_instance, &surface);
    try pickPhysicalDevice();
    try createLogicalDevice();
    try createSwapChain();
    try createImageViews();
    try createRenderPass();
    try createGraphicsPipeline();
    try createFrameBuffers();
    try createCommandPool();
    try createCommandBuffers();
    try createSyncObjects();
}

fn createInstance() !void {
    if (enable_validation_layers and !try checkValidationLayerSupport()) {
        return error.ValidationLayersUnsupported;
    }

    const app_info = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "Hello Triangle",
        .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "No Engine",
        .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = c.VK_API_VERSION_1_0,
    };

    const extensions = try getRequiredExtensions();
    defer if (enable_validation_layers) {
        // We had to add the debug utils ext by allocating a bigger buffer.
        gpa.free(extensions);
    };

    var create_info = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = @intCast(extensions.len),
        .ppEnabledExtensionNames = extensions.ptr,
    };

    if (enable_validation_layers) {
        create_info.enabledLayerCount = @intCast(validation_layers.len);
        create_info.ppEnabledLayerNames = &validation_layers;
        create_info.pNext = &default_debug_messenger_create_info;
    } else {
        create_info.enabledLayerCount = 0;
        create_info.pNext = null;
    }

    if (c.vkCreateInstance(&create_info, null, &vk_instance) != c.VK_SUCCESS)
        return error.VKCreateInstanceFailed;
}

fn checkValidationLayerSupport() !bool {
    var layer_count: u32 = 0;
    _ = c.vkEnumerateInstanceLayerProperties(&layer_count, null);

    const available_layers = try gpa.alloc(c.VkLayerProperties, layer_count);
    defer gpa.free(available_layers);
    _ = c.vkEnumerateInstanceLayerProperties(&layer_count, available_layers.ptr);

    for (validation_layers) |layer_name| {
        var found_layer = false;
        find_layer: for (available_layers) |layer_properties| {
            var i: usize = 0;
            while (layer_properties.layerName[i] == layer_name[i]) : (i += 1) {
                if (layer_name[i] == '\x00') {
                    found_layer = true;
                    break :find_layer;
                }
            }
        }
        if (!found_layer) return false;
    }

    return true;
}

fn getRequiredExtensions() ![][*c]const u8 {
    var glfw_ext_count: u32 = 0;
    const glfw_exts = c.glfwGetRequiredInstanceExtensions(&glfw_ext_count);

    for (glfw_exts[0..glfw_ext_count]) |ext| {
        std.log.info("glfw requires extension: {s}", .{std.mem.span(ext)});
    }

    if (!enable_validation_layers) {
        return glfw_exts[0..glfw_ext_count :0];
    }

    const new_exts = try gpa.alloc([*c]const u8, glfw_ext_count + 1);
    std.mem.copyForwards([*c]const u8, new_exts, glfw_exts[0..glfw_ext_count]);
    new_exts[new_exts.len - 1] = c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME;
    return new_exts;
}

fn setupDebugMessenger() !void {
    if (!enable_validation_layers) return;

    if (createDebugUtilsMessengerEXT(
        vk_instance,
        &default_debug_messenger_create_info,
        null,
        &debug_messenger,
    ) != c.VK_SUCCESS) {
        return error.CreateDebugUtilsMessengerFailed;
    }
}

fn debugCallback(
    msg_severity: c.VkDebugUtilsMessageSeverityFlagBitsEXT,
    msg_type: c.VkDebugUtilsMessageTypeFlagsEXT,
    callback_data: [*c]const c.VkDebugUtilsMessengerCallbackDataEXT,
    user_data: ?*anyopaque,
) callconv(.C) c.VkBool32 {
    _ = user_data;
    _ = msg_type;
    _ = msg_severity;

    const message = std.mem.span(callback_data.*.pMessage);
    std.debug.print("validation layer: {s}\n", .{message});

    return c.VK_FALSE;
}

fn createDebugUtilsMessengerEXT(
    instance: c.VkInstance,
    create_info: [*c]const c.VkDebugUtilsMessengerCreateInfoEXT,
    allocator: [*c]const c.VkAllocationCallbacks,
    dbg_messenger: [*c]c.VkDebugUtilsMessengerEXT,
) c.VkResult {
    const get_func: c.PFN_vkCreateDebugUtilsMessengerEXT =
        @ptrCast(c.vkGetInstanceProcAddr(vk_instance, "vkCreateDebugUtilsMessengerEXT"));
    if (get_func) |func| {
        return func(instance, create_info, allocator, dbg_messenger);
    } else {
        return c.VK_ERROR_EXTENSION_NOT_PRESENT;
    }
}

fn destroyDebugUtilsMessengerEXT(
    instance: c.VkInstance,
    dbg_messenger: c.VkDebugUtilsMessengerEXT,
    allocator: [*c]const c.VkAllocationCallbacks,
) void {
    const get_func: c.PFN_vkDestroyDebugUtilsMessengerEXT =
        @ptrCast(c.vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT"));
    if (get_func) |func| {
        func(instance, dbg_messenger, allocator);
    }
}

fn createSurface() !void {
    if (c.glfwCreateWindowSurface(vk_instance, window, null, &surface) != c.VK_SUCCESS) {
        return error.FailedToCreateWindowSurface;
    }
}

fn pickPhysicalDevice() !void {
    var device_count: u32 = 0;
    _ = c.vkEnumeratePhysicalDevices(vk_instance, &device_count, null);
    if (device_count == 0) {
        return error.NoVulkanSupportedGPUs;
    }

    const devices = try gpa.alloc(c.VkPhysicalDevice, device_count);
    defer gpa.free(devices);
    _ = c.vkEnumeratePhysicalDevices(vk_instance, &device_count, devices.ptr);

    for (devices) |dev| {
        if (try isDeviceSuitable(dev)) {
            physical_device = dev;
            break;
        }
    }

    if (physical_device == null) {
        return error.NoSuitableGPUs;
    }
}

fn isDeviceSuitable(dev: c.VkPhysicalDevice) !bool {
    const indices = try findQueueFamilies(dev);

    const extensions_supported = try checkDeviceExtensionSupport(dev);

    var swapchain_adequate = false;
    if (extensions_supported) {
        var swapchain_support = try querySwapChainSupport(dev);
        defer swapchain_support.deinit(gpa);
        swapchain_adequate = swapchain_support.formats.items.len != 0 and
            swapchain_support.present_modes.items.len != 0;
    }

    return indices.isComplete() and extensions_supported and swapchain_adequate;
}

const QueueFamilyIndices = struct {
    graphics_family: ?u32 = null,
    present_family: ?u32 = null,

    fn isComplete(indices: QueueFamilyIndices) bool {
        return indices.graphics_family != null and
            indices.present_family != null;
    }
};

fn findQueueFamilies(
    dev: c.VkPhysicalDevice,
) !QueueFamilyIndices {
    var indices = QueueFamilyIndices{};

    var queue_family_count: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(dev, &queue_family_count, null);

    const queue_families = try gpa.alloc(c.VkQueueFamilyProperties, queue_family_count);
    defer gpa.free(queue_families);
    c.vkGetPhysicalDeviceQueueFamilyProperties(dev, &queue_family_count, queue_families.ptr);

    for (queue_families, 0..) |queue_family, i| {
        if (queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT == 1) {
            indices.graphics_family = @intCast(i);
        }

        var present_support: c.VkBool32 = c.VK_FALSE;
        _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(dev, @intCast(i), surface, &present_support);

        if (present_support == c.VK_TRUE) {
            indices.present_family = @intCast(i);
        }

        if (indices.isComplete()) {
            break;
        }
    }

    return indices;
}

fn checkDeviceExtensionSupport(dev: c.VkPhysicalDevice) !bool {
    var ext_count: u32 = 0;
    _ = c.vkEnumerateDeviceExtensionProperties(dev, null, &ext_count, null);

    const available_exts = try gpa.alloc(c.VkExtensionProperties, ext_count);
    defer gpa.free(available_exts);
    _ = c.vkEnumerateDeviceExtensionProperties(dev, null, &ext_count, available_exts.ptr);

    var extension_present = [_]bool{false} ** device_extensions.len;
    for (available_exts) |ext| {
        for (device_extensions, 0..) |required_ext_name, i| {
            const ext_name_ptr: [*:0]const u8 = @ptrCast(&ext.extensionName);
            if (std.mem.eql(u8, std.mem.span(ext_name_ptr), std.mem.span(required_ext_name))) {
                extension_present[i] = true;
            }
        }
    }

    return std.mem.allEqual(bool, &extension_present, true);
}

const SwapChainSupportDetails = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR,
    formats: std.ArrayListUnmanaged(c.VkSurfaceFormatKHR) = .{},
    present_modes: std.ArrayListUnmanaged(c.VkPresentModeKHR) = .{},

    pub fn deinit(details: *SwapChainSupportDetails, allocator: std.mem.Allocator) void {
        details.formats.deinit(allocator);
        details.present_modes.deinit(allocator);
        details.* = undefined;
    }
};

fn querySwapChainSupport(
    dev: c.VkPhysicalDevice,
) !SwapChainSupportDetails {
    var details = SwapChainSupportDetails{ .capabilities = undefined };

    _ = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(dev, surface, &details.capabilities);

    var format_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(dev, surface, &format_count, null);

    if (format_count != 0) {
        try details.formats.resize(gpa, format_count);
        _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(
            dev,
            surface,
            &format_count,
            details.formats.items.ptr,
        );
    }

    var present_mode_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(dev, surface, &present_mode_count, null);

    if (present_mode_count != 0) {
        try details.present_modes.resize(gpa, present_mode_count);
        _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(
            dev,
            surface,
            &present_mode_count,
            details.present_modes.items.ptr,
        );
    }

    return details;
}

fn createLogicalDevice() !void {
    const indices = try findQueueFamilies(physical_device);

    var unique_queue_families = std.ArrayListUnmanaged(u32).empty;
    defer unique_queue_families.deinit(gpa);
    for ([_]u32{ indices.graphics_family.?, indices.present_family.? }) |family| {
        if (std.mem.indexOfScalar(u32, unique_queue_families.items, family) == null) {
            try unique_queue_families.append(gpa, family);
        }
    }

    var queue_create_info_list = std.ArrayListUnmanaged(c.VkDeviceQueueCreateInfo){};
    defer queue_create_info_list.deinit(gpa);

    for (unique_queue_families.items) |queue_family| {
        const queue_create_info = c.VkDeviceQueueCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = queue_family,
            .queueCount = 1,
            // This would normally be an array, but we only have 1 queue for each family.
            .pQueuePriorities = &@as(f32, 1.0),
        };
        try queue_create_info_list.append(gpa, queue_create_info);
    }

    const device_features = c.VkPhysicalDeviceFeatures{};

    var create_info = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = queue_create_info_list.items.ptr,
        .queueCreateInfoCount = @intCast(queue_create_info_list.items.len),
        .pEnabledFeatures = &device_features,
        .enabledExtensionCount = device_extensions.len,
        .ppEnabledExtensionNames = &device_extensions,
    };

    // Previous implementations of Vulkan made a distinction between instance and device specific
    // validation layers, but this is no longer the case. That means that the enabledLayerCount and
    // ppEnabledLayerNames fields of VkDeviceCreateInfo are ignored by up-to-date implementations.
    // However, it is still a good idea to set them anyway to be compatible with older implementations.
    if (enable_validation_layers) {
        create_info.enabledLayerCount = validation_layers.len;
        create_info.ppEnabledLayerNames = &validation_layers;
    } else {
        create_info.enabledLayerCount = 0;
    }

    if (c.vkCreateDevice(physical_device, &create_info, null, &device) != c.VK_SUCCESS) {
        return error.VKCreateDeviceFailed;
    }

    c.vkGetDeviceQueue(device, indices.graphics_family.?, 0, &graphics_queue);
    c.vkGetDeviceQueue(device, indices.present_family.?, 0, &present_queue);
}

fn recreateSwapChain() !void {
    var width: c_int = 0;
    var height: c_int = 0;
    c.glfwGetFramebufferSize(window.handle, &width, &height);
    while (width == 0 or height == 0) {
        c.glfwGetFramebufferSize(window.handle, width, height);
        c.glfwWaitEvents();
    }
    _ = c.vkDeviceWaitIdle(device);

    deinitSwapChain();

    try createSwapChain();
    try createImageViews();
    try createFrameBuffers();
}

fn deinitSwapChain() void {
    for (swapchain_frame_buffers.items) |frame_buffer| {
        c.vkDestroyFramebuffer(device, frame_buffer, null);
    }
    for (swapchain_image_views.items) |image_view| {
        c.vkDestroyImageView(device, image_view, null);
    }
    // we don't use deinit because we want to reuse these in recreateSwapChain.
    swapchain_frame_buffers.clearAndFree(gpa);
    swapchain_image_views.clearAndFree(gpa);
    swapchain_images.clearAndFree(gpa);
    c.vkDestroySwapchainKHR(device, swapchain, null);
}

fn createSwapChain() !void {
    var swapchain_support = try querySwapChainSupport(physical_device);
    defer swapchain_support.deinit(gpa);

    var w: c_int = 0;
    var h: c_int = 0;
    c.glfwGetWindowSize(window.handle, &w, &h);

    const surface_format = chooseSwapSurfaceFormat(swapchain_support.formats.items);
    const present_mode = chooseSwapPresentMode(swapchain_support.present_modes.items);
    const extent = chooseSwapExtent(&swapchain_support.capabilities);

    // simply sticking to this minimum means that we may sometimes have to wait on the driver to
    // complete internal operations before we can acquire another image to render to. Therefore it
    // is recommended to request at least one more image than the minimum:
    var image_count = swapchain_support.capabilities.minImageCount + 1;
    if (swapchain_support.capabilities.maxImageCount != 0 and // 0 means no maximum
        image_count > swapchain_support.capabilities.maxImageCount)
    {
        image_count = swapchain_support.capabilities.maxImageCount;
    }

    var create_info = c.VkSwapchainCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface,
        .minImageCount = image_count,
        .imageExtent = extent,
        .imageFormat = surface_format.format,
        .imageColorSpace = surface_format.colorSpace,
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .preTransform = swapchain_support.capabilities.currentTransform,
        .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = present_mode,
        .clipped = c.VK_TRUE,
        .oldSwapchain = @ptrCast(c.VK_NULL_HANDLE),
    };

    const indices = try findQueueFamilies(physical_device);
    const queue_family_indices = [_]u32{ indices.graphics_family.?, indices.present_family.? };

    if (indices.graphics_family != indices.present_family) {
        create_info.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
        create_info.queueFamilyIndexCount = @intCast(queue_family_indices.len);
        create_info.pQueueFamilyIndices = &queue_family_indices;
    } else {
        create_info.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
        create_info.queueFamilyIndexCount = 0; // nullptr
        create_info.pQueueFamilyIndices = null; // nullptr
    }

    if (c.vkCreateSwapchainKHR(device, &create_info, null, &swapchain) != c.VK_SUCCESS) {
        return error.VKCreateSwapchainFailed;
    }

    // Remember that we only specified a minimum number of images in the swap chain, so the
    // implementation is allowed to create a swap chain with more. That’s why we’ll first query the
    // final number of images with vkGetSwapchainImagesKHR, then resize the container and finally
    // call it again to retrieve the handles.
    _ = c.vkGetSwapchainImagesKHR(device, swapchain, &image_count, null);
    try swapchain_images.resize(gpa, image_count);
    _ = c.vkGetSwapchainImagesKHR(device, swapchain, &image_count, swapchain_images.items.ptr);

    swapchain_image_format = surface_format.format;
    swapchain_extent = extent;
}

fn chooseSwapSurfaceFormat(formats: []const c.VkSurfaceFormatKHR) c.VkSurfaceFormatKHR {
    std.debug.assert(formats.len > 0);

    for (formats) |format| {
        if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and
            format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
        {
            return format;
        }
    }

    return formats[0];
}

fn chooseSwapPresentMode(modes: []const c.VkPresentModeKHR) c.VkPresentModeKHR {
    std.debug.assert(modes.len > 0);
    if (std.mem.indexOfScalar(c.VkPresentModeKHR, modes, c.VK_PRESENT_MODE_MAILBOX_KHR)) |i| {
        return modes[i];
    }
    return c.VK_PRESENT_MODE_FIFO_KHR;
}

fn chooseSwapExtent(capabilities: *const c.VkSurfaceCapabilitiesKHR) c.VkExtent2D {
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return capabilities.currentExtent;
    } else {
        var extent = window.getFrameBufferExtent();
        extent.width = std.math.clamp(
            extent.width,
            capabilities.minImageExtent.width,
            capabilities.maxImageExtent.width,
        );
        extent.height = std.math.clamp(
            extent.height,
            capabilities.minImageExtent.height,
            capabilities.maxImageExtent.height,
        );

        return extent;
    }
}

fn createImageViews() !void {
    try swapchain_image_views.resize(gpa, swapchain_images.items.len);
    for (swapchain_images.items, swapchain_image_views.items) |image, *image_view| {
        const create_info = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = image,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = swapchain_image_format,
            .components = c.VkComponentMapping{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = c.VkImageSubresourceRange{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        if (c.vkCreateImageView(device, &create_info, null, image_view) != c.VK_SUCCESS) {
            return error.VKCreateImageViewFailed;
        }
    }
}

fn createRenderPass() !void {
    const color_attachment = c.VkAttachmentDescription{
        .format = swapchain_image_format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };

    const color_attachment_ref = c.VkAttachmentReference{
        .attachment = 0,
        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    const subpass = c.VkSubpassDescription{
        .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment_ref,
    };

    const dependency = c.VkSubpassDependency{
        .srcSubpass = c.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    };

    const render_pass_info = c.VkRenderPassCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &color_attachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &dependency,
    };

    if (c.vkCreateRenderPass(device, &render_pass_info, null, &render_pass) != c.VK_SUCCESS) {
        return error.VKCreateRenderpassFailed;
    }
}

const vert_shader_code = @embedFile("shaders/compiled/vert.spv");
const frag_shader_code = @embedFile("shaders/compiled/frag.spv");

fn createGraphicsPipeline() !void {
    const vert_shader_module = try createShaderModule(@alignCast(vert_shader_code));
    defer c.vkDestroyShaderModule(device, vert_shader_module, null);

    const frag_shader_module = try createShaderModule(@alignCast(frag_shader_code));
    defer c.vkDestroyShaderModule(device, frag_shader_module, null);

    const vert_shader_stage_info = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vert_shader_module,
        .pName = "main",
        .pSpecializationInfo = null,
    };

    const frag_shader_stage_info = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = frag_shader_module,
        .pName = "main",
        .pSpecializationInfo = null,
    };

    const shader_stages = [2]c.VkPipelineShaderStageCreateInfo{
        vert_shader_stage_info,
        frag_shader_stage_info,
    };

    const vertex_input_info = c.VkPipelineVertexInputStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 0,
        .pVertexBindingDescriptions = null,
        .vertexAttributeDescriptionCount = 0,
        .pVertexAttributeDescriptions = null,
    };

    const input_assembly = c.VkPipelineInputAssemblyStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = c.VK_FALSE,
    };

    const viewport_state = c.VkPipelineViewportStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .scissorCount = 1,
    };

    const rasterizer = c.VkPipelineRasterizationStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .depthClampEnable = c.VK_FALSE,
        .rasterizerDiscardEnable = c.VK_FALSE,
        .polygonMode = c.VK_POLYGON_MODE_FILL,
        .lineWidth = 1,
        .cullMode = c.VK_CULL_MODE_BACK_BIT,
        .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
        .depthBiasEnable = c.VK_FALSE,
        // for depth biasing:
        // .depthBiasConstantFactor = 0,
        // .depthBiasClamp = 0,
        // .depthBiasSlopeFactor = 0,
    };

    const multisampling = c.VkPipelineMultisampleStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .sampleShadingEnable = c.VK_FALSE,
        .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
        // for sample shading:
        // .minSampleShading = 1,
        // .pSampleMask = null,
        // .alphaToCoverageEnable = c.VK_FALSE,
        // .alphaToOneEnable = c.VK_FALSE,
    };

    const color_blend_attachment = c.VkPipelineColorBlendAttachmentState{
        .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT |
            c.VK_COLOR_COMPONENT_G_BIT |
            c.VK_COLOR_COMPONENT_B_BIT |
            c.VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = c.VK_FALSE,
        // for blending:
        // .srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
        // .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        // .colorBlendOp = c.VK_BLEND_OP_ADD,
        // .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
        // .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        // .alphaBlendOp = c.VK_BLEND_OP_ADD,
    };

    const color_blending = c.VkPipelineColorBlendStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .logicOpEnable = c.VK_FALSE,
        .logicOp = c.VK_LOGIC_OP_COPY, // optional
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
        .blendConstants = .{0} ** 4,
    };

    const dynamic_states = [2]c.VkDynamicState{
        c.VK_DYNAMIC_STATE_VIEWPORT,
        c.VK_DYNAMIC_STATE_SCISSOR,
    };

    const dynamic_state = c.VkPipelineDynamicStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = dynamic_states.len,
        .pDynamicStates = &dynamic_states,
    };

    const pipeline_layout_info = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 0,
        .pSetLayouts = null,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = null,
    };

    if (c.vkCreatePipelineLayout(
        device,
        &pipeline_layout_info,
        null,
        &pipeline_layout,
    ) != c.VK_SUCCESS) {
        return error.VKCreatePipelineLayoutFailed;
    }

    const pipeline_info = c.VkGraphicsPipelineCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2,
        .pStages = &shader_stages,
        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &input_assembly,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pDepthStencilState = null, // optional
        .pColorBlendState = &color_blending,
        .pDynamicState = &dynamic_state,
        .layout = pipeline_layout,
        .renderPass = render_pass,
        .subpass = 0,
        .basePipelineHandle = @ptrCast(c.VK_NULL_HANDLE), // optional,
        .basePipelineIndex = -1, // optional,
    };

    if (c.vkCreateGraphicsPipelines(
        device,
        @ptrCast(c.VK_NULL_HANDLE),
        1,
        &pipeline_info,
        null,
        &graphics_pipeline,
    ) != c.VK_SUCCESS) {
        return error.VKCreateGraphicsPipelineFailed;
    }
}

fn createShaderModule(code: []align(@alignOf(u32)) const u8) !c.VkShaderModule {
    std.debug.assert(code.len % 4 == 0);
    const create_info = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code.len,
        .pCode = @ptrCast(code.ptr),
    };

    var shader_module: c.VkShaderModule = null;
    if (c.vkCreateShaderModule(device, &create_info, null, &shader_module) != c.VK_SUCCESS) {
        return error.VKCreateShaderModuleFailed;
    }

    return shader_module;
}

fn createFrameBuffers() !void {
    try swapchain_frame_buffers.resize(gpa, swapchain_image_views.items.len);

    for (swapchain_image_views.items, swapchain_frame_buffers.items) |image_view, *frame_buffer| {
        const frame_buffer_info = c.VkFramebufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = render_pass,
            .attachmentCount = 1,
            .pAttachments = &image_view,
            .width = swapchain_extent.width,
            .height = swapchain_extent.height,
            .layers = 1,
        };
        if (c.vkCreateFramebuffer(device, &frame_buffer_info, null, frame_buffer) != c.VK_SUCCESS) {
            return error.VKCreateFrameBufferFailed;
        }
    }
}

fn createCommandPool() !void {
    const queue_family_indices = try findQueueFamilies(physical_device);

    const pool_info = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = queue_family_indices.graphics_family.?,
    };

    if (c.vkCreateCommandPool(device, &pool_info, null, &command_pool) != c.VK_SUCCESS) {
        return error.VKCreateCommandPoolFailed;
    }
}

fn createCommandBuffers() !void {
    const alloc_info = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 2,
    };

    if (c.vkAllocateCommandBuffers(device, &alloc_info, &command_buffers) != c.VK_SUCCESS) {
        return error.VKAllocateCommandBuffersFailed;
    }
}

fn recordCommandBuffer(cmd_buffer: c.VkCommandBuffer, image_index: u32) !void {
    const begin_info = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = 0,
        .pInheritanceInfo = null,
    };

    if (c.vkBeginCommandBuffer(cmd_buffer, &begin_info) != c.VK_SUCCESS) {
        return error.VKBeginCommandBufferFailed;
    }

    const clear_color = c.VkClearValue{ .color = .{ .float32 = .{0} ** 4 } };

    const render_pass_info = c.VkRenderPassBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = render_pass,
        .framebuffer = swapchain_frame_buffers.items[@intCast(image_index)],
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = swapchain_extent,
        },
        .clearValueCount = 1,
        .pClearValues = &clear_color,
    };

    c.vkCmdBeginRenderPass(cmd_buffer, &render_pass_info, c.VK_SUBPASS_CONTENTS_INLINE);

    c.vkCmdBindPipeline(cmd_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, graphics_pipeline);

    const viewport = c.VkViewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(swapchain_extent.width),
        .height = @floatFromInt(swapchain_extent.height),
        .minDepth = 0,
        .maxDepth = 1,
    };
    c.vkCmdSetViewport(cmd_buffer, 0, 1, &viewport);

    const scissor = c.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = swapchain_extent,
    };
    c.vkCmdSetScissor(cmd_buffer, 0, 1, &scissor);

    c.vkCmdDraw(cmd_buffer, 3, 1, 0, 0);

    c.vkCmdEndRenderPass(cmd_buffer);

    if (c.vkEndCommandBuffer(cmd_buffer) != c.VK_SUCCESS) {
        return error.VkEndCommandBufferFailed;
    }
}

fn createSyncObjects() !void {
    const semaphore_info = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    const fence_info = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };

    for (0..max_frames_in_flight) |i| {
        if (c.vkCreateSemaphore(device, &semaphore_info, null, &image_available_semaphores[i]) != c.VK_SUCCESS or
            c.vkCreateSemaphore(device, &semaphore_info, null, &render_finished_semaphores[i]) != c.VK_SUCCESS or
            c.vkCreateFence(device, &fence_info, null, &in_flight_fences[i]) != c.VK_SUCCESS)
            return error.VKCreateSyncObjectFailed;
    }
}

fn deinitVulkan() void {
    deinitSwapChain();

    c.vkDestroyPipeline(device, graphics_pipeline, null);
    c.vkDestroyPipelineLayout(device, pipeline_layout, null);
    c.vkDestroyRenderPass(device, render_pass, null);

    for (0..max_frames_in_flight) |i| {
        c.vkDestroySemaphore(device, image_available_semaphores[i], null);
        c.vkDestroySemaphore(device, render_finished_semaphores[i], null);
        c.vkDestroyFence(device, in_flight_fences[i], null);
    }

    c.vkDestroyCommandPool(device, command_pool, null);

    c.vkDestroyDevice(device, null);

    if (enable_validation_layers) {
        destroyDebugUtilsMessengerEXT(vk_instance, debug_messenger, null);
    }

    c.vkDestroySurfaceKHR(vk_instance, surface, null);

    c.vkDestroyInstance(vk_instance, null);
}
