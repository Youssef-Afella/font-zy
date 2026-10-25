const std = @import("std");
const Allocator = std.mem.Allocator;

const font_zy = @import("font-zy");

const Font = font_zy.Font;
const Edge = font_zy.Edge;
const Raster = font_zy.Raster;
const Dimensions = font_zy.Dimensions;

pub fn main(init: std.process.Init) !void {
    //const gpa = init.arena.allocator();
    const gpa = std.heap.c_allocator;

    const font_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "fonts/Roboto-Regular.ttf",
        gpa,
        .limited(10 * 1024 * 1024),
    );

    // Config -------------------------------------------------------------------
    const character = 'g';
    const size = 42;

    // Parsing ------------------------------------------------------------------
    const font = try Font.load(font_bytes);
    const scale = font.scaleForEm(size);
    const glyph = font.characterToGlyphIndex(character);
    const dims = font.glyphDimensions(glyph, scale);

    //Pre-tesselating the edges like what fontdue does
    const edges = try font.flattenEdges(gpa, glyph, scale);
    defer gpa.free(edges);
    std.debug.print("Edge count : {}\n", .{edges.len});

    // Benchmark ---------------------------------------------------------------------
    try benchmark(init.io, gpa, font, edges, dims, scale, character, size);

    //Rendering an extra one to pgm ---------------------------------------------------
    {
        const buffer = try gpa.alloc(f32, dims.w * dims.h);
        const bitmap = try gpa.alloc(u8, dims.w * dims.h);
        defer gpa.free(buffer);
        defer gpa.free(bitmap);

        font.rasterizeEdges(bitmap, buffer, edges, dims, scale);

        try dumpPGM(init.io, bitmap, dims.w, dims.h, "result.pgm");
        std.debug.print("bitmap: {}x{} px\n\n", .{ dims.w, dims.h });
    }
}

fn benchmark(io: std.Io, gpa: Allocator, font: Font, edges: []Edge, dims: Dimensions, scale: f32, character: u8, size: u32) !void {
    const warmup_iters = 5000;
    const sample_count = 101;
    const batch_size = 100;

    for (0..warmup_iters) |_| try runRaster(gpa, font, edges, dims, scale);

    var samples: [sample_count]f64 = undefined;
    for (&samples) |*s| {
        const t0: f64 = @floatFromInt(std.Io.Clock.now(.awake, io).toNanoseconds());
        for (0..batch_size) |_| try runRaster(gpa, font, edges, dims, scale);
        const t1: f64 = @floatFromInt(std.Io.Clock.now(.awake, io).toNanoseconds());
        s.* = (t1 - t0) / (batch_size * 1000.0);
    }

    std.mem.sort(f64, &samples, {}, std.sort.asc(f64));

    std.debug.print(
        "\nglyph '{c}', size {}px/em\n",
        .{ character, size },
    );
    std.debug.print(
        "warmup_iters {}, sample_count {}, batch_size {}\n\n",
        .{ warmup_iters, sample_count, batch_size },
    );
    std.debug.print(
        "min {} us | median {} us | p90 {d} us | max {} us\n",
        .{ samples[0], samples[sample_count / 2], samples[sample_count * 9 / 10], samples[sample_count - 1] },
    );
}

fn runRaster(gpa: Allocator, font: Font, edges: []Edge, dims: Dimensions, scale: f32) !void {
    //Order of freeing is very important for the benchmark!
    const buffer = try gpa.alloc(f32, dims.w * dims.h);
    const bitmap = try gpa.alloc(u8, dims.w * dims.h);
    defer gpa.free(buffer);
    defer gpa.free(bitmap);

    font.rasterizeEdges(bitmap, buffer, edges, dims, scale);

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
