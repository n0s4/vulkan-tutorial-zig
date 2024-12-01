const std = @import("std");
const c = @import("c.zig");
const math = @import("math.zig");

const App = @import("App.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    var app: App = undefined;
    try app.init(gpa.allocator());
    defer app.deinit();

    try app.run();
}
