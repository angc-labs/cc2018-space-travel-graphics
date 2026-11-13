// https://vis.uni-jena.de/Lecture/ComputerGraphics2/Lec7_a_Instancing.pdf
const std = @import("std");
const rl = @import("raylib");
const Mat4 = @import("mat4.zig").Mat4;
const Framebuffer = @import("framebuffer.zig").Framebuffer;
const camera_mod = @import("camera.zig");

// datos de una roca del cinturon
pub const Asteroid = struct {
    dist: f32,
    angle: f32,
    speed: f32,
    y_offset: f32,
    size: f32,
    color: rl.Color,
};

// particulas de humo verde en el cinturon
pub const GasParticle = struct {
    dist: f32,
    angle: f32,
    speed: f32,
    y_base: f32,
    y_freq: f32,
    world_radius: f32,
    intensity: f32,
    color: rl.Color,
};

pub const AsteroidBelt = struct {
    asteroids: [400]Asteroid,
    gas_particles: [250]GasParticle,

    // crear rocas y humo verde del cinturon
    pub fn init() AsteroidBelt {
        var belt: AsteroidBelt = undefined;
        var rng = std.Random.DefaultPrng.init(54321);
        const rand = rng.random();

        // repartir rocas alrededor del sol
        for (&belt.asteroids, 0..) |*ast, i| {
            const d = 16.8 + rand.float(f32) * 3.4;
            const a = rand.float(f32) * 2.0 * std.math.pi;
            const spd = (0.32 + rand.float(f32) * 0.12) * @sqrt(18.0 / d);
            const y = (rand.float(f32) - 0.5) * 0.7;
            const sz = 1.0 + rand.float(f32) * 1.5;
            const c_base: u8 = @intCast(110 + (i % 60));
            ast.* = .{
                .dist = d,
                .angle = a,
                .speed = spd,
                .y_offset = y,
                .size = sz,
                .color = .{ .r = c_base, .g = c_base - 8, .b = c_base - 16, .a = 255 },
            };
        }

        // repartir humo verde que flota
        for (&belt.gas_particles, 0..) |*gas, i| {
            const d = 16.5 + rand.float(f32) * 3.8;
            const a = rand.float(f32) * 2.0 * std.math.pi;
            const spd = (0.30 + rand.float(f32) * 0.10) * @sqrt(18.0 / d);
            const g_val: u8 = @intCast(160 + (i % 80));
            gas.* = .{
                .dist = d,
                .angle = a,
                .speed = spd,
                .y_base = (rand.float(f32) - 0.5) * 0.6,
                .y_freq = 0.8 + rand.float(f32) * 1.2,
                .world_radius = 0.55 + rand.float(f32) * 0.45,
                .intensity = 0.15 + rand.float(f32) * 0.12,
                .color = .{ .r = 20, .g = g_val, .b = 60, .a = 255 },
            };
        }

        return belt;
    }

    // dibujar rocas y humo verde
    pub fn render(self: *const AsteroidBelt, fb: *Framebuffer, vp: Mat4, cam_pos: rl.Vector3, sim_time: f32, sw: f32, sh: f32, fov: f32) void {
        // dibujar rocas del cinturon
        for (self.asteroids) |ast| {
            const ang = ast.angle + sim_time * ast.speed;
            const ast_pos = rl.Vector3{
                .x = @cos(ang) * ast.dist,
                .y = ast.y_offset,
                .z = @sin(ang) * ast.dist,
            };

            if (camera_mod.projectPointWithMVP(vp, ast_pos, sw, sh)) |scp| {
                const px: i32 = @intFromFloat(scp.p.x);
                const py: i32 = @intFromFloat(scp.p.y);
                const sun_raw = rl.Vector3{ .x = -ast_pos.x, .y = -ast_pos.y, .z = -ast_pos.z };
                const to_sun = sun_raw.normalize();
                const to_cam = cam_pos.subtract(ast_pos).normalize();
                const phase = @max(0.2, to_cam.dotProduct(to_sun) * 0.4 + 0.6);
                const lit_c = rl.Color{
                    .r = @intFromFloat(@as(f32, @floatFromInt(ast.color.r)) * phase),
                    .g = @intFromFloat(@as(f32, @floatFromInt(ast.color.g)) * phase),
                    .b = @intFromFloat(@as(f32, @floatFromInt(ast.color.b)) * phase),
                    .a = 255,
                };

                fb.set_pixel_depth(px, py, scp.z, lit_c);
                if (ast.size > 1.6) {
                    fb.set_pixel_depth(px + 1, py, scp.z, lit_c);
                    fb.set_pixel_depth(px, py + 1, scp.z, lit_c);
                    fb.set_pixel_depth(px + 1, py + 1, scp.z, lit_c);
                }
            }
        }

        // dibujar nubes de humo verde transparente
        for (self.gas_particles) |gas| {
            const gas_ang = gas.angle + sim_time * gas.speed;
            const gas_pos = rl.Vector3{
                .x = @cos(gas_ang) * gas.dist,
                .y = gas.y_base + @sin(sim_time * gas.y_freq + gas.angle) * 0.15,
                .z = @sin(gas_ang) * gas.dist,
            };

            const cam_dist = cam_pos.subtract(gas_pos).length();
            if (cam_dist > 0.2) {
                if (camera_mod.projectPointWithMVP(vp, gas_pos, sw, sh)) |scp| {
                    const screen_radius = (gas.world_radius / cam_dist) * (sh * 0.5) / @tan(fov * 0.5);
                    if (screen_radius > 1.0 and screen_radius < 50.0) {
                        fb.draw_gas_cloud(scp.p, screen_radius, scp.z, gas.color, gas.intensity);
                    }
                }
            }
        }
    }
};
