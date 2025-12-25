const std = @import("std");
const lz4 = @import("lz4");
const testing = std.testing;

// Simulated raw image data (RGBA format, 100x100 pixels)
fn generateImageData(allocator: std.mem.Allocator, width: usize, height: usize) ![]u8 {
    const size = width * height * 4; // RGBA
    const data = try allocator.alloc(u8, size);

    // Generate gradient pattern
    for (0..height) |y| {
        for (0..width) |x| {
            const idx = (y * width + x) * 4;
            data[idx + 0] = @truncate(x * 255 / width); // R
            data[idx + 1] = @truncate(y * 255 / height); // G
            data[idx + 2] = @truncate((x + y) * 255 / (width + height)); // B
            data[idx + 3] = 255; // A
        }
    }

    return data;
}

// Simulated GIF frame data (multiple frames)
fn generateGifFrames(allocator: std.mem.Allocator, width: usize, height: usize, num_frames: usize) ![]u8 {
    const frame_size = width * height * 3; // RGB
    const total_size = frame_size * num_frames;
    const data = try allocator.alloc(u8, total_size);

    for (0..num_frames) |frame| {
        const frame_offset = frame * frame_size;
        const phase = @as(f32, @floatFromInt(frame)) / @as(f32, @floatFromInt(num_frames));

        for (0..height) |y| {
            for (0..width) |x| {
                const idx = frame_offset + (y * width + x) * 3;
                data[idx + 0] = @truncate(@as(usize, @intFromFloat(@as(f32, @floatFromInt(x)) * 255.0 / @as(f32, @floatFromInt(width)) * phase))); // R
                data[idx + 1] = @truncate(@as(usize, @intFromFloat(@as(f32, @floatFromInt(y)) * 255.0 / @as(f32, @floatFromInt(height))))); // G
                data[idx + 2] = @truncate(@as(usize, @intFromFloat(255.0 * (1.0 - phase)))); // B
            }
        }
    }

    return data;
}

// Simulated video frame data (YUV420p format)
fn generateVideoData(allocator: std.mem.Allocator, width: usize, height: usize, num_frames: usize) ![]u8 {
    // YUV420p: Y plane (full size) + U plane (1/4) + V plane (1/4)
    const y_size = width * height;
    const uv_size = (width / 2) * (height / 2);
    const frame_size = y_size + uv_size * 2;
    const total_size = frame_size * num_frames;
    const data = try allocator.alloc(u8, total_size);

    for (0..num_frames) |frame| {
        const frame_offset = frame * frame_size;
        const time = @as(f32, @floatFromInt(frame)) / @as(f32, @floatFromInt(num_frames));

        // Y plane
        for (0..height) |y| {
            for (0..width) |x| {
                const idx = frame_offset + y * width + x;
                const luma = @as(f32, @floatFromInt(x + y)) / @as(f32, @floatFromInt(width + height));
                data[idx] = @truncate(@as(usize, @intFromFloat(luma * 255.0 * (0.5 + 0.5 * time))));
            }
        }

        // U and V planes (subsampled)
        const u_offset = frame_offset + y_size;
        const v_offset = u_offset + uv_size;
        for (0..height / 2) |y| {
            for (0..width / 2) |x| {
                const idx = y * (width / 2) + x;
                data[u_offset + idx] = @truncate(@as(usize, @intFromFloat(128.0 + 64.0 * time)));
                data[v_offset + idx] = @truncate(@as(usize, @intFromFloat(128.0 - 64.0 * time)));
            }
        }
    }

    return data;
}

test "compress and decompress image data" {
    const allocator = testing.allocator;

    // Generate a 1024x768 RGBA image
    const width = 1024;
    const height = 768;
    const image_data = try generateImageData(allocator, width, height);
    defer allocator.free(image_data);

    std.debug.print("\nImage test: {d}x{d} RGBA ({d} bytes)\n", .{ width, height, image_data.len });

    // Compress using default compression
    const compressed = try lz4.compressAlloc(allocator, image_data);
    defer allocator.free(compressed);

    const ratio = @as(f64, @floatFromInt(image_data.len)) / @as(f64, @floatFromInt(compressed.len));
    std.debug.print("Compressed: {d} bytes (ratio: {d:.2}:1)\n", .{ compressed.len, ratio });

    // Decompress
    const decompressed = try lz4.decompressAlloc(allocator, compressed, image_data.len);
    defer allocator.free(decompressed);

    try testing.expectEqualSlices(u8, image_data, decompressed);
    std.debug.print("Decompression successful!\n", .{});
}

test "compress and decompress image with HC" {
    const allocator = testing.allocator;

    const width = 1920;
    const height = 1080;
    const image_data = try generateImageData(allocator, width, height);
    defer allocator.free(image_data);

    std.debug.print("\nHD Image test: {d}x{d} RGBA ({d} bytes)\n", .{ width, height, image_data.len });

    // Compress using high compression level
    const compressed = try lz4.compressAllocHC(allocator, image_data, 9);
    defer allocator.free(compressed);

    const ratio = @as(f64, @floatFromInt(image_data.len)) / @as(f64, @floatFromInt(compressed.len));
    std.debug.print("HC Compressed: {d} bytes (ratio: {d:.2}:1)\n", .{ compressed.len, ratio });

    // Decompress
    const decompressed = try lz4.decompressAlloc(allocator, compressed, image_data.len);
    defer allocator.free(decompressed);

    try testing.expectEqualSlices(u8, image_data, decompressed);
    std.debug.print("HC decompression successful!\n", .{});
}

test "compress and decompress GIF frames" {
    const allocator = testing.allocator;

    const width = 640;
    const height = 480;
    const num_frames = 30;
    const gif_data = try generateGifFrames(allocator, width, height, num_frames);
    defer allocator.free(gif_data);

    std.debug.print("\nGIF test: {d}x{d} RGB, {d} frames ({d} bytes)\n", .{ width, height, num_frames, gif_data.len });

    // Compress using frame API
    const compressed = try lz4.compressFrame(allocator, gif_data);
    defer allocator.free(compressed);

    const ratio = @as(f64, @floatFromInt(gif_data.len)) / @as(f64, @floatFromInt(compressed.len));
    std.debug.print("Compressed: {d} bytes (ratio: {d:.2}:1)\n", .{ compressed.len, ratio });

    // Decompress
    const decompressed = try lz4.decompressFrame(allocator, compressed, gif_data.len * 2);
    defer allocator.free(decompressed);

    try testing.expectEqualSlices(u8, gif_data, decompressed);
    std.debug.print("GIF decompression successful!\n", .{});
}

test "compress and decompress video data" {
    const allocator = testing.allocator;

    const width = 1280;
    const height = 720;
    const num_frames = 60; // 2 seconds at 30fps
    const video_data = try generateVideoData(allocator, width, height, num_frames);
    defer allocator.free(video_data);

    std.debug.print("\nVideo test: {d}x{d} YUV420p, {d} frames ({d} bytes)\n", .{ width, height, num_frames, video_data.len });

    // Compress using high compression
    const compressed = try lz4.compressAllocHC(allocator, video_data, 12);
    defer allocator.free(compressed);

    const ratio = @as(f64, @floatFromInt(video_data.len)) / @as(f64, @floatFromInt(compressed.len));
    std.debug.print("Compressed: {d} bytes (ratio: {d:.2}:1)\n", .{ compressed.len, ratio });

    // Decompress
    const decompressed = try lz4.decompressAlloc(allocator, compressed, video_data.len);
    defer allocator.free(decompressed);

    try testing.expectEqualSlices(u8, video_data, decompressed);
    std.debug.print("Video decompression successful!\n", .{});
}

test "compress large 4K video data" {
    const allocator = testing.allocator;

    const width = 3840;
    const height = 2160;
    const num_frames = 10; // Smaller number to keep test fast
    const video_data = try generateVideoData(allocator, width, height, num_frames);
    defer allocator.free(video_data);

    std.debug.print("\n4K Video test: {d}x{d} YUV420p, {d} frames ({d} bytes)\n", .{ width, height, num_frames, video_data.len });

    // Use frame compression for better metadata handling
    const compressed = try lz4.compressFrame(allocator, video_data);
    defer allocator.free(compressed);

    const ratio = @as(f64, @floatFromInt(video_data.len)) / @as(f64, @floatFromInt(compressed.len));
    std.debug.print("Compressed: {d} bytes (ratio: {d:.2}:1)\n", .{ compressed.len, ratio });

    // Decompress
    const decompressed = try lz4.decompressFrame(allocator, compressed, video_data.len * 2);
    defer allocator.free(decompressed);

    try testing.expectEqualSlices(u8, video_data, decompressed);
    std.debug.print("4K Video decompression successful!\n", .{});
}

test "stream compress animated content" {
    const allocator = testing.allocator;

    const width = 800;
    const height = 600;
    const num_frames = 20;

    std.debug.print("\nStreaming animation test: {d}x{d}, {d} frames\n", .{ width, height, num_frames });

    var stream = try lz4.StreamEncode.init();
    defer stream.deinit();

    const frame_size = width * height * 4; // RGBA
    const max_compressed = lz4.compressBound(frame_size);

    var all_compressed = std.ArrayList(u8).init(allocator);
    defer all_compressed.deinit();

    // Keep track of frame data for streaming (streaming needs previous data available)
    var frames = std.ArrayList([]u8).init(allocator);
    defer {
        for (frames.items) |frame_data| {
            allocator.free(frame_data);
        }
        frames.deinit();
    }

    // Compress each frame
    for (0..num_frames) |frame| {
        const frame_data = try generateImageData(allocator, width, height);
        try frames.append(frame_data);

        // Add simple animation by modifying data
        for (frame_data, 0..) |*pixel, i| {
            pixel.* = @truncate(pixel.* +% @as(u8, @truncate(frame * 10 + i)));
        }

        const compressed_frame = try allocator.alloc(u8, max_compressed);
        defer allocator.free(compressed_frame);

        const compressed_size = try stream.compress(frame_data, compressed_frame);
        try all_compressed.appendSlice(compressed_frame[0..compressed_size]);
    }

    std.debug.print("Streamed {d} frames, total compressed: {d} bytes\n", .{ num_frames, all_compressed.items.len });
    std.debug.print("Average per frame: {d} bytes\n", .{all_compressed.items.len / num_frames});
}
