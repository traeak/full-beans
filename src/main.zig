//! Port of main.c -- the three-window microui demo.

const std = @import("std");
const Io = std.Io;

const fenster = @import("fenster.zig");
const mu = @import("microui.zig");
const renderer = @import("renderer.zig");

const Renderer = renderer.Renderer;

const LOG_SIZE = 64000;
const INPUT_SIZE = 128;
const FPS = 60;

const ESC: c_int = 0x1b;
const ENTER: c_int = '\n';
const BACKSPACE: c_int = 8;

/// The color rows of the Style Editor window.
const ColorRow = struct { label: []const u8, idx: c_int };

const color_rows = [_]ColorRow{
    .{ .label = "text:", .idx = @intFromEnum(mu.ColorId.text) },
    .{ .label = "border:", .idx = @intFromEnum(mu.ColorId.border) },
    .{ .label = "windowbg:", .idx = @intFromEnum(mu.ColorId.window_bg) },
    .{ .label = "titlebg:", .idx = @intFromEnum(mu.ColorId.title_bg) },
    .{ .label = "titletext:", .idx = @intFromEnum(mu.ColorId.title_text) },
    .{ .label = "panelbg:", .idx = @intFromEnum(mu.ColorId.panel_bg) },
    .{ .label = "button:", .idx = @intFromEnum(mu.ColorId.button) },
    .{ .label = "buttonhover:", .idx = @intFromEnum(mu.ColorId.button_hover) },
    .{ .label = "buttonfocus:", .idx = @intFromEnum(mu.ColorId.button_focus) },
    .{ .label = "base:", .idx = @intFromEnum(mu.ColorId.base) },
    .{ .label = "basehover:", .idx = @intFromEnum(mu.ColorId.base_hover) },
    .{ .label = "basefocus:", .idx = @intFromEnum(mu.ColorId.base_focus) },
    .{ .label = "scrollbase:", .idx = @intFromEnum(mu.ColorId.scroll_base) },
    .{ .label = "scrollthumb:", .idx = @intFromEnum(mu.ColorId.scroll_thumb) },
};

const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing " ++
    "elit. Maecenas lacinia, sem eu lacinia molestie, mi risus faucibus " ++
    "ipsum, eu varius magna felis a nulla.";

const App = struct {
    io: Io,
    win: *fenster.Fenster,
    r: *Renderer,
    ctx: *mu.Context,
    logbuf: []u8,
    input: []u8,
    log_updated: bool = false,
    bg: [3]mu.Real = .{ 90, 95, 100 },
    checks: [3]bool = .{ true, false, true },
};

// ---------------------------------------------------------------------------
// microui text callbacks -- pure atlas lookups, so no renderer instance is
// needed and no module-global state is required.
// ---------------------------------------------------------------------------

fn textWidth(font: mu.Font, str: []const u8, len: c_int) c_int {
    _ = font;
    const s = if (len < 0) str else str[0..@intCast(len)];
    return Renderer.getTextWidth(s);
}

fn textHeight(font: mu.Font) c_int {
    _ = font;
    return Renderer.getTextHeight();
}

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

fn writeLog(app: *App, text: []const u8) void {
    var len = strLen(app.logbuf);
    if (0 < len) {
        app.logbuf[len] = '\n';
        len += 1;
    }
    const n = @min(text.len, app.logbuf.len - len - 1);
    @memcpy(app.logbuf[len..][0..n], text[0..n]);
    app.logbuf[len + n] = 0;
    app.log_updated = true;
}

fn strLen(b: []const u8) usize {
    return std.mem.indexOfScalar(u8, b, 0) orelse b.len;
}

// ---------------------------------------------------------------------------
// Demo Window
// ---------------------------------------------------------------------------

fn testWindow(app: *App) void {
    const ctx = app.ctx;
    if (mu.beginWindow(ctx, "Demo Window", mu.Rect.rect(40, 40, 300, 450)) == 0) return;
    defer mu.endWindow(ctx);

    const win = mu.getCurrentContainer(ctx);
    win.rect.w = @max(win.rect.w, 240);
    win.rect.h = @max(win.rect.h, 300);

    // -- window info --
    if (mu.header(ctx, "Window Info") != 0) {
        const w = mu.getCurrentContainer(ctx);
        var buf: [64]u8 = undefined;
        mu.layoutRow(ctx, 2, &.{ 54, -1 }, 0);
        mu.label(ctx, "Position:");
        mu.label(ctx, std.fmt.bufPrint(&buf, "{d}, {d}", .{ w.rect.x, w.rect.y }) catch "??");
        mu.label(ctx, "Size:");
        mu.label(ctx, std.fmt.bufPrint(&buf, "{d}, {d}", .{ w.rect.w, w.rect.h }) catch "??");
    }

    // -- labels + buttons --
    if (mu.headerEx(ctx, "Test Buttons", mu.OPT_EXPANDED) != 0) {
        mu.layoutRow(ctx, 3, &.{ 86, -110, -1 }, 0);
        mu.label(ctx, "Test buttons 1:");
        if (mu.button(ctx, "Button 1") & mu.RES_SUBMIT != 0) writeLog(app, "Pressed button 1");
        if (mu.button(ctx, "Button 2") & mu.RES_SUBMIT != 0) writeLog(app, "Pressed button 2");
        mu.label(ctx, "Test buttons 2:");
        if (mu.button(ctx, "Button 3") & mu.RES_SUBMIT != 0) writeLog(app, "Pressed button 3");
        if (mu.button(ctx, "Popup") & mu.RES_SUBMIT != 0) mu.openPopup(ctx, "Test Popup");
        if (mu.beginPopup(ctx, "Test Popup") != 0) {
            defer mu.endPopup(ctx);
            _ = mu.button(ctx, "Hello");
            _ = mu.button(ctx, "World");
        }
    }

    // -- tree --
    if (mu.headerEx(ctx, "Tree and Text", mu.OPT_EXPANDED) != 0) {
        mu.layoutRow(ctx, 2, &.{ 140, -1 }, 0);
        mu.layoutBeginColumn(ctx);
        if (mu.beginTreenode(ctx, "Test 1") != 0) {
            defer mu.endTreenode(ctx);
            if (mu.beginTreenode(ctx, "Test 1a") != 0) {
                defer mu.endTreenode(ctx);
                mu.label(ctx, "Hello");
                mu.label(ctx, "world");
            }
            if (mu.beginTreenode(ctx, "Test 1b") != 0) {
                defer mu.endTreenode(ctx);
                if (mu.button(ctx, "Button 1") & mu.RES_SUBMIT != 0) writeLog(app, "Pressed button 1");
                if (mu.button(ctx, "Button 2") & mu.RES_SUBMIT != 0) writeLog(app, "Pressed button 2");
            }
        }
        if (mu.beginTreenode(ctx, "Test 2") != 0) {
            defer mu.endTreenode(ctx);
            mu.layoutRow(ctx, 2, &.{ 54, 54 }, 0);
            if (mu.button(ctx, "Button 3") & mu.RES_SUBMIT != 0) writeLog(app, "Pressed button 3");
            if (mu.button(ctx, "Button 4") & mu.RES_SUBMIT != 0) writeLog(app, "Pressed button 4");
            if (mu.button(ctx, "Button 5") & mu.RES_SUBMIT != 0) writeLog(app, "Pressed button 5");
            if (mu.button(ctx, "Button 6") & mu.RES_SUBMIT != 0) writeLog(app, "Pressed button 6");
        }
        if (mu.beginTreenode(ctx, "Test 3") != 0) {
            defer mu.endTreenode(ctx);
            var i: usize = 0;
            while (i < 3) : (i += 1) {
                _ = mu.checkbox(ctx, "Checkbox 1", &app.checks[i]);
            }
        }
        mu.layoutEndColumn(ctx);

        mu.layoutBeginColumn(ctx);
        mu.layoutRow(ctx, 1, &.{-1}, 0);
        mu.text(ctx, lorem);
        mu.layoutEndColumn(ctx);
    }

    // -- background color sliders --
    if (mu.headerEx(ctx, "Background Color", mu.OPT_EXPANDED) != 0) {
        mu.layoutRow(ctx, 2, &.{ -78, -1 }, 74);
        mu.layoutBeginColumn(ctx);
        mu.layoutRow(ctx, 2, &.{ 46, -1 }, 0);
        mu.label(ctx, "Red:");
        _ = mu.slider(ctx, &app.bg[0], 0, 255);
        mu.label(ctx, "Green:");
        _ = mu.slider(ctx, &app.bg[1], 0, 255);
        mu.label(ctx, "Blue:");
        _ = mu.slider(ctx, &app.bg[2], 0, 255);
        mu.layoutEndColumn(ctx);

        // color preview swatch
        const r = mu.layoutNext(ctx);
        mu.drawRect(ctx, r, muColorFromReal(app.bg));
        var buf: [32]u8 = undefined;
        const hex = std.fmt.bufPrint(
            &buf,
            "#{X:0>2}{X:0>2}{X:0>2}",
            .{ @as(u8, @intFromFloat(@trunc(app.bg[0]))), @as(u8, @intFromFloat(@trunc(app.bg[1]))), @as(u8, @intFromFloat(@trunc(app.bg[2]))) },
        ) catch "??????";
        mu.drawControlText(ctx, hex, r, @intFromEnum(mu.ColorId.text), mu.OPT_ALIGNCENTER);
    }
}

fn muColorFromReal(bg: [3]mu.Real) mu.Color {
    return mu.Color.color(
        toU8(bg[0]),
        toU8(bg[1]),
        toU8(bg[2]),
        255,
    );
}

fn toU8(v: mu.Real) u8 {
    const t: c_int = @intFromFloat(@trunc(v));
    return @intCast(@max(0, @min(255, t)));
}

// ---------------------------------------------------------------------------
// Log Window
// ---------------------------------------------------------------------------

fn logWindow(app: *App) void {
    const ctx = app.ctx;
    if (mu.beginWindow(ctx, "Log Window", mu.Rect.rect(350, 40, 300, 200)) == 0) return;
    defer mu.endWindow(ctx);

    // output text panel
    mu.layoutRow(ctx, 1, &.{-1}, -25);
    mu.beginPanel(ctx, "Log Output");
    const panel = mu.getCurrentContainer(ctx);
    mu.layoutRow(ctx, 1, &.{-1}, -1);
    mu.text(ctx, app.logbuf[0..strLen(app.logbuf)]);
    mu.endPanel(ctx);
    if (app.log_updated) {
        panel.scroll.y = panel.content_size.y;
        app.log_updated = false;
    }

    // input textbox + submit button
    var submitted = false;
    mu.layoutRow(ctx, 2, &.{ -70, -1 }, 0);
    if (mu.textbox(ctx, app.input) & mu.RES_SUBMIT != 0) {
        mu.setFocus(ctx, ctx.last_id);
        submitted = true;
    }
    if (mu.button(ctx, "Submit") & mu.RES_SUBMIT != 0) submitted = true;
    if (submitted) {
        writeLog(app, app.input[0..strLen(app.input)]);
        app.input[0] = 0;
    }
}

// ---------------------------------------------------------------------------
// Style Editor
// ---------------------------------------------------------------------------

/// Slider bound to a u8 style component. C keeps a single `static float tmp`;
/// the value is copied in and back out around the float-domain slider.
fn uint8Slider(ctx: *mu.Context, value: *u8, low: mu.Real, high: mu.Real) c_int {
    var tmp: mu.Real = @floatFromInt(value.*);
    mu.pushId(ctx, std.mem.asBytes(&value));
    defer mu.popId(ctx);
    const res = mu.sliderEx(ctx, &tmp, low, high, 0, "%.0f", mu.OPT_ALIGNCENTER);
    value.* = toU8(tmp);
    return res;
}

fn styleWindow(app: *App) void {
    const ctx = app.ctx;
    if (mu.beginWindow(ctx, "Style Editor", mu.Rect.rect(350, 250, 300, 240)) == 0) return;
    defer mu.endWindow(ctx);

    const sw: c_int = @intFromFloat(@trunc(@as(f64, mu.getCurrentContainer(ctx).body.w) * 0.14));
    mu.layoutRow(ctx, 6, &.{ 80, sw, sw, sw, sw, -1 }, 0);
    for (color_rows) |row| {
        mu.label(ctx, row.label);
        const c = &ctx.style.colors[@intCast(row.idx)];
        _ = uint8Slider(ctx, &c.r, 0, 255);
        _ = uint8Slider(ctx, &c.g, 0, 255);
        _ = uint8Slider(ctx, &c.b, 0, 255);
        _ = uint8Slider(ctx, &c.a, 0, 255);
        mu.drawRect(ctx, mu.layoutNext(ctx), c.*);
    }
}

// ---------------------------------------------------------------------------
// Frame + main loop
// ---------------------------------------------------------------------------

fn processFrame(app: *App) void {
    mu.begin(app.ctx);
    styleWindow(app);
    logWindow(app);
    testWindow(app);
    mu.end(app.ctx);
}

fn pumpInput(app: *App) bool {
    const ctx = app.ctx;
    const r = app.r;

    if (r.mouseMoved()) mu.inputMousemove(ctx, r.mouse_x, r.mouse_y);
    if (r.mouseDown()) {
        mu.inputMousedown(ctx, r.mouse_x, r.mouse_y, mu.MOUSE_LEFT);
    } else if (r.mouseUp()) {
        mu.inputMouseup(ctx, r.mouse_x, r.mouse_y, mu.MOUSE_LEFT);
    }

    if (r.keyDown(ESC)) return false;

    if (r.keyDown(ENTER)) {
        mu.inputKeydown(ctx, mu.KEY_RETURN);
    } else if (r.keyUp(ENTER)) {
        mu.inputKeyup(ctx, mu.KEY_RETURN);
    }
    if (r.keyDown(BACKSPACE)) {
        mu.inputKeydown(ctx, mu.KEY_BACKSPACE);
    } else if (r.keyUp(BACKSPACE)) {
        mu.inputKeyup(ctx, mu.KEY_BACKSPACE);
    }

    var i: usize = 0;
    while (i < 256) : (i += 1) {
        if (!r.keyDown(@intCast(i))) continue;
        if (32 <= i and i <= 126) {
            var ch: [1]u8 = .{@intCast(i)};
            if (std.ascii.isAlphabetic(ch[0]) and !r.shiftPressed()) {
                ch[0] = std.ascii.toLower(ch[0]);
            }
            mu.inputText(ctx, &ch);
        }
    }
    return true;
}

fn dispatch(app: *App) void {
    const ctx = app.ctx;
    const r = app.r;
    var cmd: ?*mu.Command = null;
    while (mu.nextCommand(ctx, &cmd)) {
        const c = cmd.?;
        switch (c.*.type) {
            .text => r.drawText(mu.textSlice(c), c.*.text.pos, c.*.text.color),
            .rect => r.drawRect(c.*.rect.rect, c.*.rect.color),
            .icon => r.drawIcon(c.*.icon.id, c.*.icon.rect, c.*.icon.color),
            .clip => r.setClipRect(c.*.clip.rect),
            .jump, .max => {},
        }
    }
}

fn timingRequested(init: std.process.Init) bool {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch return false;
    for (args) |a| {
        if (std.mem.eql(u8, a, "--timing")) return true;
    }
    return false;
}

fn dumpRequested(init: std.process.Init) bool {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch return false;
    for (args) |a| {
        if (std.mem.eql(u8, a, "--dump")) return true;
    }
    return false;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    const win = try arena.create(fenster.Fenster);
    win.* = std.mem.zeroes(fenster.Fenster);
    win.title = "full-beans";
    win.width = 800;
    win.height = 600;
    win.buf = @ptrCast(try arena.alloc(u32, 800 * 600));
    try fenster.open(win);
    defer fenster.close(win);

    const r = try arena.create(Renderer);
    r.init(win);
    r.dump = dumpRequested(init);

    const ctx = try arena.create(mu.Context);
    ctx.* = undefined;
    mu.init(ctx);
    ctx.text_width = textWidth;
    ctx.text_height = textHeight;

    const timing = timingRequested(init);
    var frame_times: [60]i64 = undefined;
    var n_frames: usize = 0;

    var app = App{
        .io = io,
        .win = win,
        .r = r,
        .ctx = ctx,
        .logbuf = try arena.alloc(u8, LOG_SIZE),
        .input = try arena.alloc(u8, INPUT_SIZE),
    };
    @memset(app.logbuf, 0);
    @memset(app.input, 0);

    while (true) {
        const before = fenster.fenster_time(io);
        if (!pumpInput(&app)) break;

        processFrame(&app);

        r.clear(muColorFromReal(app.bg));
        dispatch(&app);
        r.present();

        const painted = fenster.fenster_time(io) - before;
        if (timing) {
            frame_times[n_frames % frame_times.len] = painted;
            n_frames += 1;
            if (n_frames % frame_times.len == 0) {
                var sum: i64 = 0;
                var worst: i64 = 0;
                for (frame_times) |t| {
                    sum += t;
                    if (worst < t) worst = t;
                }
                const avg = @divTrunc(sum, @as(i64, @intCast(frame_times.len)));
                std.debug.print(
                    "frames {d}..{d}: avg {d} ms  max {d} ms  (budget {d} ms)\n",
                    .{ n_frames - frame_times.len, n_frames, avg, worst, @divTrunc(1000, FPS) },
                );
            }
        }
        const budget: i64 = @divTrunc(1000, FPS);
        const sleep_ms = budget - painted;
        if (0 < sleep_ms) fenster.fenster_sleep(io, sleep_ms);
    }
}
