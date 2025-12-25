const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the lz4 module
    const lz4_module = b.addModule("lz4", .{
        .root_source_file = b.path("src/lz4.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link against system liblz4
    lz4_module.linkSystemLibrary("lz4", .{});

    // Create test executable for multimedia tests
    const tests = b.addTest(.{
        .root_source_file = b.path("tests/multimedia_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("lz4", lz4_module);
    tests.linkSystemLibrary("lz4");
    tests.linkLibC();

    // Create test executable for general functionality tests
    const general_tests = b.addTest(.{
        .root_source_file = b.path("tests/general_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    general_tests.root_module.addImport("lz4", lz4_module);
    general_tests.linkSystemLibrary("lz4");
    general_tests.linkLibC();

    // Create test executable for streaming tests
    const stream_tests = b.addTest(.{
        .root_source_file = b.path("tests/stream_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    stream_tests.root_module.addImport("lz4", lz4_module);
    stream_tests.linkSystemLibrary("lz4");
    stream_tests.linkLibC();

    // Run all tests
    const run_tests = b.addRunArtifact(tests);
    const run_general_tests = b.addRunArtifact(general_tests);
    const run_stream_tests = b.addRunArtifact(stream_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_general_tests.step);
    test_step.dependOn(&run_stream_tests.step);

    // Example executable demonstrating usage
    const example = b.addExecutable(.{
        .name = "lz4_example",
        .root_source_file = b.path("examples/basic_usage.zig"),
        .target = target,
        .optimize = optimize,
    });
    example.root_module.addImport("lz4", lz4_module);
    example.linkSystemLibrary("lz4");
    example.linkLibC();

    const install_example = b.addInstallArtifact(example, .{});
    const example_step = b.step("example", "Build example executable");
    example_step.dependOn(&install_example.step);

    // Default install step
    b.installArtifact(example);
}
