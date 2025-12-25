# zig-lz4

Comprehensive LZ4 compression bindings for Zig 0.14.1 using C interop. Perfect for compressing images, GIFs, videos, and any binary data in wallpaper daemons, video players, and multimedia applications.

## Features

- Full LZ4 API coverage including:
  - Basic compression/decompression
  - High compression (HC) mode
  - Streaming API for continuous data
  - Frame API with metadata support
  - Dictionary support
- Optimized for multimedia data (images, GIFs, video frames)
- Zero-copy where possible
- Comprehensive test suite
- Easy integration into existing projects

## Requirements

- Zig 0.14.1 or later
- liblz4 installed on your system

### Installing liblz4

**Ubuntu/Debian:**
```bash
sudo apt-get install liblz4-dev
```

**Fedora/RHEL:**
```bash
sudo dnf install lz4-devel
```

**macOS:**
```bash
brew install lz4
```

**Arch Linux:**
```bash
sudo pacman -S lz4
```

## Installation

Add this package to your `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add lz4 module
    const lz4 = b.dependency("zig-lz4", .{
        .target = target,
        .optimize = optimize,
    }).module("lz4");

    // Add to your executable
    const exe = b.addExecutable(.{
        .name = "your-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("lz4", lz4);
    exe.linkSystemLibrary("lz4");
    exe.linkLibC();
}
```

Or clone this repository and use it directly:

```bash
git clone https://codeberg.org/blx/zig-lz4.git
cd zig-lz4
zig build test
```

## Quick Start

### Basic Compression

```zig
const std = @import("std");
const lz4 = @import("lz4");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = "Hello, LZ4!";

    // Compress
    const compressed = try lz4.compressAlloc(allocator, original);
    defer allocator.free(compressed);

    // Decompress
    const decompressed = try lz4.decompressAlloc(allocator, compressed, original.len);
    defer allocator.free(decompressed);
}
```

### Image Compression

```zig
// Compress RGBA image data
const width = 1920;
const height = 1080;
const image_data: []u8 = loadImageData(); // Your RGBA data

// Use high compression for better ratios on image data
const compressed = try lz4.compressAllocHC(allocator, image_data, 9);
defer allocator.free(compressed);

// Later, decompress
const decompressed = try lz4.decompressAlloc(allocator, compressed, image_data.len);
defer allocator.free(decompressed);
```

### Video Frame Streaming

```zig
// Initialize stream encoder
var encoder = try lz4.StreamEncode.init();
defer encoder.deinit();

// Compress each frame
for (video_frames) |frame| {
    const max_size = lz4.compressBound(frame.len);
    var compressed = try allocator.alloc(u8, max_size);
    defer allocator.free(compressed);

    const compressed_size = try encoder.compress(frame, compressed);
    // Store or transmit compressed[0..compressed_size]
}
```

### GIF Animation Compression

```zig
// Compress all GIF frames at once with frame API
const all_frames: []u8 = loadGifFrames(); // RGB data for all frames

// Frame compression includes metadata
const compressed = try lz4.compressFrame(allocator, all_frames);
defer allocator.free(compressed);

// Decompress (no need to specify original size)
const decompressed = try lz4.decompressFrame(allocator, compressed, 65536);
defer allocator.free(decompressed);
```

## API Reference

### Basic Compression Functions

#### `compress(src: []const u8, dst: []u8) !usize`
Compress data using default compression level.

#### `compressFast(src: []const u8, dst: []u8, acceleration: i32) !usize`
Compress with acceleration factor (higher = faster but less compression).

#### `compressHC(src: []const u8, dst: []u8, compression_level: i32) !usize`
High compression mode. Levels 1-12 (higher = better compression, slower).

#### `decompress(src: []const u8, dst: []u8, original_size: usize) !usize`
Safe decompression.

#### `compressBound(input_size: usize) usize`
Calculate maximum compressed size for buffer allocation.

### Allocating Variants

#### `compressAlloc(allocator: Allocator, src: []const u8) ![]u8`
Compress and allocate exact size for result.

#### `compressAllocHC(allocator: Allocator, src: []const u8, level: i32) ![]u8`
High compression with allocation.

#### `decompressAlloc(allocator: Allocator, src: []const u8, original_size: usize) ![]u8`
Decompress with allocation.

### Streaming API

#### `StreamEncode`
For continuous compression (video frames, network streams).

```zig
var stream = try lz4.StreamEncode.init();
defer stream.deinit();

// Compress chunks
const size = try stream.compress(chunk, output_buffer);

// Reset stream to start over
stream.reset();

// Load dictionary for better compression
try stream.loadDict(dictionary);
```

#### `StreamDecode`
For continuous decompression.

```zig
var stream = try lz4.StreamDecode.init();
defer stream.deinit();

const size = try stream.decompress(chunk, output_buffer);
```

### Frame API

#### `FrameCompress`
Self-contained frames with metadata (recommended for files).

```zig
var frame = try lz4.FrameCompress.init();
defer frame.deinit();

var output = std.ArrayList(u8).init(allocator);
defer output.deinit();

// Write header
const header_size = try frame.begin(header_buffer, null);
try output.appendSlice(header_buffer[0..header_size]);

// Write compressed data
const data_size = try frame.update(input_data, data_buffer);
try output.appendSlice(data_buffer[0..data_size]);

// Write footer
const footer_size = try frame.end(footer_buffer);
try output.appendSlice(footer_buffer[0..footer_size]);
```

#### `FrameDecompress`
Decompress frame data.

```zig
var frame = try lz4.FrameDecompress.init();
defer frame.deinit();

const result = try frame.decompress(src, dst);
// result.src_consumed: bytes read from src
// result.dst_written: bytes written to dst
```

### Helper Functions

#### `compressFrame(allocator: Allocator, src: []const u8) ![]u8`
One-shot frame compression with allocation.

#### `decompressFrame(allocator: Allocator, src: []const u8, max_size: usize) ![]u8`
One-shot frame decompression with allocation.

## Use Cases

### Wallpaper Daemon

Compress background images to reduce memory usage:

```zig
const wallpaper_data = try loadWallpaper("image.png");
const compressed = try lz4.compressAllocHC(allocator, wallpaper_data, 9);
// Store compressed, decompress when needed for display
```

### Video Player

Stream-compress video frames for caching:

```zig
var encoder = try lz4.StreamEncode.init();
defer encoder.deinit();

for (frames) |frame| {
    const compressed_frame = try compressFrame(allocator, encoder, frame);
    try cache.store(compressed_frame);
}
```

### Image Gallery

Compress thumbnails:

```zig
for (images) |img| {
    const thumbnail = generateThumbnail(img);
    const compressed = try lz4.compressFrame(allocator, thumbnail);
    try saveToCache(img.id, compressed);
}
```

## Performance Tips

1. **Use HC mode for storage**: Better compression ratios for archived data
2. **Use fast mode for real-time**: Lower latency for streaming applications
3. **Use streaming API for sequential data**: Video frames, network packets
4. **Use frame API for files**: Includes checksums and metadata
5. **Reuse streams**: Reset instead of recreating for better performance

## Compression Ratios

Typical ratios for multimedia data:

- **Text**: 3-5:1
- **Images (RGBA)**: 2-4:1 (depending on content)
- **Video frames (YUV)**: 2-6:1 (higher for similar frames)
- **GIF animations**: 3-8:1 (high redundancy between frames)
- **Random data**: ~1:1 (incompressible)

## Testing

Run all tests:

```bash
zig build test
```

Tests include:
- Basic compression/decompression
- Image data compression (various resolutions)
- GIF animation compression
- Video frame compression (HD, 4K)
- Streaming compression
- Edge cases and error handling

## Examples

Build and run the example:

```bash
zig build example
./zig-out/bin/lz4_example
```

## License

Choose your preferred license (MIT, Apache-2.0, etc.)

## Contributing

Contributions welcome! Please ensure all tests pass before submitting PRs.

## Credits

Based on the excellent [LZ4](https://github.com/lz4/lz4) compression library by Yann Collet.
