const std = @import("std");

const font_zy = @import("font-zy");

const Font = font_zy.Font;
const Edge = font_zy.Edge;
const Raster = font_zy.Raster;

pub fn main(init: std.process.Init) !void {
    const gpa = std.heap.c_allocator;

    const font_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, "fonts/Roboto-Regular.ttf", gpa, .limited(10 * 1024 * 1024));

    // Config -------------------------------------------------------------------
    const character = 'g';
    const size = 40;
    const iterations = 5000;

    // Parsing ------------------------------------------------------------------
    const font = try Font.load(font_bytes);
    const scale = font.scaleForEm(size);
    const glyph = font.characterToGlyphIndex(character);

    const box = font.glyphBitmapBox(glyph, scale);
    const w: u32 = @intCast(box.x1 - box.x0 + 1);
    const h: u32 = @intCast(box.y1 - box.y0);

    const edges = try font.precomputeEdges(gpa, glyph, scale);
    std.debug.print("Edge count : {}\n", .{edges.len});
    defer gpa.free(edges);

    const buffer = try gpa.alloc(f32, w * h);
    defer gpa.free(buffer);

    // Benchmark ---------------------------------------------------------------------
    const start = std.Io.Clock.now(.awake, init.io);
    for (0..iterations) |i| {
        _ = i;

        const bitmap = try gpa.alloc(u8, w * h);
        defer gpa.free(bitmap);

        var raster = Raster.init(buffer, bitmap, w);

        for (edges) |edge| {
            const x0 = edge.x0 * scale;
            const x1 = edge.x1 * scale;
            const y0 = edge.y0 * scale;
            const y1 = edge.y1 * scale;
            raster.drawLine(x0, y0, x1, y1);
        }

        raster.fill();
    }
    const end = std.Io.Clock.now(.awake, init.io);

    const duration = start.durationTo(end);
    const fd: f32 = @floatFromInt(duration.toMicroseconds());
    std.debug.print("\nglyph '{c}', scale {}px/em, {} iterations\nbitmap {}x{} \navg {:.3} us\n\n", .{ character, size, iterations, w, h, fd / iterations });

    //Rendering an extra one to pgm ---------------------------------------------------
    const bitmap = try gpa.alloc(u8, w * h);
    defer gpa.free(bitmap);
    //const buffer = try gpa.alloc(f32, w * h);
    //defer gpa.free(buffer);

    var raster = Raster.init(buffer, bitmap, w);

    for (edges) |edge| {
        const x0 = edge.x0 * scale;
        const x1 = edge.x1 * scale;
        const y0 = edge.y0 * scale;
        const y1 = edge.y1 * scale;
        raster.drawLine(x0, y0, x1, y1);
    }
    raster.fill();

    try dumpPGM(init.io, bitmap, w, h, "result.pgm");
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
