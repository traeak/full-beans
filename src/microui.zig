//! microui — a minimal immediate mode GUI library in Zig.
//!
//! Ported from rxi/microui (C) to Zig 0.16.
//! Safety > Performance > Developer Experience.

const std = @import("std");

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Clip result codes.
pub const Clip = enum(c_int) {
    none = 0,
    part = 1,
    all,
};

/// Command types for the draw command list.
pub const CommandType = enum(c_int) {
    jump = 1,
    clip,
    rect,
    text,
    icon,
    max,
};

/// Color IDs used in the style table.
pub const ColorId = enum(c_int) {
    text,
    border,
    window_bg,
    title_bg,
    title_text,
    panel_bg,
    button,
    button_hover,
    button_focus,
    base,
    base_hover,
    base_focus,
    scroll_base,
    scroll_thumb,
    max,
};

/// Built-in icon IDs.
pub const IconId = enum(c_int) {
    close = 1,
    check,
    collapsed,
    expanded,
    max,
};

/// Result flags returned by controls.
///
/// Bit-compatible with C's `int` MU_RES_* mask (see the top-level RES_ACTIVE /
/// RES_SUBMIT / RES_CHANGE constants), so widget return values can be bitcast
/// without changing the wire layout.
pub const Result = packed struct(c_int) {
    active: bool = false,
    submit: bool = false,
    change: bool = false,
};

/// Option flags passed to controls.
pub const Option = packed struct(c_int) {
    align_center: bool = false,
    align_right: bool = false,
    no_interact: bool = false,
    no_frame: bool = false,
    no_resize: bool = false,
    no_scroll: bool = false,
    no_close: bool = false,
    no_title: bool = false,
    hold_focus: bool = false,
    auto_size: bool = false,
    popup: bool = false,
    closed: bool = false,
    expanded: bool = false,
};

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

pub const COMMANDLIST_SIZE = 256 * 1024;
pub const ROOTLIST_SIZE = 32;
pub const CONTAINERSTACK_SIZE = 32;
pub const CLIPSTACK_SIZE = 32;
pub const IDSTACK_SIZE = 32;
pub const LAYOUTSTACK_SIZE = 16;
pub const CONTAINERPOOL_SIZE = 48;
pub const TREENODEPOOL_SIZE = 48;
pub const MAX_WIDTHS = 16;
pub const MAX_FMT = 127;

pub const REAL_FMT = "%.3g";
pub const SLIDER_FMT = "%.2f";

// ---------------------------------------------------------------------------
// Core types
// ---------------------------------------------------------------------------

pub const Real = f32;
pub const Id = u32;
pub const Font = ?*const anyopaque;

/// Generic fixed-capacity stack (replaces C `mu_stack` macro).
pub fn Stack(comptime T: type, comptime n: comptime_int) type {
    return struct {
        idx: usize = 0,
        items: [n]T = undefined,

        const Self = @This();

        pub fn push(self: *Self, val: T) void {
            std.debug.assert(self.idx < n);
            self.items[self.idx] = val;
            self.idx += 1;
        }

        pub fn pop(self: *Self) void {
            std.debug.assert(self.idx > 0);
            self.idx -= 1;
        }
    };
}

/// 2D integer vector.
pub const Vec2 = extern struct {
    x: c_int,
    y: c_int,

    pub fn vec2(x: c_int, y: c_int) Vec2 {
        return .{ .x = x, .y = y };
    }
};

/// Axis-aligned rectangle.
pub const Rect = extern struct {
    x: c_int,
    y: c_int,
    w: c_int,
    h: c_int,

    pub fn rect(x: c_int, y: c_int, w: c_int, h: c_int) Rect {
        return .{ .x = x, .y = y, .w = w, .h = h };
    }
};

/// RGBA color (8-bit per channel).
pub const Color = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn color(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }
};

/// Pool item for retained state tracking.
pub const PoolItem = extern struct {
    id: Id,
    last_update: c_int,
};

// ---------------------------------------------------------------------------
// Command types
// ---------------------------------------------------------------------------

pub const BaseCommand = extern struct {
    type: CommandType,
    size: c_int,
};

pub const JumpCommand = extern struct {
    base: BaseCommand,
    dst: ?*anyopaque,
};

pub const ClipCommand = extern struct {
    base: BaseCommand,
    rect: Rect,
};

pub const RectCommand = extern struct {
    base: BaseCommand,
    rect: Rect,
    color: Color,
};

pub const TextCommand = extern struct {
    base: BaseCommand,
    font: Font,
    pos: Vec2,
    color: Color,
    str: [1]u8,
};

pub const IconCommand = extern struct {
    base: BaseCommand,
    rect: Rect,
    id: c_int,
    color: Color,
};

/// Draw command union. All variants share the BaseCommand layout at offset 0.
pub const Command = extern union {
    type: CommandType,
    base: BaseCommand,
    jump: JumpCommand,
    clip: ClipCommand,
    rect: RectCommand,
    text: TextCommand,
    icon: IconCommand,
};

// ---------------------------------------------------------------------------
// Layout state
// ---------------------------------------------------------------------------

pub const Layout = extern struct {
    body: Rect,
    next: Rect,
    position: Vec2,
    size: Vec2,
    max: Vec2,
    widths: [MAX_WIDTHS]c_int,
    items: c_int,
    item_index: c_int,
    next_row: c_int,
    next_type: c_int,
    indent: c_int,
};

// ---------------------------------------------------------------------------
// Container state
// ---------------------------------------------------------------------------

pub const Container = extern struct {
    head: ?*Command,
    tail: ?*Command,
    rect: Rect,
    body: Rect,
    content_size: Vec2,
    scroll: Vec2,
    zindex: c_int,
    open: c_int,
};

// ---------------------------------------------------------------------------
// Style
// ---------------------------------------------------------------------------

pub const Style = extern struct {
    font: Font,
    size: Vec2,
    padding: c_int,
    spacing: c_int,
    indent: c_int,
    title_height: c_int,
    scrollbar_size: c_int,
    thumb_size: c_int,
    colors: [@intFromEnum(ColorId.max)]Color,
};

// ---------------------------------------------------------------------------
// Context — the main UI state
// ---------------------------------------------------------------------------

const DrawFrameFn = *const fn (ctx: *Context, rect: Rect, colorid: c_int) void;

pub const Context = struct {
    // Callbacks — set by the application.
    text_width: ?*const fn (font: Font, str: []const u8, len: c_int) c_int = null,
    text_height: ?*const fn (font: Font) c_int = null,
    draw_frame: ?DrawFrameFn = null,

    // Core state.
    _style: Style = undefined,
    style: *Style = undefined,
    hover: Id = 0,
    focus: Id = 0,
    last_id: Id = 0,
    last_rect: Rect = Rect.rect(0, 0, 0, 0),
    last_zindex: c_int = 0,
    updated_focus: c_int = 0,
    frame: c_int = 0,
    hover_root: ?*Container = null,
    next_hover_root: ?*Container = null,
    scroll_target: ?*Container = null,
    number_edit_buf: [MAX_FMT + 1]u8 = .{0} ** (MAX_FMT + 1),
    number_edit: Id = 0,

    // Stacks.
    command_list: Stack(u8, COMMANDLIST_SIZE) = .{},
    root_list: Stack(?*Container, ROOTLIST_SIZE) = .{},
    container_stack: Stack(?*Container, CONTAINERSTACK_SIZE) = .{},
    clip_stack: Stack(Rect, CLIPSTACK_SIZE) = .{},
    id_stack: Stack(Id, IDSTACK_SIZE) = .{},
    layout_stack: Stack(Layout, LAYOUTSTACK_SIZE) = .{},

    // Retained state pools.
    container_pool: [CONTAINERPOOL_SIZE]PoolItem = .{PoolItem{
        .id = 0,
        .last_update = 0,
    }} ** CONTAINERPOOL_SIZE,
    containers: [CONTAINERPOOL_SIZE]Container = .{Container{
        .head = null,
        .tail = null,
        .rect = Rect.rect(0, 0, 0, 0),
        .body = Rect.rect(0, 0, 0, 0),
        .content_size = Vec2.vec2(0, 0),
        .scroll = Vec2.vec2(0, 0),
        .zindex = 0,
        .open = 0,
    }} ** CONTAINERPOOL_SIZE,
    treenode_pool: [TREENODEPOOL_SIZE]PoolItem = .{PoolItem{
        .id = 0,
        .last_update = 0,
    }} ** TREENODEPOOL_SIZE,

    // Input state.
    mouse_pos: Vec2 = Vec2.vec2(0, 0),
    last_mouse_pos: Vec2 = Vec2.vec2(0, 0),
    mouse_delta: Vec2 = Vec2.vec2(0, 0),
    scroll_delta: Vec2 = Vec2.vec2(0, 0),
    mouse_down: c_int = 0,
    mouse_pressed: c_int = 0,
    key_down: c_int = 0,
    key_pressed: c_int = 0,
    input_text: [32]u8 = .{0} ** 32,
};

// ---------------------------------------------------------------------------
// Mouse / Key bitmasks
// ---------------------------------------------------------------------------

pub const MOUSE_LEFT = 1 << 0;
pub const MOUSE_RIGHT = 1 << 1;
pub const MOUSE_MIDDLE = 1 << 2;

pub const KEY_SHIFT = 1 << 0;
pub const KEY_CTRL = 1 << 1;
pub const KEY_ALT = 1 << 2;
pub const KEY_BACKSPACE = 1 << 3;
pub const KEY_RETURN = 1 << 4;

// ---------------------------------------------------------------------------
// Result bitmasks (for bitwise ops)
// ---------------------------------------------------------------------------

pub const RES_ACTIVE: c_int = 1 << 0;
pub const RES_SUBMIT: c_int = 1 << 1;
pub const RES_CHANGE: c_int = 1 << 2;

// ---------------------------------------------------------------------------
// Option bitmasks (for bitwise ops)
// ---------------------------------------------------------------------------

pub const OPT_ALIGNCENTER: c_int = 1 << 0;
pub const OPT_ALIGNRIGHT: c_int = 1 << 1;
pub const OPT_NOINTERACT: c_int = 1 << 2;
pub const OPT_NOFRAME: c_int = 1 << 3;
pub const OPT_NORESIZE: c_int = 1 << 4;
pub const OPT_NOSCROLL: c_int = 1 << 5;
pub const OPT_NOCLOSE: c_int = 1 << 6;
pub const OPT_NOTITLE: c_int = 1 << 7;
pub const OPT_HOLDFOCUS: c_int = 1 << 8;
pub const OPT_AUTOSIZE: c_int = 1 << 9;
pub const OPT_POPUP: c_int = 1 << 10;
pub const OPT_CLOSED: c_int = 1 << 11;
pub const OPT_EXPANDED: c_int = 1 << 12;

// ---------------------------------------------------------------------------
// Core -- rect helpers
// ---------------------------------------------------------------------------

/// Sentinel meaning "no clipping". Matches C's { 0, 0, 0x1000000, 0x1000000 }.
pub const unclipped_rect: Rect = .{ .x = 0, .y = 0, .w = 0x1000000, .h = 0x1000000 };

pub const default_style: Style = .{
    .font = null,
    .size = .{ .x = 68, .y = 10 },
    .padding = 5,
    .spacing = 4,
    .indent = 24,
    .title_height = 24,
    .scrollbar_size = 12,
    .thumb_size = 8,
    .colors = .{
        .{ .r = 230, .g = 230, .b = 230, .a = 255 }, // text
        .{ .r = 25, .g = 25, .b = 25, .a = 255 }, // border
        .{ .r = 50, .g = 50, .b = 50, .a = 255 }, // window_bg
        .{ .r = 25, .g = 25, .b = 25, .a = 255 }, // title_bg
        .{ .r = 240, .g = 240, .b = 240, .a = 255 }, // title_text
        .{ .r = 0, .g = 0, .b = 0, .a = 0 }, // panel_bg (transparent -> blend)
        .{ .r = 75, .g = 75, .b = 75, .a = 255 }, // button
        .{ .r = 95, .g = 95, .b = 95, .a = 255 }, // button_hover
        .{ .r = 115, .g = 115, .b = 115, .a = 255 }, // button_focus
        .{ .r = 30, .g = 30, .b = 30, .a = 255 }, // base
        .{ .r = 35, .g = 35, .b = 35, .a = 255 }, // base_hover
        .{ .r = 40, .g = 40, .b = 40, .a = 255 }, // base_focus
        .{ .r = 43, .g = 43, .b = 43, .a = 255 }, // scroll_base
        .{ .r = 30, .g = 30, .b = 30, .a = 255 }, // scroll_thumb
    },
};

fn expandRect(r: Rect, n: c_int) Rect {
    return Rect.rect(r.x - n, r.y - n, r.w + n * 2, r.h + n * 2);
}

fn intersectRects(r1: Rect, r2: Rect) Rect {
    const x1 = @max(r1.x, r2.x);
    const y1 = @max(r1.y, r2.y);
    var x2 = @min(r1.x + r1.w, r2.x + r2.w);
    var y2 = @min(r1.y + r1.h, r2.y + r2.h);
    if (x2 < x1) x2 = x1;
    if (y2 < y1) y2 = y1;
    return Rect.rect(x1, y1, x2 - x1, y2 - y1);
}

fn rectOverlapsVec2(r: Rect, p: Vec2) bool {
    return p.x >= r.x and p.x < r.x + r.w and p.y >= r.y and p.y < r.y + r.h;
}

/// Default draw_frame callback: fill with the style color, then a 1px border for
/// everything except the three colors that are drawn borderless.
fn drawFrame(ctx: *Context, rect: Rect, colorid: c_int) void {
    drawRect(ctx, rect, ctx.style.colors[@intCast(colorid)]);
    if (colorid == @intFromEnum(ColorId.scroll_base) or
        colorid == @intFromEnum(ColorId.scroll_thumb) or
        colorid == @intFromEnum(ColorId.title_bg))
    {
        return;
    }
    if (ctx.style.colors[@intFromEnum(ColorId.border)].a != 0) {
        drawBox(ctx, expandRect(rect, 1), ctx.style.colors[@intFromEnum(ColorId.border)]);
    }
}

// ---------------------------------------------------------------------------
// Core -- command arena
//
// Plan decision 2c: keep C's byte-arena layout. Records are variable sized and
// walked by `base.size`, and mu_end patches absolute intra-arena jump targets.
// Record sizes are rounded up to @alignOf(Command) so every @alignCast below is
// provably satisfied -- C got away with unaligned records on x86, Zig must not
// assume it. The rounding is invisible to callers: push and next agree on size.
// ---------------------------------------------------------------------------

pub const Error = error{
    CommandListFull,
};

const cmd_align: usize = @alignOf(Command);

fn roundUp(n: usize) usize {
    return (n + cmd_align - 1) & ~(cmd_align - 1);
}

/// Raw byte base of the command arena.
fn arena(self: *Context) [*]u8 {
    return &self.command_list.items;
}

fn arenaEnd(self: *Context) [*]u8 {
    return arena(self) + self.command_list.idx;
}

/// Append `total` bytes of record of type T at the arena cursor and return it.
/// `total` must already be rounded and must be >= @sizeOf(T).
fn pushRecord(self: *Context, comptime T: type, total: usize, comptime kind: CommandType) Error!*T {
    const start = self.command_list.idx;
    if (start + total >= COMMANDLIST_SIZE) return Error.CommandListFull;
    const p: *T = @ptrCast(@alignCast(arena(self) + start));
    p.* = std.mem.zeroes(T);
    const base: *BaseCommand = @ptrCast(p);
    base.* = .{ .type = kind, .size = @intCast(total) };
    self.command_list.idx = start + total;
    return p;
}

pub fn pushCommand(self: *Context, comptime T: type, comptime kind: CommandType) Error!*T {
    return pushRecord(self, T, roundUp(@sizeOf(T)), kind);
}

/// Walk the arena, following jump records, and return the next non-jump command.
/// Mirrors mu_next_command: pass a null `cmd` to start from the beginning.
pub fn nextCommand(self: *Context, cmd: *?*Command) bool {
    var p: [*]u8 = if (cmd.*) |c|
        @as([*]u8, @ptrCast(c)) + @as(usize, @intCast(c.base.size))
    else
        arena(self);

    while (p != arenaEnd(self)) {
        const c: *Command = @ptrCast(@alignCast(p));
        if (c.*.type != .jump) {
            cmd.* = c;
            return true;
        }
        p = @ptrCast(@alignCast(c.*.jump.dst.?));
    }
    cmd.* = null;
    return false;
}

fn pushJump(self: *Context, dst: ?*Command) Error!*JumpCommand {
    const cmd = try pushCommand(self, JumpCommand, .jump);
    cmd.dst = dst;
    return cmd;
}

pub fn setClip(ctx: *Context, rect: Rect) Error!void {
    const cmd = try pushCommand(ctx, ClipCommand, .clip);
    cmd.rect = rect;
}

pub fn drawRect(ctx: *Context, rect: Rect, color: Color) void {
    const r = intersectRects(rect, getClipRect(ctx));
    if (r.w != 0 and r.h != 0) {
        const cmd = pushCommand(ctx, RectCommand, .rect) catch return;
        cmd.rect = r;
        cmd.color = color;
    }
}

pub fn drawBox(ctx: *Context, rect: Rect, color: Color) void {
    drawRect(ctx, Rect.rect(rect.x + 1, rect.y, rect.w - 2, 1), color);
    drawRect(ctx, Rect.rect(rect.x + 1, rect.y + rect.h - 1, rect.w - 2, 1), color);
    drawRect(ctx, Rect.rect(rect.x, rect.y, 1, rect.h), color);
    drawRect(ctx, Rect.rect(rect.x + rect.w - 1, rect.y, 1, rect.h), color);
}

pub fn drawText(ctx: *Context, font: Font, str: []const u8, pos: Vec2, color: Color) void {
    const rect = Rect.rect(
        pos.x,
        pos.y,
        ctx.text_width.?(font, str, @intCast(str.len)),
        ctx.text_height.?(font),
    );
    const clipped = checkClip(ctx, rect);
    if (clipped == .all) return;
    if (clipped == .part) setClip(ctx, getClipRect(ctx)) catch return;

    // C allocates sizeof(TextCommand) + len: the struct's inline [1]u8 plus `len`
    // extra bytes, which hold the string and its NUL terminator.
    const total = roundUp(@sizeOf(TextCommand) + str.len);
    const cmd = pushRecord(ctx, TextCommand, total, .text) catch return;
    cmd.pos = pos;
    cmd.color = color;
    cmd.font = font;
    const dst: [*]u8 = @ptrCast(&cmd.str);
    @memcpy(dst[0..str.len], str);
    dst[str.len] = 0;

    if (clipped != .none) setClip(ctx, unclipped_rect) catch return;
}

pub fn drawIcon(ctx: *Context, id: c_int, rect: Rect, color: Color) void {
    const clipped = checkClip(ctx, rect);
    if (clipped == .all) return;
    if (clipped == .part) setClip(ctx, getClipRect(ctx)) catch return;
    const cmd = pushCommand(ctx, IconCommand, .icon) catch return;
    cmd.id = id;
    cmd.rect = rect;
    cmd.color = color;
    if (clipped != .none) setClip(ctx, unclipped_rect) catch return;
}

// ---------------------------------------------------------------------------
// Core -- lifecycle
// ---------------------------------------------------------------------------

pub fn init(ctx: *Context) void {
    ctx.* = .{};
    ctx.draw_frame = drawFrame;
    ctx._style = default_style;
    ctx.style = &ctx._style;
    // NOTE: C's mu_init memsets and leaves clip_stack EMPTY. A container push
    // (mu_push_clip_rect in begin_window/begin_panel) is what establishes the
    // initial clip; mu_end then asserts the stack is balanced back to 0. Do not
    // pre-push unclipped_rect here -- it breaks that balance.
}

pub fn begin(ctx: *Context) void {
    std.debug.assert(ctx.text_width != null);
    std.debug.assert(ctx.text_height != null);
    ctx.command_list.idx = 0;
    ctx.root_list.idx = 0;
    ctx.scroll_target = null;
    ctx.hover_root = ctx.next_hover_root;
    ctx.next_hover_root = null;
    ctx.mouse_delta = Vec2.vec2(
        ctx.mouse_pos.x - ctx.last_mouse_pos.x,
        ctx.mouse_pos.y - ctx.last_mouse_pos.y,
    );
    ctx.frame += 1;
}

fn zindexLess(_: void, a: ?*Container, b: ?*Container) bool {
    return a.?.*.zindex < b.?.*.zindex;
}

pub fn end(ctx: *Context) void {
    std.debug.assert(ctx.container_stack.idx == 0);
    std.debug.assert(ctx.clip_stack.idx == 0);
    std.debug.assert(ctx.id_stack.idx == 0);
    std.debug.assert(ctx.layout_stack.idx == 0);

    if (ctx.scroll_target) |st| {
        st.scroll.x += ctx.scroll_delta.x;
        st.scroll.y += ctx.scroll_delta.y;
    }

    // Unset focus if the focus id was not touched this frame.
    if (ctx.updated_focus == 0) ctx.focus = 0;
    ctx.updated_focus = 0;

    // Bring the hovered root to the front when the mouse was pressed on it.
    if (ctx.mouse_pressed != 0 and ctx.next_hover_root != null and
        ctx.next_hover_root.?.*.zindex < ctx.last_zindex and
        ctx.next_hover_root.?.*.zindex >= 0)
    {
        bringToFront(ctx, ctx.next_hover_root.?);
    }

    // Reset per-frame input state.
    ctx.key_pressed = 0;
    ctx.input_text[0] = 0;
    ctx.mouse_pressed = 0;
    ctx.scroll_delta = Vec2.vec2(0, 0);
    ctx.last_mouse_pos = ctx.mouse_pos;

    // Sort root containers by zindex. C qsorts the *pointer array*, leaving the
    // Container structs themselves in place -- the head/tail pointers embedded in
    // them stay valid only because of that. Sorting the containers would corrupt
    // the jump chain. (Risk R2.)
    const roots = ctx.root_list.items[0..@intCast(ctx.root_list.idx)];
    std.sort.insertion(?*Container, roots, {}, zindexLess);

    // Wire the jump chain: first command jumps into container 0, each container's
    // tail jumps to the next container's head, last tail jumps to the arena end.
    const n = roots.len;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const cnt = roots[i].?;
        if (i == 0) {
            const first: *Command = @ptrCast(@alignCast(arena(ctx)));
            first.*.jump.dst = @ptrCast(@alignCast(
                @as([*]u8, @ptrCast(cnt.head.?)) + @sizeOf(JumpCommand),
            ));
        } else {
            const prev = roots[i - 1].?;
            prev.tail.?.*.jump.dst = @ptrCast(@alignCast(
                @as([*]u8, @ptrCast(cnt.head.?)) + @sizeOf(JumpCommand),
            ));
        }
        if (i + 1 == n) {
            cnt.tail.?.*.jump.dst = @ptrCast(@alignCast(arenaEnd(ctx)));
        }
    }
}

pub fn setFocus(ctx: *Context, id: Id) void {
    ctx.focus = id;
    ctx.updated_focus = 1;
}

// ---------------------------------------------------------------------------
// Core -- ids
// ---------------------------------------------------------------------------

/// 32-bit FNV-1a, identical constants to C.
const HASH_INITIAL: Id = 2166136261;
const HASH_PRIME: Id = 16777619;

fn fnvHash(hash: *Id, data: []const u8) void {
    for (data) |b| {
        hash.* = (hash.* ^ @as(Id, b)) *% HASH_PRIME;
    }
}

pub fn getId(ctx: *Context, data: []const u8) Id {
    const idx = ctx.id_stack.idx;
    var res: Id = if (0 < idx) ctx.id_stack.items[idx - 1] else HASH_INITIAL;
    fnvHash(&res, data);
    ctx.last_id = res;
    return res;
}

pub fn pushId(ctx: *Context, data: []const u8) void {
    ctx.id_stack.push(getId(ctx, data));
}

pub fn popId(ctx: *Context) void {
    ctx.id_stack.pop();
}

// ---------------------------------------------------------------------------
// Core -- clip stack
// ---------------------------------------------------------------------------

pub fn pushClipRect(ctx: *Context, rect: Rect) void {
    ctx.clip_stack.push(intersectRects(rect, getClipRect(ctx)));
}

pub fn popClipRect(ctx: *Context) void {
    ctx.clip_stack.pop();
}

pub fn getClipRect(ctx: *Context) Rect {
    std.debug.assert(0 < ctx.clip_stack.idx);
    return ctx.clip_stack.items[ctx.clip_stack.idx - 1];
}

pub fn checkClip(ctx: *Context, r: Rect) Clip {
    const cr = getClipRect(ctx);
    if (cr.x + cr.w < r.x or r.x + r.w < cr.x or
        cr.y + cr.h < r.y or r.y + r.h < cr.y)
    {
        return .all;
    }
    if (r.x >= cr.x and r.x + r.w <= cr.x + cr.w and
        r.y >= cr.y and r.y + r.h <= cr.y + cr.h)
    {
        return .none;
    }
    return .part;
}

// ---------------------------------------------------------------------------
// Core -- containers
// ---------------------------------------------------------------------------

pub fn getCurrentContainer(ctx: *Context) *Container {
    std.debug.assert(0 < ctx.container_stack.idx);
    return ctx.container_stack.items[ctx.container_stack.idx - 1].?;
}

fn getLayout(ctx: *Context) *Layout {
    return &ctx.layout_stack.items[ctx.layout_stack.idx - 1];
}

fn pushLayout(ctx: *Context, body: Rect, scroll: Vec2) void {
    var layout: Layout = std.mem.zeroes(Layout);
    layout.body = Rect.rect(body.x - scroll.x, body.y - scroll.y, body.w, body.h);
    layout.max = Vec2.vec2(-0x1000000, -0x1000000);
    ctx.layout_stack.push(layout);
    layoutRow(ctx, 1, &[_]c_int{0}, 0);
}

fn popContainer(ctx: *Context) void {
    const cnt = getCurrentContainer(ctx);
    const layout = getLayout(ctx);
    cnt.content_size.x = layout.max.x - layout.body.x;
    cnt.content_size.y = layout.max.y - layout.body.y;
    ctx.container_stack.pop();
    ctx.layout_stack.pop();
    popId(ctx);
}

pub fn getContainerByName(ctx: *Context, name: []const u8) ?*Container {
    return getContainer(ctx, getId(ctx, name), 0);
}

fn getContainer(ctx: *Context, id: Id, opt: c_int) ?*Container {
    const idx = poolGet(ctx, &ctx.container_pool, id);
    if (0 <= idx) {
        if (ctx.containers[idx].open != 0 or (opt & OPT_CLOSED) == 0) {
            poolUpdate(ctx, &ctx.container_pool, idx);
        }
        return &ctx.containers[idx];
    }
    if (opt & OPT_CLOSED != 0) return null;
    const ni = poolInit(ctx, &ctx.container_pool, id);
    const cnt = &ctx.containers[ni];
    cnt.* = std.mem.zeroes(Container);
    cnt.open = 1;
    bringToFront(ctx, cnt);
    return cnt;
}

pub fn bringToFront(ctx: *Context, cnt: *Container) void {
    ctx.last_zindex += 1;
    cnt.zindex = ctx.last_zindex;
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

const RELATIVE = 1;
const ABSOLUTE = 2;

pub fn layoutBeginColumn(ctx: *Context) void {
    pushLayout(ctx, layoutNext(ctx), Vec2.vec2(0, 0));
}

pub fn layoutEndColumn(ctx: *Context) void {
    const b = getLayout(ctx);
    ctx.layout_stack.pop();
    // Inherit position / next_row / max from the child layout if they are greater.
    const a = getLayout(ctx);
    a.position.x = @max(a.position.x, b.position.x + b.body.x - a.body.x);
    a.next_row = @max(a.next_row, b.next_row + b.body.y - a.body.y);
    a.max.x = @max(a.max.x, b.max.x);
    a.max.y = @max(a.max.y, b.max.y);
}

pub fn layoutRow(ctx: *Context, items: c_int, widths: ?[]const c_int, height: c_int) void {
    const layout = getLayout(ctx);
    if (widths) |w| {
        std.debug.assert(items <= MAX_WIDTHS);
        @memcpy(layout.widths[0..@intCast(items)], w[0..@intCast(items)]);
    }
    layout.items = items;
    layout.position = Vec2.vec2(layout.indent, layout.next_row);
    layout.size.y = height;
    layout.item_index = 0;
}

pub fn layoutWidth(ctx: *Context, width: c_int) void {
    getLayout(ctx).size.x = width;
}

pub fn layoutHeight(ctx: *Context, height: c_int) void {
    getLayout(ctx).size.y = height;
}

pub fn layoutSetNext(ctx: *Context, r: Rect, relative: bool) void {
    const layout = getLayout(ctx);
    layout.next = r;
    layout.next_type = if (relative) RELATIVE else ABSOLUTE;
}

pub fn layoutNext(ctx: *Context) Rect {
    const layout = getLayout(ctx);
    const style = ctx.style;
    var res: Rect = undefined;

    if (layout.next_type != 0) {
        // Handle a rect explicitly set by layoutSetNext.
        const kind = layout.next_type;
        layout.next_type = 0;
        res = layout.next;
        if (kind == ABSOLUTE) {
            ctx.last_rect = res;
            return res;
        }
    } else {
        // Handle next row.
        if (layout.item_index == layout.items) {
            layoutRow(ctx, layout.items, null, layout.size.y);
        }
        res.x = layout.position.x;
        res.y = layout.position.y;
        res.w = if (0 < layout.items) layout.widths[@intCast(layout.item_index)] else layout.size.x;
        res.h = layout.size.y;
        if (res.w == 0) res.w = style.size.x + style.padding * 2;
        if (res.h == 0) res.h = style.size.y + style.padding * 2;
        // Negative widths/heights are relative to the remaining body extent.
        if (res.w < 0) res.w += layout.body.w - res.x + 1;
        if (res.h < 0) res.h += layout.body.h - res.y + 1;
        layout.item_index += 1;
    }

    layout.position.x += res.w + style.spacing;
    layout.next_row = @max(layout.next_row, res.y + res.h + style.spacing);

    res.x += layout.body.x;
    res.y += layout.body.y;

    layout.max.x = @max(layout.max.x, res.x + res.w);
    layout.max.y = @max(layout.max.y, res.y + res.h);

    ctx.last_rect = res;
    return res;
}

// ---------------------------------------------------------------------------
// Core -- pools (LRU by frame)
// ---------------------------------------------------------------------------

pub fn poolInit(ctx: *Context, items: []PoolItem, id: Id) usize {
    var f = ctx.frame;
    var n: isize = -1;
    for (items, 0..) |it, i| {
        if (it.last_update < f) {
            f = it.last_update;
            n = @intCast(i);
        }
    }
    std.debug.assert(0 <= n);
    const idx: usize = @intCast(n);
    items[idx].id = id;
    poolUpdate(ctx, items, idx);
    return idx;
}

pub fn poolGet(ctx: *Context, items: []const PoolItem, id: Id) isize {
    _ = ctx;
    for (items, 0..) |it, i| {
        if (it.id == id) return @intCast(i);
    }
    return -1;
}

pub fn poolUpdate(ctx: *Context, items: []PoolItem, idx: usize) void {
    items[idx].last_update = ctx.frame;
}

// ---------------------------------------------------------------------------
// Core -- input handlers
// ---------------------------------------------------------------------------

pub fn inputMousemove(ctx: *Context, x: c_int, y: c_int) void {
    ctx.mouse_pos = Vec2.vec2(x, y);
}

pub fn inputMousedown(ctx: *Context, x: c_int, y: c_int, btn: c_int) void {
    inputMousemove(ctx, x, y);
    ctx.mouse_down |= btn;
    ctx.mouse_pressed |= btn;
}

pub fn inputMouseup(ctx: *Context, x: c_int, y: c_int, btn: c_int) void {
    inputMousemove(ctx, x, y);
    ctx.mouse_down &= ~btn;
}

pub fn inputScroll(ctx: *Context, x: c_int, y: c_int) void {
    ctx.scroll_delta.x += x;
    ctx.scroll_delta.y += y;
}

pub fn inputKeydown(ctx: *Context, key: c_int) void {
    ctx.key_pressed |= key;
    ctx.key_down |= key;
}

pub fn inputKeyup(ctx: *Context, key: c_int) void {
    ctx.key_down &= ~key;
}

pub fn inputText(ctx: *Context, str: []const u8) void {
    const len = std.mem.indexOfScalar(u8, &ctx.input_text, 0) orelse ctx.input_text.len;
    const size = str.len + 1;
    std.debug.assert(len + size <= ctx.input_text.len);
    @memcpy(ctx.input_text[len..][0..size], str);
    ctx.input_text[len + str.len] = 0;
}

// ---------------------------------------------------------------------------
// Tests -- expectations generated from the C implementation (microui.c) so the
// port is checked against authoritative values, not against itself.
// ---------------------------------------------------------------------------

const testing = std.testing;

fn cTextWidth(font: Font, str: []const u8, len: c_int) c_int {
    _ = font;
    const n: usize = if (len < 0) str.len else @intCast(len);
    return @intCast(n * 7);
}

fn cTextHeight(font: Font) c_int {
    _ = font;
    return 18;
}

fn testContext() Context {
    var ctx: Context = undefined;
    init(&ctx);
    ctx.text_width = cTextWidth;
    ctx.text_height = cTextHeight;
    // Seed the clip stack the way begin_window_ex does (C line 1068).
    ctx.clip_stack.push(unclipped_rect);
    return ctx;
}

test "microui: id stability matches C FNV-1a" {
    var ctx = testContext();
    try testing.expectEqual(@as(Id, 2166136261), getId(&ctx, ""));
    try testing.expectEqual(@as(Id, 2949673445), getId(&ctx, "test"));
    pushId(&ctx, "outer");
    try testing.expectEqual(@as(Id, 2718680436), ctx.id_stack.items[0]);
    try testing.expectEqual(@as(Id, 1009144564), getId(&ctx, "inner"));
    popId(&ctx);
    // After popping the parent, "test" must hash back to the same value.
    try testing.expectEqual(@as(Id, 2949673445), getId(&ctx, "test"));
    try testing.expectEqual(@as(Id, 2949673445), ctx.last_id);
}

test "microui: command arena round-trip" {
    var ctx = testContext();
    begin(&ctx);
    ctx.command_list.idx = 0;

    drawRect(&ctx, Rect.rect(10, 10, 20, 20), Color.color(255, 0, 0, 255));
    drawText(&ctx, null, "hi", Vec2.vec2(30, 40), Color.color(0, 255, 0, 255));
    drawIcon(&ctx, 3, Rect.rect(50, 60, 16, 16), Color.color(0, 0, 255, 255));
    try setClip(&ctx, Rect.rect(1, 2, 3, 4));
    drawBox(&ctx, Rect.rect(70, 80, 30, 30), Color.color(1, 2, 3, 4));

    // C emitted 8 commands with sizes 28/34/32/24/28/28/28/28. The port rounds
    // every record up to @alignOf(Command) so @alignCast is provably satisfied
    // (C left text records 2-byte aligned and relied on x86 tolerating it).
    const expect_types = [_]CommandType{ .rect, .text, .icon, .clip, .rect, .rect, .rect, .rect };
    const expect_sizes = [_]usize{ 32, 40, 32, 24, 32, 32, 32, 32 };

    var c: ?*Command = null;
    var n: usize = 0;
    while (nextCommand(&ctx, &c)) : (n += 1) {
        try testing.expect(n < expect_types.len);
        const cmd = c.?;
        try testing.expectEqual(expect_types[n], cmd.*.type);
        try testing.expectEqual(@as(c_int, @intCast(expect_sizes[n])), cmd.*.base.size);
    }
    try testing.expectEqual(@as(usize, 8), n);
    try testing.expectEqual(@as(usize, 256), ctx.command_list.idx);
}

test "microui: text payload survives the arena round-trip" {
    var ctx = testContext();
    begin(&ctx);
    ctx.command_list.idx = 0;
    drawText(&ctx, null, "hello world", Vec2.vec2(5, 6), Color.color(9, 9, 9, 255));

    var c: ?*Command = null;
    try testing.expect(nextCommand(&ctx, &c));
    const cmd = c.?;
    try testing.expectEqual(CommandType.text, cmd.*.type);
    const s: [*]const u8 = @ptrCast(&cmd.*.text.str);
    try testing.expectEqualStrings("hello world", s[0..11]);
    try testing.expectEqual(@as(u8, 0), s[11]);
    try testing.expectEqual(@as(c_int, 5), cmd.*.text.pos.x);
}

test "microui: layout_next matches C" {
    var ctx = testContext();
    begin(&ctx);
    ctx.layout_stack.idx = 0;
    var l: Layout = std.mem.zeroes(Layout);
    l.body = Rect.rect(0, 0, 400, 300);
    l.max = Vec2.vec2(-0x1000000, -0x1000000);
    ctx.layout_stack.push(l);

    const widths = [_]c_int{ 86, -110, -1 };
    layoutRow(&ctx, 3, &widths, 0);

    const expect = [_]Rect{
        Rect.rect(0, 0, 86, 20),
        Rect.rect(90, 0, 201, 20),
        Rect.rect(295, 0, 105, 20),
        Rect.rect(0, 24, 86, 20),
        Rect.rect(90, 24, 201, 20),
        Rect.rect(295, 24, 105, 20),
    };
    for (expect) |e| {
        try testing.expectEqual(e, layoutNext(&ctx));
    }
}

test "microui: checkClip" {
    var ctx = testContext();
    ctx.clip_stack.pop();
    ctx.clip_stack.push(Rect.rect(10, 10, 100, 100));
    try testing.expectEqual(Clip.all, checkClip(&ctx, Rect.rect(200, 200, 10, 10)));
    try testing.expectEqual(Clip.none, checkClip(&ctx, Rect.rect(20, 20, 10, 10)));
    try testing.expectEqual(Clip.part, checkClip(&ctx, Rect.rect(90, 90, 50, 50)));
}

test "microui: pool is LRU by frame" {
    var ctx = testContext();
    // poolInit picks the item with the smallest last_update strictly less than the
    // current frame, so frame must be >= 1. C relies on mu_begin() incrementing
    // the frame before any control runs; at frame 0 both implementations fail to
    // find an eviction candidate.
    ctx.frame = 1;
    var items: [4]PoolItem = undefined;
    @memset(&items, .{ .id = 0, .last_update = 0 });
    const a = poolInit(&ctx, &items, 111);
    ctx.frame += 1;
    const b = poolInit(&ctx, &items, 222);
    try testing.expect(a != b);
    try testing.expectEqual(@as(isize, 0), poolGet(&ctx, &items, 111));
    try testing.expectEqual(@as(isize, 1), poolGet(&ctx, &items, 222));
    try testing.expectEqual(@as(isize, -1), poolGet(&ctx, &items, 333));
}

// ---------------------------------------------------------------------------
// Controls -- shared state machine
// ---------------------------------------------------------------------------

fn inHoverRoot(ctx: *Context) bool {
    var i = ctx.container_stack.idx;
    while (0 < i) {
        i -= 1;
        const c = ctx.container_stack.items[i].?;
        if (c == ctx.hover_root) return true;
        // Only root containers have their `head` field set; stop searching once we
        // reach the current root container.
        if (c.head != null) break;
    }
    return false;
}

pub fn drawControlFrame(ctx: *Context, id: Id, rect: Rect, colorid: c_int, opt: c_int) void {
    if (opt & OPT_NOFRAME != 0) return;
    // focus shifts the color id by 2, hover by 1 (BUTTON -> BUTTONHOVER ->
    // BUTTONFOCUS, BASE -> BASEHOVER -> BASEFOCUS).
    const delta: c_int = if (ctx.focus == id) 2 else if (ctx.hover == id) 1 else 0;
    ctx.draw_frame.?(ctx, rect, colorid + delta);
}

pub fn drawControlText(ctx: *Context, str: []const u8, rect: Rect, colorid: c_int, opt: c_int) void {
    const font = ctx.style.font;
    const tw = ctx.text_width.?(font, str, -1);
    pushClipRect(ctx, rect);
    var pos = Vec2.vec2(0, rect.y + @divTrunc(rect.h - ctx.text_height.?(font), 2));
    if (opt & OPT_ALIGNCENTER != 0) {
        pos.x = rect.x + @divTrunc(rect.w - tw, 2);
    } else if (opt & OPT_ALIGNRIGHT != 0) {
        pos.x = rect.x + rect.w - tw - ctx.style.padding;
    } else {
        pos.x = rect.x + ctx.style.padding;
    }
    drawText(ctx, font, str, pos, ctx.style.colors[@intCast(colorid)]);
    popClipRect(ctx);
}

pub fn mouseOver(ctx: *Context, rect: Rect) bool {
    return rectOverlapsVec2(rect, ctx.mouse_pos) and
        rectOverlapsVec2(getClipRect(ctx), ctx.mouse_pos) and
        inHoverRoot(ctx);
}

/// Hover / focus bookkeeping shared by every interactive control.
pub fn updateControl(ctx: *Context, id: Id, rect: Rect, opt: c_int) void {
    const over = mouseOver(ctx, rect);

    if (ctx.focus == id) ctx.updated_focus = 1;
    if (opt & OPT_NOINTERACT != 0) return;
    if (over and ctx.mouse_down == 0) ctx.hover = id;

    if (ctx.focus == id) {
        if (ctx.mouse_pressed != 0 and !over) setFocus(ctx, 0);
        if (ctx.mouse_down == 0 and (opt & OPT_HOLDFOCUS) == 0) setFocus(ctx, 0);
    }

    if (ctx.hover == id) {
        if (ctx.mouse_pressed != 0) {
            setFocus(ctx, id);
        } else if (!over) {
            ctx.hover = 0;
        }
    }
}

// ---------------------------------------------------------------------------
// Controls -- text, label, button, checkbox
// ---------------------------------------------------------------------------

/// Byte at `i`, or 0 past the end. Mirrors C's NUL-terminated `*p` reads so the
/// word-wrap loop below can be a faithful transliteration.
fn at(s: []const u8, i: usize) u8 {
    return if (i < s.len) s[i] else 0;
}

/// Word-wrapped text.
pub fn text(ctx: *Context, str: []const u8) void {
    const wdt: c_int = -1;
    const font = ctx.style.font;
    const color = ctx.style.colors[@intFromEnum(ColorId.text)];
    var p: usize = 0;
    var wrap_end: usize = 0;

    layoutBeginColumn(ctx);
    layoutRow(ctx, 1, &[_]c_int{wdt}, ctx.text_height.?(font));

    while (true) {
        const r = layoutNext(ctx);
        var w: c_int = 0;
        const start = p;
        wrap_end = p;

        while (true) {
            const word = p;
            while (at(str, p) != 0 and str[p] != ' ' and str[p] != '\n') p += 1;
            w += ctx.text_width.?(font, str[word..p], @intCast(p - word));
            if (r.w < w and wrap_end != start) break;
            // C measures the delimiter byte itself with len 1.
            const delim = if (p < str.len) str[p .. p + 1] else "\x00";
            w += ctx.text_width.?(font, delim, 1);
            wrap_end = p;
            p += 1;
            // C: `} while (*end && *end != '\n');` -- stop the line at the
            // terminator or an explicit newline.
            if (at(str, wrap_end) == 0 or at(str, wrap_end) == '\n') break;
        }

        drawText(ctx, font, str[start..wrap_end], Vec2.vec2(r.x, r.y), color);
        p = wrap_end + 1;
        if (at(str, wrap_end) == 0) break;
    }

    layoutEndColumn(ctx);
}

pub fn label(ctx: *Context, str: []const u8) void {
    drawControlText(ctx, str, layoutNext(ctx), @intFromEnum(ColorId.text), 0);
}

/// Returns a Result bitmask (RES_SUBMIT when clicked).
pub fn buttonEx(ctx: *Context, label_: ?[]const u8, icon: c_int, opt: c_int) c_int {
    var res: c_int = 0;
    const id = if (label_) |l| getId(ctx, l) else blk: {
        // C hashes the icon int's storage: mu_get_id(ctx, &icon, sizeof(icon)).
        var tmp = icon;
        break :blk getId(ctx, std.mem.asBytes(&tmp));
    };
    const r = layoutNext(ctx);
    updateControl(ctx, id, r, opt);

    if (ctx.mouse_pressed == MOUSE_LEFT and ctx.focus == id) res |= RES_SUBMIT;

    drawControlFrame(ctx, id, r, @intFromEnum(ColorId.button), opt);
    if (label_) |l| drawControlText(ctx, l, r, @intFromEnum(ColorId.text), opt);
    if (icon != 0) drawIcon(ctx, icon, r, ctx.style.colors[@intFromEnum(ColorId.text)]);
    return res;
}

pub fn button(ctx: *Context, label_: []const u8) c_int {
    return buttonEx(ctx, label_, 0, 0);
}

/// Returns a Result bitmask (RES_CHANGE when toggled).
pub fn checkbox(ctx: *Context, label_: []const u8, state: *bool) c_int {
    var res: c_int = 0;
    // C hashes the pointer value itself: mu_get_id(ctx, &state, sizeof(state)).
    var ptr_tmp = state;
    const id = getId(ctx, std.mem.asBytes(&ptr_tmp));
    const r = layoutNext(ctx);
    const box = Rect.rect(r.x, r.y, r.h, r.h);
    updateControl(ctx, id, r, 0);

    if (ctx.mouse_pressed == MOUSE_LEFT and ctx.focus == id) {
        res |= RES_CHANGE;
        state.* = !state.*;
    }

    drawControlFrame(ctx, id, box, @intFromEnum(ColorId.base), 0);
    if (state.*) {
        drawIcon(ctx, @intFromEnum(IconId.check), box, ctx.style.colors[@intFromEnum(ColorId.text)]);
    }
    const tr = Rect.rect(r.x + box.w, r.y, r.w - box.w, r.h);
    drawControlText(ctx, label_, tr, @intFromEnum(ColorId.text), 0);
    return res;
}

/// Collects the drawn text runs from the command arena, exactly as the renderer
/// would consume them. Returns the count; fills `out` in draw order.
fn collectTextRuns(ctx: *Context, out: *[64][]const u8) usize {
    var n: usize = 0;
    var c: ?*Command = null;
    while (nextCommand(ctx, &c)) {
        const cmd = c.?;
        if (cmd.*.type == .text) {
            const sp: [*]const u8 = @ptrCast(&cmd.*.text.str);
            const len = std.mem.indexOfScalar(u8, sp[0..4096], 0) orelse 4096;
            out[n] = sp[0..len];
            n += 1;
        }
    }
    return n;
}

fn wrapRuns(str: []const u8, out: *[64][]const u8) usize {
    var ctx = testContext();
    begin(&ctx);
    ctx.command_list.idx = 0;
    var l: Layout = std.mem.zeroes(Layout);
    l.body = Rect.rect(0, 0, 100, 1000);
    l.max = Vec2.vec2(-0x1000000, -0x1000000);
    ctx.layout_stack.idx = 0;
    ctx.layout_stack.push(l);
    text(&ctx, str);
    return collectTextRuns(&ctx, out);
}

test "microui: mu_text word wrap matches C" {
    const cases = [_]struct { in: []const u8, want: []const []const u8 }{
        .{
            .in = "The quick brown fox jumps over the lazy dog and keeps running far",
            .want = &.{ "The quick", "brown fox", "jumps over", "the lazy", "dog and", "keeps", "running far" },
        },
        .{ .in = "one two\nthree four five\nsix", .want = &.{ "one two", "three four", "five", "six" } },
        .{ .in = "exactlyoneword", .want = &.{"exactlyoneword"} },
        .{ .in = "a b c", .want = &.{"a b c"} },
    };
    for (cases) |c| {
        var buf: [64][]const u8 = undefined;
        const n = wrapRuns(c.in, &buf);
        const got = buf[0..n];
        testing.expectEqual(c.want.len, got.len) catch |e| {
            std.debug.print("\nfor '{s}': got {any}\n", .{ c.in, got });
            return e;
        };
        for (c.want, got) |w, g| {
            testing.expectEqualStrings(w, g) catch |e| {
                std.debug.print("\nfor '{s}': want '{s}' got '{s}'\n", .{ c.in, w, g });
                return e;
            };
        }
    }
}

/// A minimal root container + layout so `inHoverRoot()` and `layoutNext()` work
/// without the full window code (Phase 5).
const Fixture = struct {
    ctx: Context,
    jump: JumpCommand,
    cnt: Container,

    fn init(hover_x: c_int, hover_y: c_int) Fixture {
        var f = Fixture{
            .ctx = testContext(),
            .jump = .{
                .base = .{ .type = .jump, .size = @sizeOf(JumpCommand) },
                .dst = null,
            },
            .cnt = std.mem.zeroes(Container),
        };
        // A root container is identified by having `head` set (see inHoverRoot).
        f.cnt.head = @ptrCast(&f.jump);
        f.cnt.tail = @ptrCast(&f.jump);
        f.ctx.mouse_pos = Vec2.vec2(hover_x, hover_y);
        return f;
    }

    fn frame(self: *Fixture) void {
        begin(&self.ctx);
        self.ctx.hover_root = &self.cnt;
        self.ctx.container_stack.idx = 0;
        self.ctx.container_stack.push(&self.cnt);
        var l: Layout = std.mem.zeroes(Layout);
        l.body = Rect.rect(0, 0, 400, 300);
        l.max = Vec2.vec2(-0x1000000, -0x1000000);
        self.ctx.layout_stack.idx = 0;
        self.ctx.layout_stack.push(l);
        const widths = [_]c_int{100};
        layoutRow(&self.ctx, 1, &widths, 20);
    }
};

test "microui: button hover then click yields RES_SUBMIT" {
    var f = Fixture.init(50, 10);

    // Frame 1: pointer is over the button, no button held -> hover is set.
    f.frame();
    var res = buttonEx(&f.ctx, "Click", 0, 0);
    try testing.expectEqual(@as(c_int, 0), res);
    try testing.expectEqual(f.ctx.last_id, f.ctx.hover);
    const hovered = f.ctx.hover;

    // Frame 2: left button goes down while still hovering -> focus + submit.
    f.frame();
    inputMousedown(&f.ctx, 50, 10, MOUSE_LEFT);
    res = buttonEx(&f.ctx, "Click", 0, 0);
    try testing.expectEqual(RES_SUBMIT, res & RES_SUBMIT);
    try testing.expectEqual(hovered, f.ctx.focus);
}

test "microui: button outside the pointer never submits" {
    var f = Fixture.init(350, 250); // far from the 100x20 button at the origin
    f.frame();
    try testing.expectEqual(@as(c_int, 0), buttonEx(&f.ctx, "Click", 0, 0));
    f.frame();
    inputMousedown(&f.ctx, 350, 250, MOUSE_LEFT);
    try testing.expectEqual(@as(c_int, 0), buttonEx(&f.ctx, "Click", 0, 0) & RES_SUBMIT);
}

test "microui: checkbox toggles state on click" {
    var f = Fixture.init(50, 10);
    var state = false;

    f.frame();
    try testing.expectEqual(@as(c_int, 0), checkbox(&f.ctx, "Flag", &state));
    try testing.expectEqual(false, state);

    f.frame();
    inputMousedown(&f.ctx, 50, 10, MOUSE_LEFT);
    const res = checkbox(&f.ctx, "Flag", &state);
    try testing.expectEqual(RES_CHANGE, res & RES_CHANGE);
    try testing.expectEqual(true, state);

    // And back again.
    f.frame();
    inputMouseup(&f.ctx, 50, 10, MOUSE_LEFT);
    f.frame();
    inputMousedown(&f.ctx, 50, 10, MOUSE_LEFT);
    _ = checkbox(&f.ctx, "Flag", &state);
    try testing.expectEqual(false, state);
}

// ---------------------------------------------------------------------------
// Comptime assertions
// ---------------------------------------------------------------------------

comptime {
    std.debug.assert(@sizeOf(Vec2) == 8);
    std.debug.assert(@sizeOf(Rect) == 16);
    std.debug.assert(@sizeOf(Color) == 4);
    std.debug.assert(@sizeOf(BaseCommand) == 8);
    std.debug.assert(@sizeOf(PoolItem) == 8);
}
