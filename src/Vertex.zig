const Vertex = @This();

const std = @import("std");
const c = @import("c.zig");

pos: [3]f32,
color: [3]f32,
tex_coord: [2]f32,

pub const binding_description = c.VkVertexInputBindingDescription{
    .binding = 0,
    .stride = @sizeOf(Vertex),
    .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
};

pub const attribute_descriptions = [3]c.VkVertexInputAttributeDescription{
    // position attribute
    c.VkVertexInputAttributeDescription{
        .binding = 0,
        .location = 0,
        .format = c.VK_FORMAT_R32G32B32_SFLOAT,
        .offset = @offsetOf(Vertex, "pos"),
    },
    // color attribute
    c.VkVertexInputAttributeDescription{
        .binding = 0,
        .location = 1,
        .format = c.VK_FORMAT_R32G32B32_SFLOAT,
        .offset = @offsetOf(Vertex, "color"),
    },
    // texture coordinate
    c.VkVertexInputAttributeDescription{
        .binding = 0,
        .location = 2,
        .format = c.VK_FORMAT_R32G32_SFLOAT,
        .offset = @offsetOf(Vertex, "tex_coord"),
    },
};

pub const HashContext = struct {
    pub fn hash(_: HashContext, vertex: Vertex) u64 {
        var wyhash = std.hash.Wyhash.init(0);
        for (vertex.pos) |v| {
            wyhash.update(std.mem.asBytes(&v));
        }
        for (vertex.tex_coord) |v| {
            wyhash.update(std.mem.asBytes(&v));
        }
        for (vertex.color) |v| {
            wyhash.update(std.mem.asBytes(&v));
        }
        return wyhash.final();
    }

    pub fn eql(_: HashContext, a: Vertex, b: Vertex) bool {
        return std.meta.eql(a, b);
    }
};
