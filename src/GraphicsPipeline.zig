const GraphicsPipeline = @This();

const std = @import("std");
const c = @import("c.zig");

const Vertex = @import("Vertex.zig");

handle: c.VkPipeline,
layout: c.VkPipelineLayout,

pub fn create(
    device: c.VkDevice,
    render_pass: c.VkRenderPass,
    descriptor_set_layout: c.VkDescriptorSetLayout,
    swapchain_extent: c.VkExtent2D,
) !GraphicsPipeline {
    const vert_shader_code align(@alignOf(u32)) = @embedFile("shaders/compiled/vert.spv").*;
    const vert_shader_module = try createShaderModule(device, &vert_shader_code);
    defer c.vkDestroyShaderModule(device, vert_shader_module, null);

    const frag_shader_code align(@alignOf(u32)) = @embedFile("shaders/compiled/frag.spv").*;
    const frag_shader_module = try createShaderModule(device, &frag_shader_code);
    defer c.vkDestroyShaderModule(device, frag_shader_module, null);

    const shader_stages = [_]c.VkPipelineShaderStageCreateInfo{
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vert_shader_module,
            .pName = "main",
        },
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = frag_shader_module,
            .pName = "main",
        },
    };

    const vertex_input_info = c.VkPipelineVertexInputStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &Vertex.binding_description,
        .vertexAttributeDescriptionCount = Vertex.attribute_descriptions.len,
        .pVertexAttributeDescriptions = &Vertex.attribute_descriptions,
    };

    const input_assembly = c.VkPipelineInputAssemblyStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = c.VK_FALSE,
    };

    const viewport = c.VkViewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(swapchain_extent.width),
        .height = @floatFromInt(swapchain_extent.height),
        .minDepth = 0,
        .maxDepth = 1,
    };

    const scissor = c.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = swapchain_extent,
    };

    const dynamic_states = [_]c.VkDynamicState{
        c.VK_DYNAMIC_STATE_VIEWPORT,
        c.VK_DYNAMIC_STATE_SCISSOR,
    };

    const dynamic_state = c.VkPipelineDynamicStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = dynamic_states.len,
        .pDynamicStates = &dynamic_states,
    };

    const viewport_state = c.VkPipelineViewportStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .pViewports = &viewport,
        .scissorCount = 1,
        .pScissors = &scissor,
    };

    const rasterizer = c.VkPipelineRasterizationStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .depthClampEnable = c.VK_FALSE,
        .rasterizerDiscardEnable = c.VK_FALSE,
        .polygonMode = c.VK_POLYGON_MODE_FILL,
        .lineWidth = 1,
        .cullMode = c.VK_CULL_MODE_BACK_BIT,
        .frontFace = c.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        .depthBiasEnable = c.VK_FALSE,
    };

    const multisampling = c.VkPipelineMultisampleStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .sampleShadingEnable = c.VK_FALSE,
        .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
    };

    const depth_stencil = c.VkPipelineDepthStencilStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .depthTestEnable = c.VK_TRUE,
        .depthWriteEnable = c.VK_TRUE,
        .depthCompareOp = c.VK_COMPARE_OP_LESS,
        .depthBoundsTestEnable = c.VK_FALSE,
        .stencilTestEnable = c.VK_FALSE,
    };

    const color_blend_attachment = c.VkPipelineColorBlendAttachmentState{
        .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT |
            c.VK_COLOR_COMPONENT_G_BIT |
            c.VK_COLOR_COMPONENT_B_BIT |
            c.VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = c.VK_FALSE,
    };

    const color_blending = c.VkPipelineColorBlendStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .logicOpEnable = c.VK_FALSE,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
    };

    const pipeline_layout_info = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &descriptor_set_layout,
    };

    var layout: c.VkPipelineLayout = undefined;
    if (c.vkCreatePipelineLayout(device, &pipeline_layout_info, null, &layout) != c.VK_SUCCESS) {
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
        .pDepthStencilState = &depth_stencil,
        .pColorBlendState = &color_blending,
        .pDynamicState = &dynamic_state,
        .layout = layout,
        .renderPass = render_pass,
        .subpass = 0,
        .basePipelineHandle = @ptrCast(c.VK_NULL_HANDLE),
        .basePipelineIndex = 0,
    };

    var graphics_pipeline: c.VkPipeline = undefined;
    if (c.vkCreateGraphicsPipelines(
        device,
        @ptrCast(c.VK_NULL_HANDLE),
        1,
        &pipeline_info,
        null,
        &graphics_pipeline,
    ) != c.VK_SUCCESS) {
        return error.VkCreateGraphicsPipelinesFailed;
    }

    return GraphicsPipeline{
        .handle = graphics_pipeline,
        .layout = layout,
    };
}

pub fn destroy(graphics_pipeline: GraphicsPipeline, device: c.VkDevice) void {
    c.vkDestroyPipeline(device, graphics_pipeline.handle, null);
    c.vkDestroyPipelineLayout(device, graphics_pipeline.layout, null);
}

fn createShaderModule(device: c.VkDevice, code: []align(@alignOf(u32)) const u8) !c.VkShaderModule {
    const create_info = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code.len,
        .pCode = @ptrCast(code.ptr),
    };

    var shader_module: c.VkShaderModule = undefined;
    if (c.vkCreateShaderModule(device, &create_info, null, &shader_module) != c.VK_SUCCESS) {
        return error.VKCreateShaderModuleFailed;
    }

    return shader_module;
}
