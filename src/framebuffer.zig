const std = @import("std");
const rl = @import("raylib");
const triangle_mod = @import("triangle.zig");
pub const edgeFunction2D = triangle_mod.edgeFunction2D;

pub const Framebuffer = struct {
    width: i32,
    height: i32,
    image: rl.Image,
    texture: ?rl.Texture = null,
    background_color: rl.Color,
    z_buffer: []f32,
    allocator: std.mem.Allocator,

    // crear framebuffer y buffer z
    pub fn init(allocator: std.mem.Allocator, width: i32, height: i32, bg_color: ?rl.Color) !Framebuffer {
        const bg = bg_color orelse rl.Color.black;
        const zb = try allocator.alloc(f32, @intCast(width * height));
        @memset(zb, std.math.inf(f32));

        return .{
            .width = width,
            .height = height,
            .image = rl.genImageColor(width, height, bg),
            .texture = null,
            .background_color = bg,
            .z_buffer = zb,
            .allocator = allocator,
        };
    }

    // liberar memoria al cerrar
    pub fn deinit(self: *Framebuffer) void {
        if (self.texture) |texture| {
            rl.unloadTexture(texture);
        }
        self.image.unload();
        self.allocator.free(self.z_buffer);
    }

    // limpiar la pantalla y el buffer z
    pub fn clear(self: *Framebuffer) void {
        self.image.clearBackground(self.background_color);
        @memset(self.z_buffer, std.math.inf(f32));
        if (self.texture) |texture| {
            rl.unloadTexture(texture);
            self.texture = null;
        }
    }

    // pintar pixel si esta mas cerca que el anterior
    pub fn set_pixel_depth(self: *Framebuffer, x: i32, y: i32, depth: f32, color: rl.Color) void {
        if (x >= 0 and x < self.width and y >= 0 and y < self.height) {
            const idx: usize = @intCast(y * self.width + x);
            if (depth < self.z_buffer[idx]) {
                self.z_buffer[idx] = depth;
                self.image.drawPixel(x, y, color);
            }
        }
    }

    // dibujar triangulo con iluminacion suave
    pub fn draw_triangle_gouraud(
        self: *Framebuffer,
        v0: rl.Vector2,
        v1: rl.Vector2,
        v2: rl.Vector2,
        z0: f32,
        z1: f32,
        z2: f32,
        c0: rl.Color,
        c1: rl.Color,
        c2: rl.Color,
    ) void {
        const area = edgeFunction2D(v0, v1, v2);
        if (@abs(area) < 0.0001) {
            return;
        }
        const inv_area = 1.0 / area;

        // caja limite en pantalla
        const min_x: i32 = @max(0, @as(i32, @intFromFloat(@min(v0.x, @min(v1.x, v2.x)))));
        const max_x: i32 = @min(self.width - 1, @as(i32, @intFromFloat(@max(v0.x, @max(v1.x, v2.x)))));
        const min_y: i32 = @max(0, @as(i32, @intFromFloat(@min(v0.y, @min(v1.y, v2.y)))));
        const max_y: i32 = @min(self.height - 1, @as(i32, @intFromFloat(@max(v0.y, @max(v1.y, v2.y)))));
        if (min_x > max_x or min_y > max_y) {
            return;
        }

        const r0: f32 = @floatFromInt(c0.r);
        const g0: f32 = @floatFromInt(c0.g);
        const b0: f32 = @floatFromInt(c0.b);
        const r1: f32 = @floatFromInt(c1.r);
        const g1: f32 = @floatFromInt(c1.g);
        const b1: f32 = @floatFromInt(c1.b);
        const r2: f32 = @floatFromInt(c2.r);
        const g2: f32 = @floatFromInt(c2.g);
        const b2: f32 = @floatFromInt(c2.b);

        var y = min_y;
        while (y <= max_y) : (y += 1) {
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                const p = rl.Vector2{ .x = @as(f32, @floatFromInt(x)) + 0.5, .y = @as(f32, @floatFromInt(y)) + 0.5 };
                const w0 = edgeFunction2D(v1, v2, p);
                const w1 = edgeFunction2D(v2, v0, p);
                const w2 = edgeFunction2D(v0, v1, p);

                const inside = if (area > 0)
                    (w0 >= 0 and w1 >= 0 and w2 >= 0)
                else
                    (w0 <= 0 and w1 <= 0 and w2 <= 0);

                if (inside) {
                    const l0 = w0 * inv_area;
                    const l1 = w1 * inv_area;
                    const l2 = w2 * inv_area;
                    const depth = l0 * z0 + l1 * z1 + l2 * z2;

                    const r: u8 = @intFromFloat(std.math.clamp(l0 * r0 + l1 * r1 + l2 * r2, 0.0, 255.0));
                    const g: u8 = @intFromFloat(std.math.clamp(l0 * g0 + l1 * g1 + l2 * g2, 0.0, 255.0));
                    const b: u8 = @intFromFloat(std.math.clamp(l0 * b0 + l1 * b1 + l2 * b2, 0.0, 255.0));

                    self.set_pixel_depth(x, y, depth, .{ .r = r, .g = g, .b = b, .a = 255 });
                }
            }
        }
    }

    // dibujar brillo alrededor del sol
    pub fn draw_sun_halo(self: *Framebuffer, center: rl.Vector2, screen_radius: f32, depth: f32) void {
        const outer_radius = screen_radius * 3.0;
        const min_x: i32 = @max(0, @as(i32, @intFromFloat(center.x - outer_radius)));
        const max_x: i32 = @min(self.width - 1, @as(i32, @intFromFloat(center.x + outer_radius)));
        const min_y: i32 = @max(0, @as(i32, @intFromFloat(center.y - outer_radius)));
        const max_y: i32 = @min(self.height - 1, @as(i32, @intFromFloat(center.y + outer_radius)));
        if (min_x > max_x or min_y > max_y) {
            return;
        }

        const r_core = screen_radius * 0.92;
        const r_range = outer_radius - r_core;
        if (r_range <= 0.0) {
            return;
        }

        var y = min_y;
        while (y <= max_y) : (y += 1) {
            const dy = @as(f32, @floatFromInt(y)) + 0.5 - center.y;
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                const dx = @as(f32, @floatFromInt(x)) + 0.5 - center.x;
                const d = @sqrt(dx * dx + dy * dy);
                if (d >= r_core and d < outer_radius) {
                    const idx: usize = @intCast(y * self.width + x);
                    if (depth <= self.z_buffer[idx]) {
                        const factor = 1.0 - ((d - r_core) / r_range);
                        const glow = factor * factor * factor;
                        const existing = rl.getImageColor(self.image, x, y);

                        // sumar el brillo dorado del sol
                        const add_r = 255.0 * glow * 0.95;
                        const add_g = 195.0 * glow * 0.70;
                        const add_b = 60.0 * glow * 0.30;

                        const nr: u8 = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(existing.r)) + add_r));
                        const ng: u8 = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(existing.g)) + add_g));
                        const nb: u8 = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(existing.b)) + add_b));

                        self.image.drawPixel(x, y, .{ .r = nr, .g = ng, .b = nb, .a = 255 });
                    }
                }
            }
        }
    }

    // dibujar nube de gas
    pub fn draw_gas_cloud(self: *Framebuffer, center: rl.Vector2, screen_radius: f32, depth: f32, color: rl.Color, intensity: f32) void {
        const min_x: i32 = @max(0, @as(i32, @intFromFloat(center.x - screen_radius)));
        const max_x: i32 = @min(self.width - 1, @as(i32, @intFromFloat(center.x + screen_radius)));
        const min_y: i32 = @max(0, @as(i32, @intFromFloat(center.y - screen_radius)));
        const max_y: i32 = @min(self.height - 1, @as(i32, @intFromFloat(center.y + screen_radius)));
        if (min_x > max_x or min_y > max_y) {
            return;
        }

        const r_sq = screen_radius * screen_radius;
        if (r_sq <= 0.0) {
            return;
        }

        var y = min_y;
        while (y <= max_y) : (y += 1) {
            const dy = @as(f32, @floatFromInt(y)) + 0.5 - center.y;
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                const dx = @as(f32, @floatFromInt(x)) + 0.5 - center.x;
                const d_sq = dx * dx + dy * dy;
                if (d_sq < r_sq) {
                    const idx: usize = @intCast(y * self.width + x);
                    if (depth <= self.z_buffer[idx]) {
                        const factor = 1.0 - (d_sq / r_sq);
                        const alpha = factor * factor * intensity;
                        const existing = rl.getImageColor(self.image, x, y);

                        const add_r = @as(f32, @floatFromInt(color.r)) * alpha;
                        const add_g = @as(f32, @floatFromInt(color.g)) * alpha;
                        const add_b = @as(f32, @floatFromInt(color.b)) * alpha;

                        const nr: u8 = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(existing.r)) + add_r));
                        const ng: u8 = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(existing.g)) + add_g));
                        const nb: u8 = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(existing.b)) + add_b));

                        self.image.drawPixel(x, y, .{ .r = nr, .g = ng, .b = nb, .a = 255 });
                    }
                }
            }
        }
    }

    // dibujar planeta o sol con su textura
    pub fn draw_triangle_textured_sphere(
        self: *Framebuffer,
        v0: rl.Vector2,
        v1: rl.Vector2,
        v2: rl.Vector2,
        z0: f32,
        z1: f32,
        z2: f32,
        n0: rl.Vector3,
        n1: rl.Vector3,
        n2: rl.Vector3,
        texture: rl.Image,
        rot_y: f32,
        lit0: f32,
        lit1: f32,
        lit2: f32,
        spec0: f32,
        spec1: f32,
        spec2: f32,
        is_sun: bool,
    ) void {
        const area = edgeFunction2D(v0, v1, v2);
        if (@abs(area) < 0.0001) {
            return;
        }
        const inv_area = 1.0 / area;

        const min_x: i32 = @max(0, @as(i32, @intFromFloat(@min(v0.x, @min(v1.x, v2.x)))));
        const max_x: i32 = @min(self.width - 1, @as(i32, @intFromFloat(@max(v0.x, @max(v1.x, v2.x)))));
        const min_y: i32 = @max(0, @as(i32, @intFromFloat(@min(v0.y, @min(v1.y, v2.y)))));
        const max_y: i32 = @min(self.height - 1, @as(i32, @intFromFloat(@max(v0.y, @max(v1.y, v2.y)))));
        if (min_x > max_x or min_y > max_y) {
            return;
        }

        const cos_r = @cos(rot_y);
        const sin_r = @sin(rot_y);
        const tw_f = @as(f32, @floatFromInt(texture.width - 1));
        const th_f = @as(f32, @floatFromInt(texture.height - 1));

        var y = min_y;
        while (y <= max_y) : (y += 1) {
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                const p = rl.Vector2{ .x = @as(f32, @floatFromInt(x)) + 0.5, .y = @as(f32, @floatFromInt(y)) + 0.5 };
                const w0 = edgeFunction2D(v1, v2, p);
                const w1 = edgeFunction2D(v2, v0, p);
                const w2 = edgeFunction2D(v0, v1, p);

                const inside = if (area > 0)
                    (w0 >= 0 and w1 >= 0 and w2 >= 0)
                else
                    (w0 <= 0 and w1 <= 0 and w2 <= 0);

                if (inside) {
                    const l0 = w0 * inv_area;
                    const l1 = w1 * inv_area;
                    const l2 = w2 * inv_area;
                    const depth = l0 * z0 + l1 * z1 + l2 * z2;

                    // calcular la normal de la esfera
                    const nx = l0 * n0.x + l1 * n1.x + l2 * n2.x;
                    const ny = l0 * n0.y + l1 * n1.y + l2 * n2.y;
                    const nz = l0 * n0.z + l1 * n1.z + l2 * n2.z;

                    const len_sq = nx * nx + ny * ny + nz * nz;
                    if (len_sq > 0.0001) {
                        const inv_len = 1.0 / @sqrt(len_sq);
                        // girar la textura del planeta
                        const unx = (nx * cos_r + nz * sin_r) * inv_len;
                        const uny = ny * inv_len;
                        const unz = (-nx * sin_r + nz * cos_r) * inv_len;

                        var u = 0.5 + std.math.atan2(unz, unx) * (0.5 / std.math.pi);
                        if (u < 0.0) {
                            u += 1.0;
                        }
                        if (u >= 1.0) {
                            u -= 1.0;
                        }

                        const v = std.math.clamp(0.5 - std.math.asin(std.math.clamp(uny, -1.0, 1.0)) * (1.0 / std.math.pi), 0.0, 0.999);
                        const tx: i32 = @intFromFloat(u * tw_f);
                        const ty: i32 = @intFromFloat(v * th_f);

                        const color = rl.getImageColor(texture, tx, ty);

                        if (is_sun) {
                            // darle mas brillo al sol
                            const r_boost: u8 = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(color.r)) * 1.15 + 10.0));
                            const g_boost: u8 = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(color.g)) * 1.08 + 5.0));
                            const b_boost: u8 = @intFromFloat(@min(255.0, @as(f32, @floatFromInt(color.b)) * 1.05));
                            self.set_pixel_depth(x, y, depth, .{ .r = r_boost, .g = g_boost, .b = b_boost, .a = 255 });
                        } else {
                            // aplicar luz del sol a la textura
                            const lit = l0 * lit0 + l1 * lit1 + l2 * lit2;
                            const spec = l0 * spec0 + l1 * spec1 + l2 * spec2;
                            const rf = (@as(f32, @floatFromInt(color.r)) * lit) + (spec * 255.0);
                            const gf = (@as(f32, @floatFromInt(color.g)) * lit * 0.96) + (spec * 245.0);
                            const bf = (@as(f32, @floatFromInt(color.b)) * lit * 0.86) + (spec * 220.0);
                            self.set_pixel_depth(x, y, depth, .{
                                .r = @intFromFloat(std.math.clamp(rf, 0.0, 255.0)),
                                .g = @intFromFloat(std.math.clamp(gf, 0.0, 255.0)),
                                .b = @intFromFloat(std.math.clamp(bf, 0.0, 255.0)),
                                .a = 255,
                            });
                        }
                    }
                }
            }
        }
    }

    // mostrar la imagen en pantalla
    pub fn swap_buffers(self: *Framebuffer) !void {
        const texture = try rl.loadTextureFromImage(self.image);
        self.texture = texture;
        rl.drawTexture(texture, 0, 0, .white);
    }
};
