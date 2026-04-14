const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Create the Module
    // In 0.15, we link the system library once here.
    // Anything that imports this module will now "inherit" the need to link lz4.
    const lz4_module = b.addModule("lz4", .{
        .root_source_file = b.path("src/lz4.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true, // <--- Add this line here
    });
    lz4_module.linkSystemLibrary("lz4", .{});

    // 2. Define Tests
    // We can use a simple array and a loop to avoid repeating code.
    const test_files = [_][]const u8{
        "tests/multimedia_tests.zig",
        "tests/general_tests.zig",
        "tests/stream_tests.zig",
    };

    const test_step = b.step("test", "Run all tests");

    for (test_files) |path| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
            }),
        });

        // This is all you need; linkage is inherited from lz4_module!
        t.root_module.addImport("lz4", lz4_module);

        const run_t = b.addRunArtifact(t);
        test_step.dependOn(&run_t.step);
    }

    // 3. Example Executable
    const example = b.addExecutable(.{
        .name = "lz4_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/basic_usage.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Inherits system lz4 and libc automatically from the import
    example.root_module.addImport("lz4", lz4_module);

    // Install the example
    const install_example = b.addInstallArtifact(example, .{});
    const example_step = b.step("example", "Build example executable");
    example_step.dependOn(&install_example.step);

    // Default 'zig build' will also install the example
    b.installArtifact(example);
}
