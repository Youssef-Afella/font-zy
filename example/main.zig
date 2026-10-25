const std = @import("std");

const font_zy = @import("font-zy");

const Font = font_zy.Font;
const Edge = font_zy.Edge;
const Raster = font_zy.Raster;

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const gpa = arena.allocator();

    const text = "Hello";

    const font_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "fonts/Roboto-Regular.ttf",
        gpa,
        .limited(10 * 1024 * 1024),
    );
    const font = try Font.load(font_bytes);
    const scale = font.scaleForPixelHeight(60);
    const vmetrics = font.verticalMetrics(scale);

    const width = 400;
    const height = 100;
    const bitmap = try gpa.alloc(u8, width * height);
    @memset(bitmap, 0);
    defer gpa.free(bitmap);

    var x: i32 = 0;

    var it = std.unicode.Utf8View.initComptime(text).iterator();
    while (it.nextCodepoint()) |codepoint| {
        const glyph = font.characterToGlyphIndex(codepoint);
        const hmetrics = font.glyphHorizontalMetrics(glyph, scale);

        const char_bitmap, const w, const h = try font.rasterize(gpa, glyph, scale);
        const y: i32 = vmetrics.ascent - @as(i16, @intCast(h));
        blit(char_bitmap, bitmap, @intCast(x), @intCast(y), w, h, width);

        gpa.free(char_bitmap);

        x += hmetrics.advance_width;
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
