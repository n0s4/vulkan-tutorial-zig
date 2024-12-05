const std = @import("std");
const c = @import("c.zig");

pub fn create(image: c.VkImage, format: c.VkFormat, aspect_flags: c.VkImageAspectFlags, device: c.VkDevice) !c.VkImageView {
    const view_info = c.VkImageViewCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .components = .{
            .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
        },
        .subresourceRange = .{
            .aspectMask = aspect_flags,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    var view: c.VkImageView = undefined;
    if (c.vkCreateImageView(device, &view_info, null, &view) != c.VK_SUCCESS) {
        return error.VKCreateImageViewFailed;
    }

    return view;
}
