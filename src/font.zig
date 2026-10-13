//WIP Parser
//Based on: https://codeberg.org/andrewrk/TrueType by Andrew Kelly (Thank you so much)

const std = @import("std");
const Allocator = std.mem.Allocator;

const Raster = @import("raster.zig").Raster;

pub const Font = struct {
    font_bytes: []const u8,
    table_offsets: [Tables.count()]u32,
    index_map: u32,
    glyphs_len: u32,

    pub fn load(bytes: []const u8) FontError!Font {
        var table_offsets: [Tables.count()]u32 = @splat(0);
        if (bytes.len < 6) return error.EndOfStream;

        const tables_len = readInt(u16, bytes[4..][0..2]);
        if (12 + 16 * tables_len > bytes.len) return error.EndOfStream;

        for (0..tables_len) |i| {
            const loc = 12 + 16 * i;
            const id: Tables = switch (readInt(u32, bytes[loc..][0..4])) {
                Tables.cmap.tag() => .cmap,
                Tables.loca.tag() => .loca,
                Tables.head.tag() => .head,
                Tables.glyf.tag() => .glyf,
                Tables.hhea.tag() => .hhea,
                Tables.hmtx.tag() => .hmtx,
                Tables.maxp.tag() => .maxp,
                Tables.kern.tag() => .kern,
                else => continue,
            };
            table_offsets[id.int()] = readInt(u32, bytes[loc + 8 ..][0..4]);
        }

        if (table_offsets[Tables.cmap.int()] == 0) return error.MissingRequiredTable;
        if (table_offsets[Tables.loca.int()] == 0) return error.MissingRequiredTable;
        if (table_offsets[Tables.head.int()] == 0) return error.MissingRequiredTable;
        if (table_offsets[Tables.glyf.int()] == 0) return error.MissingRequiredTable;
        if (table_offsets[Tables.hhea.int()] == 0) return error.MissingRequiredTable;
        if (table_offsets[Tables.hmtx.int()] == 0) return error.MissingRequiredTable;
        if (table_offsets[Tables.maxp.int()] == 0) return error.MissingRequiredTable;

        const maxp = table_offsets[Tables.maxp.int()];
        const glyphs_len = readInt(u16, bytes[maxp + 4 ..][0..2]);

        const cmap = table_offsets[Tables.cmap.int()];
        const cmap_tables_len = readInt(u16, bytes[cmap + 2 ..][0..2]);

        const index_map = im: {
            var i = cmap_tables_len - 1;
            while (i > 0) : (i -= 1) {
                const encoding_record = cmap + 4 + 8 * i;
                const platform_id = readInt(u16, bytes[encoding_record..][0..2]);
                switch (platform_id) {
                    @backingInt(PlatformId.microsoft) => switch (readInt(u16, bytes[encoding_record + 2 ..][0..2])) {
                        @backingInt(MicrosoftEncodingId.unicode_bmp),
                        @backingInt(MicrosoftEncodingId.unicode_full),
                        => {
                            break :im cmap + readInt(u32, bytes[encoding_record + 4 ..][0..4]);
                        },
                        else => continue,
                    },
                    @backingInt(PlatformId.unicode) => {
                        break :im cmap + readInt(u32, bytes[encoding_record + 4 ..][0..4]);
                    },
                    else => continue,
                }
            }
            return error.IndexMapMissing;
        };

        return .{
            .table_offsets = table_offsets,
            .font_bytes = bytes,
            .index_map = index_map,
            .glyphs_len = glyphs_len,
        };
    }

    // ---
    // Raster
    // ---
    pub fn rasterize(f: *const Font, raster: *Raster, gpa: Allocator, glyph: i32, scale_x: f32, scale_y: f32, shift_x: f32, shift_y: f32) FontError!void {
        const box = glyphBitmapBox(f, glyph, scale_x, scale_y, shift_x, shift_y);

        const vertices = try glyphShape(f, gpa, glyph);
        defer gpa.free(vertices);

        var curves = try flattenCurves(gpa, vertices, scale_x, scale_y);
        defer curves.deinit(gpa);

        try rasterizeInner(gpa, curves.points, curves.contour_lengths, box, raster);
        raster.fill();
    }

    pub fn precomputeEdges(f: *const Font, gpa: Allocator, glyph: i32, scale_x: f32, scale_y: f32, shift_x: f32, shift_y: f32) FontError![]Edge {
        const box = glyphBitmapBox(f, glyph, scale_x, scale_y, shift_x, shift_y);

        const vertices = try glyphShape(f, gpa, glyph);
        defer gpa.free(vertices);

        var curves = try flattenCurves(gpa, vertices, scale_x, scale_y);
        defer curves.deinit(gpa);

        return try toEdgeList(gpa, curves.points, curves.contour_lengths, box);
    }

    fn toEdgeList(gpa: Allocator, pts: []Point, wcount: []u32, box: BitmapBox) FontError![]Edge {
        const xmin: f32 = @floatFromInt(box.x0);
        const ymax: f32 = @floatFromInt(box.y1);

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
                e[n].y0 = ymax - p[a].y;
                e[n].x1 = p[b].x - xmin;
                e[n].y1 = ymax - p[b].y;

                n += 1;
            }
        }
        return try gpa.realloc(e, n);
    }

    fn rasterizeInner(gpa: Allocator, pts: []Point, wcount: []u32, box: BitmapBox, raster: *Raster) FontError!void {
        const he: []Edge = try toEdgeList(gpa, pts, wcount, box);
        defer gpa.free(he);

        for (he) |edge| {
            raster.drawLine(edge.x0, edge.y0, edge.x1, edge.y1);
        }
    }

    // ---
    // Shape Tranform
    // ---
    const Point = struct { x: f32, y: f32 };
    const FlatCurves = struct {
        points: []Point,
        contour_lengths: []u32,

        const empty: FlatCurves = .{
            .points = &.{},
            .contour_lengths = &.{},
        };

        fn deinit(fc: *FlatCurves, gpa: Allocator) void {
            gpa.free(fc.points);
            gpa.free(fc.contour_lengths);
            fc.* = undefined;
        }
    };
    fn flattenCurves(gpa: Allocator, vertices: []const Vertex, scale_x: f32, scale_y: f32) FontError!FlatCurves {
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
                    try points.append(gpa, .{ .x = x * scale_x, .y = y * scale_y });
                },
                .vquad => {
                    try tesselateQuadratic(
                        gpa,
                        &points,
                        x * scale_x,
                        y * scale_y,
                        @as(f32, @floatFromInt(v.cx)) * scale_x,
                        @as(f32, @floatFromInt(v.cy)) * scale_y,
                        @as(f32, @floatFromInt(v.x)) * scale_x,
                        @as(f32, @floatFromInt(v.y)) * scale_y,
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
    pub fn tesselateQuadratic(gpa: Allocator, points: *std.ArrayList(Point), x0: f32, y0: f32, x1: f32, y1: f32, x2: f32, y2: f32) !void {
        const devx = x0 - 2.0 * x1 + x2;
        const devy = y0 - 2.0 * y1 + y2;
        const devsq = devx * devx + devy * devy;
        if (devsq < 0.333) {
            try points.append(gpa, .{ .x = x2, .y = y2 });
            return;
        }

        const tol = 3.0;
        const n: f32 = 1.0 + @floor(@sqrt(@sqrt(tol * (devx * devx + devy * devy))));

        var px = x0;
        var py = y0;

        const nrecip = 1.0 / n;
        var t: f32 = 0.0;

        for (0..@as(usize, @intFromFloat(n - 1))) |i| {
            _ = i;

            t += nrecip;
            const tt = 1.0 - t;

            const xx0 = tt * x0 + t * x1;
            const xx1 = tt * x1 + t * x2;
            const x = tt * xx0 + t * xx1;

            const yy0 = tt * y0 + t * y1;
            const yy1 = tt * y1 + t * y2;
            const y = tt * yy0 + t * yy1;

            try points.append(gpa, .{ .x = x, .y = y });

            px = x;
            py = y;
        }

        try points.append(gpa, .{ .x = x2, .y = y2 });
    }

    // ---
    // Shape Parsing
    // ---
    pub const Vertex = struct {
        x: i16,
        y: i16,
        cx: i16,
        cy: i16,
        cx1: i16,
        cy1: i16,
        type: Type,

        pub const Type = enum(u8) { vmove = 1, vline = 2, vquad = 3, vcubic = 4, _ };
        fn set(v: *Vertex, ty: Type, x: i32, y: i32, cx: i32, cy: i32) void {
            v.type = ty;
            v.x = @intCast(x);
            v.y = @intCast(y);
            v.cx = @intCast(cx);
            v.cy = @intCast(cy);
        }
    };
    fn glyphShape(f: *const Font, gpa: Allocator, glyph: i32) ![]Vertex {
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

    // ---
    // Character Mapping
    // ---
    pub fn glyphIndex(f: *const Font, codepoint: u21) i32 {
        const bytes = f.font_bytes;
        const index_map = f.index_map;
        const format = readInt(u16, bytes[index_map..][0..2]);
        switch (format) {
            0 => {
                const n = readInt(u16, bytes[index_map + 2 ..][0..2]);
                if (codepoint < n - 6)
                    return @intCast(bytes[index_map + 6 + codepoint]);

                return -1;
            },
            2 => {
                return -1;
            },
            4 => {
                const seg_count = readInt(u16, bytes[index_map + 6 ..][0..2]) >> 1;
                var search_range = readInt(u16, bytes[index_map + 8 ..][0..2]) >> 1;
                var entry_selector = readInt(u16, bytes[index_map + 10 ..][0..2]);
                const range_shift = readInt(u16, bytes[index_map + 12 ..][0..2]) >> 1;

                const end_count = index_map + 14;
                var search = end_count;

                if (codepoint > 0xffff)
                    return -1;

                if (codepoint >= readInt(u16, bytes[search + range_shift * 2 ..][0..2]))
                    search += range_shift * 2;

                search -= 2;
                while (entry_selector > 0) {
                    search_range >>= 1;
                    const end = readInt(u16, bytes[search + search_range * 2 ..][0..2]);
                    if (codepoint > end)
                        search += search_range * 2;
                    entry_selector -= 1;
                }
                search += 2;

                const item: u16 = @intCast((search - end_count) >> 1);

                const start = readInt(u16, bytes[index_map + 14 + seg_count * 2 + 2 + 2 * item ..][0..2]);
                const last = readInt(u16, bytes[end_count + 2 * item ..][0..2]);
                if (codepoint < start or codepoint > last)
                    return -1;

                const offset = readInt(u16, bytes[index_map + 14 + seg_count * 6 + 2 + 2 * item ..][0..2]);
                if (offset == 0) {
                    const result = @as(i32, codepoint) + readInt(i16, bytes[index_map + 14 + seg_count * 4 + 2 + 2 * item ..][0..2]);
                    return result;
                }

                return @intCast(readInt(u16, bytes[offset + (codepoint - start) * 2 + index_map + 14 + seg_count * 6 + 2 + 2 * item ..][0..2]));
            },
            6 => {
                const first = readInt(u16, bytes[index_map + 6 ..][0..2]);
                const count = readInt(u16, bytes[index_map + 8 ..][0..2]);
                if (codepoint >= first and codepoint < first + count)
                    return @intCast(readInt(u16, bytes[index_map + 10 + (codepoint - first) * 2 ..][0..2]));

                return -1;
            },
            12, 13 => {
                const ngroups = readInt(u32, bytes[index_map + 12 ..][0..4]);
                var low: u32 = 0;
                var high: u32 = ngroups;
                while (low < high) {
                    const mid = low + ((high - low) >> 1);
                    const off = index_map + 16 + mid * 12;
                    const start_char = readInt(u32, bytes[off..][0..4]);
                    const end_char = readInt(u32, bytes[off + 4 ..][0..4]);
                    if (codepoint < start_char) {
                        high = mid;
                    } else if (codepoint > end_char) {
                        low = mid + 1;
                    } else {
                        const start_glyph = readInt(u32, bytes[off + 8 ..][0..4]);
                        return @intCast(start_glyph + if (format == 12) codepoint - start_char else 0);
                    }
                }
                return -1;
            },
            else => {
                return -1;
            },
        }
    }

    // ---
    // Glyph Info
    // ---
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
    fn glyphBox(f: *const Font, glyph: i32) ?BitmapBox {
        const g = glyfOffset(f, glyph) orelse return null;
        return .{
            .x0 = readInt(i16, f.font_bytes[g + 2 ..][0..2]),
            .y0 = readInt(i16, f.font_bytes[g + 4 ..][0..2]),
            .x1 = readInt(i16, f.font_bytes[g + 6 ..][0..2]),
            .y1 = readInt(i16, f.font_bytes[g + 8 ..][0..2]),
        };
    }
    pub const BitmapBox = struct {
        x0: i32,
        y0: i32,
        x1: i32,
        y1: i32,

        pub const empty: BitmapBox = .{
            .x0 = 0,
            .y0 = 0,
            .x1 = 0,
            .y1 = 0,
        };
    };
    pub fn glyphBitmapBox(f: *const Font, glyph: i32, scale_x: f32, scale_y: f32, shift_x: f32, shift_y: f32) BitmapBox {
        const box = glyphBox(f, glyph) orelse return .empty;
        return .{
            .x0 = @intFromFloat(@floor(@as(f32, @floatFromInt(box.x0)) * scale_x + shift_x)),
            .y0 = @intFromFloat(@floor(@as(f32, @floatFromInt(box.y0)) * scale_y + shift_y)),
            .x1 = @intFromFloat(@ceil(@as(f32, @floatFromInt(box.x1)) * scale_x + shift_x)),
            .y1 = @intFromFloat(@ceil(@as(f32, @floatFromInt(box.y1)) * scale_y + shift_y)),
        };
    }

    // ---
    // Metrics
    // ---
    pub fn scaleForEm(f: *const Font, pixels: f32) f32 {
        const bytes = f.font_bytes;
        const head = f.table_offsets[Tables.head.int()];
        const unit_per_em: f32 = @floatFromInt(readInt(u16, bytes[head + 18 ..][0..2]));
        return pixels / unit_per_em;
    }
    pub fn scaleForPixelHeight(f: *const Font, height: f32) f32 {
        const vm = f.verticalMetrics();
        const fheight: f32 = @floatFromInt(vm.ascent - vm.descent);
        return height / fheight;
    }
    pub const VMetrics = struct { ascent: i16, descent: i16, line_gap: i16 };
    pub fn verticalMetrics(f: *const Font) VMetrics {
        const bytes = f.font_bytes;
        const hhea = f.table_offsets[Tables.hhea.int()];
        return .{
            .ascent = readInt(i16, bytes[hhea + 4 ..][0..2]),
            .descent = readInt(i16, bytes[hhea + 6 ..][0..2]),
            .line_gap = readInt(i16, bytes[hhea + 8 ..][0..2]),
        };
    }
    pub const HMetrics = struct { advance_width: i16, left_side_bearing: i16 };
    pub fn glyphHorizontalMetrics(f: *const Font, glyph: i32) HMetrics {
        const glyph_index: usize = @backingInt(glyph);
        const bytes = f.font_bytes;
        const hhea = f.table_offsets[Tables.hhea.int()];
        const hmtx = f.table_offsets[Tables.hmtx.int()];
        const n_long_h_metrics = readInt(u16, bytes[hhea + 34 ..][0..2], .big);
        if (glyph_index < n_long_h_metrics) return .{
            .advance_width = readInt(i16, bytes[hmtx + 4 * glyph_index ..][0..2], .big),
            .left_side_bearing = readInt(i16, bytes[hmtx + 4 * glyph_index + 2 ..][0..2], .big),
        };
        return .{
            .advance_width = readInt(i16, bytes[hmtx + 4 * (n_long_h_metrics - 1) ..][0..2], .big),
            .left_side_bearing = readInt(i16, bytes[hmtx + 4 * n_long_h_metrics + 2 * (glyph_index - n_long_h_metrics) ..][0..2], .big),
        };
    }
};

// ---
// Utility Functions
// ---
inline fn readCursor(comptime T: type, bytes: []const u8, cursor: *u32) T {
    const start = cursor.*;
    const result = readInt(T, bytes[start..][0..@sizeOf(T)]);
    cursor.* = start + @sizeOf(T);
    return result;
}
inline fn readInt(comptime T: type, buffer: *const [@divExact(@typeInfo(T).int.bits, 8)]u8) T {
    const v: T = @bitCast(buffer.*);
    return @byteSwap(v);
}

// ---
// Internal Types
// ---
const Tables = enum {
    cmap,
    loca,
    head,
    glyf,
    hhea,
    hmtx,
    kern,
    maxp,

    fn count() usize {
        return @typeInfo(Tables).@"enum".field_names.len;
    }

    fn int(id: Tables) u8 {
        return @backingInt(id);
    }

    fn tag(id: Tables) u32 {
        const arr: [4]u8 = @tagName(id).*;
        const a: u32 = @bitCast(arr);
        return if (@import("builtin").cpu.arch.endian() == .little) @byteSwap(a) else a;
    }
};
const PlatformId = enum(u16) { unicode = 0, mac = 1, iso = 2, microsoft = 3 };
const MicrosoftEncodingId = enum(u16) { symbol = 0, unicode_bmp = 1, shiftjis = 2, unicode_full = 10 };

pub const Edge = struct { x0: f32, y0: f32, x1: f32, y1: f32 };
// ---
// Errors
// ---
const FontError = error{
    EndOfStream,
    MissingRequiredTable,
    IndexMapMissing,
} || Allocator.Error;
