const std = @import("std");

const Font = @import("font-zy").Font;

pub fn main(init: std.process.Init) !void {
    const gpa = std.heap.page_allocator;

    const font_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "fonts/Roboto/Roboto-Regular.ttf",
        //"fonts/JetBrainsMono/JetBrainsMono-Medium.ttf",
        gpa,
        .limited(10 * 1024 * 1024),
    );

    const font = try Font.load(font_bytes);

    for (1..300) |k| {
        const size: f32 = @as(f32, @floatFromInt(k)) * 1.0;
        const scale = font.scaleForEm(size);

        for (0..font.glyphs_len) |glyph| {
            const char_bitmap, const metrics = try font.rasterize(gpa, @intCast(glyph), scale);
            gpa.free(char_bitmap);

            std.debug.print("Size: {} Glyph: {} passed!\n", .{ size, glyph });

            std.mem.doNotOptimizeAway(char_bitmap);
            std.mem.doNotOptimizeAway(metrics);
        }
    }
}
