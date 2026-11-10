const std = @import("std");

pub fn build(b: *std.Build) void {
    // Settings ----------------------------------------------------------------------
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Module ------------------------------------------------------------------------
    const mod = b.addModule("font-zy", .{
        .root_source_file = b.path("src/font.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Bench -------------------------------------------------------------------------
    const bench = b.addExecutable(.{
        .name = "font-zy-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "font-zy", .module = mod },
            },
        }),
    });
    b.installArtifact(bench);

    const bench_cmd = b.addRunArtifact(bench);
    bench_cmd.step.dependOn(b.getInstallStep());
    bench_cmd.addPassthruArgs();

    const bench_step = b.step("bench", "Run the benchmark");
    bench_step.dependOn(&bench_cmd.step);

    // Example ---------------------------------------------------------
    const example = b.addExecutable(.{
        .name = "font-zy-example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("example/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "font-zy", .module = mod },
            },
        }),
    });
    b.installArtifact(example);

    const example_cmd = b.addRunArtifact(example);
    example_cmd.step.dependOn(b.getInstallStep());

    const example_step = b.step("example", "Run the example");
    example_step.dependOn(&example_cmd.step);

    // Test ---------------------------------------------------------
    const tester = b.addExecutable(.{
        .name = "font-zy-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "font-zy", .module = mod },
            },
        }),
    });
    b.installArtifact(tester);

    const tester_cmd = b.addRunArtifact(tester);
    tester_cmd.step.dependOn(b.getInstallStep());

    const tester_step = b.step("test", "Run the test");
    tester_step.dependOn(&tester_cmd.step);
}
