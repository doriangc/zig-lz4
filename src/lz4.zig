const std = @import("std");

// Link against liblz4
pub const c = @cImport({
    @cInclude("lz4.h");
    @cInclude("lz4hc.h");
    @cInclude("lz4frame.h");
});

// Core LZ4 compression/decompression functions
pub fn compress(src: []const u8, dst: []u8) !usize {
    const max_dst_size = compressBound(src.len);
    if (dst.len < max_dst_size) {
        return error.BufferTooSmall;
    }

    const result = c.LZ4_compress_default(
        src.ptr,
        dst.ptr,
        @intCast(src.len),
        @intCast(dst.len),
    );

    if (result <= 0) {
        return error.CompressionFailed;
    }

    return @intCast(result);
}

pub fn compressFast(src: []const u8, dst: []u8, acceleration: i32) !usize {
    const max_dst_size = compressBound(src.len);
    if (dst.len < max_dst_size) {
        return error.BufferTooSmall;
    }

    const result = c.LZ4_compress_fast(
        src.ptr,
        dst.ptr,
        @intCast(src.len),
        @intCast(dst.len),
        acceleration,
    );

    if (result <= 0) {
        return error.CompressionFailed;
    }

    return @intCast(result);
}

pub fn compressHC(src: []const u8, dst: []u8, compression_level: i32) !usize {
    const max_dst_size = compressBound(src.len);
    if (dst.len < max_dst_size) {
        return error.BufferTooSmall;
    }

    const result = c.LZ4_compress_HC(
        src.ptr,
        dst.ptr,
        @intCast(src.len),
        @intCast(dst.len),
        compression_level,
    );

    if (result <= 0) {
        return error.CompressionFailed;
    }

    return @intCast(result);
}

pub fn decompress(src: []const u8, dst: []u8, original_size: usize) !usize {
    if (dst.len < original_size) {
        return error.BufferTooSmall;
    }

    const result = c.LZ4_decompress_safe(
        src.ptr,
        dst.ptr,
        @intCast(src.len),
        @intCast(dst.len),
    );

    if (result < 0) {
        return error.DecompressionFailed;
    }

    return @intCast(result);
}

pub fn decompressFast(src: []const u8, dst: []u8, original_size: usize) !void {
    const result = c.LZ4_decompress_fast(
        src.ptr,
        dst.ptr,
        @intCast(original_size),
    );

    if (result < 0) {
        return error.DecompressionFailed;
    }
}

pub fn compressBound(input_size: usize) usize {
    return @intCast(c.LZ4_compressBound(@intCast(input_size)));
}

// Streaming compression API
pub const StreamEncode = struct {
    stream: *c.LZ4_stream_t,

    pub fn init() !StreamEncode {
        const stream = c.LZ4_createStream() orelse return error.StreamCreationFailed;
        return StreamEncode{ .stream = stream };
    }

    pub fn deinit(self: *StreamEncode) void {
        _ = c.LZ4_freeStream(self.stream);
    }

    pub fn reset(self: *StreamEncode) void {
        c.LZ4_resetStream(self.stream);
    }

    pub fn compress(self: *StreamEncode, src: []const u8, dst: []u8) !usize {
        const result = c.LZ4_compress_fast_continue(
            self.stream,
            src.ptr,
            dst.ptr,
            @intCast(src.len),
            @intCast(dst.len),
            1,
        );

        if (result <= 0) {
            return error.CompressionFailed;
        }

        return @intCast(result);
    }

    pub fn loadDict(self: *StreamEncode, dict: []const u8) !void {
        const result = c.LZ4_loadDict(self.stream, dict.ptr, @intCast(dict.len));
        if (result < 0) {
            return error.DictLoadFailed;
        }
    }
};

pub const StreamDecode = struct {
    stream: *c.LZ4_streamDecode_t,

    pub fn init() !StreamDecode {
        const stream = c.LZ4_createStreamDecode() orelse return error.StreamCreationFailed;
        return StreamDecode{ .stream = stream };
    }

    pub fn deinit(self: *StreamDecode) void {
        _ = c.LZ4_freeStreamDecode(self.stream);
    }

    pub fn decompress(self: *StreamDecode, src: []const u8, dst: []u8) !usize {
        const result = c.LZ4_decompress_safe_continue(
            self.stream,
            src.ptr,
            dst.ptr,
            @intCast(src.len),
            @intCast(dst.len),
        );

        if (result < 0) {
            return error.DecompressionFailed;
        }

        return @intCast(result);
    }
};

// LZ4 Frame API (for self-contained compressed frames)
pub const FramePreferences = struct {
    frame_info: c.LZ4F_frameInfo_t = .{
        .blockSizeID = c.LZ4F_default,
        .blockMode = c.LZ4F_blockLinked,
        .contentChecksumFlag = c.LZ4F_noContentChecksum,
        .frameType = c.LZ4F_frame,
        .contentSize = 0,
        .dictID = 0,
        .blockChecksumFlag = c.LZ4F_noBlockChecksum,
    },
    compression_level: c_int = 0,
    auto_flush: c_uint = 0,
    favor_dec_speed: c_uint = 0,
    reserved: [3]c_uint = [_]c_uint{0} ** 3,
};

pub const FrameCompress = struct {
    ctx: ?*c.struct_LZ4F_cctx_s,

    pub fn init() !FrameCompress {
        var ctx: ?*c.struct_LZ4F_cctx_s = null;
        const result = c.LZ4F_createCompressionContext(@ptrCast(&ctx), c.LZ4F_VERSION);
        if (c.LZ4F_isError(result) != 0) {
            return error.ContextCreationFailed;
        }
        return FrameCompress{ .ctx = ctx };
    }

    pub fn deinit(self: *FrameCompress) void {
        _ = c.LZ4F_freeCompressionContext(self.ctx);
    }

    pub fn begin(self: *FrameCompress, dst: []u8, prefs: ?*const FramePreferences) !usize {
        const preferences: ?*const c.LZ4F_preferences_t = if (prefs) |p| @ptrCast(p) else null;
        const result = c.LZ4F_compressBegin(self.ctx, dst.ptr, dst.len, preferences);
        if (c.LZ4F_isError(result) != 0) {
            return error.CompressBeginFailed;
        }
        return result;
    }

    pub fn update(self: *FrameCompress, src: []const u8, dst: []u8) !usize {
        const result = c.LZ4F_compressUpdate(
            self.ctx,
            dst.ptr,
            dst.len,
            src.ptr,
            src.len,
            null,
        );
        if (c.LZ4F_isError(result) != 0) {
            return error.CompressUpdateFailed;
        }
        return result;
    }

    pub fn end(self: *FrameCompress, dst: []u8) !usize {
        const result = c.LZ4F_compressEnd(self.ctx, dst.ptr, dst.len, null);
        if (c.LZ4F_isError(result) != 0) {
            return error.CompressEndFailed;
        }
        return result;
    }

    pub fn compressBound(src_size: usize) usize {
        return c.LZ4F_compressBound(src_size, null);
    }
};

pub const FrameDecompress = struct {
    ctx: ?*c.struct_LZ4F_dctx_s,

    pub fn init() !FrameDecompress {
        var ctx: ?*c.struct_LZ4F_dctx_s = null;
        const result = c.LZ4F_createDecompressionContext(@ptrCast(&ctx), c.LZ4F_VERSION);
        if (c.LZ4F_isError(result) != 0) {
            return error.ContextCreationFailed;
        }
        return FrameDecompress{ .ctx = ctx };
    }

    pub fn deinit(self: *FrameDecompress) void {
        _ = c.LZ4F_freeDecompressionContext(self.ctx);
    }

    pub fn decompress(self: *FrameDecompress, src: []const u8, dst: []u8) !struct { src_consumed: usize, dst_written: usize } {
        var src_size = src.len;
        var dst_size = dst.len;

        const result = c.LZ4F_decompress(
            self.ctx,
            dst.ptr,
            &dst_size,
            src.ptr,
            &src_size,
            null,
        );

        if (c.LZ4F_isError(result) != 0) {
            return error.DecompressFailed;
        }

        return .{
            .src_consumed = src_size,
            .dst_written = dst_size,
        };
    }
};

// High-level helper functions for common use cases
pub fn compressAlloc(allocator: std.mem.Allocator, src: []const u8) ![]u8 {
    const max_dst_size = compressBound(src.len);
    const dst = try allocator.alloc(u8, max_dst_size);
    errdefer allocator.free(dst);

    const compressed_size = try compress(src, dst);
    return allocator.realloc(dst, compressed_size);
}

pub fn compressAllocHC(allocator: std.mem.Allocator, src: []const u8, level: i32) ![]u8 {
    const max_dst_size = compressBound(src.len);
    const dst = try allocator.alloc(u8, max_dst_size);
    errdefer allocator.free(dst);

    const compressed_size = try compressHC(src, dst, level);
    return allocator.realloc(dst, compressed_size);
}

pub fn decompressAlloc(allocator: std.mem.Allocator, src: []const u8, original_size: usize) ![]u8 {
    const dst = try allocator.alloc(u8, original_size);
    errdefer allocator.free(dst);

    _ = try decompress(src, dst, original_size);
    return dst;
}

// Frame-based compression/decompression (includes size information)
pub fn compressFrame(allocator: std.mem.Allocator, src: []const u8) ![]u8 {
    var frame = try FrameCompress.init();
    defer frame.deinit();

    const max_size = FrameCompress.compressBound(src.len);
    const dst = try allocator.alloc(u8, max_size);
    errdefer allocator.free(dst);

    var offset: usize = 0;
    offset += try frame.begin(dst[offset..], null);
    offset += try frame.update(src, dst[offset..]);
    offset += try frame.end(dst[offset..]);

    return allocator.realloc(dst, offset);
}

pub fn decompressFrame(allocator: std.mem.Allocator, src: []const u8, max_size: usize) ![]u8 {
    var frame = try FrameDecompress.init();
    defer frame.deinit();

    const dst = try allocator.alloc(u8, max_size);
    errdefer allocator.free(dst);

    var src_offset: usize = 0;
    var dst_offset: usize = 0;

    while (src_offset < src.len) {
        const result = try frame.decompress(src[src_offset..], dst[dst_offset..]);
        src_offset += result.src_consumed;
        dst_offset += result.dst_written;

        if (result.src_consumed == 0 and result.dst_written == 0) {
            break;
        }
    }

    return allocator.realloc(dst, dst_offset);
}

test "basic compression and decompression" {
    const allocator = std.testing.allocator;
    const original = "Hello, World! This is a test of LZ4 compression.";

    const compressed = try compressAlloc(allocator, original);
    defer allocator.free(compressed);

    const decompressed = try decompressAlloc(allocator, compressed, original.len);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

test "frame compression and decompression" {
    const allocator = std.testing.allocator;
    const original = "Hello, World! This is a test of LZ4 frame compression.";

    const compressed = try compressFrame(allocator, original);
    defer allocator.free(compressed);

    const decompressed = try decompressFrame(allocator, compressed, 1024);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}
