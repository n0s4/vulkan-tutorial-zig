const std = @import("std");

pub const Matrix = [4][4]f32;

pub const identity = Matrix{
    .{ 1, 0, 0, 0 },
    .{ 0, 1, 0, 0 },
    .{ 0, 0, 1, 0 },
    .{ 0, 0, 0, 1 },
};

pub fn rotateZ(radians: f32) Matrix {
    const sin = std.math.sin(radians);
    const cos = std.math.cos(radians);

    return Matrix{
        .{ cos, -sin, 0, 0 },
        .{ sin, cos, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };
}

// https://github.com/g-truc/glm/blob/33b4a621a697a305bc3a7610d290677b96beb181/glm/ext/matrix_transform.inl#L153
pub fn lookAt(eye: Vec, target: Vec, up: Vec) Matrix {
    const forward = target.minus(eye).norm();
    const right = forward.cross(up).norm();
    const true_up = right.cross(forward);

    return Matrix{
        .{ right.x, true_up.x, -forward.x, 0 },
        .{ right.y, true_up.y, -forward.y, 0 },
        .{ right.z, true_up.z, -forward.z, 0 },
        .{ -right.dot(eye), -true_up.dot(eye), forward.dot(eye), 1 },
    };
}

// https://github.com/g-truc/glm/blob/33b4a621a697a305bc3a7610d290677b96beb181/glm/ext/matrix_clip_space.inl#L249
pub fn perspective(fovy: f32, aspect: f32, znear: f32, zfar: f32) Matrix {
    const tan_half_fovy = std.math.tan(fovy / 2);

    return Matrix{
        .{ 1 / (aspect * tan_half_fovy), 0, 0, 0 },
        .{ 0, 1 / tan_half_fovy, 0, 0 },
        .{ 0, 0, zfar / (znear - zfar), -1 },
        .{ 0, 0, -(zfar * znear) / (zfar - znear), 1 },
    };
}

pub const Vec = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,

    pub fn minus(a: Vec, b: Vec) Vec {
        return Vec{
            .x = a.x - b.x,
            .y = a.y - b.y,
            .z = a.z - b.z,
        };
    }

    pub fn dot(a: Vec, b: Vec) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }

    test dot {
        const a = Vec{ .x = 1 };
        const b = Vec{ .y = 1 };
        const c = Vec{ .x = 1, .y = 1 };

        std.testing.expect(dot(a, b) == 0);
        std.testing.expect(dot(a, c) == 1);
    }

    pub fn cross(a: Vec, b: Vec) Vec {
        return Vec{
            .x = a.y * b.z - a.z * b.y,
            .y = a.z * b.x - a.x * b.z,
            .z = a.x * b.y - a.y * b.x,
        };
    }

    test cross {
        std.testing.expect(cross(Vec{ .x = 1 }, Vec{ .y = 1 }) == .{ .z = 1 });
        std.testing.expect(cross(Vec{ .y = 1 }, Vec{ .x = 1 }) == .{ .z = -1 });
        std.testing.expect(cross(Vec{ .x = 1 }, Vec{ .z = 1 }) == .{ .y = -1 });
    }

    pub fn norm(v: Vec) Vec {
        const length = std.math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
        return Vec{
            .x = v.x / length,
            .y = v.y / length,
            .z = v.z / length,
        };
    }
};
