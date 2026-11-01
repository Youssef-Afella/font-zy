const std = @import("std");
const Allocator = std.mem.Allocator;

const Font = @import("font.zig").Font;
const Vertex = @import("font.zig").Vertex;
const Point = @import("font.zig").Point;
const Edge = @import("font.zig").Edge;
const Rect = @import("font.zig").Rect;

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

pub fn getEdgeList(gpa: Allocator, vertices: []Vertex, scale: f32, rect: Rect) !struct { []Edge, []Edge } {
    var curves = try flattenCurves(gpa, vertices, 6.0 / scale);
    defer curves.deinit(gpa);

    return try toEdgeList(gpa, curves.points, curves.contour_lengths, rect);
}

fn toEdgeList(gpa: Allocator, pts: []Point, wcount: []u32, rect: Rect) !struct { []Edge, []Edge } {
    const xmin: f32 = @floatFromInt(rect.x0);
    const ymin: f32 = @floatFromInt(rect.y0);

    const edge_alloc_n = n: {
        var n: u32 = 1;
        for (wcount) |elem| n += elem;
        break :n n;
    };

    const m_lines = try gpa.alloc(Edge, edge_alloc_n);
    const v_lines = try gpa.alloc(Edge, edge_alloc_n);

    var m_line_count: u32 = 0;
    var v_line_count: u32 = 0;

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

            const x0 = p[a].x - xmin;
            const y0 = -p[a].y - ymin;
            const x1 = p[b].x - xmin;
            const y1 = -p[b].y - ymin;

            if (x0 == x1) {
                v_lines[v_line_count].x0 = x0;
                v_lines[v_line_count].y0 = y0;
                v_lines[v_line_count].x1 = x1;
                v_lines[v_line_count].y1 = y1;
                v_line_count += 1;
            } else {
                m_lines[m_line_count].x0 = x0;
                m_lines[m_line_count].y0 = y0;
                m_lines[m_line_count].x1 = x1;
                m_lines[m_line_count].y1 = y1;
                m_line_count += 1;
            }
        }
    }

    return .{
        try gpa.realloc(m_lines, m_line_count),
        try gpa.realloc(v_lines, v_line_count),
    };
}

fn flattenCurves(gpa: Allocator, vertices: []const Vertex, max_area: f32) !FlatCurves {
    var points: std.ArrayList(Point) = .empty;
    defer points.deinit(gpa);
    var contour_lengths: std.ArrayList(u32) = .empty;
    defer contour_lengths.deinit(gpa);

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
                    max_area,
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

fn tesselateQuadratic(gpa: Allocator, points: *std.ArrayList(Point), x0: f32, y0: f32, x1: f32, y1: f32, x2: f32, y2: f32, max_area: f32) !void {
    const Seg = struct { ax: f32, ay: f32, at: f32, cx: f32, cy: f32, ct: f32, depth: u8 };
    const max_depth = 16;

    var stack: [max_depth + 2]Seg = undefined;
    stack[0] = .{ .ax = x0, .ay = y0, .at = 0.0, .cx = x2, .cy = y2, .ct = 1.0, .depth = 0 };
    var sp: usize = 1;

    while (sp > 0) {
        sp -= 1;
        const s = stack[sp];

        const bt = (s.at + s.ct) * 0.5;
        const tm = 1.0 - bt;
        const qa = tm * tm;
        const qb = 2.0 * tm * bt;
        const qc = bt * bt;
        const bx = qa * x0 + qb * x1 + qc * x2;
        const by = qa * y0 + qb * y1 + qc * y2;

        const area = (bx - s.ax) * (s.cy - s.ay) - (s.cx - s.ax) * (by - s.ay);

        if (@abs(area) > max_area and s.depth < max_depth) {
            stack[sp] = .{ .ax = bx, .ay = by, .at = bt, .cx = s.cx, .cy = s.cy, .ct = s.ct, .depth = s.depth + 1 };
            sp += 1;
            stack[sp] = .{ .ax = s.ax, .ay = s.ay, .at = s.at, .cx = bx, .cy = by, .ct = bt, .depth = s.depth + 1 };
            sp += 1;
        } else {
            try points.append(gpa, .{ .x = s.cx, .y = s.cy });
        }
    }
}
