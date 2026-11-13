const std = @import("std");
const rl = @import("raylib");
const triangle_mod = @import("triangle.zig");
const mat4_mod = @import("mat4.zig");
pub const Triangle2D = triangle_mod.Triangle2D;
pub const Triangle3D = triangle_mod.Triangle3D;
pub const Mat4 = mat4_mod.Mat4;

pub const Camera = struct {
    target: rl.Vector3,
    distance: f32,
    yaw: f32,
    pitch: f32,
    fov: f32,

    position: rl.Vector3,
    forward: rl.Vector3,
    right: rl.Vector3,
    up: rl.Vector3,

    // crear camara que gira alrededor del objetivo
    pub fn init(target: rl.Vector3, distance: f32, yaw_deg: f32, pitch_deg: f32, fov_deg: f32) Camera {
        var cam = Camera{
            .target = target,
            .distance = distance,
            .yaw = yaw_deg * (std.math.pi / 180.0),
            .pitch = pitch_deg * (std.math.pi / 180.0),
            .fov = fov_deg * (std.math.pi / 180.0),
            .position = .zero(),
            .forward = .zero(),
            .right = .zero(),
            .up = .{ .x = 0, .y = 1, .z = 0 },
        };
        cam.updateVectors();
        return cam;
    }

    // calcular posicion y direccion de la camara
    pub fn updateVectors(self: *Camera) void {
        const cos_p = @cos(self.pitch);
        const sin_p = @sin(self.pitch);
        const cos_y = @cos(self.yaw);
        const sin_y = @sin(self.yaw);

        self.position = .{
            .x = self.target.x + self.distance * cos_p * sin_y,
            .y = self.target.y + self.distance * sin_p,
            .z = self.target.z + self.distance * cos_p * cos_y,
        };

        const to_target = self.target.subtract(self.position);
        const dist = to_target.length();
        if (dist > 0.0001) {
            self.forward = to_target.scale(1.0 / dist);
        } else {
            self.forward = .{ .x = 0, .y = 0, .z = 1 };
        }

        const world_up = rl.Vector3{ .x = 0, .y = 1, .z = 0 };
        const dot = @abs(self.forward.dotProduct(world_up));
        const up_ref = if (dot > 0.99) rl.Vector3{ .x = 0, .y = 0, .z = -1 } else world_up;

        self.right = self.forward.crossProduct(up_ref).normalize();
        self.up = self.right.crossProduct(self.forward).normalize();
    }

    // rotar camara con wasd o mouse
    pub fn rotate(self: *Camera, delta_yaw: f32, delta_pitch: f32) void {
        self.yaw += delta_yaw;
        while (self.yaw > std.math.pi) {
            self.yaw -= 2.0 * std.math.pi;
        }
        while (self.yaw < -std.math.pi) {
            self.yaw += 2.0 * std.math.pi;
        }

        self.pitch = std.math.clamp(self.pitch + delta_pitch, -1.45, 1.45);
        self.updateVectors();
    }

    // acercar o alejar la camara con zoom
    pub fn zoom(self: *Camera, delta: f32) void {
        self.distance = std.math.clamp(self.distance + delta, 2.5, 120.0);
        self.updateVectors();
    }

    // cambiar la vista a otro planeta con viaje rapido
    pub fn setTarget(self: *Camera, new_target: rl.Vector3, new_distance: f32) void {
        self.target = new_target;
        self.distance = new_distance;
        self.updateVectors();
    }

    // evitar chocar o atravesar los planetas
    pub fn applyCollisionSphere(self: *Camera, sphere_center: rl.Vector3, min_radius: f32) void {
        const to_cam = self.position.subtract(sphere_center);
        const dist = to_cam.length();
        if (dist < min_radius and dist > 0.0001) {
            self.position = sphere_center.add(to_cam.scale(min_radius / dist));
            self.distance = @max(self.distance, min_radius);
        }
    }

    // matriz de vista apuntando al centro
    pub fn getViewMatrix(self: *const Camera) Mat4 {
        const world_up = rl.Vector3{ .x = 0, .y = 1, .z = 0 };
        const dot = @abs(self.forward.dotProduct(world_up));
        const up_ref = if (dot > 0.99) rl.Vector3{ .x = 0, .y = 0, .z = -1 } else world_up;
        return Mat4.lookAt(self.position, self.target, up_ref);
    }

    // matriz de proyeccion en perspectiva
    pub fn getProjectionMatrix(self: *const Camera, aspect: f32) Mat4 {
        return Mat4.perspective(self.fov, aspect, 0.1, 500.0);
    }
};

// pasar punto 3d a 2d en pantalla usando mvp
pub fn projectPointWithMVP(mvp: Mat4, point: rl.Vector3, screen_w: f32, screen_h: f32) ?struct { p: rl.Vector2, z: f32 } {
    const clip = mvp.transformPoint(point);
    if (clip.w <= 0.05) {
        return null;
    }

    const inv_w = 1.0 / clip.w;
    return .{
        .p = .{
            .x = (clip.x * inv_w + 1.0) * 0.5 * screen_w,
            .y = (1.0 - clip.y * inv_w) * 0.5 * screen_h,
        },
        .z = clip.z * inv_w,
    };
}
