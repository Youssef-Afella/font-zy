const std = @import("std");

const Font = @import("font.zig").Font;
const Glyph = @import("font.zig").Glyph;
const Raster = @import("raster.zig").Raster;

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const font_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "fonts/Roboto-Regular.ttf",
        allocator,
        .limited(10 * 1024 * 1024),
    );

    // Config -------------------------------------------------------------------
    const character = 'g';
    const scale = 400;

    // Parsing ------------------------------------------------------------------
    var font = try Font.load(allocator, font_bytes);
    defer font.deinit();
    const glyph = font.glyphs[font.cmap[character]];
    const width, const height = font.getMetricsForScale(glyph, scale);

    // Benchmark ---------------------------------------------------------------------
    // (A much smarter approach would be to allocate the buffer once with the max size
    // of all glyphs from the head table and reuse it for all characters, but for the
    // sake of a fair comparaison with font-rs we are doing exactly the same they are doing)
    const iterations = 1000;
    const start = std.Io.Clock.now(.awake, init.io);

    for (0..iterations) |i| {
        _ = i;
        const bitmap = try allocator.alloc(u8, width * height);
        const buffer = try allocator.alloc(f32, width * height);
        defer allocator.free(bitmap);
        defer allocator.free(buffer);

        var raster = Raster.init(width, height, buffer, bitmap);
        font.drawGlyph(&raster, glyph, scale);
    }

    const end = std.Io.Clock.now(.awake, init.io);

    const duration = start.durationTo(end);
    const fd: f32 = @floatFromInt(duration.toMicroseconds());
    std.debug.print("\nglyph '{c}', scale {}px/em, {} iterations\nbitmap {}x{} \navg {:.3} us\n\n", .{ character, scale, iterations, width, height, fd / iterations });

    //Rendering an extra one to pgm ---------------------------------------------------
    const bitmap = try allocator.alloc(u8, width * height);
    const buffer = try allocator.alloc(f32, width * height);
    defer allocator.free(bitmap);
    defer allocator.free(buffer);

    var raster = Raster.init(width, height, buffer, bitmap);
    font.drawGlyph(&raster, glyph, scale);

    try dumpPGM(init.io, bitmap, width, height, "result.pgm");
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
