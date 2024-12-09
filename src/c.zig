pub usingnamespace @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", "");
    @cInclude("GLFW/glfw3.h");
    @cInclude("stb_image.h");
    @cInclude("tinyobj_loader_c.h");

    // @cDefine("GLM_FORCE_DEPTH_ZERO_TO_ONE", "");
    // @cInclude("glm/vec4.hpp");
    // @cInclude("glm/mat4x4.hpp");
});
