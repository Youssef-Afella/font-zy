const std = @import("std");
const Allocator = std.mem.Allocator;

const font_zy = @import("font-zy");

const Font = font_zy.Font;
const Edge = font_zy.Edge;
const Raster = font_zy.Raster;
const GlyphMetrics = font_zy.GlyphMetrics;

pub fn main(init: std.process.Init) !void {
    const gpa = init.arena.allocator();

    const font_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "fonts/Roboto-Regular.ttf",
        gpa,
        .limited(10 * 1024 * 1024),
    );

    // Config -------------------------------------------------------------------
    const character = 'g';
    const size = 40;

    // Parsing ------------------------------------------------------------------
    const font = try Font.load(font_bytes);
    const scale = font.scaleForEm(size);
    const glyph = font.characterToGlyphIndex(character);
    const metrics = font.glyphMetrics(glyph, scale);

    //Pre-tesselating the edges
    const edges = try font.flattenEdges(gpa, glyph, scale);
    defer gpa.free(edges);

    //Allocations are excluded from the benchmark (zeroing is not)
    const buffer = try gpa.alloc(f32, metrics.width * metrics.height);
    const bitmap = try gpa.alloc(u8, metrics.width * metrics.height);
    defer gpa.free(buffer);
    defer gpa.free(bitmap);

    // Benchmark ---------------------------------------------------------------------
    // Steps timed here are : Edges transform, Zeroing, Rasterizing, Accumulation
    std.debug.print("\nglyph '{c}', size {}px/em\n", .{ character, size });
    try benchmark(init.io, font, edges, &metrics, scale, buffer, bitmap);

    //Rendering an extra one to pgm ---------------------------------------------------
    {
        font.rasterizeEdges(bitmap, buffer, edges, &metrics, scale);

        try dumpPGM(init.io, bitmap, metrics.width, metrics.height, "result.pgm");
        std.debug.print("bitmap: {}x{} px\n\n", .{ metrics.width, metrics.height });
    }
}

fn benchmark(io: std.Io, font: Font, edges: []Edge, metrics: *const GlyphMetrics, scale: f32, buffer: []f32, bitmap: []u8) !void {
    const warmup_iters = 5000;
    const sample_count = 101;
    const batch_size = 100;

    for (0..warmup_iters) |_| runRaster(font, edges, metrics, scale, buffer, bitmap);

    var samples: [sample_count]f64 = undefined;
    for (&samples) |*s| {
        const t0: f64 = @floatFromInt(std.Io.Clock.now(.awake, io).toNanoseconds());
        for (0..batch_size) |_| runRaster(font, edges, metrics, scale, buffer, bitmap);
        const t1: f64 = @floatFromInt(std.Io.Clock.now(.awake, io).toNanoseconds());
        s.* = (t1 - t0) / (batch_size * 1000.0);
    }

    std.mem.sort(f64, &samples, {}, std.sort.asc(f64));

    std.debug.print(
        "warmup_iters {}, sample_count {}, batch_size {}\n\n",
        .{ warmup_iters, sample_count, batch_size },
    );
    std.debug.print(
        "min {} us | median {} us | p90 {d} us | max {} us\n",
        .{ samples[0], samples[sample_count / 2], samples[sample_count * 9 / 10], samples[sample_count - 1] },
    );
}

fn runRaster(font: Font, edges: []Edge, metrics: *const GlyphMetrics, scale: f32, buffer: []f32, bitmap: []u8) void {
    font.rasterizeEdges(bitmap, buffer, edges, metrics, scale);

    std.mem.doNotOptimizeAway(buffer);
    std.mem.doNotOptimizeAway(bitmap);
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
