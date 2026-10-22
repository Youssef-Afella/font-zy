const Font = @import("../font.zig").Font;
const Tables = @import("../font.zig").Tables;
const VMetrics = @import("../font.zig").VMetrics;
const HMetrics = @import("../font.zig").HMetrics;

const readInt = @import("../font.zig").readInt;

pub fn unitPerEm(f: *const Font) u16 {
    const bytes = f.font_bytes;
    const head = f.table_offsets[Tables.head.int()];
    return readInt(u16, bytes[head + 18 ..][0..2]);
}

pub fn verticalMetrics(f: *const Font) VMetrics {
    const bytes = f.font_bytes;
    const hhea = f.table_offsets[Tables.hhea.int()];
    return .{
        .ascent = readInt(i16, bytes[hhea + 4 ..][0..2]),
        .descent = readInt(i16, bytes[hhea + 6 ..][0..2]),
        .line_gap = readInt(i16, bytes[hhea + 8 ..][0..2]),
    };
}

pub fn glyphHorizontalMetrics(f: *const Font, glyph: i32) HMetrics {
    const glyph_index: usize = @intCast(glyph);
    const bytes = f.font_bytes;
    const hhea = f.table_offsets[Tables.hhea.int()];
    const hmtx = f.table_offsets[Tables.hmtx.int()];
    const n_long_h_metrics = readInt(u16, bytes[hhea + 34 ..][0..2]);
    if (glyph_index < n_long_h_metrics) return .{
        .advance_width = readInt(i16, bytes[hmtx + 4 * glyph_index ..][0..2]),
        .left_side_bearing = readInt(i16, bytes[hmtx + 4 * glyph_index + 2 ..][0..2]),
    };
    return .{
        .advance_width = readInt(i16, bytes[hmtx + 4 * (n_long_h_metrics - 1) ..][0..2]),
        .left_side_bearing = readInt(i16, bytes[hmtx + 4 * n_long_h_metrics + 2 * (glyph_index - n_long_h_metrics) ..][0..2]),
    };
}
