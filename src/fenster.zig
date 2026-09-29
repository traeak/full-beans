//! Platform-specific windowing via C interop.
//!
//! macOS: Cocoa + Objective-C runtime + CoreGraphics.
//! Windows: Win32 (CreateWindowEx, PeekMessage, DIB rendering).
//! Linux: X11 (XCreateSimpleWindow, XPutImage, XkbKeycodeToKeysym).

const std = @import("std");
const mem = std.mem;
const c = std.c;
const builtin = @import("builtin");

pub const FensterError = error{
    DeviceOpen,
};

// Platform-specific handle types.
const id = *anyopaque;
const HWND = ?*anyopaque;

/// Window context.
///
/// The `buf` pixel buffer is allocated and owned by the caller.
pub const Fenster: type = if (builtin.target.os.tag == .macos)
    extern struct {
        pub const Self = @This();
        title: [*:0]const u8,
        width: c_int,
        height: c_int,
        buf: [*]u32,
        keys: [256]c_int,
        mod: c_int,
        x: c_int,
        y: c_int,
        mouse: c_int,
        wnd: id,
    }
else if (builtin.target.os.tag == .windows)
    extern struct {
        pub const Self = @This();
        title: [*:0]const u8,
        width: c_int,
        height: c_int,
        buf: [*]u32,
        keys: [256]c_int,
        mod: c_int,
        x: c_int,
        y: c_int,
        mouse: c_int,
        hwnd: HWND,
    }
else if (builtin.target.os.tag == .linux)
    extern struct {
        pub const Self = @This();
        title: [*:0]const u8,
        width: c_int,
        height: c_int,
        buf: [*]u32,
        keys: [256]c_int,
        mod: c_int,
        x: c_int,
        y: c_int,
        mouse: c_int,
        dpy: ?*anyopaque,
        w: c_ulong,
        gc: ?*anyopaque,
        img: ?*anyopaque,
    }
else
    @compileError("fenster: unsupported OS " ++ @tagName(builtin.target.os.tag));

/// Return a pointer to the pixel at (x, y) for in-place mutation.
pub fn pixel(self: *Fenster, x: usize, y: usize) *u32 {
    return &self.buf[y * @as(usize, @intCast(self.width)) + x];
}

// ---------------------------------------------------------------------------
// Cross-platform utilities — std.Io (no C interop)
// ---------------------------------------------------------------------------

/// Sleep for the given number of milliseconds.
pub fn fenster_sleep(io: std.Io, ms: i64) void {
    std.Io.sleep(io, .fromMilliseconds(ms), .real) catch {};
}

/// Current time in milliseconds since the Unix epoch.
pub fn fenster_time(io: std.Io) i64 {
    const ts = std.Io.Clock.now(.real, io);
    return @divTrunc(ts.nanoseconds, 1_000_000);
}

// ---------------------------------------------------------------------------
// macOS — Objective-C runtime + CoreGraphics
// ---------------------------------------------------------------------------

const Class = *anyopaque;
const SEL = *anyopaque;
const IMP = *const anyopaque;
const BOOL = c_int;
const NSInteger = c_long;
const NSUInteger = c_ulong;
const CGFloat = f64;

const CGRect = extern struct {
    origin: CGPoint,
    size: CGSize,
};
const CGPoint = extern struct {
    x: CGFloat,
    y: CGFloat,
};
const CGSize = extern struct {
    width: CGFloat,
    height: CGFloat,
};

const CGContextRef = *anyopaque;
const CGColorSpaceRef = *anyopaque;
const CGDataProviderRef = *anyopaque;
const CGImageRef = *anyopaque;

const kCGImageAlphaNoneSkipFirst: c_uint = 1;
const kCGBitmapByteOrder32Little: c_uint = 1;
const kCGRenderingIntentDefault: c_int = 0;

const NSEventTypeMouseDown: NSUInteger = 1;
const NSEventTypeMouseUp: NSUInteger = 2;
const NSEventTypeMouseMoved: NSUInteger = 5;
const NSEventTypeLeftMouseDragged: NSUInteger = 6;
const NSEventTypeKeyDown: NSUInteger = 10;
const NSEventTypeKeyUp: NSUInteger = 11;

extern "objc" fn objc_msgSend(receiver: id, selector: SEL, args: anytype) callconv(.c) id;
extern "objc" fn objc_getClass(name: [*:0]const u8) Class;
extern "objc" fn sel_getUid(name: [*:0]const u8) SEL;
extern "objc" fn objc_allocateClassPair(class: Class, name: [*:0]const u8, reserved: c_ulong) Class;
extern "objc" fn class_addMethod(cls: Class, name: SEL, imp: IMP, types: [*:0]const u8) BOOL;
extern "objc" fn objc_registerClassPair(cls: Class) void;
extern "objc" fn objc_setAssociatedObject(object: id, key: [*:0]const u8, value: id, policy: c_ulong) void;
extern "objc" fn objc_getAssociatedObject(object: id, key: [*:0]const u8) id;

const OBJC_ASSOCIATION_ASSIGN: c_ulong = 1;

extern "CoreGraphics" fn CGColorSpaceCreateDeviceRGB() CGColorSpaceRef;
extern "CoreGraphics" fn CGDataProviderCreateWithData(consumer: ?*anyopaque, data: ?*const anyopaque, size: c_ulong, release_callback: ?*anyopaque) CGDataProviderRef;
extern "CoreGraphics" fn CGImageCreate(width: c_ulong, height: c_ulong, bitsPerComponent: c_int, bitsPerPixel: c_int, bytesPerRow: c_ulong, space: CGColorSpaceRef, bitmapInfo: c_uint, provider: CGDataProviderRef, decode: ?*anyopaque, shouldInterpolate: BOOL, intent: c_int) CGImageRef;
extern "CoreGraphics" fn CGColorSpaceRelease(space: CGColorSpaceRef) void;
extern "CoreGraphics" fn CGDataProviderRelease(provider: CGDataProviderRef) void;
extern "CoreGraphics" fn CGImageRelease(img: CGImageRef) void;
extern "CoreGraphics" fn CGRectMake(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) CGRect;

extern var NSApp: id;
extern var NSDefaultRunLoopMode: id;

fn msg_void(receiver: id, selector: SEL, args: anytype) void {
    _ = objc_msgSend(receiver, selector, args);
}
fn msg_id(receiver: id, selector: SEL, args: anytype) id {
    return objc_msgSend(receiver, selector, args);
}
fn msg_NSUInteger(receiver: id, selector: SEL) NSUInteger {
    return @ptrCast(objc_msgSend(receiver, selector));
}
fn msg_CGPoint(receiver: id, selector: SEL) CGPoint {
    return objc_msgSend(receiver, selector);
}
fn msg_CGContextRef(receiver: id, selector: SEL) CGContextRef {
    return @ptrCast(objc_msgSend(receiver, selector));
}

/// ObjC callback: drawRect: — render pixel buffer via CoreGraphics.
fn fenster_draw_rect(view: id, sel: SEL, rect: CGRect) callconv(.c) c_int {
    _ = sel;
    _ = rect;
    const f: *Fenster = @ptrCast(@alignCast(
        objc_getAssociatedObject(view, "fenster"),
    ));

    const context: CGContextRef = msg_CGContextRef(
        msg_id(objc_getClass("NSGraphicsContext"), "currentContext"),
        "graphicsPort",
    );
    const space = CGColorSpaceCreateDeviceRGB();
    const provider = CGDataProviderCreateWithData(
        null,
        f.buf,
        @as(c_ulong, @intCast(f.width * f.height * 4)),
        null,
    );
    const img = CGImageCreate(
        @intCast(f.width),
        @intCast(f.height),
        8,
        32,
        @intCast(f.width * 4),
        space,
        kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little,
        provider,
        null,
        0,
        kCGRenderingIntentDefault,
    );
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);

    const draw_rect = CGRectMake(0, 0, @floatFromInt(f.width), @floatFromInt(f.height));
    msg_void(context, sel_getUid("drawImage:"), draw_rect);

    CGImageRelease(img);
    return 0;
}

/// ObjC callback: windowShouldClose: — terminate the app.
fn fenster_should_close(delegate: id, sel: SEL, window: id) callconv(.c) BOOL {
    _ = delegate;
    _ = sel;
    _ = window;
    msg_void(NSApp, sel_getUid("terminate:"), NSApp);
    return 1;
}

// clang-format off
const FENSTER_KEYCODES_MACOS: [128]u8 = .{
    65, 83, 68, 70,  72, 71, 90, 88, 67, 86, 0,  66,
    81, 87, 69, 82,  89, 84, 49, 50, 51, 52, 54, 53,
    61, 57, 55, 45,  56, 48, 93, 79, 85, 91, 73, 80,
    10, 76, 74, 39,  75, 59, 92, 44, 47, 78, 77, 46,
    9,  32, 96, 8,   0,  27, 0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,   0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,   0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,   0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,   0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,   0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,   0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,   0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,   0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,   0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,   0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,   0,  0,  0,  0,  0,  0,  0,  0,
    26, 2,  3,  127, 0,  5,  0,  4,  0,  20, 19, 18,
    17, 0,
};
// clang-format on

// ---------------------------------------------------------------------------
// Windows — Win32
// ---------------------------------------------------------------------------

const HDC = ?*anyopaque;
const HBITMAP = ?*anyopaque;
const HINSTANCE = ?*anyopaque;
// Windows uses the LLP64 data model: `long` stays 32-bit even on x86_64, while
// pointer-sized types are 64-bit. Declaring these as c_long/c_ulong would truncate
// every pointer passed through them, so use isize/usize, which track pointer width
// correctly on both win32 and win64.
const LPARAM = isize;
const WPARAM = usize;
const LRESULT = isize;
const LONG_PTR = isize;

const CS_VREDRAW: c_uint = 1;
const CS_HREDRAW: c_uint = 2;
const GWLP_USERDATA: c_int = -21;
const SW_NORMAL: c_int = 1;
const PM_REMOVE: c_uint = 1;
const SRCCOPY: c_uint = 0xCC0020;

const WM_PAINT: c_uint = 0x000F;
const WM_CLOSE: c_uint = 0x0010;
const WM_DESTROY: c_uint = 0x0002;
const WM_LBUTTONDOWN: c_uint = 0x0201;
const WM_LBUTTONUP: c_uint = 0x0202;
const WM_MOUSEMOVE: c_uint = 0x0200;
const WM_KEYDOWN: c_uint = 0x0100;
const WM_KEYUP: c_uint = 0x0101;
const WM_QUIT: c_uint = 0x0012;

const VK_CONTROL: c_uint = 0x11;
const VK_SHIFT: c_uint = 0x10;
const VK_MENU: c_uint = 0x12;
const VK_LWIN: c_uint = 0x5B;
const VK_RWIN: c_uint = 0x5C;

const BI_BITFIELDS: c_uint = 3;

const WNDCLASSEX = extern struct {
    cbSize: c_uint,
    style: c_uint,
    lpfnWndProc: *const anyopaque,
    cbClsExtra: c_int,
    cbWndExtra: c_int,
    hInstance: HINSTANCE,
    hIcon: ?*anyopaque,
    hCursor: ?*anyopaque,
    hbrBackground: ?*anyopaque,
    lpszMenuName: ?[*:0]const u8,
    lpszClassName: [*:0]const u8,
    hIconSm: ?*anyopaque,
};

const MSG = extern struct {
    hwnd: HWND,
    message: c_uint,
    wParam: WPARAM,
    lParam: LPARAM,
    time: c_uint,
    pt: POINT,
};
const POINT = extern struct {
    x: c_long,
    y: c_long,
};

const PAINTSTRUCT = extern struct {
    hdc: HDC,
    erase: c_int,
    rcPaint: RECT,
    fRestore: c_int,
    fIncUpdate: c_int,
    rgbReserved: [32]u8,
};
const RECT = extern struct {
    left: c_long,
    top: c_long,
    right: c_long,
    bottom: c_long,
};

const BITMAPINFOHEADER = extern struct {
    biSize: c_uint,
    biWidth: c_long,
    biHeight: c_long,
    biPlanes: c_ushort,
    biBitCount: c_ushort,
    biCompression: c_uint,
    biSizeImage: c_uint,
    biXPelsPerMeter: c_long,
    biYPelsPerMeter: c_long,
    biClrUsed: c_uint,
    biClrImportant: c_uint,
};

const RGBQUAD = extern struct {
    rgbBlue: c_uint,
    rgbGreen: c_uint,
    rgbRed: c_uint,
    rgbReserved: c_uint,
};

const BINFO = extern struct {
    bmiHeader: BITMAPINFOHEADER,
    bmiColors: [3]RGBQUAD,
};

// Windows headers expose many entry points as A/W *macros* over the real ANSI and
// wide exports -- the plain names are not symbols. This port passes
// `[*:0]const u8` for class names and titles, so bind the ANSI variants and alias
// them back to the plain names the call sites use. GetModuleHandle lives in
// kernel32, not user32.
extern "kernel32" fn GetModuleHandleA(name: ?[*:0]const u8) HINSTANCE;
extern "user32" fn RegisterClassExA(wndclass: *const WNDCLASSEX) c_ushort;
extern "user32" fn CreateWindowExA(ex_style: c_ulong, class_name: [*:0]const u8, window_name: [*:0]const u8, style: c_ulong, x: c_int, y: c_int, width: c_int, height: c_int, parent: HWND, menu: ?*anyopaque, instance: HINSTANCE, param: ?*anyopaque) HWND;
extern "user32" fn SetWindowLongPtrA(hwnd: HWND, index: c_int, value: LONG_PTR) LONG_PTR;
extern "user32" fn GetWindowLongPtrA(hwnd: HWND, index: c_int) LONG_PTR;
extern "user32" fn PeekMessageA(msg: *MSG, hwnd: HWND, msg_filter_min: c_uint, msg_filter_max: c_uint, remove_msg: c_uint) c_int;
extern "user32" fn DispatchMessageA(msg: *const MSG) LRESULT;
extern "user32" fn DefWindowProcA(hwnd: HWND, msg: c_uint, wParam: WPARAM, lParam: LPARAM) LRESULT;

const GetModuleHandle = GetModuleHandleA;
const RegisterClassEx = RegisterClassExA;
const CreateWindowEx = CreateWindowExA;
const SetWindowLongPtr = SetWindowLongPtrA;
const GetWindowLongPtr = GetWindowLongPtrA;
const PeekMessage = PeekMessageA;
const DispatchMessage = DispatchMessageA;
const DefWindowProc = DefWindowProcA;

extern "user32" fn ShowWindow(hwnd: HWND, cmd_show: c_int) c_int;
extern "user32" fn UpdateWindow(hwnd: HWND) c_int;
extern "user32" fn TranslateMessage(msg: *const MSG) c_int;
extern "user32" fn InvalidateRect(hwnd: HWND, rect: ?*const anyopaque, erase: c_int) c_int;
extern "user32" fn GetKeyState(virt_key: c_int) c_short;
extern "user32" fn DestroyWindow(hwnd: HWND) c_int;
extern "user32" fn PostQuitMessage(exit_code: c_int) void;

extern "gdi32" fn BeginPaint(hwnd: HWND, ps: *PAINTSTRUCT) HDC;
extern "gdi32" fn EndPaint(hwnd: HWND, ps: *const PAINTSTRUCT) c_int;
extern "gdi32" fn CreateCompatibleDC(hdc: HDC) HDC;
extern "gdi32" fn CreateCompatibleBitmap(hdc: HDC, width: c_int, height: c_int) HBITMAP;
extern "gdi32" fn SelectObject(hdc: HDC, object: ?*anyopaque) ?*anyopaque;
extern "gdi32" fn SetDIBitsToDevice(hdc: HDC, x: c_int, y: c_int, width: c_uint, height: c_uint, src_x: c_int, src_y: c_int, start_scan: c_uint, num_scan_lines: c_uint, bits: ?*const anyopaque, bmi: ?*const anyopaque, color_usage: c_uint) c_int;
extern "gdi32" fn BitBlt(hdc: HDC, x: c_int, y: c_int, width: c_int, height: c_int, src_hdc: HDC, src_x: c_int, src_y: c_int, rop: c_uint) c_int;
extern "gdi32" fn DeleteObject(object: ?*anyopaque) c_int;
extern "gdi32" fn DeleteDC(hdc: HDC) c_int;

fn loWord(val: LPARAM) c_uint {
    const u: u64 = @bitCast(val);
    return @intCast(u & 0xffff);
}
fn hiWord(val: LPARAM) c_uint {
    const u: u64 = @bitCast(val);
    return @intCast((u >> 16) & 0xffff);
}

/// GetKeyState returns a signed SHORT; reinterpret as u16 so the 0x8000 key-down
/// bit can be masked without overflowing the type.
fn keyDown(vk: c_int) u16 {
    return @as(u16, @bitCast(GetKeyState(vk))) & 0x8000;
}

// clang-format off
const FENSTER_KEYCODES_WIN: [256]u8 = .{ 0, 27, 49, 50, 51, 52, 53, 54, 55, 56, 57, 48, 45, 61, 8, 9, 81, 87, 69, 82, 84, 89, 85, 73, 79, 80, 91, 93, 10, 0, 65, 83, 68, 70, 71, 72, 74, 75, 76, 59, 39, 96, 0, 92, 90, 88, 67, 86, 66, 78, 77, 44, 46, 47, 0, 0, 0, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
// clang-format on

fn fenster_wndproc(hwnd: HWND, msg: c_uint, wParam: WPARAM, lParam: LPARAM) callconv(.c) LRESULT {
    // Mirrors C: GetWindowLongPtr(hwnd, GWLP_USERDATA) recovers the Fenster
    // pointer stashed in open(). (The port previously called SetWindowLongPtr
    // with two arguments here.)
    const f: *Fenster = @ptrFromInt(@as(usize, @bitCast(GetWindowLongPtr(hwnd, GWLP_USERDATA))));
    switch (msg) {
        WM_PAINT => {
            var ps: PAINTSTRUCT = undefined;
            const hdc = BeginPaint(hwnd, &ps);
            const memdc = CreateCompatibleDC(hdc);
            const hbmp = CreateCompatibleBitmap(hdc, f.width, f.height);
            const oldbmp = SelectObject(memdc, hbmp);
            var bi = BINFO{
                .bmiHeader = BITMAPINFOHEADER{
                    .biSize = @sizeOf(BITMAPINFOHEADER),
                    .biWidth = f.width,
                    .biHeight = -f.height,
                    .biPlanes = 1,
                    .biBitCount = 32,
                    .biCompression = BI_BITFIELDS,
                    .biSizeImage = 0,
                    .biXPelsPerMeter = 0,
                    .biYPelsPerMeter = 0,
                    .biClrUsed = 0,
                    .biClrImportant = 0,
                },
                .bmiColors = .{
                    .{ .rgbBlue = 0, .rgbGreen = 0, .rgbRed = 0xff, .rgbReserved = 0 },
                    .{ .rgbBlue = 0, .rgbGreen = 0xff, .rgbRed = 0, .rgbReserved = 0 },
                    .{ .rgbBlue = 0xff, .rgbGreen = 0, .rgbRed = 0, .rgbReserved = 0 },
                },
            };
            _ = SetDIBitsToDevice(memdc, 0, 0, @intCast(f.width), @intCast(f.height), 0, 0, 0, @intCast(f.height), f.buf, &bi, 0);
            _ = BitBlt(hdc, 0, 0, f.width, f.height, memdc, 0, 0, SRCCOPY);
            _ = SelectObject(memdc, oldbmp);
            _ = DeleteObject(hbmp);
            _ = DeleteDC(memdc);
            _ = EndPaint(hwnd, &ps);
        },
        WM_CLOSE => {
            _ = DestroyWindow(hwnd);
        },
        WM_LBUTTONDOWN => f.mouse = 1,
        WM_LBUTTONUP => f.mouse = 0,
        WM_MOUSEMOVE => {
            f.y = @as(c_int, @intCast(hiWord(lParam)));
            f.x = @as(c_int, @intCast(loWord(lParam)));
        },
        WM_KEYDOWN, WM_KEYUP => {
            // Bit layout matches C (and renderer.c's expectations):
            //   bit0 ctrl, bit1 shift, bit2 alt, bit3 super
            f.mod = @intCast(
                @as(c_int, @intFromBool(keyDown(VK_CONTROL) != 0)) |
                    (@as(c_int, @intFromBool(keyDown(VK_SHIFT) != 0)) << 1) |
                    (@as(c_int, @intFromBool(keyDown(VK_MENU) != 0)) << 2) |
                    (@as(c_int, @intFromBool(keyDown(VK_LWIN) != 0 or keyDown(VK_RWIN) != 0)) << 3),
            );
            const scan_code = hiWord(lParam) & 0x1ff;
            const key = if (scan_code < 256) FENSTER_KEYCODES_WIN[scan_code] else 0;
            f.keys[key] = if (msg == WM_KEYDOWN) 1 else 0;
        },
        WM_DESTROY => PostQuitMessage(0),
        else => return DefWindowProc(hwnd, msg, wParam, lParam),
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Linux — X11
// ---------------------------------------------------------------------------

const KeySym = c_ulong;

const ButtonPress: c_int = 4;
const ButtonRelease: c_int = 5;
const MotionNotify: c_int = 6;
const KeyPress: c_int = 2;
const KeyRelease: c_int = 3;

const ControlMask: c_int = 4;
const ShiftMask: c_int = 1;
const Mod1Mask: c_int = 8;
const Mod4Mask: c_int = 64;

const KeyPressMask: c_ulong = 1 << 0;
const KeyReleaseMask: c_ulong = 1 << 1;
const ButtonPressMask: c_ulong = 1 << 4;
const ButtonReleaseMask: c_ulong = 1 << 5;
const PointerMotionMask: c_ulong = 1 << 6;
const ExposureMask: c_ulong = 1 << 15;

const ZPixmap: c_int = 2;

extern "X11" fn XOpenDisplay(name: ?[*:0]const u8) ?*anyopaque;
extern "X11" fn XCreateSimpleWindow(dpy: ?*anyopaque, parent: c_ulong, x: c_int, y: c_int, width: c_uint, height: c_uint, border_width: c_uint, border_pixel: c_ulong, background_pixel: c_ulong) c_ulong;
extern "X11" fn XCreateGC(dpy: ?*anyopaque, drawable: c_ulong, mask: c_ulong, values: ?*const anyopaque) ?*anyopaque;
extern "X11" fn XSelectInput(dpy: ?*anyopaque, w: c_ulong, event_mask: c_ulong) c_int;
extern "X11" fn XStoreName(dpy: ?*anyopaque, w: c_ulong, name: [*:0]const u8) c_int;
extern "X11" fn XMapWindow(dpy: ?*anyopaque, w: c_ulong) c_int;
extern "X11" fn XSync(dpy: ?*anyopaque, discard: c_int) c_int;
extern "X11" fn XCreateImage(dpy: ?*anyopaque, visual: ?*anyopaque, depth: c_uint, format: c_int, offset: c_int, data: [*]u8, width: c_uint, height: c_uint, bitmap_pad: c_int, bytes_per_line: c_int) ?*anyopaque;
extern "X11" fn XPutImage(dpy: ?*anyopaque, d: c_ulong, gc: ?*anyopaque, img: ?*anyopaque, src_x: c_int, src_y: c_int, dest_x: c_int, dest_y: c_int, width: c_uint, height: c_uint) c_int;
extern "X11" fn XFlush(dpy: ?*anyopaque) c_int;
extern "X11" fn XPending(dpy: ?*anyopaque) c_int;
extern "X11" fn XNextEvent(dpy: ?*anyopaque, event: *XEvent) c_int;
extern "X11" fn XFreeGC(dpy: ?*anyopaque, gc: ?*anyopaque) c_int;
extern "X11" fn XDestroyImage(img: ?*anyopaque) c_int;
extern "X11" fn XCloseDisplay(dpy: ?*anyopaque) c_int;
extern "X11" fn XScreenOfDisplay(dpy: ?*anyopaque, screen_number: c_int) *Screen;
extern "X11" fn XDefaultScreenOfDisplay(dpy: ?*anyopaque) *Screen;
extern "X11" fn XkbKeycodeToKeysym(dpy: ?*anyopaque, keycode: c_uint, index: c_int, group: c_int) KeySym;

/// Screen (<X11/Xlib.h>), declared only through `black_pixel`.
///
/// `DefaultScreen`, `RootWindow`, `DefaultVisual`, `BlackPixel` and `WhitePixel`
/// are C *macros* that expand to Display/Screen struct field loads -- they are not
/// exported symbols, so they cannot be `extern`-declared. Use XScreenOfDisplay()
/// / XDefaultScreenOfDisplay() (real functions) and read these fields instead.
const Screen = extern struct {
    ext_data: ?*anyopaque,
    display: ?*anyopaque,
    root: c_ulong,
    width: c_int,
    height: c_int,
    mwidth: c_int,
    mheight: c_int,
    ndepths: c_int,
    depths: ?*anyopaque,
    root_depth: c_int,
    root_visual: ?*anyopaque,
    default_gc: ?*anyopaque,
    cmap: c_ulong,
    white_pixel: c_ulong,
    black_pixel: c_ulong,
};

/// Leading fields of XImage (<X11/Xlib.h>), declared only as far as `data` so
/// close() can clear it before XDestroyImage() would try to XFree() our buffer.
const XImagePrefix = extern struct {
    width: c_int,
    height: c_int,
    xoffset: c_int,
    format: c_int,
    data: ?[*]u8,
};

const XEvent = extern union {
    type: c_int,
    xkey: XKeyEvent,
    xbutton: XButtonEvent,
    xmotion: XMotionEvent,
    _pad: [128]u8,
};

const XKeyEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: c_int,
    display: ?*anyopaque,
    window: c_ulong,
    root: c_ulong,
    subwindow: c_ulong,
    time: c_ulong,
    x: c_int,
    y: c_int,
    x_root: c_int,
    y_root: c_int,
    state: c_uint,
    keycode: c_uint,
    same_screen: c_int,
    _pad: [48]u8,
};

const XButtonEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: c_int,
    display: ?*anyopaque,
    window: c_ulong,
    root: c_ulong,
    subwindow: c_ulong,
    time: c_ulong,
    x: c_int,
    y: c_int,
    x_root: c_int,
    y_root: c_int,
    state: c_uint,
    button: c_uint,
    same_screen: c_int,
    _pad: [48]u8,
};

const XMotionEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: c_int,
    display: ?*anyopaque,
    window: c_ulong,
    root: c_ulong,
    subwindow: c_ulong,
    time: c_ulong,
    x: c_int,
    y: c_int,
    x_root: c_int,
    y_root: c_int,
    state: c_uint,
    is_hint: c_int,
    same_screen: c_int,
    _pad: [48]u8,
};

// X11 keysym constants (from <X11/keysym.h>).
const XK_BackSpace: c_ulong = 0xff08;
const XK_Delete: c_ulong = 0xffff;
const XK_Down: c_ulong = 0xff54;
const XK_End: c_ulong = 0xff57;
const XK_Escape: c_ulong = 0xff1b;
const XK_Home: c_ulong = 0xff50;
const XK_Insert: c_ulong = 0xff63;
const XK_Left: c_ulong = 0xff51;
const XK_Page_Down: c_ulong = 0xff56;
const XK_Page_Up: c_ulong = 0xff55;
const XK_Return: c_ulong = 0xff0d;
const XK_Right: c_ulong = 0xff53;
const XK_Tab: c_ulong = 0xff09;
const XK_Up: c_ulong = 0xff52;
const XK_apostrophe: c_ulong = 0x27;
const XK_backslash: c_ulong = 0x5c;
const XK_bracketleft: c_ulong = 0x5b;
const XK_bracketright: c_ulong = 0x5d;
const XK_comma: c_ulong = 0x2c;
const XK_equal: c_ulong = 0x3d;
const XK_grave: c_ulong = 0x60;
const XK_minus: c_ulong = 0x2d;
const XK_period: c_ulong = 0x2e;
const XK_semicolon: c_ulong = 0x3b;
const XK_slash: c_ulong = 0x2f;
const XK_space: c_ulong = 0x20;
const XK_a: c_ulong = 0x61;
const XK_b: c_ulong = 0x62;
const XK_c: c_ulong = 0x63;
const XK_d: c_ulong = 0x64;
const XK_e: c_ulong = 0x65;
const XK_f: c_ulong = 0x66;
const XK_g: c_ulong = 0x67;
const XK_h: c_ulong = 0x68;
const XK_i: c_ulong = 0x69;
const XK_j: c_ulong = 0x6a;
const XK_k: c_ulong = 0x6b;
const XK_l: c_ulong = 0x6c;
const XK_m: c_ulong = 0x6d;
const XK_n: c_ulong = 0x6e;
const XK_o: c_ulong = 0x6f;
const XK_p: c_ulong = 0x70;
const XK_q: c_ulong = 0x71;
const XK_r: c_ulong = 0x72;
const XK_s: c_ulong = 0x73;
const XK_t: c_ulong = 0x74;
const XK_u: c_ulong = 0x75;
const XK_v: c_ulong = 0x76;
const XK_w: c_ulong = 0x77;
const XK_x: c_ulong = 0x78;
const XK_y: c_ulong = 0x79;
const XK_z: c_ulong = 0x7a;
const XK_0: c_ulong = 0x30;
const XK_1: c_ulong = 0x31;
const XK_2: c_ulong = 0x32;
const XK_3: c_ulong = 0x33;
const XK_4: c_ulong = 0x34;
const XK_5: c_ulong = 0x35;
const XK_6: c_ulong = 0x36;
const XK_7: c_ulong = 0x37;
const XK_8: c_ulong = 0x38;
const XK_9: c_ulong = 0x39;

// clang-format off
const FENSTER_KEYCODES_LIN: [124]c_ulong = .{ XK_BackSpace, 8, XK_Delete, 127, XK_Down, 18, XK_End, 5, XK_Escape, 27, XK_Home, 2, XK_Insert, 26, XK_Left, 20, XK_Page_Down, 4, XK_Page_Up, 3, XK_Return, 10, XK_Right, 19, XK_Tab, 9, XK_Up, 17, XK_apostrophe, 39, XK_backslash, 92, XK_bracketleft, 91, XK_bracketright, 93, XK_comma, 44, XK_equal, 61, XK_grave, 96, XK_minus, 45, XK_period, 46, XK_semicolon, 59, XK_slash, 47, XK_space, 32, XK_a, 65, XK_b, 66, XK_c, 67, XK_d, 68, XK_e, 69, XK_f, 70, XK_g, 71, XK_h, 72, XK_i, 73, XK_j, 74, XK_k, 75, XK_l, 76, XK_m, 77, XK_n, 78, XK_o, 79, XK_p, 80, XK_q, 81, XK_r, 82, XK_s, 83, XK_t, 84, XK_u, 85, XK_v, 86, XK_w, 87, XK_x, 88, XK_y, 89, XK_z, 90, XK_0, 48, XK_1, 49, XK_2, 50, XK_3, 51, XK_4, 52, XK_5, 53, XK_6, 54, XK_7, 55, XK_8, 56, XK_9, 57 };
// clang-format on

// ---------------------------------------------------------------------------
// Public API — platform-specific implementations
// ---------------------------------------------------------------------------

/// Open the window and initialize platform resources.
pub fn open(self: *Fenster) FensterError!void {
    if (builtin.target.os.tag == .macos) {
        _ = msg_id(objc_getClass("NSApplication"), "sharedApplication");
        msg_void(NSApp, sel_getUid("setActivationPolicy:"), @as(NSInteger, 0));

        const rect = CGRectMake(0, 0, @floatFromInt(self.width), @floatFromInt(self.height));
        self.wnd = msg_id(
            msg_id(objc_getClass("NSWindow"), "alloc"),
            "initWithContentRect:styleMask:backing:defer:",
            rect,
            @as(NSUInteger, 3),
            @as(NSUInteger, 2),
            @as(BOOL, 0),
        );

        const windelegate = objc_allocateClassPair(
            objc_getClass("NSObject"),
            "FensterDelegate",
            0,
        );
        class_addMethod(windelegate, sel_getUid("windowShouldClose:"), fenster_should_close, "c@:@");
        objc_registerClassPair(windelegate);
        msg_void(self.wnd, sel_getUid("setDelegate:"), msg_id(msg_id(windelegate, "alloc"), "init"));

        const view_class = objc_allocateClassPair(
            objc_getClass("NSView"),
            "FensterView",
            0,
        );
        class_addMethod(view_class, sel_getUid("drawRect:"), fenster_draw_rect, "i@:@");
        objc_registerClassPair(view_class);

        const view = msg_id(msg_id(view_class, "alloc"), "init");
        msg_void(self.wnd, sel_getUid("setContentView:"), view);
        objc_setAssociatedObject(view, "fenster", self, OBJC_ASSOCIATION_ASSIGN);

        const title_str = msg_id(
            objc_getClass("NSString"),
            "stringWithUTF8String:",
            self.title,
        );
        msg_void(self.wnd, sel_getUid("setTitle:"), title_str);
        msg_void(self.wnd, sel_getUid("makeKeyAndOrderFront:"), null);
        msg_void(self.wnd, sel_getUid("center"));
        msg_void(NSApp, sel_getUid("activateIgnoringOtherApps:"), @as(BOOL, 1));
    } else if (builtin.target.os.tag == .windows) {
        const hInstance = GetModuleHandle(null);
        // Zig 0.16 @memset needs an indexable pointer; zero-init the whole struct.
        var wc: WNDCLASSEX = std.mem.zeroes(WNDCLASSEX);
        wc.cbSize = @sizeOf(WNDCLASSEX);
        wc.style = CS_VREDRAW | CS_HREDRAW;
        wc.lpfnWndProc = &fenster_wndproc;
        wc.hInstance = hInstance;
        wc.lpszClassName = self.title;
        _ = RegisterClassEx(&wc);

        self.hwnd = CreateWindowEx(
            0,
            self.title,
            self.title,
            0x00CF0000,
            0,
            0,
            self.width,
            self.height,
            null,
            null,
            hInstance,
            null,
        );
        if (self.hwnd == null) return FensterError.DeviceOpen;
        _ = SetWindowLongPtr(self.hwnd, GWLP_USERDATA, @intCast(@intFromPtr(self)));
        _ = ShowWindow(self.hwnd, SW_NORMAL);
        _ = UpdateWindow(self.hwnd);
    } else if (builtin.target.os.tag == .linux) {
        self.dpy = XOpenDisplay(null) orelse return FensterError.DeviceOpen;
        // The C original took the root window from the default screen but the
        // visual from screen 0. Use the default screen for both; identical on any
        // normal single-screen setup, and avoids a cross-screen visual mismatch.
        const screen = XDefaultScreenOfDisplay(self.dpy);
        self.w = XCreateSimpleWindow(
            self.dpy,
            screen.root,
            0,
            0,
            @intCast(self.width),
            @intCast(self.height),
            0,
            screen.black_pixel,
            screen.white_pixel,
        );
        self.gc = XCreateGC(self.dpy, self.w, 0, null);
        _ = XSelectInput(
            self.dpy,
            self.w,
            ExposureMask | KeyPressMask | KeyReleaseMask |
                ButtonPressMask | ButtonReleaseMask | PointerMotionMask,
        );
        _ = XStoreName(self.dpy, self.w, self.title);
        _ = XMapWindow(self.dpy, self.w);
        _ = XSync(self.dpy, 0);
        self.img = XCreateImage(
            self.dpy,
            screen.root_visual,
            24,
            ZPixmap,
            0,
            @ptrCast(self.buf),
            @intCast(self.width),
            @intCast(self.height),
            32,
            0,
        );
    }
}

/// Close the window and release platform resources.
pub fn close(self: *Fenster) void {
    if (builtin.target.os.tag == .macos) {
        msg_void(self.wnd, sel_getUid("close"));
    } else if (builtin.target.os.tag == .windows) {} else if (builtin.target.os.tag == .linux) {
        _ = XFreeGC(self.dpy, self.gc);
        // XDestroyImage() calls XFree() on image->data. Our buffer is owned by
        // the caller, so clear the pointer first. `data` sits at byte offset 16 of
        // XImage (4 x int: width, height, xoffset, format) -- see
        // <X11/Xlib.h>. Declared as a prefix struct rather than raw index math so
        // the offset is explicit.
        const img: *XImagePrefix = @ptrCast(@alignCast(self.img));
        img.data = null;
        _ = XDestroyImage(self.img);
        _ = XCloseDisplay(self.dpy);
    }
}

/// Process one frame of input events and trigger redraw.
///
/// Returns `true` to continue, `false` if the window was closed (Windows only).
pub fn loop(self: *Fenster) bool {
    if (builtin.target.os.tag == .macos) {
        msg_void(
            msg_id(self.wnd, sel_getUid("contentView")),
            "setNeedsDisplay:",
            @as(BOOL, 1),
        );

        const ev = msg_id(
            NSApp,
            "nextEventMatchingMask:untilDate:inMode:dequeue:",
            std.math.maxInt(NSUInteger),
            null,
            NSDefaultRunLoopMode,
            @as(BOOL, 1),
        );
        if (ev == null) return true;

        const evtype = msg_NSUInteger(ev, "type");
        switch (evtype) {
            NSEventTypeMouseDown => self.mouse = 1,
            NSEventTypeMouseUp => self.mouse = 0,
            NSEventTypeMouseMoved,
            NSEventTypeLeftMouseDragged,
            => {
                const xy = msg_CGPoint(ev, "locationInWindow");
                self.x = @intFromFloat(xy.x);
                self.y = self.height - @as(c_int, @intFromFloat(xy.y));
                return true;
            },
            NSEventTypeKeyDown, NSEventTypeKeyUp => {
                const k = msg_NSUInteger(ev, "keyCode");
                const key_idx = if (k < 127) FENSTER_KEYCODES_MACOS[k] else 0;
                self.keys[key_idx] = if (evtype == NSEventTypeKeyDown) 1 else 0;
                const mod_flags = msg_NSUInteger(ev, "modifierFlags") >> 17;
                self.mod = @as(c_int, @intCast(
                    (mod_flags & 0xC) |
                        ((mod_flags & 1) << 1) |
                        ((mod_flags >> 1) & 1),
                ));
                return true;
            },
            else => {},
        }

        msg_void(NSApp, sel_getUid("sendEvent:"), ev);
        return true;
    } else if (builtin.target.os.tag == .windows) {
        var msg: MSG = undefined;
        while (PeekMessage(&msg, null, 0, 0, PM_REMOVE) != 0) {
            if (msg.message == WM_QUIT) return false;
            _ = TranslateMessage(&msg);
            _ = DispatchMessage(&msg);
        }
        _ = InvalidateRect(self.hwnd, null, 1);
        return true;
    } else if (builtin.target.os.tag == .linux) {
        _ = XPutImage(self.dpy, self.w, self.gc, self.img, 0, 0, 0, 0, @intCast(self.width), @intCast(self.height));
        _ = XFlush(self.dpy);

        while (0 < XPending(self.dpy)) {
            var ev: XEvent = undefined;
            _ = XNextEvent(self.dpy, &ev);
            switch (ev.type) {
                ButtonPress => self.mouse = 1,
                ButtonRelease => self.mouse = 0,
                MotionNotify => {
                    self.x = ev.xmotion.x;
                    self.y = ev.xmotion.y;
                },
                KeyPress, KeyRelease => {
                    const m = ev.xkey.state;
                    const k = XkbKeycodeToKeysym(self.dpy, ev.xkey.keycode, 0, 0);
                    var i: usize = 0;
                    while (i < 124) : (i += 2) {
                        if (FENSTER_KEYCODES_LIN[i] == k) {
                            self.keys[FENSTER_KEYCODES_LIN[i + 1]] = if (ev.type == KeyPress) 1 else 0;
                            break;
                        }
                    }
                    self.mod = @as(c_int, @intCast(
                        @as(c_int, @intFromBool(m & ControlMask != 0)) |
                            @as(c_int, @intFromBool(m & ShiftMask != 0)) << 1 |
                            @as(c_int, @intFromBool(m & Mod1Mask != 0)) << 2 |
                            @as(c_int, @intFromBool(m & Mod4Mask != 0)) << 3,
                    ));
                },
                else => {},
            }
        }
        return true;
    }
    unreachable;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Verify that struct sizes are sane.
test "fenster: struct sizes" {
    try std.testing.expect(@sizeOf(Fenster) > 0);
    try std.testing.expectEqual(256 * @sizeOf(c_int), @sizeOf(@TypeOf(@as(Fenster, undefined).keys)));
}

// Verify the per-OS struct can be constructed and sized portably. Actually
// opening a window here would flash one on the user's desktop on every
// `zig build test`; real window behaviour is covered by `zig build smoke`.
test "fenster: construct and tear down without a display" {
    var buf: [800 * 600]u32 = undefined;
    var f: Fenster = std.mem.zeroes(Fenster);
    f.title = "test";
    f.width = 800;
    f.height = 600;
    f.buf = @ptrCast(&buf);

    try std.testing.expectEqual(@as(c_int, 800), f.width);
    try std.testing.expectEqual(@as(c_int, 600), f.height);
    try std.testing.expectEqual(@as(usize, 256 * @sizeOf(c_int)), @sizeOf(@TypeOf(f.keys)));
    // pixel() must land on the right offset for a couple of known coordinates.
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(pixel(&f, 0, 0)) - @intFromPtr(f.buf));
    try std.testing.expectEqual(
        @as(usize, @intCast(3 * 800 + 2)) * @sizeOf(u32),
        @intFromPtr(pixel(&f, 2, 3)) - @intFromPtr(f.buf),
    );
}
