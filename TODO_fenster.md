# TODO — Convert fenster.h to src/fenster.zig

## Goal
Convert `fenster.h` (C single-header windowing library) to `src/fenster.zig` using `std.c`/`std.os` platform bindings for macOS (Cocoa/objc), Windows (Win32), and Linux (X11), and wire it into `build.zig`.

## Tasks

### 1. Shared declarations
- [ ] Define `Fenster` struct with common fields (title, width, height, buf, keys, mod, x, y, mouse) and platform-conditional fields
- [ ] Define `FensterError` error set
- [ ] Declare methods: `open()`, `loop()`, `close()`, `pixel()` on `Fenster`
- [ ] Declare `fenster_sleep(io, ms)` and `fenster_time(io)` using `std.Io`
- [ ] Declare shared keycode lookup tables (macOS 128-entry, Windows 256-entry, Linux 124-entry)

### 2. macOS implementation (Cocoa + Objective-C runtime)
- [ ] Declare C types/functions: `objc_msgSend`, `objc_getClass`, `sel_getUid`, `objc_allocateClassPair`, `class_addMethod`, `objc_registerClassPair`, `objc_setAssociatedObject`, `objc_getAssociatedObject`
- [ ] Declare CoreGraphics types/functions: `CGColorSpaceCreateDeviceRGB`, `CGDataProviderCreateWithData`, `CGImageCreate`, `CGContextDrawImage`, `CGRectMake`, etc.
- [ ] Declare external symbols: `NSApp`, `NSDefaultRunLoopMode`
- [ ] Implement `fenster_draw_rect` callback (CGImage creation from pixel buffer)
- [ ] Implement `fenster_should_close` callback
- [ ] Implement `open()` — create NSApplication, NSWindow, dynamic delegate/view classes, associate Fenster pointer
- [ ] Implement `loop()` — event loop with mouse/keyboard handling, trigger redraw
- [ ] Implement `close()` — close window

### 3. Windows implementation (Win32)
- [ ] Declare C types: `WNDCLASSEX`, `MSG`, `PAINTSTRUCT`, `BITMAPINFOHEADER`, `RGBQUAD`, `BINFO`
- [ ] Declare C functions: `GetModuleHandle`, `RegisterClassEx`, `CreateWindowEx`, `SetWindowLongPtr`, `ShowWindow`, `UpdateWindow`, `PeekMessage`, `TranslateMessage`, `DispatchMessage`, `InvalidateRect`, `BeginPaint`, `CreateCompatibleDC`, `CreateCompatibleBitmap`, `SelectObject`, `SetDIBitsToDevice`, `BitBlt`, `DeleteObject`, `DeleteDC`, `EndPaint`, `GetKeyState`, `DefWindowProc`, `DestroyWindow`, `PostQuitMessage`, `Sleep`
- [ ] Implement `fenster_wndproc` callback (WM_PAINT with DIB rendering, WM_KEYDOWN/UP, WM_MOUSEMOVE, WM_LBUTTONDOWN/UP, WM_CLOSE, WM_DESTROY)
- [ ] Implement `open()` — register window class, create window, store Fenster pointer
- [ ] Implement `loop()` — PeekMessage loop, InvalidateRect for redraw
- [ ] Implement `close()` — no-op (window closed via WM_CLOSE)

### 4. Linux implementation (X11)
- [ ] Declare C functions: `XOpenDisplay`, `XCreateSimpleWindow`, `XCreateGC`, `XSelectInput`, `XStoreName`, `XMapWindow`, `XSync`, `XCreateImage`, `XPutImage`, `XFlush`, `XPending`, `XNextEvent`, `XkbKeycodeToKeysym`, `XFreeGC`, `XDestroyImage`, `XCloseDisplay`, `DefaultScreen`, `RootWindow`, `DefaultVisual`, `BlackPixel`, `WhitePixel`, `clock_gettime`, `nanosleep`
- [ ] Declare C constants: masks (KeyPressMask, etc.), ZPixmap, key symbols
- [ ] Implement `open()` — open display, create window, GC, XImage from pixel buffer, select events
- [ ] Implement `loop()` — XPutImage, XFlush, process XEvents (mouse, keyboard, keysym lookup)
- [ ] Implement `close()` — free GC, destroy image, close display

### 5. Cross-platform utilities
- [ ] Implement `fenster_sleep(io, ms)` using `std.Io.sleep`
- [ ] Implement `fenster_time(io)` using `std.Io.Clock.now`

### 6. Update build.zig and root.zig
- [ ] Link macOS: `Cocoa`, `CoreGraphics`, `objc` frameworks
- [ ] Link Windows: `user32`, `gdi32` system libraries
- [ ] Link Linux: `X11`, `X11-xkb` system libraries
- [ ] Re-export `fenster` from `src/root.zig`

### 7. Tests
- [ ] Add comptime tests for struct sizes and constants
- [ ] Add integration test: open/close (gracefully passes if no display)

## Notes
- Methods take `self: *Fenster` as first parameter (Zig idiom, no OOP).
- `fenster_sleep` and `fenster_time` use `std.Io` — need `io: std.Io` parameter.
- macOS uses heavy Objective-C runtime interop (dynamic class creation, objc_msgSend).
- The `buf: [*]u32` pixel buffer is allocated by the caller (see renderer.c).
- `loop` returns `bool` — `true` = continue, `false` = quit (Windows WM_QUIT).
- `pixel(f, x, y)` returns `*u32` for in-place mutation.
- Key code tables are large arrays — keep them as-is but in Zig syntax.
- Follow TigerStyle: PascalCase types, camelCase functions, explicit error handling.
