const Vertex = @This();

const c = @import("c.zig");

pos: [2]f32,
color: [3]f32,

pub const binding_description = c.VkVertexInputBindingDescription{
    .binding = 0,
    .stride = @sizeOf(Vertex),
    .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
};

pub const attribute_descriptions = [2]c.VkVertexInputAttributeDescription{
    // position attribute
    c.VkVertexInputAttributeDescription{
        .binding = 0,
        .location = 0,
        .format = c.VK_FORMAT_R32G32_SFLOAT,
        .offset = @offsetOf(Vertex, "pos"),
    },
    // color attribute
    c.VkVertexInputAttributeDescription{
        .binding = 0,
        .location = 1,
        .format = c.VK_FORMAT_R32G32B32_SFLOAT,
        .offset = @offsetOf(Vertex, "color"),
    },
};
