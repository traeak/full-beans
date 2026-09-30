//! Phase 0 smoke test for `src/fenster.zig`.
//!
//! `fenster.zig` compiles but has never opened a window. This exercises the Linux
//! (X11) path end to end before anything else is built on top of it:
//!
//!   1. open an 800x600 window with an owned pixel buffer
//!   2. paint a left-to-right / top-to-bottom RGB ramp + a moving bar
//!   3. run `loop()` for N frames
//!   4. report every observed change to x, y, mouse, mod and keys[]
//!
//! Run with: `zig build smoke`

const std = @import("std");
const Io = std.Io;

const fenster = @import("full_beans").fenster;
const builtin = @import("builtin");
const Fenster = fenster.Fenster;

const width: c_int = 800;
const height: c_int = 600;
const frames: usize = 120;
const frame_ms: i64 = 16;

/// Snapshot of the input-visible fields, so we can diff frame to frame.
const Input = struct {
    x: c_int = 0,
    y: c_int = 0,
    mouse: c_int = 0,
    mod: c_int = 0,
    keys: [256]c_int = .{0} ** 256,
};

/// Paint the color ramp for a given frame. Frame index drives a moving white bar
/// so it is obvious on screen that frames are actually being presented.
fn paint(f: *Fenster, frame: usize) void {
    const w_us: usize = @intCast(width);
    const h_us: usize = @intCast(height);
    const bar_x: usize = frame % (w_us - 40);
    for (0..h_us) |y| {
        const g: u32 = @intCast(y * 255 / h_us);
        for (0..w_us) |x| {
            const r: u32 = @intCast(x * 255 / w_us);
            var px: u32 = (r << 16) | (g << 8) | 128;
            // Opaque white bar, moves left to right across the ramp.
            if (x >= bar_x and x < bar_x + 40) px = 0xFF_FFF_FFF;
            fenster.pixel(f, x, y).* = 0xFF000000 | px;
        }
    }
}

/// Which input channels we actually saw fire. Printed at exit so the run is
/// self-verifying: a channel still `false` after scripted input means the field
/// is never written by fenster.loop().
const Observed = struct {
    mouse_move: bool = false,
    mouse_btn: bool = false,
    modifier: bool = false,
    key: bool = false,
};

// ---------------------------------------------------------------------------
// Synthetic event injection
//
// This X server drops XTEST fake *button* events (motion fakes arrive fine, but
// `xdotool mousedown` produces nothing on the device -- verified with
// `xinput test "Virtual core XTEST pointer"`). So the button path is exercised
// by XSendEvent'ing a ButtonPress/ButtonRelease to our own window on separate
// frames. Separate frames matter: fenster.loop() drains every pending event in
// one call, so a press+release pair processed together leaves `mouse` back at 0
// and a frame-to-frame diff would see no change.
// ---------------------------------------------------------------------------

/// X11 event type numbers, duplicated here so the smoke test does not depend on
/// fenster.zig keeping its private constants in sync.
const XK_KeyPress: c_int = 2;
const XK_KeyRelease: c_int = 3;
const XK_ButtonPress: c_int = 4;
const XK_ButtonRelease: c_int = 5;

/// Platform-gated synthetic input injection.
///
/// On Linux the X11 self-injection path exercises fenster's button/key
/// dispatch without needing XTEST (this X server drops XTEST fake button
/// events -- see NOTES_fenster_smoke.md). On other platforms the helpers are
/// no-ops so the smoke test still compiles and still opens a window.
const inject = if (builtin.target.os.tag == .linux) struct {
    const XButtonEvent = extern struct {
        type: c_int,
        serial: c_ulong = 0,
        send_event: c_int = 1,
        display: ?*anyopaque = null,
        window: c_ulong = 0,
        root: c_ulong = 0,
        subwindow: c_ulong = 0,
        time: c_ulong = 0,
        x: c_int = 0,
        y: c_int = 0,
        x_root: c_int = 0,
        y_root: c_int = 0,
        state: c_uint = 0,
        button: c_uint = 1,
        same_screen: c_int = 1,
    };

    const XKeyEvent = extern struct {
        type: c_int,
        serial: c_ulong = 0,
        send_event: c_int = 1,
        display: ?*anyopaque = null,
        window: c_ulong = 0,
        root: c_ulong = 0,
        subwindow: c_ulong = 0,
        time: c_ulong = 0,
        x: c_int = 0,
        y: c_int = 0,
        x_root: c_int = 0,
        y_root: c_int = 0,
        state: c_uint = 0,
        keycode: c_uint = 0,
        same_screen: c_int = 1,
    };

    const ButtonPressMask: c_ulong = 1 << 4;
    const KeyPressMask: c_ulong = 1 << 0;
    const KeyReleaseMask: c_ulong = 1 << 1;

    extern "X11" fn XSendEvent(
        dpy: ?*anyopaque,
        w: c_ulong,
        propagate: c_int,
        mask: c_ulong,
        event: *const anyopaque,
    ) c_int;

    fn button(f: *Fenster, etype: c_int) void {
        var ev = XButtonEvent{ .type = etype, .display = f.dpy, .window = f.w };
        _ = XSendEvent(f.dpy, f.w, 0, ButtonPressMask, &ev);
    }

    /// keycode 39 is 's' on a standard layout; XkbKeycodeToKeysym maps it to 0x73,
    /// which FENSTER_KEYCODES_LIN turns into keys[83].
    fn key(f: *Fenster, etype: c_int, keycode: c_uint) void {
        var ev = XKeyEvent{ .type = etype, .display = f.dpy, .window = f.w, .keycode = keycode };
        _ = XSendEvent(f.dpy, f.w, 0, KeyPressMask | KeyReleaseMask, &ev);
    }
} else struct {
    fn button(f: *Fenster, etype: c_int) void {
        _ = f;
        _ = etype;
    }

    fn key(f: *Fenster, etype: c_int, keycode: c_uint) void {
        _ = f;
        _ = etype;
        _ = keycode;
    }
};

/// Report any input state that changed since `prev`, then update `prev`.
fn reportInput(
    w: *Io.Writer,
    f: *Fenster,
    prev: *Input,
    obs: *Observed,
    frame: usize,
) Io.Writer.Error!void {
    if (f.x != prev.x or f.y != prev.y) {
        try w.print("f{d:>4}  mouse pos  x={d} y={d}\n", .{ frame, f.x, f.y });
        obs.mouse_move = true;
        prev.x = f.x;
        prev.y = f.y;
    }
    if (f.mouse != prev.mouse) {
        try w.print("f{d:>4}  mouse btn  {d}\n", .{ frame, f.mouse });
        obs.mouse_btn = true;
        prev.mouse = f.mouse;
    }
    if (f.mod != prev.mod) {
        try w.print("f{d:>4}  mod        {d} (ctrl={d} shift={d} alt={d} super={d})\n", .{
            frame,
            f.mod,
            f.mod & 1,
            (f.mod >> 1) & 1,
            (f.mod >> 2) & 1,
            (f.mod >> 3) & 1,
        });
        obs.modifier = true;
        prev.mod = f.mod;
    }
    for (0..256) |k| {
        if (f.keys[k] != prev.keys[k]) {
            const printable = if (k >= 32 and k < 127) @as(u8, @intCast(k)) else '?';
            try w.print("f{d:>4}  key[{d}] = {d}  ('{c}')\n", .{ frame, k, f.keys[k], printable });
            obs.key = true;
            prev.keys[k] = f.keys[k];
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;

    var stdout_buf: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buf);
    const w = &stdout_file_writer.interface;

    const buf = try arena.alloc(
        u32,
        @as(usize, @intCast(width)) * @as(usize, @intCast(height)),
    );

    var f: Fenster = std.mem.zeroes(Fenster);
    f.title = "fenster smoke";
    f.width = width;
    f.height = height;
    f.buf = buf.ptr;

    try w.print("opening {d}x{d} window...\n", .{ width, height });
    fenster.open(&f) catch |err| {
        try w.print("OPEN FAILED: {t}\n", .{err});
        try w.flush();
        return err;
    };
    defer fenster.close(&f);

    // Frame count is env-tunable so the driver script can hold the window open
    // long enough to inject synthetic X events.
    var total_frames: usize = frames;
    if (init.environ_map.get("SMOKE_FRAMES")) |s| {
        total_frames = std.fmt.parseInt(usize, s, 10) catch total_frames;
    }

    try w.print("opened. running {d} frames (~{d}ms each). move the mouse,\n", .{
        total_frames,
        frame_ms,
    });
    try w.print("press buttons and keys to see them reported. ESC to quit early.\n\n", .{});
    try w.flush();

    var prev: Input = .{};
    var obs: Observed = .{};
    var ran: usize = 0;
    var i: usize = 0;
    while (i < total_frames) : (i += 1) {
        ran = i + 1;
        paint(&f, i);

        // Inject on separate frames so each level change is observable.
        if (i == 5) inject.button(&f, XK_ButtonPress);
        if (i == 12) inject.button(&f, XK_ButtonRelease);
        if (i == 20) inject.key(&f, XK_KeyPress, 39); // 's' -> keys[83]
        if (i == 27) inject.key(&f, XK_KeyRelease, 39);

        const keep_going = fenster.loop(&f);
        try reportInput(w, &f, &prev, &obs, i);
        try w.flush();
        if (!keep_going) {
            try w.print("f{d}  loop() returned false (quit signal)\n", .{i});
            break;
        }
        // ESC quits early.
        if (f.keys[27] != 0) {
            try w.print("f{d}  ESC pressed -- quitting early\n", .{i});
            break;
        }
        fenster.fenster_sleep(io, frame_ms);
    }

    try w.print("\nsmoke done: {d} frames presented, buf[0]=0x{x} buf[last]=0x{x}\n", .{
        ran,
        buf[0],
        buf[buf.len - 1],
    });
    try w.print("observed: mouse_move={d} mouse_btn={d} modifier={d} key={d}\n", .{
        @intFromBool(obs.mouse_move),
        @intFromBool(obs.mouse_btn),
        @intFromBool(obs.modifier),
        @intFromBool(obs.key),
    });
    try w.flush();
}
