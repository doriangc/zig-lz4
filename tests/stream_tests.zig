const std = @import("std");
const lz4 = @import("lz4");
const testing = std.testing;

test "stream compression and decompression" {
    const allocator = testing.allocator;

    const chunks = [_][]const u8{
        "First chunk of data. ",
        "Second chunk of data. ",
        "Third chunk of data. ",
        "Fourth chunk of data. ",
    };

    // For streaming, we compress and decompress independently for each chunk
    // without interdependencies between chunks
    for (chunks) |chunk| {
        // Create fresh encoder and decoder for each chunk
        var encoder = try lz4.StreamEncode.init();
        defer encoder.deinit();

        var decoder = try lz4.StreamDecode.init();
        defer decoder.deinit();

        const max_size = lz4.compressBound(chunk.len);
        const compressed = try allocator.alloc(u8, max_size);
        defer allocator.free(compressed);

        const compressed_size = try encoder.compress(chunk, compressed);

        var out_buffer = try allocator.alloc(u8, chunk.len * 2);
        defer allocator.free(out_buffer);

        const decompressed_size = try decoder.decompress(compressed[0..compressed_size], out_buffer);
        try testing.expectEqualSlices(u8, chunk, out_buffer[0..decompressed_size]);
    }
}

test "stream compression with dictionary" {
    const allocator = testing.allocator;

    const dictionary = "common pattern common pattern common pattern";
    const data = "This contains common pattern in the text";

    var encoder = try lz4.StreamEncode.init();
    defer encoder.deinit();

    // Load dictionary
    try encoder.loadDict(dictionary);

    const max_size = lz4.compressBound(data.len);
    const compressed = try allocator.alloc(u8, max_size);
    defer allocator.free(compressed);

    const compressed_size = try encoder.compress(data, compressed);
    try testing.expect(compressed_size > 0);
}

test "stream reset and reuse" {
    const allocator = testing.allocator;

    var encoder = try lz4.StreamEncode.init();
    defer encoder.deinit();

    const data1 = "First dataset to compress";
    const data2 = "Second dataset to compress";

    // Compress first dataset
    const max_size = lz4.compressBound(data1.len);
    const compressed1 = try allocator.alloc(u8, max_size);
    defer allocator.free(compressed1);

    const size1 = try encoder.compress(data1, compressed1);
    try testing.expect(size1 > 0);

    // Reset stream
    encoder.reset();

    // Compress second dataset with reset stream
    const compressed2 = try allocator.alloc(u8, max_size);
    defer allocator.free(compressed2);

    const size2 = try encoder.compress(data2, compressed2);
    try testing.expect(size2 > 0);
}

test "frame compression streaming" {
    const allocator = testing.allocator;

    var frame = try lz4.FrameCompress.init();
    defer frame.deinit();

    const chunks = [_][]const u8{
        "Chunk one. ",
        "Chunk two. ",
        "Chunk three. ",
    };

    var all_compressed = std.ArrayList(u8).init(allocator);
    defer all_compressed.deinit();

    // Begin frame
    var header_buffer: [64]u8 = undefined;
    const header_size = try frame.begin(&header_buffer, null);
    try all_compressed.appendSlice(header_buffer[0..header_size]);

    // Compress chunks
    for (chunks) |chunk| {
        const max_size = lz4.FrameCompress.compressBound(chunk.len);
        var compressed = try allocator.alloc(u8, max_size);
        defer allocator.free(compressed);

        const compressed_size = try frame.update(chunk, compressed);
        try all_compressed.appendSlice(compressed[0..compressed_size]);
    }

    // End frame
    var footer_buffer: [64]u8 = undefined;
    const footer_size = try frame.end(&footer_buffer);
    try all_compressed.appendSlice(footer_buffer[0..footer_size]);

    // Decompress entire frame
    var decompressor = try lz4.FrameDecompress.init();
    defer decompressor.deinit();

    var decompressed = std.ArrayList(u8).init(allocator);
    defer decompressed.deinit();

    var src_offset: usize = 0;
    while (src_offset < all_compressed.items.len) {
        var dst_buffer: [1024]u8 = undefined;
        const result = try decompressor.decompress(
            all_compressed.items[src_offset..],
            &dst_buffer,
        );

        try decompressed.appendSlice(dst_buffer[0..result.dst_written]);
        src_offset += result.src_consumed;

        if (result.src_consumed == 0 and result.dst_written == 0) {
            break;
        }
    }

    // Verify decompressed data
    var expected = std.ArrayList(u8).init(allocator);
    defer expected.deinit();
    for (chunks) |chunk| {
        try expected.appendSlice(chunk);
    }

    try testing.expectEqualSlices(u8, expected.items, decompressed.items);
}

test "large stream compression for video frames" {
    const allocator = testing.allocator;

    var encoder = try lz4.StreamEncode.init();
    defer encoder.deinit();

    const frame_size = 1920 * 1080 * 3; // Full HD RGB frame
    const num_frames = 10;

    var total_original: usize = 0;
    var total_compressed: usize = 0;

    for (0..num_frames) |frame_num| {
        // Simulate video frame data
        const frame_data = try allocator.alloc(u8, frame_size);
        defer allocator.free(frame_data);

        // Fill with pattern (simulating video content)
        for (frame_data, 0..) |*byte, i| {
            byte.* = @truncate((i + frame_num * 1000) % 256);
        }

        const max_compressed = lz4.compressBound(frame_size);
        const compressed = try allocator.alloc(u8, max_compressed);
        defer allocator.free(compressed);

        const compressed_size = try encoder.compress(frame_data, compressed);

        total_original += frame_size;
        total_compressed += compressed_size;
    }

    const ratio = @as(f64, @floatFromInt(total_original)) / @as(f64, @floatFromInt(total_compressed));
    std.debug.print("\nStreamed {d} Full HD frames\n", .{num_frames});
    std.debug.print("Original: {d} bytes, Compressed: {d} bytes\n", .{ total_original, total_compressed });
    std.debug.print("Compression ratio: {d:.2}:1\n", .{ratio});
}

test "interleaved frame compression" {
    const allocator = testing.allocator;

    // Simulate compressing multiple streams simultaneously
    var encoder1 = try lz4.StreamEncode.init();
    defer encoder1.deinit();

    var encoder2 = try lz4.StreamEncode.init();
    defer encoder2.deinit();

    const data_stream1 = [_][]const u8{
        "Stream 1 - Frame 1",
        "Stream 1 - Frame 2",
        "Stream 1 - Frame 3",
    };

    const data_stream2 = [_][]const u8{
        "Stream 2 - Frame 1",
        "Stream 2 - Frame 2",
        "Stream 2 - Frame 3",
    };

    const max_size = lz4.compressBound(100);
    const buffer = try allocator.alloc(u8, max_size);
    defer allocator.free(buffer);

    // Compress frames from both streams in interleaved fashion
    for (0..data_stream1.len) |i| {
        // Compress from stream 1
        const size1 = try encoder1.compress(data_stream1[i], buffer);
        try testing.expect(size1 > 0);

        // Compress from stream 2
        const size2 = try encoder2.compress(data_stream2[i], buffer);
        try testing.expect(size2 > 0);
    }
}

test "frame preferences configuration" {
    const allocator = testing.allocator;

    const data = "Test data for frame preferences. " ** 100;

    // Test with different block sizes
    const block_sizes = [_]c_uint{
        lz4.c.LZ4F_max64KB,
        lz4.c.LZ4F_max256KB,
        lz4.c.LZ4F_max1MB,
        lz4.c.LZ4F_max4MB,
    };

    for (block_sizes) |block_size| {
        var frame = try lz4.FrameCompress.init();
        defer frame.deinit();

        var prefs = lz4.FramePreferences{
            .frame_info = .{
                .blockSizeID = block_size,
                .blockMode = lz4.c.LZ4F_blockLinked,
                .contentChecksumFlag = lz4.c.LZ4F_contentChecksumEnabled,
                .frameType = lz4.c.LZ4F_frame,
                .contentSize = 0,
                .dictID = 0,
                .blockChecksumFlag = lz4.c.LZ4F_noBlockChecksum,
            },
            .compression_level = 9,
            .auto_flush = 0,
            .favor_dec_speed = 0,
            .reserved = [_]c_uint{0} ** 3,
        };

        const max_size = lz4.FrameCompress.compressBound(data.len);
        var compressed = try allocator.alloc(u8, max_size);
        defer allocator.free(compressed);

        var offset: usize = 0;
        offset += try frame.begin(compressed[offset..], &prefs);
        offset += try frame.update(data, compressed[offset..]);
        offset += try frame.end(compressed[offset..]);

        try testing.expect(offset > 0);

        // Verify decompression
        const decompressed = try lz4.decompressFrame(allocator, compressed[0..offset], data.len * 2);
        defer allocator.free(decompressed);

        try testing.expectEqualStrings(data, decompressed);
    }
}
