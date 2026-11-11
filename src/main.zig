const std = @import("std");
const rl = @import("raylib");
const root = @import("root.zig");

const Mat4 = root.Mat4;
const Camera = root.Camera;
const Framebuffer = root.Framebuffer;
const Mesh = root.Mesh;
const Triangle3D = root.Triangle3D;
const TriangleFace = root.TriangleFace;
const Skybox = root.Skybox;
const loadOBJ = root.loadOBJ;

// datos de cada planeta en el sistema solar
const CelestialBody = struct {
    radius: f32,
    orbit_distance: f32,
    orbit_speed: f32,
    rotation_speed: f32,
    color: rl.Color,
    is_sun: bool = false,
    parent_index: ?usize = null,
};

pub fn main(init: std.process.Init) !void {
    const screen_width: i32 = 900;
    const screen_height: i32 = 700;
    const allocator = std.heap.page_allocator;

    // crear ventana con el titulo requerido
    rl.initWindow(screen_width, screen_height, "24248 - Space travel");
    rl.setTraceLogLevel(.warning);
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // crear framebuffer y buffer z
    var fb = try Framebuffer.init(allocator, screen_width, screen_height, rl.Color.black);
    defer fb.deinit();

    // codigo implementado con gemini e inspirado por https://www.raylib.com/examples/models/loader.html?name=models_skybox_rendering
    // crear estrellas y nebulosas de fondo
    const sky = Skybox.init();

    // cargar textura del sol y modelos 3d
    const sun_texture: ?rl.Image = rl.loadImage("assets/textures/sun.png") catch null;
    defer if (sun_texture) |tex| rl.unloadImage(tex);

    var sphere_mesh: ?Mesh = loadOBJ(allocator, "assets/sphere.obj") catch null;
    defer if (sphere_mesh) |*m| m.deinit();

    var ship_mesh: ?Mesh = loadOBJ(allocator, "assets/cohete.obj") catch null;
    defer if (ship_mesh) |*m| m.deinit();

    // camara centrada en el sol
    var cam = Camera.init(.{ .x = 0, .y = 0, .z = 0 }, 26.0, 25.0, 20.0, 55.0);

    // lista de planetas y el sol
    const bodies = [_]CelestialBody{
        .{ .radius = 2.4, .orbit_distance = 0.0, .orbit_speed = 0.0, .rotation_speed = 0.25, .color = .{ .r = 255, .g = 200, .b = 40, .a = 255 }, .is_sun = true },
        .{ .radius = 0.45, .orbit_distance = 5.5, .orbit_speed = 1.3, .rotation_speed = 0.8, .color = .{ .r = 160, .g = 155, .b = 150, .a = 255 } },
        .{ .radius = 0.85, .orbit_distance = 9.8, .orbit_speed = 0.7, .rotation_speed = 1.2, .color = .{ .r = 45, .g = 120, .b = 215, .a = 255 } },
        .{ .radius = 0.28, .orbit_distance = 1.8, .orbit_speed = 2.4, .rotation_speed = 0.5, .color = .{ .r = 210, .g = 210, .b = 220, .a = 255 }, .parent_index = 2 },
        .{ .radius = 0.65, .orbit_distance = 15.0, .orbit_speed = 0.45, .rotation_speed = 1.0, .color = .{ .r = 220, .g = 80, .b = 50, .a = 255 } },
        .{ .radius = 1.6, .orbit_distance = 22.0, .orbit_speed = 0.25, .rotation_speed = 1.5, .color = .{ .r = 220, .g = 180, .b = 130, .a = 255 } },
    };

    var sim_time: f32 = 0.0;
    var use_backface_culling: bool = true;
    var prev_mouse = rl.getMousePosition();

    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();
        sim_time += dt;

        // mover camara con mouse y wasd
        const mouse = rl.getMousePosition();
        if (rl.isMouseButtonDown(.right)) {
            cam.rotate((prev_mouse.x - mouse.x) * 0.005, (prev_mouse.y - mouse.y) * 0.005);
        }
        prev_mouse = mouse;

        const rot_speed = 1.8 * dt;
        var delta_yaw: f32 = 0.0;
        var delta_pitch: f32 = 0.0;
        if (rl.isKeyDown(.w)) delta_pitch += rot_speed;
        if (rl.isKeyDown(.s)) delta_pitch -= rot_speed;
        if (rl.isKeyDown(.a)) delta_yaw -= rot_speed;
        if (rl.isKeyDown(.d)) delta_yaw += rot_speed;
        cam.rotate(delta_yaw, delta_pitch);

        // acercar o alejar con rueda o flechas
        const wheel = rl.getMouseWheelMove();
        if (wheel != 0.0) cam.zoom(-wheel * 2.0);
        if (rl.isKeyDown(.up)) cam.zoom(-15.0 * dt);
        if (rl.isKeyDown(.down)) cam.zoom(15.0 * dt);

        // calcular posiciones de los planetas
        var body_positions: [bodies.len]rl.Vector3 = undefined;
        for (bodies, 0..) |b, i| {
            const ang = sim_time * b.orbit_speed;
            const local = rl.Vector3{ .x = @cos(ang) * b.orbit_distance, .y = 0, .z = @sin(ang) * b.orbit_distance };
            body_positions[i] = if (b.parent_index) |p_idx| body_positions[p_idx].add(local) else local;
        }

        // viaje rapido con teclas del 1 al 6
        const targets = [_]struct { key: rl.KeyboardKey, idx: usize, dist: f32 }{
            .{ .key = .one, .idx = 0, .dist = 25.0 },
            .{ .key = .two, .idx = 1, .dist = 4.0 },
            .{ .key = .three, .idx = 2, .dist = 5.0 },
            .{ .key = .four, .idx = 3, .dist = 3.0 },
            .{ .key = .five, .idx = 4, .dist = 5.0 },
            .{ .key = .six, .idx = 5, .dist = 8.5 },
        };
        for (targets) |t| {
            if (rl.isKeyPressed(t.key)) cam.setTarget(body_positions[t.idx], t.dist);
        }

        if (rl.isKeyPressed(.b)) use_backface_culling = !use_backface_culling;

        // no atravesar los planetas con la camara
        for (bodies, 0..) |b, i| cam.applyCollisionSphere(body_positions[i], b.radius + 0.5);

        fb.clear();

        const sw: f32 = @floatFromInt(screen_width);
        const sh: f32 = @floatFromInt(screen_height);
        const view_mat = cam.getViewMatrix();
        const proj_mat = cam.getProjectionMatrix(sw / sh);

        // dibujar estrellas de fondo
        sky.render(&fb, cam.forward, cam.up, cam.fov, sw, sh);

        // dibujar los planetas
        if (sphere_mesh) |*sm| {
            for (bodies, 0..) |b, i| {
                const pos = body_positions[i];
                const trans = Mat4.translation(pos.x, pos.y, pos.z);
                const rot = Mat4.rotationY(sim_time * b.rotation_speed);
                const scale = Mat4.scaling(b.radius, b.radius, b.radius);
                const model_mat = Mat4.multiply(trans, Mat4.multiply(rot, scale));
                const mvp = Mat4.multiply(proj_mat, Mat4.multiply(view_mat, model_mat));

                try renderMesh(init.io, sm, .{
                    .model_mat = model_mat,
                    .mvp = mvp,
                    .pos = pos,
                    .cam_pos = cam.position,
                    .sun_pos = .{ .x = 0, .y = 0, .z = 0 },
                    .override_color = b.color,
                    .is_sun = b.is_sun,
                    .is_sphere = true,
                    .sun_texture = if (b.is_sun) sun_texture else null,
                    .sim_time = sim_time,
                    .rot_speed = b.rotation_speed,
                    .sw = sw,
                    .sh = sh,
                    .use_backface_culling = use_backface_culling,
                }, &fb);
            }
        }

        // dibujar la nave en su orbita
        if (ship_mesh) |*sm| {
            const ship_angle = sim_time * 0.5;
            const ship_dist: f32 = 12.5;
            const ship_pos = rl.Vector3{
                .x = @cos(ship_angle) * ship_dist,
                .y = @sin(sim_time * 0.8) * 0.6,
                .z = @sin(ship_angle) * ship_dist,
            };

            const trans = Mat4.translation(ship_pos.x, ship_pos.y, ship_pos.z);
            const rot = Mat4.rotationY(-ship_angle + std.math.pi * 0.5);
            const scale = Mat4.scaling(0.25, 0.25, 0.25);
            const model_mat = Mat4.multiply(trans, Mat4.multiply(rot, scale));
            const mvp = Mat4.multiply(proj_mat, Mat4.multiply(view_mat, model_mat));

            try renderMesh(init.io, sm, .{
                .model_mat = model_mat,
                .mvp = mvp,
                .pos = ship_pos,
                .cam_pos = cam.position,
                .sun_pos = .{ .x = 0, .y = 0, .z = 0 },
                .override_color = null,
                .is_sun = false,
                .is_sphere = false,
                .sun_texture = null,
                .sim_time = sim_time,
                .rot_speed = 0.0,
                .sw = sw,
                .sh = sh,
                .use_backface_culling = use_backface_culling,
            }, &fb);
        }

        // brillo del sol hacia los demas planetas
        const sun_dist = cam.position.length();
        if (sun_dist > 0.1) {
            const vp = Mat4.multiply(proj_mat, view_mat);
            if (root.camera.projectPointWithMVP(vp, .{ .x = 0, .y = 0, .z = 0 }, sw, sh)) |scp| {
                const s_rad = (bodies[0].radius / sun_dist) * (sh * 0.5) / @tan(cam.fov * 0.5);
                if (s_rad > 1.5 and s_rad < sw * 2.0) fb.draw_sun_halo(scp.p, s_rad, scp.z);
            }
        }

        // mostrar imagen final en pantalla
        rl.beginDrawing();
        try fb.swap_buffers();
        rl.endDrawing();
    }
}

// parametros para dibujar un modelo
const RenderParams = struct {
    model_mat: Mat4,
    mvp: Mat4,
    pos: rl.Vector3,
    cam_pos: rl.Vector3,
    sun_pos: rl.Vector3,
    override_color: ?rl.Color,
    is_sun: bool,
    is_sphere: bool,
    sun_texture: ?rl.Image,
    sim_time: f32,
    rot_speed: f32,
    sw: f32,
    sh: f32,
    use_backface_culling: bool,
};

// dibujar en paralelo usando varios hilos
fn renderMesh(init_io: anytype, mesh: *const Mesh, params: RenderParams, fb: *Framebuffer) !void {
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
fn shadeVertex(base: rl.Color, v: rl.Vector3, n: rl.Vector3, sun_pos: rl.Vector3, cam_pos: rl.Vector3) rl.Color {
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

    // color calido de la luz del sol
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

        const p0 = root.camera.projectPointWithMVP(params.mvp, v0, params.sw, params.sh) orelse continue;
        const p1 = root.camera.projectPointWithMVP(params.mvp, v1, params.sw, params.sh) orelse continue;
        const p2 = root.camera.projectPointWithMVP(params.mvp, v2, params.sw, params.sh) orelse continue;

        if (params.use_backface_culling and root.isBackFace2D(p0.p, p1.p, p2.p)) continue;

        if (params.is_sun and params.sun_texture != null) {
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
                params.sun_texture.?,
                -params.sim_time * params.rot_speed,
            );
        } else {
            const base_color = params.override_color orelse face.color;

            const w0 = params.model_mat.transformPoint(v0);
            const w1 = params.model_mat.transformPoint(v1);
            const w2 = params.model_mat.transformPoint(v2);
            const v0_w = rl.Vector3{ .x = w0.x, .y = w0.y, .z = w0.z };
            const v1_w = rl.Vector3{ .x = w1.x, .y = w1.y, .z = w1.z };
            const v2_w = rl.Vector3{ .x = w2.x, .y = w2.y, .z = w2.z };

            const n0: rl.Vector3 = if (params.is_sphere) v0_w.subtract(params.pos).normalize() else (Triangle3D{ .v0 = v0_w, .v1 = v1_w, .v2 = v2_w }).normal();
            const n1: rl.Vector3 = if (params.is_sphere) v1_w.subtract(params.pos).normalize() else n0;
            const n2: rl.Vector3 = if (params.is_sphere) v2_w.subtract(params.pos).normalize() else n0;

            const c0 = shadeVertex(base_color, v0_w, n0, params.sun_pos, params.cam_pos);
            const c1 = shadeVertex(base_color, v1_w, n1, params.sun_pos, params.cam_pos);
            const c2 = shadeVertex(base_color, v2_w, n2, params.sun_pos, params.cam_pos);

            fb.draw_triangle_gouraud(p0.p, p1.p, p2.p, p0.z, p1.z, p2.z, c0, c1, c2);
        }
    }
}
