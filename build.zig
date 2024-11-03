const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "vulkan",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    exe.linkSystemLibrary("glfw");
    exe.linkSystemLibrary("vulkan");

    b.installArtifact(exe);

    const shader_step = createShaderStep(b);
    exe.step.dependOn(shader_step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

const shader_names = [_][]const u8{ "vert", "frag" };
const shader_dir: []const u8 = "src/shaders";
const shader_out_dir: []const u8 = "src/shaders/compiled";

fn createShaderStep(b: *std.Build) *std.Build.Step {
    const step = b.step("shaders", "Compile shaders using glslc");

    inline for (shader_names) |shader_name| {
        const compile_cmd = b.addSystemCommand(&.{
            "glslc",
            b.fmt("{s}/shader.{s}", .{ shader_dir, shader_name }),
            "-o",
            b.fmt("{s}/{s}.spv", .{ shader_out_dir, shader_name }),
        });
        step.dependOn(&compile_cmd.step);
    }

    return step;
}
