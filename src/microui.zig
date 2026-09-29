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
pub const Font = *const anyopaque;

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
// Comptime assertions
// ---------------------------------------------------------------------------

comptime {
    std.debug.assert(@sizeOf(Vec2) == 8);
    std.debug.assert(@sizeOf(Rect) == 16);
    std.debug.assert(@sizeOf(Color) == 4);
    std.debug.assert(@sizeOf(BaseCommand) == 8);
    std.debug.assert(@sizeOf(PoolItem) == 8);
}
