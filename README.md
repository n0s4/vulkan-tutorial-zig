# Vulkan Tutorial in Zig

Tracking my progress through the [vulkan tutorial](https://docs.vulkan.org/tutorial/latest/) with [Zig](https://ziglang.org/).

Currently, I have just completed the "Loading Models" chapter.

![application screenshot](screenshot.png)

## Build Instructions

### Dependencies
- build-time dependencies:
  - [Zig](https://ziglang.org/download/) v0.14-dev...
  - [glslc](https://github.com/google/shaderc)
- runtime dependencies:
  - [glfw](https://www.glfw.org/)
  - [vulkan](https://vulkan.org/)

After all dependencies are available, simply run `zig build run` in the root of the repository.
