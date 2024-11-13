const SwapChain = @This();

const std = @import("std");
const c = @import("c.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");
const Window = @import("Window.zig");

const Allocator = std.mem.Allocator;

handle: c.VkSwapchainKHR,
format: c.VkFormat,
extent: c.VkExtent2D,
images: []const c.VkImage,
image_views: []const c.VkImageView,

pub fn create(
    device: c.VkDevice,
    indices: PhysicalDevice.QueueFamilyIndices,
    support: PhysicalDevice.SwapChainSupport,
    window: Window,
    surface: c.VkSurfaceKHR,
    allocator: Allocator,
) !SwapChain {
    const format = chooseSurfaceFormat(support.formats);
    const present_mode = choosePresentMode(support.present_modes);

    const extent = if (support.capabilities.currentExtent.width != std.math.maxInt(u32))
        support.capabilities.currentExtent
    else
        clampExtent(
            window.getFrameBufferExtent(),
            support.capabilities.minImageExtent,
            support.capabilities.maxImageExtent,
        );

    var image_count = support.capabilities.minImageCount + 1;
    if (support.capabilities.maxImageCount != 0 and image_count > support.capabilities.maxImageCount) {
        image_count = support.capabilities.maxImageCount;
    }

    var create_info = c.VkSwapchainCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface,
        .minImageCount = image_count,
        .imageFormat = format.format,
        .imageColorSpace = format.colorSpace,
        .imageExtent = extent,
        .imageArrayLayers = 1, // This is always 1 unless you are developing a stereoscopic 3D application.
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .preTransform = support.capabilities.currentTransform,
        .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = present_mode,
        .clipped = c.VK_TRUE,
        .oldSwapchain = @ptrCast(c.VK_NULL_HANDLE),
    };

    const queue_family_indices = [2]u32{ indices.graphics_index, indices.present_index };
    if (indices.graphics_index != indices.present_index) {
        create_info.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
        create_info.queueFamilyIndexCount = 2;
        create_info.pQueueFamilyIndices = &queue_family_indices;
    } else {
        create_info.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
        create_info.queueFamilyIndexCount = 0; // Optional.
        create_info.pQueueFamilyIndices = null; // Optional.
    }

    var swapchain: c.VkSwapchainKHR = null;
    if (c.vkCreateSwapchainKHR(device, &create_info, null, &swapchain) != c.VK_SUCCESS) {
        return error.VKCreateSwapchainFailed;
    }

    var actual_image_count: u32 = 0;
    _ = c.vkGetSwapchainImagesKHR(device, swapchain, &actual_image_count, null);
    const images = try allocator.alloc(c.VkImage, actual_image_count);
    _ = c.vkGetSwapchainImagesKHR(device, swapchain, &actual_image_count, images.ptr);

    const image_views = try allocator.alloc(c.VkImageView, actual_image_count);
    for (images, image_views) |image, *image_view| {
        const image_view_create_info = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = image,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = format.format,
            .components = .{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = .{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        if (c.vkCreateImageView(device, &image_view_create_info, null, image_view) != c.VK_SUCCESS) {
            return error.VKCreateImageViewFailed;
        }
    }

    return SwapChain{
        .handle = swapchain,
        .format = format.format,
        .extent = extent,
        .images = images,
        .image_views = image_views,
    };
}

pub fn destroy(swapchain: SwapChain, device: c.VkDevice, allocator: Allocator) void {
    for (swapchain.image_views) |image_view| {
        c.vkDestroyImageView(device, image_view, null);
    }
    allocator.free(swapchain.image_views);
    // NOTE: vkDestroySwapchainKHR will automatically destroy the individual images.
    allocator.free(swapchain.images);

    c.vkDestroySwapchainKHR(device, swapchain.handle, null);
}

fn chooseSurfaceFormat(formats: []const c.VkSurfaceFormatKHR) c.VkSurfaceFormatKHR {
    for (formats) |format| {
        if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and
            format.colorSpace == c.VK_COLORSPACE_SRGB_NONLINEAR_KHR)
        {
            return format;
        }
    }

    return formats[0];
}

fn choosePresentMode(modes: []const c.VkPresentModeKHR) c.VkPresentModeKHR {
    for (modes) |mode| {
        if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
            return mode;
        }
    }
    return c.VK_PRESENT_MODE_FIFO_KHR;
}

fn clampExtent(
    extent: c.VkExtent2D,
    min_extent: c.VkExtent2D,
    max_extent: c.VkExtent2D,
) c.VkExtent2D {
    return c.VkExtent2D{
        .width = std.math.clamp(extent.width, min_extent.width, max_extent.width),
        .height = std.math.clamp(extent.height, min_extent.height, max_extent.height),
    };
}
