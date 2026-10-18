const std = @import("std");
const Allocator = std.mem.Allocator;

const Font = @import("../font.zig").Font;
const Tables = @import("../font.zig").Tables;
const BitmapBox = @import("../font.zig").BitmapBox;
const Vertex = @import("../font.zig").Vertex;

const readInt = @import("../font.zig").readInt;
const readCursor = @import("../font.zig").readCursor;

pub fn glyphBox(f: *const Font, glyph: i32) ?BitmapBox {
    const g = glyfOffset(f, glyph) orelse return null;
    return .{
        .x0 = readInt(i16, f.font_bytes[g + 2 ..][0..2]),
        .y1 = -readInt(i16, f.font_bytes[g + 4 ..][0..2]),
        .x1 = readInt(i16, f.font_bytes[g + 6 ..][0..2]),
        .y0 = -readInt(i16, f.font_bytes[g + 8 ..][0..2]),
    };
}

pub fn glyphShape(f: *const Font, gpa: Allocator, glyph: i32) ![]Vertex {
    const bytes = f.font_bytes;
    const g = glyfOffset(f, glyph) orelse return &.{};

    var vertices: std.ArrayList(Vertex) = .empty;
    defer vertices.deinit(gpa);

    const n_contours_signed = readInt(i16, bytes[g..][0..2]);

    if (n_contours_signed > 0) {
        const n_contours: u16 = @intCast(n_contours_signed);
        const contours_end_pts: u32 = g + 10;
        const ins: i32 = readInt(u16, bytes[g + 10 + n_contours * 2 ..][0..2]);
        var points: u32 = @intCast(g + 10 + @as(i64, n_contours) * 2 + 2 + ins);

        const n: u32 = 1 + readInt(u16, bytes[contours_end_pts + n_contours * 2 - 2 ..][0..2]);

        // A loose bound on how many vertices we might need.
        const m: u32 = n + 2 * n_contours;
        try vertices.resize(gpa, m);

        var next_move: i32 = 0;
        var flagcount: u8 = 0;

        // in first pass, we load uninterpreted data into the allocated array
        // above, shifted to the end of the array so we won't overwrite it when
        // we create our final data starting from the front

        // Starting offset for uninterpreted data, regardless of how m ends up being calculated.
        const off: u32 = m - n;

        // first load flags
        {
            var flags: u8 = 0;
            for (0..n) |i| {
                if (flagcount == 0) {
                    flags = bytes[points];
                    points += 1;
                    if ((flags & 8) != 0) {
                        flagcount = bytes[points];
                        points += 1;
                    }
                } else {
                    flagcount -= 1;
                }
                vertices.items[off + i].type = @fromBackingInt(@intCast(flags));
            }
        }

        // now load x coordinates
        var x: i32 = 0;
        for (0..n) |i| {
            const flags = @backingInt(vertices.items[off + i].type);
            if ((flags & 2) != 0) {
                const dx: i16 = bytes[points];
                points += 1;
                x += if ((flags & 16) != 0) dx else -dx;
            } else {
                if ((flags & 16) == 0) {
                    x += readInt(i16, bytes[points..][0..2]);
                    points += 2;
                }
            }
            vertices.items[off + i].x = @intCast(x);
        }

        // now load y coordinates
        var y: i32 = 0;
        for (0..n) |i| {
            const flags = @backingInt(vertices.items[off + i].type);
            if ((flags & 4) != 0) {
                const dy: i16 = bytes[points];
                points += 1;
                y += if ((flags & 32) != 0) dy else -dy;
            } else {
                if ((flags & 32) == 0) {
                    y += readInt(i16, bytes[points..][0..2]);
                    points += 2;
                }
            }
            vertices.items[off + i].y = @intCast(y);
        }

        // now convert them to our format
        var num_vertices: u32 = 0;
        var sx: i32 = 0;
        var sy: i32 = 0;
        var cx: i32 = 0;
        var cy: i32 = 0;
        var scx: i32 = 0;
        var scy: i32 = 0;
        var i: u32 = 0;
        var j: u32 = 0;
        var start_off: bool = false;
        var was_off: bool = false;

        while (i < n) : (i += 1) {
            const flags = @backingInt(vertices.items[off + i].type);
            x = @intCast(vertices.items[off + i].x);
            y = @intCast(vertices.items[off + i].y);

            if (next_move == i) {
                if (i != 0)
                    num_vertices = closeShape(vertices.items, num_vertices, was_off, start_off, sx, sy, scx, scy, cx, cy);

                // now start the new one
                start_off = (flags & 1) == 0;
                if (start_off) {
                    // if we start off with an off-curve point, then when we need to find a point on the curve
                    // where we can start, and we need to save some state for when we wraparound.
                    scx = x;
                    scy = y;
                    if ((@backingInt(vertices.items[off + i + 1].type) & 1) == 0) {
                        // next point is also a curve point, so interpolate an on-point curve
                        sx = (x + vertices.items[off + i + 1].x) >> 1;
                        sy = (y + vertices.items[off + i + 1].y) >> 1;
                    } else {
                        // otherwise just use the next point as our start point
                        sx = vertices.items[off + i + 1].x;
                        sy = vertices.items[off + i + 1].y;
                        i += 1; // we're using point i+1 as the starting point, so skip it
                    }
                } else {
                    sx = x;
                    sy = y;
                }
                vertices.items[num_vertices].set(.vmove, sx, sy, 0, 0);
                num_vertices += 1;
                was_off = false;
                next_move = 1 + readInt(u16, bytes[contours_end_pts + j * 2 ..][0..2]);
                j += 1;
            } else {
                if ((flags & 1) == 0) { // if it's a curve
                    if (was_off) {
                        // two off-curve control points in a row means interpolate an on-curve midpoint
                        vertices.items[num_vertices].set(.vquad, (cx + x) >> 1, (cy + y) >> 1, cx, cy);
                        num_vertices += 1;
                    }
                    cx = x;
                    cy = y;
                    was_off = true;
                } else {
                    if (was_off)
                        vertices.items[num_vertices].set(.vquad, x, y, cx, cy)
                    else
                        vertices.items[num_vertices].set(.vline, x, y, 0, 0);
                    num_vertices += 1;
                    was_off = false;
                }
            }
        }
        num_vertices = closeShape(vertices.items, num_vertices, was_off, start_off, sx, sy, scx, scy, cx, cy);
        vertices.shrinkRetainingCapacity(num_vertices);
    } else if (n_contours_signed < 0) {
        // Compound shapes.
        var more = true;
        var comp = g + 10;
        while (more) {
            var mtx: [6]f32 = .{ 1, 0, 0, 1, 0, 0 };

            const flags = readCursor(u16, bytes, &comp);
            const gidx: i32 = @intCast(readCursor(u16, bytes, &comp));

            if ((flags & 2) != 0) { // XY values
                if ((flags & 1) != 0) { // shorts
                    mtx[4] = @floatFromInt(readCursor(i16, bytes, &comp));
                    mtx[5] = @floatFromInt(readCursor(i16, bytes, &comp));
                } else {
                    mtx[4] = @floatFromInt(readCursor(i8, bytes, &comp));
                    mtx[5] = @floatFromInt(readCursor(i8, bytes, &comp));
                }
            } else {
                //if (debug_todo) @panic("TODO handle matching point");
            }
            if ((flags & (1 << 3)) != 0) { // WE_HAVE_A_SCALE
                mtx[0] = @as(f32, @floatFromInt(readCursor(i16, bytes, &comp))) / 16384.0;
                mtx[1] = 0;
                mtx[2] = 0;
                mtx[3] = mtx[0];
            } else if ((flags & (1 << 6)) != 0) { // WE_HAVE_AN_X_AND_YSCALE
                mtx[0] = @as(f32, @floatFromInt(readCursor(i16, bytes, &comp))) / 16384.0;
                mtx[1] = 0;
                mtx[2] = 0;
                mtx[3] = @as(f32, @floatFromInt(readCursor(i16, bytes, &comp))) / 16384.0;
            } else if ((flags & (1 << 7)) != 0) { // WE_HAVE_A_TWO_BY_TWO
                mtx[0] = @as(f32, @floatFromInt(readCursor(i16, bytes, &comp))) / 16384.0;
                mtx[1] = @as(f32, @floatFromInt(readCursor(i16, bytes, &comp))) / 16384.0;
                mtx[2] = @as(f32, @floatFromInt(readCursor(i16, bytes, &comp))) / 16384.0;
                mtx[3] = @as(f32, @floatFromInt(readCursor(i16, bytes, &comp))) / 16384.0;
            }

            // Find transformation scales.
            const m: f32 = @sqrt(mtx[0] * mtx[0] + mtx[1] * mtx[1]);
            const n: f32 = @sqrt(mtx[2] * mtx[2] + mtx[3] * mtx[3]);

            // Get indexed glyph.
            const comp_verts = try glyphShape(f, gpa, gidx);
            defer gpa.free(comp_verts);
            if (comp_verts.len > 0) {
                // Transform vertices.
                for (comp_verts) |*v| {
                    {
                        const x: f32 = @floatFromInt(v.x);
                        const y: f32 = @floatFromInt(v.y);
                        v.x = @intFromFloat(m * (mtx[0] * x + mtx[2] * y + mtx[4]));
                        v.y = @intFromFloat(n * (mtx[1] * x + mtx[3] * y + mtx[5]));
                    }
                    {
                        const x: f32 = @floatFromInt(v.cx);
                        const y: f32 = @floatFromInt(v.cy);
                        v.cx = @intFromFloat(m * (mtx[0] * x + mtx[2] * y + mtx[4]));
                        v.cy = @intFromFloat(n * (mtx[1] * x + mtx[3] * y + mtx[5]));
                    }
                }
                try vertices.appendSlice(gpa, comp_verts);
            }
            more = (flags & (1 << 5)) != 0;
        }
    }
    return vertices.toOwnedSlice(gpa);
}

fn closeShape(vertices: []Vertex, vertices_len_start: u32, was_off: bool, start_off: bool, sx: i32, sy: i32, scx: i32, scy: i32, cx: i32, cy: i32) u32 {
    var vertices_len = vertices_len_start;
    if (start_off) {
        if (was_off) {
            vertices[vertices_len].set(.vquad, (cx + scx) >> 1, (cy + scy) >> 1, cx, cy);
            vertices_len += 1;
        }
        vertices[vertices_len].set(.vquad, sx, sy, scx, scy);
        vertices_len += 1;
    } else {
        if (was_off) {
            vertices[vertices_len].set(.vquad, sx, sy, cx, cy);
            vertices_len += 1;
        } else {
            vertices[vertices_len].set(.vline, sx, sy, 0, 0);
            vertices_len += 1;
        }
    }
    return vertices_len;
}

fn glyfOffset(f: *const Font, glyph: i32) ?u32 {
    const bytes = f.font_bytes;
    const glyph_index: usize = @intCast(glyph);

    if (glyph_index >= f.glyphs_len) return null;

    const glyf = f.table_offsets[Tables.glyf.int()];
    const loca = f.table_offsets[Tables.loca.int()];
    const head = f.table_offsets[Tables.head.int()];
    const index_to_loc_format = readInt(u16, bytes[head + 50 ..][0..2]);

    const g1, const g2 = if (index_to_loc_format == 0) .{
        glyf + @as(u32, readInt(u16, bytes[loca + glyph_index * 2 ..][0..2])) * 2,
        glyf + @as(u32, readInt(u16, bytes[loca + glyph_index * 2 + 2 ..][0..2])) * 2,
    } else .{
        glyf + readInt(u32, bytes[loca + glyph_index * 4 ..][0..4]),
        glyf + readInt(u32, bytes[loca + glyph_index * 4 + 4 ..][0..4]),
    };
    if (g1 == g2) return null;
    return g1;
}
