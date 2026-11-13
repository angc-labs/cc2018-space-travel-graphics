// codigo implementado con gemini 3.8
// https://www.raylib.com/examples/models/loader.html?name=models_skybox_rendering
const std = @import("std");
const rl = @import("raylib");
const camera_mod = @import("camera.zig");
const Framebuffer = @import("framebuffer.zig").Framebuffer;
const Mat4 = @import("mat4.zig").Mat4;

// datos de cada estrella en el cielo
pub const Star = struct {
    dir: rl.Vector3,
    color: rl.Color,
};

// datos de cada punto de nebulosa
pub const NebulaParticle = struct {
    pos: rl.Vector3,
    color: rl.Color,
};

pub const Skybox = struct {
    stars: [1000]Star,
    nebula_particles: [300]NebulaParticle,

    // crear estrellas y nebulosas de fondo
    pub fn init() Skybox {
        var sb: Skybox = undefined;
        var rng = std.Random.DefaultPrng.init(12345);
        const random = rng.random();

        // repartir estrellas por todo el cielo
        for (&sb.stars, 0..) |*star, i| {
            const theta = random.float(f32) * 2.0 * std.math.pi;
            const phi = std.math.acos(2.0 * random.float(f32) - 1.0);

            star.dir = .{
                .x = @sin(phi) * @cos(theta),
                .y = @cos(phi),
                .z = @sin(phi) * @sin(theta),
            };

            // colores blanco azul y amarillo para estrellas
            const intensity: u8 = @intCast(160 + (i % 95));
            star.color = switch (i % 5) {
                0 => .{ .r = intensity, .g = intensity, .b = 255, .a = 255 },
                1 => .{ .r = 255, .g = intensity, .b = intensity, .a = 255 },
                else => .{ .r = intensity, .g = intensity, .b = intensity, .a = 255 },
            };
        }

        // posiciones de las nubes de nebulosa
        const nebula_centers = [_]struct { pos: rl.Vector3, col: rl.Color }{
            .{ .pos = .{ .x = 0.6, .y = 0.3, .z = 0.7 }, .col = .{ .r = 180, .g = 60, .b = 190, .a = 255 } },
            .{ .pos = .{ .x = -0.7, .y = -0.2, .z = 0.6 }, .col = .{ .r = 40, .g = 130, .b = 200, .a = 255 } },
            .{ .pos = .{ .x = 0.2, .y = -0.6, .z = -0.7 }, .col = .{ .r = 210, .g = 90, .b = 120, .a = 255 } },
        };

        var p_idx: usize = 0;
        for (nebula_centers) |nc| {
            const base_norm = nc.pos.normalize();
            for (0..100) |_| {
                const spread: f32 = 0.18;
                const offset = rl.Vector3{
                    .x = (random.float(f32) - 0.5) * spread,
                    .y = (random.float(f32) - 0.5) * spread,
                    .z = (random.float(f32) - 0.5) * spread,
                };
                const dir = base_norm.add(offset).normalize();
                const fade = 0.4 + 0.6 * random.float(f32);
                sb.nebula_particles[p_idx] = .{
                    .pos = dir,
                    .color = .{
                        .r = @intFromFloat(@as(f32, @floatFromInt(nc.col.r)) * fade),
                        .g = @intFromFloat(@as(f32, @floatFromInt(nc.col.g)) * fade),
                        .b = @intFromFloat(@as(f32, @floatFromInt(nc.col.b)) * fade),
                        .a = 255,
                    },
                };
                p_idx += 1;
            }
        }

        return sb;
    }

    // dibujar estrellas y nebulosas en el fondo
    pub fn render(self: *const Skybox, fb: *Framebuffer, forward: rl.Vector3, up: rl.Vector3, fov: f32, sw: f32, sh: f32) void {
        const origin = rl.Vector3{ .x = 0, .y = 0, .z = 0 };
        const view_mat = Mat4.lookAt(origin, forward, up);
        const proj_mat = Mat4.perspective(fov, sw / sh, 0.1, 500.0);
        const mvp = Mat4.multiply(proj_mat, view_mat);

        // dibujar puntos de nebulosas
        for (self.nebula_particles) |p| {
            const pt_far = p.pos.scale(200.0);
            if (camera_mod.projectPointWithMVP(mvp, pt_far, sw, sh)) |proj| {
                const px: i32 = @intFromFloat(proj.p.x);
                const py: i32 = @intFromFloat(proj.p.y);
                fb.set_pixel_depth(px, py, 490.0, p.color);
                fb.set_pixel_depth(px + 1, py, 490.0, p.color);
                fb.set_pixel_depth(px, py + 1, 490.0, p.color);
            }
        }

        // dibujar puntos de estrellas
        for (self.stars) |star| {
            const pt_far = star.dir.scale(250.0);
            if (camera_mod.projectPointWithMVP(mvp, pt_far, sw, sh)) |proj| {
                const px: i32 = @intFromFloat(proj.p.x);
                const py: i32 = @intFromFloat(proj.p.y);
                fb.set_pixel_depth(px, py, 495.0, star.color);
            }
        }
    }
};
