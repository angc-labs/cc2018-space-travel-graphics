const std = @import("std");
const rl = @import("raylib");
const Mat4 = @import("mat4.zig").Mat4;
const Framebuffer = @import("framebuffer.zig").Framebuffer;
const Mesh = @import("model.zig").Mesh;
const TriangleFace = @import("model.zig").TriangleFace;
const Triangle3D = @import("triangle.zig").Triangle3D;
const camera_mod = @import("camera.zig");

// parametros para dibujar un modelo
pub const RenderParams = struct {
    model_mat: Mat4,
    mvp: Mat4,
    pos: rl.Vector3,
    cam_pos: rl.Vector3,
    sun_pos: rl.Vector3,
    override_color: ?rl.Color,
    is_sun: bool,
    is_sphere: bool,
    texture: ?rl.Image,
    sim_time: f32,
    rot_speed: f32,
    sw: f32,
    sh: f32,
};

// dibujar en paralelo usando varios hilos
pub fn renderMesh(init_io: anytype, mesh: *const Mesh, params: RenderParams, fb: *Framebuffer) !void {
    var group = std.Io.Group.init;
    defer group.cancel(init_io);

    const thread_count = 8;
    for (0..thread_count) |i| {
        const stride = mesh.triangles.len / thread_count;
        const start = i * stride;
        const end = if (i == thread_count - 1) mesh.triangles.len else (i + 1) * stride;

        group.async(init_io, renderTriangles, .{ mesh.triangles[start..end], mesh, params, fb });
    }

    try group.await(init_io);
}

// calcular la luz del sol en cada punto
pub fn calcLight(v: rl.Vector3, n: rl.Vector3, sun_pos: rl.Vector3, cam_pos: rl.Vector3) struct { lit: f32, spec: f32 } {
    const to_sun = sun_pos.subtract(v);
    const dist = to_sun.length();
    const light_dir = if (dist > 0.0001) to_sun.scale(1.0 / dist) else rl.Vector3{ .x = 0, .y = 1, .z = 0 };

    // luz directa y brillo del sol
    const n_dot_l = n.dotProduct(light_dir);
    const diff = @max(0.0, n_dot_l);

    const to_cam = cam_pos.subtract(v);
    const cam_dist = to_cam.length();
    const view_dir = if (cam_dist > 0.0001) to_cam.scale(1.0 / cam_dist) else rl.Vector3{ .x = 0, .y = 0, .z = 1 };

    var spec: f32 = 0.0;
    if (n_dot_l > 0.0) {
        const half_dir = light_dir.add(view_dir).normalize();
        spec = std.math.pow(f32, @max(0.0, n.dotProduct(half_dir)), 24.0) * 0.85;
    }

    // brillo en la orilla del planeta
    const rim = (1.0 - @max(0.0, n.dotProduct(view_dir))) * diff;
    const lit = 0.08 + diff * 0.92 + rim * rim * 0.45;

    return .{ .lit = lit, .spec = spec };
}

// aplicar luz calculada a un color base
pub fn shadeColor(base: rl.Color, lit: f32, spec: f32) rl.Color {
    const rf = (@as(f32, @floatFromInt(base.r)) * lit) + (spec * 255.0);
    const gf = (@as(f32, @floatFromInt(base.g)) * lit * 0.96) + (spec * 245.0);
    const bf = (@as(f32, @floatFromInt(base.b)) * lit * 0.86) + (spec * 220.0);

    return .{
        .r = @intFromFloat(std.math.clamp(rf, 0.0, 255.0)),
        .g = @intFromFloat(std.math.clamp(gf, 0.0, 255.0)),
        .b = @intFromFloat(std.math.clamp(bf, 0.0, 255.0)),
        .a = 255,
    };
}

// dibujar triangulos en la pantalla
fn renderTriangles(triangles: []const TriangleFace, mesh: *const Mesh, params: RenderParams, fb: *Framebuffer) error{Canceled}!void {
    for (triangles) |face| {
        const v0 = mesh.vertices[face.v0];
        const v1 = mesh.vertices[face.v1];
        const v2 = mesh.vertices[face.v2];

        const p0 = camera_mod.projectPointWithMVP(params.mvp, v0, params.sw, params.sh) orelse continue;
        const p1 = camera_mod.projectPointWithMVP(params.mvp, v1, params.sw, params.sh) orelse continue;
        const p2 = camera_mod.projectPointWithMVP(params.mvp, v2, params.sw, params.sh) orelse continue;

        const w0 = params.model_mat.transformPoint(v0);
        const w1 = params.model_mat.transformPoint(v1);
        const w2 = params.model_mat.transformPoint(v2);
        const v0_w = rl.Vector3{ .x = w0.x, .y = w0.y, .z = w0.z };
        const v1_w = rl.Vector3{ .x = w1.x, .y = w1.y, .z = w1.z };
        const v2_w = rl.Vector3{ .x = w2.x, .y = w2.y, .z = w2.z };

        const n0: rl.Vector3 = if (params.is_sphere) v0_w.subtract(params.pos).normalize() else (Triangle3D{ .v0 = v0_w, .v1 = v1_w, .v2 = v2_w }).normal();
        const n1: rl.Vector3 = if (params.is_sphere) v1_w.subtract(params.pos).normalize() else n0;
        const n2: rl.Vector3 = if (params.is_sphere) v2_w.subtract(params.pos).normalize() else n0;

        const f0 = calcLight(v0_w, n0, params.sun_pos, params.cam_pos);
        const f1 = calcLight(v1_w, n1, params.sun_pos, params.cam_pos);
        const f2 = calcLight(v2_w, n2, params.sun_pos, params.cam_pos);

        if (params.texture) |tex| {
            fb.draw_triangle_textured_sphere(
                p0.p,
                p1.p,
                p2.p,
                p0.z,
                p1.z,
                p2.z,
                v0.normalize(),
                v1.normalize(),
                v2.normalize(),
                tex,
                -params.sim_time * params.rot_speed,
                f0.lit,
                f1.lit,
                f2.lit,
                f0.spec,
                f1.spec,
                f2.spec,
                params.is_sun,
            );
        } else {
            const base_color = params.override_color orelse face.color;
            const c0 = shadeColor(base_color, f0.lit, f0.spec);
            const c1 = shadeColor(base_color, f1.lit, f1.spec);
            const c2 = shadeColor(base_color, f2.lit, f2.spec);

            fb.draw_triangle_gouraud(p0.p, p1.p, p2.p, p0.z, p1.z, p2.z, c0, c1, c2);
        }
    }
}
