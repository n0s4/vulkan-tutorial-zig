const RenderPass = @This();

const std = @import("std");
const c = @import("c.zig");

handle: c.VkRenderPass,

pub fn create(device: c.VkDevice, swapchain_image_format: c.VkFormat) !RenderPass {
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

    var render_pass_info = c.VkRenderPassCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &color_attachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,
    };

    var render_pass: c.VkRenderPass = undefined;
    if (c.vkCreateRenderPass(device, &render_pass_info, null, &render_pass) != c.VK_SUCCESS) {
        return error.VKCreateRenderPassFailed;
    }

    return RenderPass{ .handle = render_pass };
}

pub fn destroy(render_pass: RenderPass, device: c.VkDevice) void {
    c.vkDestroyRenderPass(device, render_pass.handle, null);
}
