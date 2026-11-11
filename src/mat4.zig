const std = @import("std");
const rl = @import("raylib");

pub const Vec4 = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,
};

pub const Mat4 = struct {
    data: [4][4]f32,

    // matriz base con unos en la diagonal
    pub fn identity() Mat4 {
        return .{
            .data = .{
                .{ 1, 0, 0, 0 },
                .{ 0, 1, 0, 0 },
                .{ 0, 0, 1, 0 },
                .{ 0, 0, 0, 1 },
            },
        };
    }

    // multiplicar dos matrices
    pub fn multiply(a: Mat4, b: Mat4) Mat4 {
        var res: Mat4 = undefined;
        for (0..4) |row| {
            for (0..4) |col| {
                var sum: f32 = 0.0;
                for (0..4) |k| {
                    sum += a.data[row][k] * b.data[k][col];
                }
                res.data[row][col] = sum;
            }
        }
        return res;
    }

    // matriz para mover un objeto
    pub fn translation(x: f32, y: f32, z: f32) Mat4 {
        var m = identity();
        m.data[0][3] = x;
        m.data[1][3] = y;
        m.data[2][3] = z;
        return m;
    }

    // matriz para cambiar el tamano
    pub fn scaling(sx: f32, sy: f32, sz: f32) Mat4 {
        var m = identity();
        m.data[0][0] = sx;
        m.data[1][1] = sy;
        m.data[2][2] = sz;
        return m;
    }

    // matriz para girar en el eje y
    pub fn rotationY(rad: f32) Mat4 {
        var m = identity();
        const c = @cos(rad);
        const s = @sin(rad);
        m.data[0][0] = c;
        m.data[0][2] = s;
        m.data[2][0] = -s;
        m.data[2][2] = c;
        return m;
    }

    // matriz para apuntar la camara
    pub fn lookAt(eye: rl.Vector3, target: rl.Vector3, up: rl.Vector3) Mat4 {
        const forward = target.subtract(eye).normalize();
        const right = forward.crossProduct(up).normalize();
        const real_up = right.crossProduct(forward).normalize();

        var m = identity();
        m.data[0][0] = right.x;
        m.data[0][1] = right.y;
        m.data[0][2] = right.z;
        m.data[0][3] = -right.dotProduct(eye);

        m.data[1][0] = real_up.x;
        m.data[1][1] = real_up.y;
        m.data[1][2] = real_up.z;
        m.data[1][3] = -real_up.dotProduct(eye);

        m.data[2][0] = forward.x;
        m.data[2][1] = forward.y;
        m.data[2][2] = forward.z;
        m.data[2][3] = -forward.dotProduct(eye);

        return m;
    }

    // matriz para dar efecto de profundidad
    pub fn perspective(fov_rad: f32, aspect: f32, near: f32, far: f32) Mat4 {
        var m = identity();
        const tan_half_fov = @tan(fov_rad * 0.5);

        m.data[0][0] = 1.0 / (aspect * tan_half_fov);
        m.data[1][1] = 1.0 / tan_half_fov;
        m.data[2][2] = far / (far - near);
        m.data[2][3] = -(far * near) / (far - near);
        m.data[3][2] = 1.0;
        m.data[3][3] = 0.0;

        return m;
    }

    // multiplicar un punto por la matriz
    pub fn transformPoint(self: Mat4, p: rl.Vector3) Vec4 {
        return .{
            .x = self.data[0][0] * p.x + self.data[0][1] * p.y + self.data[0][2] * p.z + self.data[0][3],
            .y = self.data[1][0] * p.x + self.data[1][1] * p.y + self.data[1][2] * p.z + self.data[1][3],
            .z = self.data[2][0] * p.x + self.data[2][1] * p.y + self.data[2][2] * p.z + self.data[2][3],
            .w = self.data[3][0] * p.x + self.data[3][1] * p.y + self.data[3][2] * p.z + self.data[3][3],
        };
    }
};
