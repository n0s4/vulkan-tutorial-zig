const App = @This();

const std = @import("std");
const c = @import("c.zig");
const math = @import("math.zig");

const Allocator = std.mem.Allocator;
const Window = @import("Window.zig");
const Instance = @import("Instance.zig");
const DebugMessenger = @import("DebugMessenger.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");
const Device = @import("Device.zig");
const SwapChain = @import("SwapChain.zig");
const RenderPass = @import("RenderPass.zig");
const GraphicsPipeline = @import("GraphicsPipeline.zig");
const CommandPool = @import("CommandPool.zig");
const Image = @import("Image.zig");
const Vertex = @import("Vertex.zig");
const Buffer = @import("Buffer.zig");
const createImageView = @import("image_view.zig").create;

const Matrix = math.Matrix;

const vertices = [_]Vertex{
    .{ .pos = .{ -0.5, -0.5, 0 }, .color = .{ 1, 0, 0 }, .tex_coord = .{ 1, 0 } },
    .{ .pos = .{ 0.5, -0.5, 0 }, .color = .{ 0, 1, 0 }, .tex_coord = .{ 0, 0 } },
    .{ .pos = .{ 0.5, 0.5, 0 }, .color = .{ 0, 0, 1 }, .tex_coord = .{ 0, 1 } },
    .{ .pos = .{ -0.5, 0.5, 0 }, .color = .{ 1, 1, 1 }, .tex_coord = .{ 1, 1 } },

    .{ .pos = .{ -0.5, -0.5, -0.5 }, .color = .{ 1, 0, 0 }, .tex_coord = .{ 1, 0 } },
    .{ .pos = .{ 0.5, -0.5, -0.5 }, .color = .{ 0, 1, 0 }, .tex_coord = .{ 0, 0 } },
    .{ .pos = .{ 0.5, 0.5, -0.5 }, .color = .{ 0, 0, 1 }, .tex_coord = .{ 0, 1 } },
    .{ .pos = .{ -0.5, 0.5, -0.5 }, .color = .{ 1, 1, 1 }, .tex_coord = .{ 1, 1 } },
};

const indices =
    [6]u16{ 0, 1, 2, 2, 3, 0 } ++
    [6]u16{ 4, 5, 6, 6, 7, 4 };

const max_frames_in_flight = 2;

const enable_validation_layers = @import("builtin").mode == .Debug;

const validation_layers: []const [*:0]const u8 = if (enable_validation_layers) &validation_layer_names else &.{};

const validation_layer_names = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const device_extensions = [_][*:0]const u8{
    c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

const UniformBufferObject = struct {
    model: Matrix,
    view: Matrix,
    projection: Matrix,
};

gpa: Allocator,
window: Window,
instance: Instance,
debug_messenger: if (enable_validation_layers) DebugMessenger else void,
physical_device: PhysicalDevice,
device: Device,
surface: c.VkSurfaceKHR,
swapchain: SwapChain,
render_pass: RenderPass,
graphics_pipeline: GraphicsPipeline,
frame_buffers: []const c.VkFramebuffer = &.{},
command_pool: CommandPool,
texture: Image,
texture_view: c.VkImageView,
texture_sampler: c.VkSampler,
depth_format: c.VkFormat,
depth_image: Image,
depth_view: c.VkImageView,
vertex_buffer: Buffer,
index_buffer: Buffer,
image_available_semaphores: [max_frames_in_flight]c.VkSemaphore,
render_finished_semaphores: [max_frames_in_flight]c.VkSemaphore,
in_flight_fences: [max_frames_in_flight]c.VkFence,
descriptor_pool: c.VkDescriptorPool,
descriptor_set_layout: c.VkDescriptorSetLayout,
descriptor_sets: [max_frames_in_flight]c.VkDescriptorSet,
uniform_buffers: [max_frames_in_flight]Buffer,
uniform_buffers_mapped: [max_frames_in_flight][*]UniformBufferObject,
start_time: std.time.Instant,
current_frame: usize = 0,
frame_buffer_did_resize: bool = false,

// Would prefer this to return an App, but due to the window (or rather, GLFW) holding a pointer to
// `frame_buffer_did_resize`, we need the memory to live after the function.
pub fn init(app: *App, gpa: Allocator) !void {
    const window = try Window.create(&app.frame_buffer_did_resize);
    const instance = try Instance.create(validation_layers, gpa);
    const debug_messenger = if (enable_validation_layers) try DebugMessenger.create(instance.handle) else {};
    const surface = try window.createSurface(instance.handle);
    const physical_device = try PhysicalDevice.selectAndCreate(
        instance.handle,
        surface,
        &device_extensions,
        gpa,
    );
    const device = try Device.create(physical_device, validation_layers, &device_extensions, gpa);
    const swapchain = try SwapChain.create(
        device.handle,
        physical_device.queue_families,
        physical_device.swapchain_support,
        window,
        surface,
        gpa,
    );
    const depth_format = PhysicalDevice.findSupportedFormat(
        physical_device.handle,
        &.{
            c.VK_FORMAT_D32_SFLOAT,
            c.VK_FORMAT_D32_SFLOAT_S8_UINT,
            c.VK_FORMAT_D24_UNORM_S8_UINT,
        },
        c.VK_IMAGE_TILING_OPTIMAL,
        c.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT,
    ) orelse {
        return error.NoSuitableDepthFormat;
    };
    const render_pass = try RenderPass.create(device.handle, swapchain.format, depth_format);
    const descriptor_set_layout = try createDescriptorSetLayout(device.handle);
    const graphics_pipeline = try GraphicsPipeline.create(
        device.handle,
        render_pass.handle,
        descriptor_set_layout,
        swapchain.extent,
    );
    const command_pool = try CommandPool.create(
        device.handle,
        physical_device.queue_families,
        max_frames_in_flight,
        gpa,
    );
    const raw_image = @embedFile("texture.jpg").*;
    const texture = try createTextureImage(
        &raw_image,
        device.handle,
        physical_device.mem_props,
        command_pool.handle,
        device.graphics_queue,
    );
    const texture_view = try createImageView(
        texture.handle,
        c.VK_FORMAT_R8G8B8A8_SRGB,
        c.VK_IMAGE_ASPECT_COLOR_BIT,
        device.handle,
    );
    const texture_sampler = try createTextureSampler(device.handle, physical_device.properties);
    const vertex_buffer = try createDeviceLocalBuffer(
        Vertex,
        &vertices,
        c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        device.handle,
        physical_device.mem_props,
        command_pool.handle,
        device.graphics_queue,
    );
    const depth_image = try Image.create(
        swapchain.extent.width,
        swapchain.extent.height,
        depth_format,
        c.VK_IMAGE_TILING_OPTIMAL,
        c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
        c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        device.handle,
        physical_device.mem_props,
    );
    const depth_view = try createImageView(
        depth_image.handle,
        depth_format,
        c.VK_IMAGE_ASPECT_DEPTH_BIT,
        device.handle,
    );
    const frame_buffers = try createFrameBuffers(
        swapchain.image_views,
        depth_view,
        swapchain.extent,
        render_pass.handle,
        device.handle,
        gpa,
    );
    const index_buffer = try createDeviceLocalBuffer(
        u16,
        &indices,
        c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        device.handle,
        physical_device.mem_props,
        command_pool.handle,
        device.graphics_queue,
    );
    var uniform_buffers: [max_frames_in_flight]Buffer = undefined;
    var uniform_buffers_mapped: [max_frames_in_flight][*]UniformBufferObject = undefined;
    try createUniformBuffers(
        &uniform_buffers,
        &uniform_buffers_mapped,
        device.handle,
        physical_device.mem_props,
    );
    const descriptor_pool = try createDescriptorPool(device.handle);
    const descriptor_sets = try createDescriptorSets(
        descriptor_pool,
        descriptor_set_layout,
        &uniform_buffers,
        texture_view,
        texture_sampler,
        device.handle,
    );
    var image_available_semaphores: [max_frames_in_flight]c.VkSemaphore = undefined;
    var render_finished_semaphores: [max_frames_in_flight]c.VkSemaphore = undefined;
    var in_flight_fences: [max_frames_in_flight]c.VkFence = undefined;
    try createSyncObjects(
        device.handle,
        &image_available_semaphores,
        &render_finished_semaphores,
        &in_flight_fences,
    );

    app.* = App{
        .gpa = gpa,
        .window = window,
        .surface = surface,
        .instance = instance,
        .debug_messenger = debug_messenger,
        .physical_device = physical_device,
        .device = device,
        .swapchain = swapchain,
        .render_pass = render_pass,
        .descriptor_set_layout = descriptor_set_layout,
        .graphics_pipeline = graphics_pipeline,
        .frame_buffers = frame_buffers,
        .command_pool = command_pool,
        .depth_format = depth_format,
        .depth_image = depth_image,
        .depth_view = depth_view,
        .texture = texture,
        .texture_view = texture_view,
        .texture_sampler = texture_sampler,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .uniform_buffers = uniform_buffers,
        .uniform_buffers_mapped = uniform_buffers_mapped,
        .descriptor_pool = descriptor_pool,
        .descriptor_sets = descriptor_sets,
        .image_available_semaphores = image_available_semaphores,
        .render_finished_semaphores = render_finished_semaphores,
        .in_flight_fences = in_flight_fences,
        .start_time = std.time.Instant.now() catch unreachable,
    };
}

pub fn deinit(app: *const App) void {
    const device = app.device.handle;
    const gpa = app.gpa;
    for (
        app.image_available_semaphores,
        app.render_finished_semaphores,
        app.in_flight_fences,
    ) |image_available_semaphore, render_finished_semaphore, in_flight_fence| {
        c.vkDestroySemaphore(device, image_available_semaphore, null);
        c.vkDestroySemaphore(device, render_finished_semaphore, null);
        c.vkDestroyFence(device, in_flight_fence, null);
    }
    c.vkDestroyDescriptorPool(device, app.descriptor_pool, null);
    for (app.uniform_buffers) |uniform_buffer| {
        c.vkUnmapMemory(device, uniform_buffer.memory);
        uniform_buffer.destroy(device);
    }
    app.depth_image.destroy(device);
    c.vkDestroyImageView(device, app.depth_view, null);
    app.index_buffer.destroy(device);
    app.vertex_buffer.destroy(device);
    app.texture.destroy(device);
    c.vkDestroySampler(device, app.texture_sampler, null);
    c.vkDestroyImageView(device, app.texture_view, null);
    app.command_pool.destroy(device, gpa);
    destroyFrameBuffers(app.frame_buffers, device, gpa);
    app.graphics_pipeline.destroy(device);
    c.vkDestroyDescriptorSetLayout(device, app.descriptor_set_layout, null);
    app.render_pass.destroy(device);
    app.swapchain.destroy(device, gpa);
    app.device.destroy();
    app.physical_device.deinit(gpa);
    c.vkDestroySurfaceKHR(app.instance.handle, app.surface, null);
    if (enable_validation_layers) {
        app.debug_messenger.destroy(app.instance.handle);
    }
    app.instance.destroy();
    app.window.deinit();
}

pub fn run(app: *App) !void {
    while (c.glfwWindowShouldClose(app.window.handle) == c.GLFW_FALSE) {
        c.glfwPollEvents();
        try app.drawFrame();
    }
    _ = c.vkDeviceWaitIdle(app.device.handle);
}

fn drawFrame(app: *App) !void {
    _ = c.vkWaitForFences(app.device.handle, 1, &app.in_flight_fences[app.current_frame], c.VK_TRUE, std.math.maxInt(u64));

    var image_index: u32 = 0;
    var result = c.vkAcquireNextImageKHR(
        app.device.handle,
        app.swapchain.handle,
        std.math.maxInt(u64),
        app.image_available_semaphores[app.current_frame],
        @ptrCast(c.VK_NULL_HANDLE),
        &image_index,
    );

    if (result == c.VK_ERROR_OUT_OF_DATE_KHR) {
        try app.recreateSwapChain();
        return;
    } else if (result != c.VK_SUCCESS and result != c.VK_SUBOPTIMAL_KHR) {
        return error.VkAcquireNextImageFailed;
    }

    // Only reset the fence if we know we are submitting work.
    _ = c.vkResetFences(app.device.handle, 1, &app.in_flight_fences[app.current_frame]);

    _ = c.vkResetCommandBuffer(app.command_pool.buffers[app.current_frame], 0);
    try app.recordCommandBuffer(image_index);

    updateUniformBuffer(
        @ptrCast(app.uniform_buffers_mapped[app.current_frame]),
        app.start_time,
        app.swapchain.extent,
    );

    const submit_info = c.VkSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &app.image_available_semaphores[app.current_frame],
        .pWaitDstStageMask = &@intCast(c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
        .commandBufferCount = 1,
        .pCommandBuffers = &app.command_pool.buffers[app.current_frame],
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &app.render_finished_semaphores[app.current_frame],
    };

    if (c.vkQueueSubmit(app.device.graphics_queue, 1, &submit_info, app.in_flight_fences[app.current_frame]) != c.VK_SUCCESS) {
        return error.VKQueueSubmitFailed;
    }

    const present_info = c.VkPresentInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &app.render_finished_semaphores[app.current_frame],
        .swapchainCount = 1,
        .pSwapchains = &app.swapchain.handle,
        .pImageIndices = &image_index,
        .pResults = null,
    };

    result = c.vkQueuePresentKHR(app.device.graphics_queue, &present_info);

    if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR or app.frame_buffer_did_resize) {
        app.frame_buffer_did_resize = false;
        try app.recreateSwapChain();
    } else if (result != c.VK_SUCCESS) {
        return error.VKQueuePresentFailed;
    }

    app.current_frame = (app.current_frame + 1) % max_frames_in_flight;
}

fn recordCommandBuffer(app: *const App, image_index: u32) !void {
    const cmd_buffer = app.command_pool.buffers[app.current_frame];
    const begin_info = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = 0,
        .pInheritanceInfo = null,
    };

    if (c.vkBeginCommandBuffer(cmd_buffer, &begin_info) != c.VK_SUCCESS) {
        return error.VKBeginCommandBufferFailed;
    }

    const clear_values = [2]c.VkClearValue{
        .{ .color = .{ .float32 = .{0} ** 4 } },
        .{ .depthStencil = c.VkClearDepthStencilValue{ .depth = 1, .stencil = 0 } },
    };

    const render_pass_info = c.VkRenderPassBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = app.render_pass.handle,
        .framebuffer = app.frame_buffers[@intCast(image_index)],
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = app.swapchain.extent,
        },
        .clearValueCount = clear_values.len,
        .pClearValues = &clear_values,
    };

    c.vkCmdBeginRenderPass(cmd_buffer, &render_pass_info, c.VK_SUBPASS_CONTENTS_INLINE);

    c.vkCmdBindPipeline(cmd_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, app.graphics_pipeline.handle);

    const viewport = c.VkViewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(app.swapchain.extent.width),
        .height = @floatFromInt(app.swapchain.extent.height),
        .minDepth = 0,
        .maxDepth = 1,
    };
    c.vkCmdSetViewport(cmd_buffer, 0, 1, &viewport);

    const scissor = c.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = app.swapchain.extent,
    };
    c.vkCmdSetScissor(cmd_buffer, 0, 1, &scissor);

    c.vkCmdBindVertexBuffers(cmd_buffer, 0, 1, &app.vertex_buffer.handle, &@as(u64, 0));

    c.vkCmdBindIndexBuffer(cmd_buffer, app.index_buffer.handle, 0, c.VK_INDEX_TYPE_UINT16);

    c.vkCmdBindDescriptorSets(
        cmd_buffer,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        app.graphics_pipeline.layout,
        0,
        1,
        &app.descriptor_sets,
        0,
        null,
    );

    c.vkCmdDrawIndexed(cmd_buffer, indices.len, 1, 0, 0, 0);

    c.vkCmdEndRenderPass(cmd_buffer);

    if (c.vkEndCommandBuffer(cmd_buffer) != c.VK_SUCCESS) {
        return error.VkEndCommandBufferFailed;
    }
}

fn recreateSwapChain(app: *App) !void {
    var width: c_int = 0;
    var height: c_int = 0;
    c.glfwGetFramebufferSize(app.window.handle, &width, &height);
    while (width == 0 or height == 0) {
        c.glfwGetFramebufferSize(app.window.handle, &width, &height);
        c.glfwWaitEvents();
    }
    _ = c.vkDeviceWaitIdle(app.device.handle);

    destroyFrameBuffers(app.frame_buffers, app.device.handle, app.gpa);

    app.swapchain.destroy(app.device.handle, app.gpa);
    app.swapchain = try SwapChain.create(
        app.device.handle,
        app.physical_device.queue_families,
        app.physical_device.swapchain_support,
        app.window,
        app.surface,
        app.gpa,
    );

    app.depth_image.destroy(app.device.handle);
    c.vkDestroyImageView(app.device.handle, app.depth_view, null);
    app.depth_image = try Image.create(
        app.swapchain.extent.width,
        app.swapchain.extent.height,
        app.depth_format,
        c.VK_IMAGE_TILING_OPTIMAL,
        c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
        c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        app.device.handle,
        app.physical_device.mem_props,
    );
    app.depth_view = try createImageView(
        app.depth_image.handle,
        app.depth_format,
        c.VK_IMAGE_ASPECT_DEPTH_BIT,
        app.device.handle,
    );

    app.frame_buffers = try createFrameBuffers(
        app.swapchain.image_views,
        app.depth_view,
        app.swapchain.extent,
        app.render_pass.handle,
        app.device.handle,
        app.gpa,
    );
}

fn updateUniformBuffer(ubo: *UniformBufferObject, start_time: std.time.Instant, extent: c.VkExtent2D) void {
    const now = std.time.Instant.now() catch unreachable;
    const time_ns: f32 = @floatFromInt(now.since(start_time));
    const time_s: f32 = time_ns / std.time.ns_per_s;

    const aspect = @as(f32, @floatFromInt(extent.width)) / @as(f32, @floatFromInt(extent.height));

    var new_ubo = UniformBufferObject{
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

    new_ubo.projection[1][1] *= -1;

    ubo.* = new_ubo;
}

fn createDescriptorSetLayout(device: c.VkDevice) !c.VkDescriptorSetLayout {
    const ubo_layout_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 0,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
        .pImmutableSamplers = null,
    };

    const sampler_layout_binding = c.VkDescriptorSetLayoutBinding{
        .binding = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 1,
        .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .pImmutableSamplers = null,
    };

    const bindings = [_]c.VkDescriptorSetLayoutBinding{ ubo_layout_binding, sampler_layout_binding };

    const layout_info = c.VkDescriptorSetLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = bindings.len,
        .pBindings = &bindings,
    };

    var layout: c.VkDescriptorSetLayout = undefined;
    if (c.vkCreateDescriptorSetLayout(device, &layout_info, null, &layout) != c.VK_SUCCESS) {
        return error.VKCreateDescriptorSetLayoutFailed;
    }

    return layout;
}

fn createFrameBuffers(
    image_views: []const c.VkImageView,
    depth_view: c.VkImageView,
    extent: c.VkExtent2D,
    render_pass: c.VkRenderPass,
    device: c.VkDevice,
    gpa: Allocator,
) ![]const c.VkFramebuffer {
    const frame_buffers = try gpa.alloc(c.VkFramebuffer, image_views.len);

    for (image_views, frame_buffers) |image_view, *frame_buffer| {
        const attachments = [_]c.VkImageView{
            image_view,
            depth_view,
        };
        const frame_buffer_info = c.VkFramebufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = render_pass,
            .attachmentCount = attachments.len,
            .pAttachments = &attachments,
            .width = extent.width,
            .height = extent.height,
            .layers = 1,
        };
        if (c.vkCreateFramebuffer(device, &frame_buffer_info, null, frame_buffer) != c.VK_SUCCESS) {
            return error.VKCreateFrameBufferFailed;
        }
    }

    return frame_buffers;
}

fn destroyFrameBuffers(framebuffers: []const c.VkFramebuffer, device: c.VkDevice, gpa: Allocator) void {
    for (framebuffers) |framebuffer| {
        c.vkDestroyFramebuffer(device, framebuffer, null);
    }
    gpa.free(framebuffers);
}

fn createDeviceLocalBuffer(
    T: type,
    data: []const T,
    usage: c.VkBufferUsageFlags,
    device: c.VkDevice,
    device_mem_props: c.VkPhysicalDeviceMemoryProperties,
    command_pool: c.VkCommandPool,
    transfer_queue: c.VkQueue,
) !Buffer {
    const size: c.VkDeviceSize = @sizeOf(T) * data.len;
    const staging_buffer = try Buffer.create(
        size,
        c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        device,
        device_mem_props,
    );
    defer staging_buffer.destroy(device);

    var mapped_mem: [*]T = undefined;
    _ = c.vkMapMemory(device, staging_buffer.memory, 0, size, 0, @ptrCast(&mapped_mem));
    @memcpy(mapped_mem, data);
    c.vkUnmapMemory(device, staging_buffer.memory);

    const buffer = try Buffer.create(
        size,
        usage | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        device,
        device_mem_props,
    );

    copyBuffer(
        staging_buffer.handle,
        buffer.handle,
        size,
        device,
        transfer_queue,
        command_pool,
    );

    return buffer;
}

fn copyBuffer(
    from: c.VkBuffer,
    to: c.VkBuffer,
    size: c.VkDeviceSize,
    device: c.VkDevice,
    transfer_queue: c.VkQueue,
    command_pool: c.VkCommandPool,
) void {
    const command_buffer = beginSingleTimeCommands(command_pool, device);
    defer endSingleTimeCommands(command_buffer, command_pool, transfer_queue, device);

    const copy = c.VkBufferCopy{ .size = size };
    c.vkCmdCopyBuffer(command_buffer, from, to, 1, &copy);
}

fn createTextureImage(
    raw_image: []const u8,
    device: c.VkDevice,
    device_mem_props: c.VkPhysicalDeviceMemoryProperties,
    command_pool: c.VkCommandPool,
    queue: c.VkQueue,
) !Image {
    var tex_width: u32 = undefined;
    var tex_height: u32 = undefined;
    var tex_channels: u32 = undefined;
    const pixels = c.stbi_load_from_memory(
        raw_image.ptr,
        @intCast(raw_image.len),
        @ptrCast(&tex_width),
        @ptrCast(&tex_height),
        @ptrCast(&tex_channels),
        c.STBI_rgb_alpha,
    ) orelse {
        return error.STBILoadTextureImageFailed;
    };
    const image_size: c.VkDeviceSize = 4 * tex_width * tex_height;

    const staging_buffer = try Buffer.create(
        image_size,
        c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        device,
        device_mem_props,
    );
    defer staging_buffer.destroy(device);

    var data: [*]u8 = undefined;
    _ = c.vkMapMemory(device, staging_buffer.memory, 0, image_size, 0, @ptrCast(&data));
    @memcpy(data, pixels[0..image_size]);
    c.vkUnmapMemory(device, staging_buffer.memory);

    c.stbi_image_free(pixels);

    const texture_image = try Image.create(
        tex_width,
        tex_height,
        c.VK_FORMAT_R8G8B8A8_SRGB,
        c.VK_IMAGE_TILING_OPTIMAL,
        c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT,
        c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        device,
        device_mem_props,
    );

    transitionImageLayout(
        texture_image.handle,
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        device,
        command_pool,
        queue,
    );

    copyBufferToImage(
        staging_buffer.handle,
        texture_image.handle,
        tex_width,
        tex_height,
        device,
        command_pool,
        queue,
    );

    transitionImageLayout(
        texture_image.handle,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        device,
        command_pool,
        queue,
    );

    return texture_image;
}

fn transitionImageLayout(
    image: c.VkImage,
    old_layout: c.VkImageLayout,
    new_layout: c.VkImageLayout,
    device: c.VkDevice,
    command_pool: c.VkCommandPool,
    queue: c.VkQueue,
) void {
    const command_buffer = beginSingleTimeCommands(command_pool, device);
    defer endSingleTimeCommands(command_buffer, command_pool, queue, device);

    var source_stage: c.VkPipelineStageFlags = undefined;
    var source_access: c.VkAccessFlags = undefined;
    var dest_stage: c.VkPipelineStageFlags = undefined;
    var dest_access: c.VkAccessFlags = undefined;

    if (old_layout == c.VK_IMAGE_LAYOUT_UNDEFINED and
        new_layout == c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)
    {
        source_stage = c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        source_access = 0;
        dest_stage = c.VK_PIPELINE_STAGE_TRANSFER_BIT;
        dest_access = c.VK_ACCESS_TRANSFER_WRITE_BIT;
    } else if (old_layout == c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL and
        new_layout == c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)
    {
        source_stage = c.VK_PIPELINE_STAGE_TRANSFER_BIT;
        source_access = c.VK_ACCESS_TRANSFER_WRITE_BIT;
        dest_stage = c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
        dest_access = c.VK_ACCESS_SHADER_READ_BIT;
    } else {
        @panic("unsupported image layout transition");
    }

    const barrier = c.VkImageMemoryBarrier{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .oldLayout = old_layout,
        .newLayout = new_layout,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresourceRange = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .srcAccessMask = source_access,
        .dstAccessMask = dest_access,
    };

    c.vkCmdPipelineBarrier(
        command_buffer,
        source_stage,
        dest_stage,
        0,
        0,
        null,
        0,
        null,
        1,
        &barrier,
    );
}

fn copyBufferToImage(
    buffer: c.VkBuffer,
    image: c.VkImage,
    width: u32,
    height: u32,
    device: c.VkDevice,
    command_pool: c.VkCommandPool,
    queue: c.VkQueue,
) void {
    const command_buffer = beginSingleTimeCommands(command_pool, device);
    defer endSingleTimeCommands(command_buffer, command_pool, queue, device);

    const region = c.VkBufferImageCopy{
        .bufferOffset = 0,
        .bufferRowLength = 0,
        .bufferImageHeight = 0,
        .imageSubresource = c.VkImageSubresourceLayers{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .mipLevel = 0,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
        .imageExtent = c.VkExtent3D{
            .width = width,
            .height = height,
            .depth = 1,
        },
    };

    c.vkCmdCopyBufferToImage(
        command_buffer,
        buffer,
        image,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        1,
        &region,
    );
}

fn beginSingleTimeCommands(command_pool: c.VkCommandPool, device: c.VkDevice) c.VkCommandBuffer {
    const alloc_info = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };

    var command_buffer: c.VkCommandBuffer = undefined;
    _ = c.vkAllocateCommandBuffers(device, &alloc_info, &command_buffer);

    const begin_info = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };

    _ = c.vkBeginCommandBuffer(command_buffer, &begin_info);

    return command_buffer;
}

fn endSingleTimeCommands(
    command_buffer: c.VkCommandBuffer,
    command_pool: c.VkCommandPool,
    queue: c.VkQueue,
    device: c.VkDevice,
) void {
    _ = c.vkEndCommandBuffer(command_buffer);

    const submit_info = c.VkSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &command_buffer,
    };
    _ = c.vkQueueSubmit(queue, 1, &submit_info, null);
    _ = c.vkQueueWaitIdle(queue);

    c.vkFreeCommandBuffers(device, command_pool, 1, &command_buffer);
}

fn createTextureSampler(
    device: c.VkDevice,
    device_properties: c.VkPhysicalDeviceProperties,
) !c.VkSampler {
    const sampler_info = c.VkSamplerCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = c.VK_FILTER_LINEAR,
        .minFilter = c.VK_FILTER_LINEAR,
        .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .anisotropyEnable = c.VK_TRUE,
        .maxAnisotropy = device_properties.limits.maxSamplerAnisotropy,
        .borderColor = c.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
        .unnormalizedCoordinates = c.VK_FALSE,
        .compareEnable = c.VK_FALSE,
        .compareOp = c.VK_COMPARE_OP_ALWAYS,
        .mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_LINEAR,
        .mipLodBias = 0,
        .minLod = 0,
        .maxLod = 0,
    };

    var sampler: c.VkSampler = undefined;
    if (c.vkCreateSampler(device, &sampler_info, null, &sampler) != c.VK_SUCCESS) {
        return error.VKCreateSamplerFailed;
    }

    return sampler;
}

fn createUniformBuffers(
    uniform_buffers: []Buffer,
    uniform_buffers_mapped: [][*]UniformBufferObject,
    device: c.VkDevice,
    device_mem_props: c.VkPhysicalDeviceMemoryProperties,
) !void {
    const buffer_size = @sizeOf(UniformBufferObject);

    for (uniform_buffers, uniform_buffers_mapped) |*buffer, *mapped| {
        buffer.* = try Buffer.create(
            buffer_size,
            c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            device,
            device_mem_props,
        );

        _ = c.vkMapMemory(device, buffer.memory, 0, buffer_size, 0, @ptrCast(mapped));
    }
}

fn createDescriptorPool(device: c.VkDevice) !c.VkDescriptorPool {
    const pool_sizes = [_]c.VkDescriptorPoolSize{ .{
        .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = max_frames_in_flight,
    }, .{
        .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = max_frames_in_flight,
    } };

    const pool_info = c.VkDescriptorPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .poolSizeCount = pool_sizes.len,
        .pPoolSizes = &pool_sizes,
        .maxSets = max_frames_in_flight,
    };

    var pool: c.VkDescriptorPool = undefined;
    if (c.vkCreateDescriptorPool(device, &pool_info, null, &pool) != c.VK_SUCCESS) {
        return error.VKCreateDescriptorPoolFailed;
    }

    return pool;
}

fn createDescriptorSets(
    pool: c.VkDescriptorPool,
    layout: c.VkDescriptorSetLayout,
    uniform_buffers: []const Buffer,
    texture_view: c.VkImageView,
    texture_sampler: c.VkSampler,
    device: c.VkDevice,
) ![max_frames_in_flight]c.VkDescriptorSet {
    const layouts = [_]c.VkDescriptorSetLayout{layout} ** max_frames_in_flight;
    const alloc_info = c.VkDescriptorSetAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = pool,
        .descriptorSetCount = max_frames_in_flight,
        .pSetLayouts = &layouts,
    };

    var descriptor_sets: [max_frames_in_flight]c.VkDescriptorSet = undefined;
    if (c.vkAllocateDescriptorSets(device, &alloc_info, &descriptor_sets) != c.VK_SUCCESS) {
        return error.VKAllocateDescriptorSetsFailed;
    }

    for (0..max_frames_in_flight) |i| {
        const buffer_info = c.VkDescriptorBufferInfo{
            .buffer = uniform_buffers[i].handle,
            .offset = 0,
            .range = @sizeOf(UniformBufferObject),
        };

        const image_info = c.VkDescriptorImageInfo{
            .imageView = texture_view,
            .sampler = texture_sampler,
            .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        };

        const descriptor_writes = [_]c.VkWriteDescriptorSet{ .{
            .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = descriptor_sets[i],
            .dstBinding = 0,
            .dstArrayElement = 0,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 1,
            .pBufferInfo = &buffer_info,
        }, .{
            .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = descriptor_sets[i],
            .dstBinding = 1,
            .dstArrayElement = 0,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .pImageInfo = &image_info,
        } };

        c.vkUpdateDescriptorSets(
            device,
            @intCast(descriptor_writes.len),
            &descriptor_writes,
            0,
            null,
        );
    }

    return descriptor_sets;
}

fn createSyncObjects(
    device: c.VkDevice,
    image_available_semaphores: *[max_frames_in_flight]c.VkSemaphore,
    render_finished_semaphores: *[max_frames_in_flight]c.VkSemaphore,
    in_flight_fences: *[max_frames_in_flight]c.VkFence,
) !void {
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
