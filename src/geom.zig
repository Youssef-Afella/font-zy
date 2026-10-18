const std = @import("std");
const Allocator = std.mem.Allocator;

const Font = @import("font.zig").Font;
const Vertex = @import("font.zig").Vertex;
const Point = @import("font.zig").Point;
const Edge = @import("font.zig").Edge;
const BitmapBox = @import("font.zig").BitmapBox;

pub const FlatCurves = struct {
    points: []Point,
    contour_lengths: []u32,

    const empty: FlatCurves = .{
        .points = &.{},
        .contour_lengths = &.{},
    };

    pub fn deinit(fc: *FlatCurves, gpa: Allocator) void {
        gpa.free(fc.points);
        gpa.free(fc.contour_lengths);
        fc.* = undefined;
    }
};

pub fn getEdgeList(gpa: Allocator, vertices: []Vertex, scale: f32, box: BitmapBox) ![]Edge {
    var curves = try flattenCurves(gpa, vertices, 0.1 / scale);
    defer curves.deinit(gpa);

    return try toEdgeList(gpa, curves.points, curves.contour_lengths, box);
}

fn toEdgeList(gpa: Allocator, pts: []Point, wcount: []u32, box: BitmapBox) ![]Edge {
    const xmin: f32 = @floatFromInt(box.x0);
    const ymin: f32 = @floatFromInt(box.y0);

    const edge_alloc_n = n: {
        var n: u32 = 1;
        for (wcount) |elem| n += elem;
        break :n n;
    };

    const e = try gpa.alloc(Edge, edge_alloc_n);

    var n: u32 = 0;
    var m: u32 = 0;
    for (wcount) |wcount_elem| {
        const p: []Point = pts[m..];
        m += wcount_elem;
        var j: u32 = wcount_elem - 1;
        var k: u32 = 0;
        while (k < wcount_elem) : ({
            j = k;
            k += 1;
        }) {
            const a = k;
            const b = j;

            if (p[j].y == p[k].y)
                continue;

            e[n].x0 = p[a].x - xmin;
            e[n].y0 = -p[a].y - ymin;
            e[n].x1 = p[b].x - xmin;
            e[n].y1 = -p[b].y - ymin;

            n += 1;
        }
    }
    return try gpa.realloc(e, n);
}

fn flattenCurves(gpa: Allocator, vertices: []const Vertex, objspace_flatness: f32) !FlatCurves {
    var points: std.ArrayList(Point) = .empty;
    defer points.deinit(gpa);
    var contour_lengths: std.ArrayList(u32) = .empty;
    defer contour_lengths.deinit(gpa);

    const objspace_flatness_squared = objspace_flatness * objspace_flatness;

    var start: u32 = 0;
    var x: f32 = 0;
    var y: f32 = 0;
    for (vertices) |v| {
        sw: switch (v.type) {
            .vmove => {
                if (points.items.len > 0) {
                    try contour_lengths.append(gpa, @intCast(points.items.len - start));
                    start = @intCast(points.items.len);
                }

                continue :sw .vline;
            },
            .vline => {
                x = @floatFromInt(v.x);
                y = @floatFromInt(v.y);
                try points.append(gpa, .{ .x = x, .y = y });
            },
            .vquad => {
                try tesselateQuadratic(
                    gpa,
                    &points,
                    x,
                    y,
                    @as(f32, @floatFromInt(v.cx)),
                    @as(f32, @floatFromInt(v.cy)),
                    @as(f32, @floatFromInt(v.x)),
                    @as(f32, @floatFromInt(v.y)),
                    objspace_flatness_squared,
                    0,
                );
                x = @floatFromInt(v.x);
                y = @floatFromInt(v.y);
            },
            .vcubic => {
                //TODO: Cubic curves (OpenType)
            },
            _ => continue,
        }
    }
    try contour_lengths.append(gpa, @intCast(points.items.len - start));

    return .{
        .points = try points.toOwnedSlice(gpa),
        .contour_lengths = try contour_lengths.toOwnedSlice(gpa),
    };
}

fn tesselateQuadratic(gpa: Allocator, points: *std.ArrayList(Point), x0: f32, y0: f32, x1: f32, y1: f32, x2: f32, y2: f32, objspace_flatness_squared: f32, n: u32) !void {
    // midpoint
    const mx: f32 = (x0 + 2 * x1 + x2) / 4;
    const my: f32 = (y0 + 2 * y1 + y2) / 4;
    // versus directly drawn line
    const dx: f32 = (x0 + x2) / 2 - mx;
    const dy: f32 = (y0 + y2) / 2 - my;
    if (n > 16) // 65536 segments on one curve better be enough!
        return;
    if (dx * dx + dy * dy > objspace_flatness_squared) { // half-pixel error allowed... need to be smaller if AA
        try tesselateQuadratic(gpa, points, x0, y0, (x0 + x1) / 2.0, (y0 + y1) / 2.0, mx, my, objspace_flatness_squared, n + 1);
        try tesselateQuadratic(gpa, points, mx, my, (x1 + x2) / 2.0, (y1 + y2) / 2.0, x2, y2, objspace_flatness_squared, n + 1);
    } else {
        try points.append(gpa, .{ .x = x2, .y = y2 });
    }
}
