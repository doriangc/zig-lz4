const std = @import("std");

const SOURCE_FILES = [_][]const u8{
    "lib/lz4.c",
    "lib/lz4frame.c",
    "lib/lz4hc.c",
    "lib/xxhash.c",
};

const HEADER_DIRS = [_][]const u8{
    "lib",
};

const LIB_SRC = "src/lib.zig";

pub fn build(b: *std.Build) void {
    const lz4_dependency = b.dependency("lz4", .{}); // Cleaner dependency fetching

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Define the Library
    const lib = b.addLibrary(.{
        .name = "lz4",
        .root_module = b.createModule(.{
            .root_source_file = b.path(LIB_SRC),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });

    // 2. Configure C Integration
    lib.linkLibC(); // Use linkLibC unless you specifically need C++ features
    const FLAGS = [_][]const u8{"-DLZ4LIB_API=extern\"C\""};

    for (SOURCE_FILES) |file| {
        lib.addCSourceFile(.{ .file = lz4_dependency.path(file), .flags = &FLAGS });
    }

    for (HEADER_DIRS) |dir| {
        lib.addIncludePath(lz4_dependency.path(dir));
    }

    // 3. Define the Public Module
    const lz4_module = b.addModule("zig-lz4", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    lz4_module.linkLibrary(lib);

    // 4. Modern Documentation (No addObject needed)
    const docs_step = b.step("docs", "Build documentation");
    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);

    // 5. Unit Tests
    const lib_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(LIB_SRC),
            .target = target,
            .optimize = optimize,
        }),
    });
    lib_unit_tests.linkLibrary(lib); // Link the C code into the test runner

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    b.installArtifact(lib);
}
