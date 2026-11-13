const std = @import("std");
const rl = @import("raylib");
const root = @import("root.zig");

const Mat4 = root.Mat4;
const Camera = root.Camera;
const Framebuffer = root.Framebuffer;
const Mesh = root.Mesh;
const Skybox = root.Skybox;
const AsteroidBelt = root.AsteroidBelt;
const renderMesh = root.renderMesh;
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

    // codigo implementado con gemini 3.8
    // https://www.raylib.com/examples/models/loader.html?name=models_skybox_rendering
    const sky = Skybox.init();

    // crear cinturon de asteroides y nubes de gas
    const belt = AsteroidBelt.init();

    // cargar texturas de los planetas y modelos 3d
    const textures = [_]?rl.Image{
        rl.loadImage("assets/textures/sun.png") catch null,
        rl.loadImage("assets/textures/mercury.png") catch null,
        rl.loadImage("assets/textures/earth.png") catch null,
        rl.loadImage("assets/textures/moon.png") catch null,
        rl.loadImage("assets/textures/mars.png") catch null,
        rl.loadImage("assets/textures/jupiter.png") catch null,
        null,
    };
    defer for (textures) |tex| {
        if (tex) |t| {
            rl.unloadImage(t);
        }
    };

    var sphere_mesh: ?Mesh = loadOBJ(allocator, "assets/sphere.obj") catch null;
    defer {
        if (sphere_mesh) |*m| {
            m.deinit();
        }
    }

    var ship_mesh: ?Mesh = loadOBJ(allocator, "assets/cohete.obj") catch null;
    defer {
        if (ship_mesh) |*m| {
            m.deinit();
        }
    }

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
        .{ .radius = 0.35, .orbit_distance = 18.2, .orbit_speed = 0.36, .rotation_speed = 0.6, .color = .{ .r = 150, .g = 145, .b = 140, .a = 255 } },
    };

    var sim_time: f32 = 0.0;
    var is_paused: bool = false;
    var prev_mouse = rl.getMousePosition();

    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();

        // pausar o reanudar el movimiento con espacio
        if (rl.isKeyPressed(.space)) {
            is_paused = !is_paused;
        }
        if (!is_paused) {
            sim_time += dt;
        }

        // mover camara con mouse y wasd
        const mouse = rl.getMousePosition();
        if (rl.isMouseButtonDown(.right)) {
            cam.rotate((prev_mouse.x - mouse.x) * 0.005, (prev_mouse.y - mouse.y) * 0.005);
        }
        prev_mouse = mouse;

        const rot_speed = 1.8 * dt;
        var delta_yaw: f32 = 0.0;
        var delta_pitch: f32 = 0.0;
        if (rl.isKeyDown(.w)) {
            delta_pitch += rot_speed;
        }
        if (rl.isKeyDown(.s)) {
            delta_pitch -= rot_speed;
        }
        if (rl.isKeyDown(.a)) {
            delta_yaw -= rot_speed;
        }
        if (rl.isKeyDown(.d)) {
            delta_yaw += rot_speed;
        }
        cam.rotate(delta_yaw, delta_pitch);

        // acercar o alejar con rueda o flechas
        const wheel = rl.getMouseWheelMove();
        if (wheel != 0.0) {
            cam.zoom(-wheel * 2.0);
        }
        if (rl.isKeyDown(.up)) {
            cam.zoom(-15.0 * dt);
        }
        if (rl.isKeyDown(.down)) {
            cam.zoom(15.0 * dt);
        }

        // calcular posiciones de los planetas
        var body_positions: [bodies.len]rl.Vector3 = undefined;
        for (bodies, 0..) |b, i| {
            const ang = sim_time * b.orbit_speed;
            const local = rl.Vector3{ .x = @cos(ang) * b.orbit_distance, .y = 0, .z = @sin(ang) * b.orbit_distance };
            body_positions[i] = if (b.parent_index) |p_idx| body_positions[p_idx].add(local) else local;
        }

        // viaje rapido con teclas del 1 al 7
        const targets = [_]struct { key: rl.KeyboardKey, idx: usize, dist: f32 }{
            .{ .key = .one, .idx = 0, .dist = 25.0 },
            .{ .key = .two, .idx = 1, .dist = 4.0 },
            .{ .key = .three, .idx = 2, .dist = 5.0 },
            .{ .key = .four, .idx = 3, .dist = 3.0 },
            .{ .key = .five, .idx = 4, .dist = 5.0 },
            .{ .key = .six, .idx = 5, .dist = 8.5 },
            .{ .key = .seven, .idx = 6, .dist = 2.5 },
        };
        for (targets) |t| {
            if (rl.isKeyPressed(t.key)) {
                cam.setTarget(body_positions[t.idx], t.dist);
            }
        }

        // no atravesar los planetas con la camara
        for (bodies, 0..) |b, i| {
            cam.applyCollisionSphere(body_positions[i], b.radius + 0.5);
        }

        fb.clear();

        const sw: f32 = @floatFromInt(screen_width);
        const sh: f32 = @floatFromInt(screen_height);
        const view_mat = cam.getViewMatrix();
        const proj_mat = cam.getProjectionMatrix(sw / sh);
        const vp = Mat4.multiply(proj_mat, view_mat);

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
                    .texture = textures[i],
                    .sim_time = sim_time,
                    .rot_speed = b.rotation_speed,
                    .sw = sw,
                    .sh = sh,
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
                .texture = null,
                .sim_time = sim_time,
                .rot_speed = 0.0,
                .sw = sw,
                .sh = sh,
            }, &fb);
        }

        // dibujar el cinturon de asteroides y gas verde
        belt.render(&fb, vp, cam.position, sim_time, sw, sh, cam.fov);

        // brillo del sol hacia los demas planetas
        const sun_dist = cam.position.length();
        if (sun_dist > 0.1) {
            if (root.camera.projectPointWithMVP(vp, .{ .x = 0, .y = 0, .z = 0 }, sw, sh)) |scp| {
                const s_rad = (bodies[0].radius / sun_dist) * (sh * 0.5) / @tan(cam.fov * 0.5);
                if (s_rad > 1.5 and s_rad < sw * 2.0) {
                    fb.draw_sun_halo(scp.p, s_rad, scp.z);
                }
            }
        }

        // mostrar imagen final en pantalla
        rl.beginDrawing();
        try fb.swap_buffers();
        rl.endDrawing();
    }
}
