# Vulkan Tutorial in Zig

An implementation of the [Vulkan Tutorial](https://docs.vulkan.org/tutorial/latest/) in [Zig](https://ziglang.org/), complete up to and including the "Multisampling" chapter.

This was written for my own learning, so you may find bugs. If you do, I'd be happy to fix them.

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

### Attribution

All the code in this repository is under the MIT license (`LICENSE.md`).

The viking room object and texture in the `assets/` directory were created by [nigelgoh](https://sketchfab.com/nigelgoh) and licensed under [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/).

