const std = @import("std");

const Font = @import("font-zy").Font;

pub fn main(init: std.process.Init) !void {
    const gpa = std.heap.page_allocator;

    const text = "the quick brown fox jumps over the lazy dog";
    //const text = "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG";

    const font_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "fonts/JetBrainsMono/JetBrainsMono-Medium.ttf",
        gpa,
        .limited(10 * 1024 * 1024),
    );
    const font = try Font.load(font_bytes);
    const scale = font.scaleForEm(64);
    const vmetrics = font.verticalMetrics(scale);

    const width = 1800;
    const height = 100;
    const bitmap = try gpa.alloc(u8, width * height);
    defer gpa.free(bitmap);
    @memset(bitmap, 0);

    var x: i32 = 0;

    var it = std.unicode.Utf8View.initComptime(text).iterator();

    while (it.nextCodepoint()) |codepoint| {
        const glyph = font.characterToGlyphIndex(codepoint);

        const char_bitmap, const metrics = try font.rasterize(gpa, glyph, scale);

        const y: i32 = vmetrics.ascent + @as(i16, @intCast(metrics.ymin));
        blit(char_bitmap, bitmap, @intCast(x), @intCast(y), metrics.width, metrics.height, width);

        gpa.free(char_bitmap);

        x += metrics.advance_width;
    }

    try dumpPGM(init.io, bitmap, width, height, "result.pgm");
}

fn blit(src: []u8, dst: []u8, x: u32, y: u32, w: u32, h: u32, width: u32) void {
    for (0..h) |j| {
        for (0..w) |i| {
            dst[x + i + (y + j) * width] = src[i + j * w];
        }
    }
}

fn dumpPGM(io: std.Io, bitmap: []const u8, width: u32, height: u32, filename: []const u8) !void {
    const file = try std.Io.Dir.cwd().createFile(io, filename, .{});
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var fw = file.writer(io, &buf);
    const w = &fw.interface;

    try w.print("P5\n{d} {d}\n255\n", .{ width, height });
    try w.writeAll(bitmap);
    try w.flush();
}
