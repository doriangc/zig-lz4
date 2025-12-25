const std = @import("std");
const lz4 = @import("lz4");
const testing = std.testing;

test "basic compression and decompression" {
    const allocator = testing.allocator;
    const original = "Hello, World! This is a test of LZ4 compression. " ** 10;

    const compressed = try lz4.compressAlloc(allocator, original);
    defer allocator.free(compressed);

    try testing.expect(compressed.len < original.len);

    const decompressed = try lz4.decompressAlloc(allocator, compressed, original.len);
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(original, decompressed);
}

test "compress with different acceleration levels" {
    const allocator = testing.allocator;
    const original = "The quick brown fox jumps over the lazy dog. " ** 100;

    const max_dst = lz4.compressBound(original.len);
    var buffer = try allocator.alloc(u8, max_dst);
    defer allocator.free(buffer);

    // Test different acceleration levels
    const levels = [_]i32{ 1, 5, 10, 50, 100 };
    for (levels) |level| {
        const size = try lz4.compressFast(original, buffer, level);
        try testing.expect(size > 0);
        try testing.expect(size < original.len);

        const decompressed = try allocator.alloc(u8, original.len);
        defer allocator.free(decompressed);

        _ = try lz4.decompress(buffer[0..size], decompressed, original.len);
        try testing.expectEqualStrings(original, decompressed);
    }
}

test "compress with HC at different levels" {
    const allocator = testing.allocator;
    const original = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " ** 50;

    const max_dst = lz4.compressBound(original.len);
    var buffer = try allocator.alloc(u8, max_dst);
    defer allocator.free(buffer);

    // Test different HC compression levels (1-12)
    const levels = [_]i32{ 1, 4, 9, 12 };
    var prev_size: usize = original.len;

    for (levels) |level| {
        const size = try lz4.compressHC(original, buffer, level);
        try testing.expect(size > 0);
        try testing.expect(size <= prev_size); // Higher levels should compress better or equal
        prev_size = size;

        const decompressed = try allocator.alloc(u8, original.len);
        defer allocator.free(decompressed);

        _ = try lz4.decompress(buffer[0..size], decompressed, original.len);
        try testing.expectEqualStrings(original, decompressed);
    }
}

test "compress empty data" {
    const allocator = testing.allocator;
    const original = "";

    const compressed = try lz4.compressAlloc(allocator, original);
    defer allocator.free(compressed);

    const decompressed = try lz4.decompressAlloc(allocator, compressed, original.len);
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(original, decompressed);
}

test "compress highly repetitive data" {
    const allocator = testing.allocator;

    // Create highly repetitive data
    const pattern = "AAAA";
    var original = try allocator.alloc(u8, pattern.len * 1000);
    defer allocator.free(original);

    for (0..1000) |i| {
        @memcpy(original[i * pattern.len ..][0..pattern.len], pattern);
    }

    const compressed = try lz4.compressAlloc(allocator, original);
    defer allocator.free(compressed);

    // Should compress very well
    const ratio = @as(f64, @floatFromInt(original.len)) / @as(f64, @floatFromInt(compressed.len));
    try testing.expect(ratio > 10.0);

    const decompressed = try lz4.decompressAlloc(allocator, compressed, original.len);
    defer allocator.free(decompressed);

    try testing.expectEqualSlices(u8, original, decompressed);
}

test "compress random-like data" {
    const allocator = testing.allocator;

    // Create pseudo-random data (won't compress well)
    const original = try allocator.alloc(u8, 4096);
    defer allocator.free(original);

    var prng = std.Random.DefaultPrng.init(12345);
    const random = prng.random();
    random.bytes(original);

    const compressed = try lz4.compressAlloc(allocator, original);
    defer allocator.free(compressed);

    // Random data typically doesn't compress well
    std.debug.print("\nRandom data compression ratio: {d:.2}\n", .{@as(f64, @floatFromInt(original.len)) / @as(f64, @floatFromInt(compressed.len))});

    const decompressed = try lz4.decompressAlloc(allocator, compressed, original.len);
    defer allocator.free(decompressed);

    try testing.expectEqualSlices(u8, original, decompressed);
}

test "frame compression includes size metadata" {
    const allocator = testing.allocator;
    const original = "Frame compression test data. " ** 100;

    const compressed = try lz4.compressFrame(allocator, original);
    defer allocator.free(compressed);

    // Frame format includes header/footer overhead
    try testing.expect(compressed.len > 0);

    // Decompression doesn't need original size
    const decompressed = try lz4.decompressFrame(allocator, compressed, 65536);
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(original, decompressed);
}

test "compress large buffer" {
    const allocator = testing.allocator;

    // Create a 10MB buffer
    const size = 10 * 1024 * 1024;
    const original = try allocator.alloc(u8, size);
    defer allocator.free(original);

    // Fill with pattern
    for (original, 0..) |*byte, i| {
        byte.* = @truncate(i / 1000);
    }

    const compressed = try lz4.compressAlloc(allocator, original);
    defer allocator.free(compressed);

    const ratio = @as(f64, @floatFromInt(original.len)) / @as(f64, @floatFromInt(compressed.len));
    std.debug.print("\n10MB buffer compression ratio: {d:.2}:1\n", .{ratio});
    try testing.expect(ratio > 2.0); // Should compress reasonably well

    const decompressed = try lz4.decompressAlloc(allocator, compressed, original.len);
    defer allocator.free(decompressed);

    try testing.expectEqualSlices(u8, original, decompressed);
}

test "compress bound calculation" {
    const sizes = [_]usize{ 0, 1, 100, 1024, 1024 * 1024 };

    for (sizes) |size| {
        const bound = lz4.compressBound(size);
        // Bound should always be >= input size
        try testing.expect(bound >= size);
        // Bound should be reasonable (not more than 2x for small inputs)
        if (size > 1024) {
            const overhead_ratio = @as(f64, @floatFromInt(bound)) / @as(f64, @floatFromInt(size));
            try testing.expect(overhead_ratio < 1.2);
        }
    }
}

test "multiple compress/decompress cycles" {
    const allocator = testing.allocator;
    const original = "Cycle test data. " ** 50;

    for (0..10) |cycle| {
        const compressed = try lz4.compressAlloc(allocator, original);
        defer allocator.free(compressed);

        const decompressed = try lz4.decompressAlloc(allocator, compressed, original.len);
        defer allocator.free(decompressed);

        try testing.expectEqualStrings(original, decompressed);
        _ = cycle;
    }
}

test "compress various data patterns" {
    const allocator = testing.allocator;

    const patterns = [_][]const u8{
        "A" ** 1000, // Single character
        "AB" ** 500, // Two character pattern
        "ABCD" ** 250, // Four character pattern
        "The quick brown fox jumps over the lazy dog. " ** 20, // English text
        "\x00\x01\x02\x03" ** 250, // Binary pattern
    };

    for (patterns, 0..) |pattern, i| {
        const compressed = try lz4.compressAlloc(allocator, pattern);
        defer allocator.free(compressed);

        const ratio = @as(f64, @floatFromInt(pattern.len)) / @as(f64, @floatFromInt(compressed.len));
        std.debug.print("Pattern {d} compression ratio: {d:.2}:1\n", .{ i, ratio });

        const decompressed = try lz4.decompressAlloc(allocator, compressed, pattern.len);
        defer allocator.free(decompressed);

        try testing.expectEqualSlices(u8, pattern, decompressed);
    }
}
