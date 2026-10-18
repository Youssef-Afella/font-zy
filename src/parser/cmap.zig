const Font = @import("../font.zig").Font;

const readInt = @import("../font.zig").readInt;

pub fn characterToGlyphIndex(f: *const Font, codepoint: u21) i32 {
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
