const std = @import("std");
const rl = @import("raylib");
const triangle_mod = @import("triangle.zig");
pub const TriangleFace = triangle_mod.TriangleFace;
pub const Triangle3D = triangle_mod.Triangle3D;

pub const Mesh = struct {
    vertices: []rl.Vector3,
    triangles: []TriangleFace,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Mesh) void {
        self.allocator.free(self.vertices);
        self.allocator.free(self.triangles);
    }
};

// cargar archivo obj y convertir caras a triangulos
pub fn loadOBJ(allocator: std.mem.Allocator, path: [:0]const u8) !Mesh {
    const raw_text = rl.loadFileText(path);
    if (raw_text.len == 0) return error.FileNotFoundOrEmpty;
    defer rl.unloadFileText(raw_text);

    var vertices: std.ArrayList(rl.Vector3) = .empty;
    defer vertices.deinit(allocator);

    var triangles: std.ArrayList(TriangleFace) = .empty;
    defer triangles.deinit(allocator);

    var face_indices: std.ArrayList(usize) = .empty;
    defer face_indices.deinit(allocator);

    // color plateado para la nave
    var current_color = rl.Color{ .r = 195, .g = 200, .b = 210, .a = 255 };

    var line_it = std.mem.splitScalar(u8, raw_text, '\n');
    while (line_it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        // revisar que parte de la nave es
        if (std.mem.startsWith(u8, line, "o ")) {
            const name = std.mem.trim(u8, line[2..], " \t\r");
            if (std.mem.startsWith(u8, name, "Cone") or std.mem.startsWith(u8, name, "Plane")) {
                // punta y aletas en rojo
                current_color = rl.Color{ .r = 215, .g = 35, .b = 35, .a = 255 };
            } else {
                // fuselaje en plateado
                current_color = rl.Color{ .r = 195, .g = 200, .b = 210, .a = 255 };
            }
        } else if (std.mem.startsWith(u8, line, "v ")) {
            var tok_it = std.mem.tokenizeAny(u8, line[2..], " \t");
            const x = std.fmt.parseFloat(f32, tok_it.next() orelse continue) catch continue;
            const y = std.fmt.parseFloat(f32, tok_it.next() orelse continue) catch continue;
            const z = std.fmt.parseFloat(f32, tok_it.next() orelse continue) catch continue;
            try vertices.append(allocator, .{ .x = x, .y = y, .z = z });
        } else if (std.mem.startsWith(u8, line, "f ")) {
            face_indices.clearRetainingCapacity();
            var tok_it = std.mem.tokenizeAny(u8, line[2..], " \t");

            while (tok_it.next()) |token| {
                var slash_it = std.mem.splitScalar(u8, token, '/');
                const v_str = slash_it.next() orelse continue;
                if (v_str.len == 0) continue;

                const raw_idx = std.fmt.parseInt(i32, v_str, 10) catch continue;
                const v_idx: usize = if (raw_idx > 0)
                    @intCast(raw_idx - 1)
                else if (raw_idx < 0)
                    @intCast(@as(i32, @intCast(vertices.items.len)) + raw_idx)
                else
                    continue;

                try face_indices.append(allocator, v_idx);
            }

            // dividir caras de cuatro lados en triangulos
            const n = face_indices.items.len;
            if (n >= 3) {
                var i: usize = 1;
                while (i + 1 < n) : (i += 1) {
                    try triangles.append(allocator, .{
                        .v0 = face_indices.items[0],
                        .v1 = face_indices.items[i],
                        .v2 = face_indices.items[i + 1],
                        .color = current_color,
                    });
                }
            }
        }
    }

    if (vertices.items.len == 0) return error.NoVerticesFound;

    return Mesh{
        .vertices = try vertices.toOwnedSlice(allocator),
        .triangles = try triangles.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}
