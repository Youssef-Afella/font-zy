const std = @import("std");
const Allocator = std.mem.Allocator;

const Cmap = @import("parser/cmap.zig");
const Glyph = @import("parser/glyph.zig");
const Metrics = @import("parser/metrics.zig");

const Geom = @import("geom.zig");

pub const Raster = @import("raster.zig").Raster;

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

    pub fn rasterize(f: *const Font, gpa: Allocator, glyph: i32, scale: f32) FontError!struct { []u8, u32, u32 } {
        const dims = f.glyphDimensions(glyph, scale);
        const edges = try f.flattenEdges(gpa, glyph, scale);
        defer gpa.free(edges);

        const buffer = try gpa.alloc(f32, dims.w * dims.h);
        const bitmap = try gpa.alloc(u8, dims.w * dims.h);
        defer gpa.free(buffer);

        f.rasterizeEdges(bitmap, buffer, edges, dims, scale);

        return .{
            bitmap,
            dims.w,
            dims.h,
        };
    }

    pub fn rasterizeEdges(_: *const Font, bitmap: []u8, buffer: []f32, edges: []Edge, dims: Dimensions, scale: f32) void {
        var raster = Raster.init(buffer, bitmap, dims.w);
        for (edges) |edge| {
            raster.drawLine(edge.x0 * scale, edge.y0 * scale, edge.x1 * scale, edge.y1 * scale);
        }
        raster.fill();
    }

    pub fn flattenEdges(f: *const Font, gpa: Allocator, glyph: i32, scale: f32) FontError![]Edge {
        const box = Glyph.glyphBox(f, glyph) orelse Rect.empty;

        const vertices = try Glyph.glyphShape(f, gpa, glyph);
        defer gpa.free(vertices);

        if (vertices.len == 0) {
            return &.{};
        }

        return try Geom.getEdgeList(gpa, vertices, scale, box);
    }

    pub fn characterToGlyphIndex(f: *const Font, codepoint: u21) i32 {
        const i = Cmap.characterToGlyphIndex(f, codepoint);
        return if (i < 0) 0 else i;
    }

    pub fn glyphDimensions(f: *const Font, glyph: i32, scale: f32) Dimensions {
        const box = Glyph.glyphBox(f, glyph) orelse return .{ .w = 0, .h = 0 };
        return .{
            .w = @as(u32, @intFromFloat(@ceil(@as(f32, @floatFromInt(box.x1 - box.x0 + 1)) * scale))) + 1,
            .h = @intFromFloat(@ceil(@as(f32, @floatFromInt(box.y1 - box.y0 + 1)) * scale)),
        };
    }

    pub fn glyphHorizontalMetrics(f: *const Font, glyph: i32, scale: f32) HMetrics {
        const m = Metrics.glyphHorizontalMetrics(f, glyph);
        return .{
            .advance_width = @intFromFloat(@round(@as(f32, @floatFromInt(m.advance_width)) * scale)),
            .left_side_bearing = @intFromFloat(@round(@as(f32, @floatFromInt(m.left_side_bearing)) * scale)),
        };
    }

    pub fn verticalMetrics(f: *const Font, scale: f32) VMetrics {
        const m = Metrics.verticalMetrics(f);
        return .{
            .ascent = @intFromFloat(@round(@as(f32, @floatFromInt(m.ascent)) * scale)),
            .descent = @intFromFloat(@round(@as(f32, @floatFromInt(m.descent)) * scale)),
            .line_gap = @intFromFloat(@round(@as(f32, @floatFromInt(m.line_gap)) * scale)),
        };
    }

    pub fn scaleForEm(f: *const Font, pixels: f32) f32 {
        const unit_per_em: f32 = Metrics.unitPerEm(f);
        return pixels / unit_per_em;
    }

    pub fn scaleForPixelHeight(f: *const Font, height: f32) f32 {
        const vm = Metrics.verticalMetrics(f);
        const fheight: f32 = @floatFromInt(vm.ascent - vm.descent);
        return height / fheight;
    }
};

// Utility Functions
pub inline fn readCursor(comptime T: type, bytes: []const u8, cursor: *u32) T {
    const start = cursor.*;
    const result = readInt(T, bytes[start..][0..@sizeOf(T)]);
    cursor.* = start + @sizeOf(T);
    return result;
}
pub inline fn readInt(comptime T: type, buffer: *const [@divExact(@typeInfo(T).int.bits, 8)]u8) T {
    const v: T = @bitCast(buffer.*);
    return @byteSwap(v);
}

// Custom Types
pub const Point = struct {
    x: f32,
    y: f32,
};

pub const Edge = struct {
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
};

pub const Vertex = struct {
    x: i16,
    y: i16,
    cx: i16,
    cy: i16,
    cx1: i16,
    cy1: i16,
    type: Type,

    pub const Type = enum(u8) { vmove = 1, vline = 2, vquad = 3, vcubic = 4, _ };

    pub fn set(v: *Vertex, ty: Type, x: i32, y: i32, cx: i32, cy: i32) void {
        v.type = ty;
        v.x = @intCast(x);
        v.y = @intCast(y);
        v.cx = @intCast(cx);
        v.cy = @intCast(cy);
    }
};

pub const VMetrics = struct {
    ascent: i16,
    descent: i16,
    line_gap: i16,
};

pub const HMetrics = struct {
    advance_width: i16,
    left_side_bearing: i16,
};

pub const Dimensions = struct {
    w: u32,
    h: u32,
};

pub const Rect = struct {
    x0: i32,
    y0: i32,
    x1: i32,
    y1: i32,

    pub const empty: Rect = .{
        .x0 = 0,
        .y0 = 0,
        .x1 = 0,
        .y1 = 0,
    };
};

pub const Tables = enum {
    cmap,
    loca,
    head,
    glyf,
    hhea,
    hmtx,
    kern,
    maxp,

    pub fn count() usize {
        return @typeInfo(Tables).@"enum".field_names.len;
    }

    pub fn int(id: Tables) u8 {
        return @backingInt(id);
    }

    pub fn tag(id: Tables) u32 {
        const arr: [4]u8 = @tagName(id).*;
        const a: u32 = @bitCast(arr);
        return if (@import("builtin").cpu.arch.endian() == .little) @byteSwap(a) else a;
    }
};

const PlatformId = enum(u16) {
    unicode = 0,
    mac = 1,
    iso = 2,
    microsoft = 3,
};

const MicrosoftEncodingId = enum(u16) {
    symbol = 0,
    unicode_bmp = 1,
    shiftjis = 2,
    unicode_full = 10,
};

const FontError = error{
    EndOfStream,
    MissingRequiredTable,
    IndexMapMissing,
} || Allocator.Error;
