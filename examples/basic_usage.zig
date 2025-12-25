const std = @import("std");
const lz4 = @import("lz4");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== LZ4 Compression Examples ===\n\n", .{});

    // Example 1: Basic compression
    try basicCompressionExample(allocator);

    // Example 2: High compression
    try highCompressionExample(allocator);

    // Example 3: Frame compression (with metadata)
    try frameCompressionExample(allocator);

    // Example 4: Stream compression for video-like data
    try streamCompressionExample(allocator);

    // Example 5: Compress image-like data
    try imageCompressionExample(allocator);
}

fn basicCompressionExample(allocator: std.mem.Allocator) !void {
    std.debug.print("--- Basic Compression ---\n", .{});

    const original = "Hello, World! This is LZ4 compression in Zig. " ** 20;
    std.debug.print("Original size: {d} bytes\n", .{original.len});

    // Compress
    const compressed = try lz4.compressAlloc(allocator, original);
    defer allocator.free(compressed);
    std.debug.print("Compressed size: {d} bytes\n", .{compressed.len});

    const ratio = @as(f64, @floatFromInt(original.len)) / @as(f64, @floatFromInt(compressed.len));
    std.debug.print("Compression ratio: {d:.2}:1\n", .{ratio});

    // Decompress
    const decompressed = try lz4.decompressAlloc(allocator, compressed, original.len);
    defer allocator.free(decompressed);

    std.debug.print("Decompression successful: {}\n\n", .{std.mem.eql(u8, original, decompressed)});
}

fn highCompressionExample(allocator: std.mem.Allocator) !void {
    std.debug.print("--- High Compression (HC) ---\n", .{});

    const original = "The quick brown fox jumps over the lazy dog. " ** 50;
    std.debug.print("Original size: {d} bytes\n", .{original.len});

    // Compress with level 9 (max is 12)
    const compressed = try lz4.compressAllocHC(allocator, original, 9);
    defer allocator.free(compressed);
    std.debug.print("HC Compressed size: {d} bytes (level 9)\n", .{compressed.len});

    const ratio = @as(f64, @floatFromInt(original.len)) / @as(f64, @floatFromInt(compressed.len));
    std.debug.print("Compression ratio: {d:.2}:1\n", .{ratio});

    const decompressed = try lz4.decompressAlloc(allocator, compressed, original.len);
    defer allocator.free(decompressed);

    std.debug.print("Decompression successful: {}\n\n", .{std.mem.eql(u8, original, decompressed)});
}

fn frameCompressionExample(allocator: std.mem.Allocator) !void {
    std.debug.print("--- Frame Compression ---\n", .{});

    const original = "Frame compression includes size metadata. " ** 30;
    std.debug.print("Original size: {d} bytes\n", .{original.len});

    // Frame compression (self-contained, includes size info)
    const compressed = try lz4.compressFrame(allocator, original);
    defer allocator.free(compressed);
    std.debug.print("Frame compressed size: {d} bytes\n", .{compressed.len});

    // Decompress (no need to specify original size)
    const decompressed = try lz4.decompressFrame(allocator, compressed, 65536);
    defer allocator.free(decompressed);

    std.debug.print("Decompression successful: {}\n\n", .{std.mem.eql(u8, original, decompressed)});
}

fn streamCompressionExample(allocator: std.mem.Allocator) !void {
    std.debug.print("--- Stream Compression ---\n", .{});

    var encoder = try lz4.StreamEncode.init();
    defer encoder.deinit();

    const chunks = [_][]const u8{
        "Frame 1 data. ",
        "Frame 2 data. ",
        "Frame 3 data. ",
        "Frame 4 data. ",
        "Frame 5 data. ",
    };

    var total_original: usize = 0;
    var total_compressed: usize = 0;

    for (chunks, 0..) |chunk, i| {
        const max_size = lz4.compressBound(chunk.len);
        const compressed = try allocator.alloc(u8, max_size);
        defer allocator.free(compressed);

        const compressed_size = try encoder.compress(chunk, compressed);

        total_original += chunk.len;
        total_compressed += compressed_size;

        std.debug.print("Chunk {d}: {d} -> {d} bytes\n", .{ i + 1, chunk.len, compressed_size });
    }

    const ratio = @as(f64, @floatFromInt(total_original)) / @as(f64, @floatFromInt(total_compressed));
    std.debug.print("Total: {d} -> {d} bytes (ratio: {d:.2}:1)\n\n", .{ total_original, total_compressed, ratio });
}

fn imageCompressionExample(allocator: std.mem.Allocator) !void {
    std.debug.print("--- Image Data Compression ---\n", .{});

    // Simulate RGBA image data (640x480)
    const width = 640;
    const height = 480;
    const pixel_size = 4; // RGBA
    const image_size = width * height * pixel_size;

    const image_data = try allocator.alloc(u8, image_size);
    defer allocator.free(image_data);

    // Generate gradient pattern
    for (0..height) |y| {
        for (0..width) |x| {
            const idx = (y * width + x) * 4;
            image_data[idx + 0] = @truncate(x * 255 / width); // R
            image_data[idx + 1] = @truncate(y * 255 / height); // G
            image_data[idx + 2] = @truncate((x + y) * 255 / (width + height)); // B
            image_data[idx + 3] = 255; // A
        }
    }

    std.debug.print("Image: {d}x{d} RGBA ({d} bytes)\n", .{ width, height, image_size });

    // Compress with HC for better ratio
    const compressed = try lz4.compressAllocHC(allocator, image_data, 9);
    defer allocator.free(compressed);

    const ratio = @as(f64, @floatFromInt(image_size)) / @as(f64, @floatFromInt(compressed.len));
    std.debug.print("Compressed: {d} bytes (ratio: {d:.2}:1)\n", .{ compressed.len, ratio });

    // Decompress
    const decompressed = try lz4.decompressAlloc(allocator, compressed, image_size);
    defer allocator.free(decompressed);

    std.debug.print("Decompression successful: {}\n\n", .{std.mem.eql(u8, image_data, decompressed)});
}
