const std = @import("std");
const c = @import("c.zig");
const math = @import("math.zig");

const Window = @import("Window.zig");
const Instance = @import("Instance.zig");
const DebugMessenger = @import("DebugMessenger.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");
const Device = @import("Device.zig");
const SwapChain = @import("SwapChain.zig");
const RenderPass = @import("RenderPass.zig");
const GraphicsPipeline = @import("GraphicsPipeline.zig");
const CommandPool = @import("CommandPool.zig");
const Vertex = @import("Vertex.zig");
const Buffer = @import("Buffer.zig");

const Matrix = math.Matrix;

var gpa: std.mem.Allocator = undefined;

var window: Window = undefined;

const vertices = [4]Vertex{
    .{ .pos = .{ -0.5, -0.5 }, .color = .{ 1, 0, 0 } },
    .{ .pos = .{ 0.5, -0.5 }, .color = .{ 0, 1, 0 } },
    .{ .pos = .{ 0.5, 0.5 }, .color = .{ 0, 0, 1 } },
    .{ .pos = .{ -0.5, 0.5 }, .color = .{ 1, 1, 1 } },
};

const indices = [6]u16{ 0, 1, 2, 2, 3, 0 };

const max_frames_in_flight = 2;
var current_frame: usize = 0;

const enable_validation_layers = @import("builtin").mode == .Debug;

const validation_layers: []const [*:0]const u8 = if (enable_validation_layers) &validation_layer_names else &.{};

const validation_layer_names = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const device_extensions = [_][*:0]const u8{
    c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

var vk_instance: Instance = undefined;
var debug_messenger: DebugMessenger = undefined;
var physical_device: PhysicalDevice = undefined;
var device: Device = undefined;
var surface: c.VkSurfaceKHR = undefined;
var swapchain: SwapChain = undefined;
var render_pass: RenderPass = undefined;
var graphics_pipeline: GraphicsPipeline = undefined;
var swapchain_frame_buffers: []c.VkFramebuffer = &.{};
var command_pool: CommandPool = undefined;
var vertex_buffer: Buffer = undefined;
var index_buffer: Buffer = undefined;
var image_available_semaphores: [max_frames_in_flight]c.VkSemaphore = undefined;
var render_finished_semaphores: [max_frames_in_flight]c.VkSemaphore = undefined;
var in_flight_fences: [max_frames_in_flight]c.VkFence = undefined;
var frame_buffer_did_resize = false;

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    gpa = gpa_state.allocator();

    window = try Window.init(&frame_buffer_did_resize);
    defer window.deinit();

    vk_instance = try Instance.create(validation_layers, gpa);
    defer vk_instance.destroy();

    debug_messenger = try DebugMessenger.create(vk_instance.handle);
    defer debug_messenger.destroy(vk_instance.handle);

    surface = try window.createSurface(vk_instance.handle);
    defer c.vkDestroySurfaceKHR(vk_instance.handle, surface, null);

    physical_device = try PhysicalDevice.selectAndCreate(
        vk_instance.handle,
        surface,
        &device_extensions,
        gpa,
    );
    defer physical_device.deinit(gpa);

    device = try Device.create(physical_device, validation_layers, &device_extensions, gpa);
    defer device.destroy();

    swapchain = try SwapChain.create(
        device.handle,
        physical_device.queue_families,
        physical_device.swapchain_support,
        window,
        surface,
        gpa,
    );
    defer swapchain.destroy(device.handle, gpa);

    render_pass = try RenderPass.create(device.handle, swapchain.format);
    defer render_pass.destroy(device.handle);

    try createDescriptorSetLayout();
    defer c.vkDestroyDescriptorSetLayout(device.handle, descriptor_set_layout, null);

    graphics_pipeline = try GraphicsPipeline.create(
        device.handle,
        render_pass.handle,
        &descriptor_set_layout,
        swapchain.extent,
    );
    defer graphics_pipeline.destroy(device.handle);

    try createFrameBuffers();
    defer destroyFrameBuffers();

    command_pool = try CommandPool.create(
        device.handle,
        physical_device.queue_families,
        max_frames_in_flight,
        gpa,
    );
    defer command_pool.destroy(device.handle, gpa);

    vertex_buffer = try Buffer.createOnDevice(
        Vertex,
        &vertices,
        c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        physical_device.mem_properties,
        device.handle,
        device.graphics_queue, // Graphics queues implicitly support transfer operations.
        command_pool.handle,
    );
    defer vertex_buffer.destroy(device.handle);

    index_buffer = try Buffer.createOnDevice(
        u16,
        &indices,
        c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        physical_device.mem_properties,
        device.handle,
        device.graphics_queue,
        command_pool.handle,
    );
    defer index_buffer.destroy(device.handle);

    try createUniformBuffers();
    defer destroyUniformBuffers();

    try createDescriptorPool();
    defer c.vkDestroyDescriptorPool(device.handle, descriptor_pool, null);

    try createDescriptorSets();

    try createSyncObjects();
    defer destroySyncObjects();

    try mainLoop();
}

fn mainLoop() !void {
    while (c.glfwWindowShouldClose(window.handle) == c.GLFW_FALSE) {
        c.glfwPollEvents();
        try drawFrame();
    }
    _ = c.vkDeviceWaitIdle(device.handle);
}

fn drawFrame() !void {
    _ = c.vkWaitForFences(device.handle, 1, &in_flight_fences[current_frame], c.VK_TRUE, std.math.maxInt(u64));

    var image_index: u32 = 0;
    var result = c.vkAcquireNextImageKHR(
        device.handle,
        swapchain.handle,
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
    _ = c.vkResetFences(device.handle, 1, &in_flight_fences[current_frame]);

    _ = c.vkResetCommandBuffer(command_pool.buffers[current_frame], 0);
    try recordCommandBuffer(command_pool.buffers[current_frame], image_index);

    updateUniformBuffer(current_frame);

    const submit_info = c.VkSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &image_available_semaphores[current_frame],
        .pWaitDstStageMask = &@intCast(c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
        .commandBufferCount = 1,
        .pCommandBuffers = &command_pool.buffers[current_frame],
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &render_finished_semaphores[current_frame],
    };

    if (c.vkQueueSubmit(device.graphics_queue, 1, &submit_info, in_flight_fences[current_frame]) != c.VK_SUCCESS) {
        return error.VKQueueSubmitFailed;
    }

    const present_info = c.VkPresentInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &render_finished_semaphores[current_frame],
        .swapchainCount = 1,
        .pSwapchains = &swapchain.handle,
        .pImageIndices = &image_index,
        .pResults = null,
    };

    result = c.vkQueuePresentKHR(device.graphics_queue, &present_info);

    if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR or frame_buffer_did_resize) {
        frame_buffer_did_resize = false;
        try recreateSwapChain();
    } else if (result != c.VK_SUCCESS) {
        return error.VKQueuePresentFailed;
    }

    current_frame = (current_frame + 1) % max_frames_in_flight;
}

var start_time: std.time.Instant = undefined;
var init_timer = std.once(startTime);

fn startTime() void {
    start_time = std.time.Instant.now() catch unreachable;
}

fn updateUniformBuffer(current_image: usize) void {
    init_timer.call();

    const now = std.time.Instant.now() catch unreachable;
    const time_ns: f32 = @floatFromInt(now.since(start_time));
    const time_s: f32 = time_ns / std.time.ns_per_s;

    const aspect = @as(f32, @floatFromInt(swapchain.extent.width)) / @as(f32, @floatFromInt(swapchain.extent.height));

    var ubo = UniformBufferObject{
        .model = math.rotateZ(90 * std.math.rad_per_deg * time_s),
        .view = math.lookAt(
            .{ .x = 2, .y = 2, .z = 2 },
            .{ .x = 0, .y = 0, .z = 0 },
            .{ .x = 0, .y = 0, .z = 1 },
        ),
        .projection = math.perspective(
            45 * std.math.rad_per_deg,
            aspect,
            0.1,
            10,
        ),
    };

    ubo.projection[1][1] *= -1;

    @memcpy(uniform_buffers_mapped[current_image], &[_]UniformBufferObject{ubo});
}

fn recreateSwapChain() !void {
    var width: c_int = 0;
    var height: c_int = 0;
    c.glfwGetFramebufferSize(window.handle, &width, &height);
    while (width == 0 or height == 0) {
        c.glfwGetFramebufferSize(window.handle, width, height);
        c.glfwWaitEvents();
    }
    _ = c.vkDeviceWaitIdle(device.handle);

    destroyFrameBuffers();

    swapchain.destroy(device.handle, gpa);
    swapchain = try SwapChain.create(
        device.handle,
        physical_device.queue_families,
        physical_device.swapchain_support,
        window,
        surface,
        gpa,
    );

    try createFrameBuffers();
}

fn createFrameBuffers() !void {
    swapchain_frame_buffers = try gpa.alloc(c.VkFramebuffer, swapchain.image_views.len);

    for (swapchain.image_views, swapchain_frame_buffers) |image_view, *frame_buffer| {
        const frame_buffer_info = c.VkFramebufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = render_pass.handle,
            .attachmentCount = 1,
            .pAttachments = &image_view,
            .width = swapchain.extent.width,
            .height = swapchain.extent.height,
            .layers = 1,
        };
        if (c.vkCreateFramebuffer(device.handle, &frame_buffer_info, null, frame_buffer) != c.VK_SUCCESS) {
            return error.VKCreateFrameBufferFailed;
        }
    }
}

fn destroyFrameBuffers() void {
    for (swapchain_frame_buffers) |frame_buffer| {
        c.vkDestroyFramebuffer(device.handle, frame_buffer, null);
    }
    gpa.free(swapchain_frame_buffers);
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
        .renderPass = render_pass.handle,
        .framebuffer = swapchain_frame_buffers[@intCast(image_index)],
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = swapchain.extent,
        },
        .clearValueCount = 1,
        .pClearValues = &clear_color,
    };

    c.vkCmdBeginRenderPass(cmd_buffer, &render_pass_info, c.VK_SUBPASS_CONTENTS_INLINE);

    c.vkCmdBindPipeline(cmd_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, graphics_pipeline.handle);

    const viewport = c.VkViewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(swapchain.extent.width),
        .height = @floatFromInt(swapchain.extent.height),
        .minDepth = 0,
        .maxDepth = 1,
    };
    c.vkCmdSetViewport(cmd_buffer, 0, 1, &viewport);

    const scissor = c.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = swapchain.extent,
    };
    c.vkCmdSetScissor(cmd_buffer, 0, 1, &scissor);

    c.vkCmdBindVertexBuffers(cmd_buffer, 0, 1, &vertex_buffer.handle, &@as(u64, 0));

    c.vkCmdBindIndexBuffer(cmd_buffer, index_buffer.handle, 0, c.VK_INDEX_TYPE_UINT16);

    c.vkCmdBindDescriptorSets(
        cmd_buffer,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        graphics_pipeline.layout,
        0,
        1,
        &descriptor_sets,
        0,
        null,
    );

    c.vkCmdDrawIndexed(cmd_buffer, indices.len, 1, 0, 0, 0);

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
        if (c.vkCreateSemaphore(device.handle, &semaphore_info, null, &image_available_semaphores[i]) != c.VK_SUCCESS or
            c.vkCreateSemaphore(device.handle, &semaphore_info, null, &render_finished_semaphores[i]) != c.VK_SUCCESS or
            c.vkCreateFence(device.handle, &fence_info, null, &in_flight_fences[i]) != c.VK_SUCCESS)
            return error.VKCreateSyncObjectFailed;
    }
}

fn destroySyncObjects() void {
    for (0..max_frames_in_flight) |i| {
        c.vkDestroySemaphore(device.handle, image_available_semaphores[i], null);
        c.vkDestroySemaphore(device.handle, render_finished_semaphores[i], null);
        c.vkDestroyFence(device.handle, in_flight_fences[i], null);
    }
}

const UniformBufferObject = struct {
    model: Matrix,
    view: Matrix,
    projection: Matrix,
};

var descriptor_set_layout: c.VkDescriptorSetLayout = undefined;

fn createDescriptorSetLayout() !void {
    const ubo_layout_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 0,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
        .pImmutableSamplers = null,
    };

    const layout_info = c.VkDescriptorSetLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 1,
        .pBindings = &ubo_layout_binding,
    };

    if (c.vkCreateDescriptorSetLayout(device.handle, &layout_info, null, &descriptor_set_layout) != c.VK_SUCCESS) {
        return error.VKCreateDescriptorSetLayoutFailed;
    }
}

var uniform_buffers: [max_frames_in_flight]Buffer = undefined;
var uniform_buffers_mapped: [max_frames_in_flight][*]UniformBufferObject = undefined;

fn createUniformBuffers() !void {
    const buffer_size = @sizeOf(UniformBufferObject);

    for (&uniform_buffers, &uniform_buffers_mapped) |*buffer, *mapped| {
        buffer.* = try Buffer.create(
            buffer_size,
            c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            device.handle,
            physical_device.mem_properties,
        );

        _ = c.vkMapMemory(device.handle, buffer.memory, 0, buffer_size, 0, @ptrCast(mapped));
    }
}

fn destroyUniformBuffers() void {
    for (uniform_buffers) |buffer| {
        buffer.destroy(device.handle);
    }
}

var descriptor_pool: c.VkDescriptorPool = undefined;

fn createDescriptorPool() !void {
    const pool_size = c.VkDescriptorPoolSize{
        .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = max_frames_in_flight,
    };

    const pool_info = c.VkDescriptorPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .poolSizeCount = 1,
        .pPoolSizes = &pool_size,
        .maxSets = max_frames_in_flight,
    };

    if (c.vkCreateDescriptorPool(device.handle, &pool_info, null, &descriptor_pool) != c.VK_SUCCESS) {
        return error.VKCreateDescriptorPoolFailed;
    }
}

var descriptor_sets: [max_frames_in_flight]c.VkDescriptorSet = undefined;

fn createDescriptorSets() !void {
    const layouts = [_]c.VkDescriptorSetLayout{descriptor_set_layout} ** max_frames_in_flight;
    const alloc_info = c.VkDescriptorSetAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = descriptor_pool,
        .descriptorSetCount = max_frames_in_flight,
        .pSetLayouts = &layouts,
    };

    if (c.vkAllocateDescriptorSets(device.handle, &alloc_info, &descriptor_sets) != c.VK_SUCCESS) {
        return error.VKAllocateDescriptorSetsFailed;
    }

    for (0..max_frames_in_flight) |i| {
        const buffer_info = c.VkDescriptorBufferInfo{
            .buffer = uniform_buffers[i].handle,
            .offset = 0,
            .range = @sizeOf(UniformBufferObject),
        };

        const descriptor_write = c.VkWriteDescriptorSet{
            .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = descriptor_sets[i],
            .dstBinding = 0,
            .dstArrayElement = 0,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 1,
            .pBufferInfo = &buffer_info,
            .pImageInfo = null,
            .pTexelBufferView = null,
        };

        c.vkUpdateDescriptorSets(device.handle, 1, &descriptor_write, 0, null);
    }
}
