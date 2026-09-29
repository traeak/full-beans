//! Glyph/icon atlas, generated from `atlas.inl` into raw binary assets.
//!
//! Plan decision 4a: `@embedFile` the atlas rather than carrying a ~1000-line C
//! initializer array into Zig. The binaries are produced by `tools/gen_atlas.py`:
//!
//!   src/assets/atlas_texture.bin  128*128 greyscale bytes, row-major
//!   src/assets/atlas_rects.bin    N * 16 bytes, little-endian int32 {x, y, w, h}
//!
//! The texture is a single-channel image; the renderer samples it and multiplies
//! the value into the draw color (see `renderer.c`'s `greyscale` / `texture_color`).

const std = @import("std");
const microui = @import("microui.zig");
const Rect = microui.Rect;

pub const width: usize = 128;
pub const height: usize = 128;

/// Atlas index of the 3x3 solid-white cell, used for plain rect fills.
/// Mirrors `enum { ATLAS_WHITE = MU_ICON_MAX, ATLAS_FONT }` in atlas.inl.
pub const ATLAS_WHITE: usize = 5;
/// First font glyph index. `fontRect(chr)` resolves to `ATLAS_FONT + chr`.
pub const ATLAS_FONT: usize = 6;

/// Icon indices, mirroring MU_ICON_* from microui.h.
pub const ICON_NONE: usize = 0;
pub const ICON_CLOSE: usize = 1;
pub const ICON_CHECK: usize = 2;
pub const ICON_COLLAPSED: usize = 3;
pub const ICON_EXPANDED: usize = 4;

const texture_bytes: *const [width * height]u8 = @embedFile("assets/atlas_texture.bin");
const rect_bytes: []const u8 = @embedFile("assets/atlas_rects.bin");

/// 128x128 greyscale source image, one byte per pixel.
/// Kept as a pointer so the 16 KiB blob is not copied into the binary again.
pub const texture: *const [width * height]u8 = texture_bytes;

/// Number of `{x, y, w, h}` records in the rect table.
pub const rect_count: usize = rect_bytes.len / @sizeOf(Rect);

/// Look up the source rectangle for an atlas index.
///
/// The rect table is stored as packed little-endian int32 quads so it can be
/// embedded as a binary blob instead of a source array.
pub fn rectAt(index: usize) Rect {
    std.debug.assert(index < rect_count);
    const off = index * 16;
    return Rect.rect(
        @bitCast(std.mem.readInt(i32, rect_bytes[off..][0..4], .little)),
        @bitCast(std.mem.readInt(i32, rect_bytes[off + 4 ..][0..4], .little)),
        @bitCast(std.mem.readInt(i32, rect_bytes[off + 8 ..][0..4], .little)),
        @bitCast(std.mem.readInt(i32, rect_bytes[off + 12 ..][0..4], .little)),
    );
}

/// Source rectangle for a printable ASCII glyph.
///
/// `renderer.c` clamps the character to 127 and skips UTF-8 continuation bytes
/// before reaching the table, so callers must apply the same filtering.
pub fn fontRect(chr: u8) Rect {
    return rectAt(ATLAS_FONT + @as(usize, chr));
}

/// Sample the greyscale texture at (x, y).
pub fn sample(x: usize, y: usize) u8 {
    std.debug.assert(x < width and y < height);
    return texture[y * width + x];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

test "atlas: blob sizes" {
    try testing.expectEqual(width * height, texture.len);
    try testing.expectEqual(@as(usize, 134), rect_count);
    try testing.expectEqual(@as(usize, 0), rect_bytes.len % @sizeOf(Rect));
}

test "atlas: icon rects match atlas.inl" {
    try testing.expectEqual(Rect.rect(88, 68, 16, 16), rectAt(ICON_CLOSE));
    try testing.expectEqual(Rect.rect(0, 0, 18, 18), rectAt(ICON_CHECK));
    // The .inl lists EXPANDED before COLLAPSED, but the enum order is
    // COLLAPSED=3, EXPANDED=4 -- designated initializers resolve them apart.
    try testing.expectEqual(Rect.rect(113, 68, 5, 7), rectAt(ICON_COLLAPSED));
    try testing.expectEqual(Rect.rect(118, 68, 7, 5), rectAt(ICON_EXPANDED));
    try testing.expectEqual(Rect.rect(125, 68, 3, 3), rectAt(ATLAS_WHITE));
}

test "atlas: sampled font glyphs match atlas.inl" {
    try testing.expectEqual(Rect.rect(84, 68, 2, 17), fontRect(' '));
    try testing.expectEqual(Rect.rect(41, 17, 7, 17), fontRect('A'));
    try testing.expectEqual(Rect.rect(54, 51, 6, 17), fontRect('a'));
    try testing.expectEqual(Rect.rect(102, 51, 6, 17), fontRect('~'));
}

test "atlas: highest font index is in range" {
    // ATLAS_FONT + 127 must exist; that is the last entry the renderer can ask for.
    try testing.expect(ATLAS_FONT + 127 < rect_count);
}

test "atlas: texture has non-zero content" {
    var nonzero: usize = 0;
    for (texture) |v| {
        if (v != 0) nonzero += 1;
    }
    // The atlas is mostly background; the C source listed 10584 explicit bytes.
    try testing.expect(nonzero > 1000);
}
