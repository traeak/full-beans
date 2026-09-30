//! Software renderer for microui command streams.
//!
//! Decision 3b: the renderer is a struct that borrows a `*Fenster` and owns its
//! own staging arrays. The original C version kept all of this in file-scope
//! globals, so a draw callback could reach into the window and mutate it in
//! place -- here that state is explicit and per-instance.

const std = @import("std");
const fenster = @import("fenster.zig");
const mu = @import("microui.zig");
const atlas = @import("atlas.zig");

const BUFFER_SIZE = 16384;

/// Precomputed `greyscale(c) == r_color(mu_color(c, c, c, 255))`, so the
/// textured inner loop is one load plus one OR instead of three shifts and three
/// ORs per pixel.
const grey_lut: [256]u32 = blk: {
    var t: [256]u32 = undefined;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        const c: u32 = @intCast(i);
        t[i] = 0xff_0000_00 | (c << 16) | (c << 8) | c;
    }
    break :blk t;
};

fn rColor(c: mu.Color) u32 {
    return @as(u32, c.a) << 24 | @as(u32, c.r) << 16 | @as(u32, c.g) << 8 | @as(u32, c.b);
}

fn muColorArgb(v: u32) mu.Color {
    return mu.Color.color(
        @truncate(v >> 16),
        @truncate(v >> 8),
        @truncate(v),
        @truncate(v >> 24),
    );
}

/// `blend_pixel` with `src.a == 255` reduces to `(src * 255) >> 8` per channel
/// and is independent of the destination.
///
/// This is NOT the same as writing `src` through: 255*255>>8 == 253, so full
/// opacity still darkens by one quantum. The fast path must reproduce that or the
/// port will render brighter than the C demo.
fn opaqueColor(c: mu.Color) u32 {
    const r: u32 = @intCast(@as(c_int, c.r) * 255 >> 8);
    const g: u32 = @intCast(@as(c_int, c.g) * 255 >> 8);
    const b: u32 = @intCast(@as(c_int, c.b) * 255 >> 8);
    // blend_pixel leaves the destination alpha untouched, and `clear` always
    // writes 255, so every pixel's alpha is 255 for the life of the frame.
    return 0xff_0000_00 | (r << 16) | (g << 8) | b;
}

fn blendPixel(dst: mu.Color, src: mu.Color) mu.Color {
    // Done in u32: Zig requires an unsigned left operand for `>>`, and the
    // products (<= 255*255 + 255*255) fit comfortably.
    const sa: u32 = src.a;
    const ia: u32 = 0xff - sa;
    return mu.Color.color(
        @truncate((@as(u32, src.r) * sa + @as(u32, dst.r) * ia) >> 8),
        @truncate((@as(u32, src.g) * sa + @as(u32, dst.g) * ia) >> 8),
        @truncate((@as(u32, src.b) * sa + @as(u32, dst.b) * ia) >> 8),
        dst.a,
    );
}

pub const Renderer = struct {
    f: *fenster.Fenster,
    tex_buf: [BUFFER_SIZE]mu.Rect = undefined,
    src_buf: [BUFFER_SIZE]mu.Rect = undefined,
    color_buf: [BUFFER_SIZE]mu.Color = undefined,
    buf_idx: usize = 0,
    clip_rect: mu.Rect = mu.Rect.rect(0, 0, 0, 0),

    // Edge-detection state. C kept `mouse_down` as a file-scope global; the
    // mouse coordinates were threaded through the caller instead.
    mouse_was_down: bool = false,
    mouse_x: c_int = 0,
    mouse_y: c_int = 0,

    /// Set from the RDUMP env var to mirror the C renderer's trace, so the two
    /// draw-call streams can be diffed directly.
    dump: bool = false,

    /// Pointer-based on purpose. `Renderer` is ~590 KB (three 16384-entry
    /// staging arrays); returning it by value made ReleaseFast lose the
    /// initialised pointer and crash on an uninitialised `self` (valgrind:
    /// "Use of uninitialised value of size 8" at the call site). Writing into a
    /// caller-owned allocation avoids both the copy and the failure mode.
    pub fn init(self: *Renderer, f: *fenster.Fenster) void {
        self.* = .{ .f = f };
        self.clip_rect = mu.Rect.rect(0, 0, f.width, f.height);
    }

    /// Draw every queued quad, then reset the buffer.
    pub fn flush(self: *Renderer) void {
        const width: usize = @intCast(self.f.width);
        const buf: [*]u32 = self.f.buf;

        var i: usize = 0;
        while (i < self.buf_idx) : (i += 1) {
            const src = self.src_buf[i];
            const tex = self.tex_buf[i];

            // Clip intersection is computed once per quad, not per pixel.
            const ystart = @max(src.y, self.clip_rect.y);
            const yend = @min(src.y + src.h, self.clip_rect.y + self.clip_rect.h);
            const xstart = @max(src.x, self.clip_rect.x);
            const xend = @min(src.x + src.w, self.clip_rect.x + self.clip_rect.w);

            if (src.w == tex.w and src.h == tex.h) {
                // Textured path: the atlas byte is a greyscale mask ORed in.
                var y = ystart;
                while (y < yend) : (y += 1) {
                    const row = @as(usize, @intCast(y)) * width;
                    var x = xstart;
                    while (x < xend) : (x += 1) {
                        // The textured path works in renderer-relative offsets
                        // and adds the atlas rect's origin itself; `atlas.sample`
                        // expects absolute atlas coordinates, so the origin has
                        // to be applied here.
                        const tx = tex.x + (x - src.x);
                        const ty = tex.y + (y - src.y);
                        const tc = atlas.sample(@intCast(tx), @intCast(ty));
                        const px = row + @as(usize, @intCast(x));
                        buf[px] |= grey_lut[tc];
                    }
                }
            } else {
                const c = self.color_buf[i];
                if (c.a == 255) {
                    // Opaque: constant across the whole quad, no dst read.
                    const fill = opaqueColor(c);
                    var y = ystart;
                    while (y < yend) : (y += 1) {
                        const row = @as(usize, @intCast(y)) * width;
                        var x = xstart;
                        while (x < xend) : (x += 1) {
                            buf[row + @as(usize, @intCast(x))] = fill;
                        }
                    }
                } else {
                    var y = ystart;
                    while (y < yend) : (y += 1) {
                        const row = @as(usize, @intCast(y)) * width;
                        var x = xstart;
                        while (x < xend) : (x += 1) {
                            const px = row + @as(usize, @intCast(x));
                            buf[px] = rColor(blendPixel(muColorArgb(buf[px]), c));
                        }
                    }
                }
            }
        }
        self.buf_idx = 0;
    }

    fn pushQuad(self: *Renderer, src: mu.Rect, tex: mu.Rect, color: mu.Color) void {
        if (self.buf_idx == BUFFER_SIZE) self.flush();
        self.tex_buf[self.buf_idx] = tex;
        self.src_buf[self.buf_idx] = src;
        self.color_buf[self.buf_idx] = color;
        self.buf_idx += 1;
    }

    pub fn drawRect(self: *Renderer, rect: mu.Rect, color: mu.Color) void {
        if (self.dump) std.debug.print("RECT {d} {d} {d} {d}\n", .{ rect.x, rect.y, rect.w, rect.h });
        self.pushQuad(rect, atlas.rectAt(atlas.ATLAS_WHITE), color);
    }

    pub fn drawText(self: *Renderer, text: []const u8, pos: mu.Vec2, color: mu.Color) void {
        if (self.dump) std.debug.print("TEXT {d} {d} [{s}]\n", .{ pos.x, pos.y, text });
        var dst = mu.Rect.rect(pos.x, pos.y, 0, 0);
        for (text) |byte| {
            // Skip UTF-8 continuation bytes so a multi-byte character does not
            // advance the pen once per byte.
            if (byte & 0xc0 == 0x80) continue;
            const chr: usize = @intCast(@min(byte, 127));
            const src = atlas.rectAt(atlas.ATLAS_FONT + chr);
            dst.w = src.w;
            dst.h = src.h;
            self.pushQuad(dst, src, color);
            dst.x += dst.w;
        }
    }

    pub fn drawIcon(self: *Renderer, id: c_int, rect: mu.Rect, color: mu.Color) void {
        if (self.dump) std.debug.print("ICON {d} {d} {d} {d} {d}\n", .{ id, rect.x, rect.y, rect.w, rect.h });
        const src = atlas.rectAt(@intCast(id));
        const x = rect.x + @divTrunc(rect.w - src.w, 2);
        const y = rect.y + @divTrunc(rect.h - src.h, 2);
        self.pushQuad(mu.Rect.rect(x, y, src.w, src.h), src, color);
    }

    pub fn getTextWidth(text: []const u8) c_int {
        var res: c_int = 0;
        for (text) |byte| {
            if (byte & 0xc0 == 0x80) continue;
            const chr: usize = @intCast(@min(byte, 127));
            res += atlas.rectAt(atlas.ATLAS_FONT + chr).w;
        }
        return res;
    }

    pub fn getTextHeight() c_int {
        return 18;
    }

    pub fn setClipRect(self: *Renderer, rect: mu.Rect) void {
        if (self.dump) std.debug.print("CLIP {d} {d} {d} {d}\n", .{ rect.x, rect.y, rect.w, rect.h });
        self.flush();
        const ystart = @max(0, rect.y);
        const yend = @min(self.f.height, rect.y + rect.h);
        const xstart = @max(0, rect.x);
        const xend = @min(self.f.width, rect.x + rect.w);
        self.clip_rect = mu.Rect.rect(xstart, ystart, xend - xstart, yend - ystart);
    }

    pub fn clear(self: *Renderer, clr: mu.Color) void {
        self.flush();
        const v = rColor(clr);
        const w: usize = @intCast(@abs(self.f.width));
        const h: usize = @intCast(@abs(self.f.height));
        const n: usize = w * h;
        var i: usize = 0;
        while (i < n) : (i += 1) self.f.buf[i] = v;
    }

    pub fn present(self: *Renderer) void {
        self.flush();
        _ = fenster.loop(self.f);
    }

    // -- input edge detection ------------------------------------------------
    //
    // fenster reports level state (`mouse`, `keys[]` are 0/1); microui wants
    // edges. C did this translation here, including the trick of bumping
    // `window.keys[k]` to 2 so the same key press is not re-reported.

    pub fn mouseDown(self: *Renderer) bool {
        if (self.f.mouse != 0 and !self.mouse_was_down) {
            self.mouse_was_down = true;
            return true;
        }
        return false;
    }

    pub fn mouseUp(self: *Renderer) bool {
        if (self.f.mouse == 0 and self.mouse_was_down) {
            self.mouse_was_down = false;
            return true;
        }
        return false;
    }

    /// Returns true (and updates `self.mouse_x/y`) when the pointer moved.
    pub fn mouseMoved(self: *Renderer) bool {
        if (self.f.x != self.mouse_x or self.f.y != self.mouse_y) {
            self.mouse_x = self.f.x;
            self.mouse_y = self.f.y;
            return true;
        }
        return false;
    }

    pub fn ctrlPressed(self: *Renderer) bool {
        return self.f.mod & 1 != 0;
    }

    pub fn shiftPressed(self: *Renderer) bool {
        return self.f.mod & 2 != 0;
    }

    pub fn altPressed(self: *Renderer) bool {
        return self.f.mod & 4 != 0;
    }

    /// First frame the key is down. Consumes the event by bumping the fenster
    /// slot past 1 so a held key does not repeat.
    pub fn keyDown(self: *Renderer, key: c_int) bool {
        const k: usize = @intCast(key);
        if (self.f.keys[k] == 1) {
            self.f.keys[k] += 1;
            return true;
        }
        return false;
    }

    /// True when the key is not currently down.
    pub fn keyUp(self: *Renderer, key: c_int) bool {
        return @as(c_int, @intCast(self.f.keys[@intCast(key)])) < 1;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

/// Owns the pixel buffer so the test frees the slice it allocated, rather than a
/// `[*]u32` re-slice -- which is not a slice at all.
const FakeWin = struct {
    f: fenster.Fenster,
    mem: []u32,

    fn deinit(self: *FakeWin) void {
        testing.allocator.free(self.mem);
    }
};

fn fakeWindow(w: c_int, h: c_int) !FakeWin {
    const mem = try testing.allocator.alloc(u32, @intCast(w * h));
    @memset(mem, 0);
    var fw: FakeWin = .{ .f = std.mem.zeroes(fenster.Fenster), .mem = mem };
    fw.f.width = w;
    fw.f.height = h;
    fw.f.buf = @ptrCast(mem.ptr);
    return fw;
}

test "renderer: opaque fast path reproduces C's lossy blend exactly" {
    // C: (255 * 255) >> 8 == 253, not 255. A "write the color straight
    // through" optimization would be visibly wrong.
    // C-verified: (255*255)>>8 == 254, so full white comes back one step down.
    try testing.expectEqual(@as(u32, 0xff_fe_fe_fe), opaqueColor(mu.Color.color(255, 255, 255, 255)));
    try testing.expectEqual(@as(u32, 0xff_7e_7e_7e), opaqueColor(mu.Color.color(127, 127, 127, 255)));
    const bg = mu.Color.color(255, 255, 255, 255);
    const c = mu.Color.color(127, 200, 64, 255);
    try testing.expectEqual(rColor(blendPixel(bg, c)), opaqueColor(c));
}

test "renderer: greyscale LUT matches r_color(c,c,c,255)" {
    for (0..256) |i| {
        const c: u8 = @intCast(i);
        try testing.expectEqual(rColor(mu.Color.color(c, c, c, 255)), grey_lut[c]);
    }
}

test "renderer: opaque rect writes expected pixels" {
    var fw = try fakeWindow(4, 2);
    defer fw.deinit();
    var r: Renderer = undefined;
    r.init(&fw.f);
    r.clear(mu.Color.color(0, 0, 0, 255));
    r.drawRect(mu.Rect.rect(1, 0, 2, 2), mu.Color.color(255, 0, 0, 255));
    r.flush();

    // `clear` writes alpha 255, so the untouched pixels are 0xff000000.
    try testing.expectEqual(@as(u32, 0xff_00_00_00), fw.mem[0]);
    try testing.expectEqual(opaqueColor(mu.Color.color(255, 0, 0, 255)), fw.mem[1]);
    try testing.expectEqual(opaqueColor(mu.Color.color(255, 0, 0, 255)), fw.mem[2]);
    try testing.expectEqual(@as(u32, 0xff_00_00_00), fw.mem[3]);
    try testing.expectEqual(opaqueColor(mu.Color.color(255, 0, 0, 255)), fw.mem[5]);
}

test "renderer: clip rect bounds the draw" {
    var fw = try fakeWindow(4, 1);
    defer fw.deinit();
    var r: Renderer = undefined;
    r.init(&fw.f);
    r.clear(mu.Color.color(0, 0, 0, 255));
    r.setClipRect(mu.Rect.rect(2, 0, 10, 10)); // clamped to the window width
    r.drawRect(mu.Rect.rect(0, 0, 4, 1), mu.Color.color(0, 255, 0, 255));
    r.flush();

    // Clip (2,0,10,10) clamps to x in [2, 4), so pixels 0 and 1 are untouched
    // and 2 and 3 are painted.
    try testing.expectEqual(@as(u32, 0xff_00_00_00), fw.mem[0]);
    try testing.expectEqual(@as(u32, 0xff_00_00_00), fw.mem[1]);
    try testing.expectEqual(opaqueColor(mu.Color.color(0, 255, 0, 255)), fw.mem[2]);
    try testing.expectEqual(opaqueColor(mu.Color.color(0, 255, 0, 255)), fw.mem[3]);
}

test "renderer: alpha blend path composites over the background" {
    var fw = try fakeWindow(1, 1);
    defer fw.deinit();
    var r: Renderer = undefined;
    r.init(&fw.f);
    r.clear(mu.Color.color(200, 100, 50, 255));
    r.drawRect(mu.Rect.rect(0, 0, 1, 1), mu.Color.color(0, 0, 0, 128));
    r.flush();
    const want = rColor(blendPixel(mu.Color.color(200, 100, 50, 255), mu.Color.color(0, 0, 0, 128)));
    try testing.expectEqual(want, fw.mem[0]);
    // C-verified: (0*128 + 200*127)>>8 == 99, (100*127)>>8 == 49,
    // (50*127)>>8 == 24 -- so the result is not simply the source color.
    try testing.expectEqual(@as(u32, 0xff_63_31_18), fw.mem[0]);
}

test "renderer: text advance skips utf-8 continuation bytes" {
    var fw = try fakeWindow(64, 16);
    defer fw.deinit();
    var r: Renderer = undefined;
    r.init(&fw.f);
    r.clear(mu.Color.color(0, 0, 0, 255));
    // 'A' and 'B' are one glyph each; the two 0x80 bytes must not add width.
    r.drawText("A\x80\x80B", mu.Vec2.vec2(0, 0), mu.Color.color(255, 255, 255, 255));
    const aw = atlas.rectAt(atlas.ATLAS_FONT + 'A').w;
    const bw = atlas.rectAt(atlas.ATLAS_FONT + 'B').w;
    try testing.expectEqual(@as(usize, 2), r.buf_idx);
    try testing.expectEqual(aw + bw, r.src_buf[1].x + r.src_buf[1].w);
    // getTextWidth returns pixels, not characters: the two continuation bytes
    // contribute nothing, so it is exactly the 'A' glyph plus the 'B' glyph.
    try testing.expectEqual(@as(c_int, aw + bw), Renderer.getTextWidth("A\x80\x80B"));
    try testing.expectEqual(@as(c_int, 0), Renderer.getTextWidth("\x80\x80"));
}
