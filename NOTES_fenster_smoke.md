# NOTES — Phase 0: fenster.zig smoke test

**Verdict: `src/fenster.zig` works on Linux/X11.** Window opens, paints, presents
120–400 frames, and all four input channels (`x`/`y`, `mouse`, `mod`, `keys[]`)
are written correctly. Clean exit, no X errors.

But it did **not** work when we started. The file had never been semantically
analyzed by the compiler — `zig build` passed because `main.zig` never referenced
`Fenster`, so every one of these errors was latent. The smoke test found **9 real
defects** before a single line of microui was written.

---

## Bugs found and fixed

### 1. `std.target` does not exist in Zig 0.16
```text
src/fenster.zig:22: error: root source file struct 'std' has no member named 'target'
```
Fixed in `fenster.zig` (12 sites) and `fenster_audio.zig` (17 sites).

**Trap:** the replacement is `@import("builtin").target.os.tag`, **not**
`std.builtin.target.os.tag`. `std.builtin` (`std/builtin.zig`) and the
compiler-injected `@import("builtin")` module are *different things* in 0.16 —
`std.builtin` has no `target` member. Verified against `std/zig/system.zig`, which
uses the `@import("builtin")` form.

### 2. `Fenster` has no methods — the API is module-level functions
`open`/`close`/`loop`/`pixel` are `pub fn ...(self: *Fenster)`, not members of the
`extern struct`. `f.open()` fails; it must be `fenster.open(&f)`.

Worth deciding before Phase 7 whether to keep this. The C original is
`fenster_open(&f)`, so module-level functions are the faithful port. Callers
throughout the app will read `fenster.open(&f)` / `fenster.loop(&f)`.

### 3. `Io.Duration` has no `.milliseconds` field
```text
error: no field named 'milliseconds' in struct 'Io.Duration'
```
`Io.Duration` is a single `nanoseconds: i96`. Use `Io.Duration.fromMilliseconds(ms)`.
Also, `std.Io.sleep` is `Cancelable!void` — `fenster_sleep` returns `void`, so the
error is swallowed with `catch {}`.

### 4. Ten Xlib calls returned values that were discarded
`XStoreName`, `XSync`, `XPutImage`, `XFlush`, `XNextEvent`, `XDestroyImage` were
declared `void` but actually return `int` (Status). Zig rejects an unused
non-void result. Return types corrected and `_ =` added.

### 5. **`DefaultScreen` / `RootWindow` / `DefaultVisual` / `BlackPixel` /
`WhitePixel` are C macros, not functions**
```text
error: undefined symbol: DefaultScreen
error: undefined symbol: RootWindow
error: undefined symbol: BlackPixel
error: undefined symbol: WhitePixel
error: undefined symbol: DefaultVisual
```
They expand to struct field loads:
```c
#define DefaultScreen(dpy) ((((_XPrivDisplay)(dpy))->default_screen)
#define RootWindow(dpy, scr) (ScreenOfDisplay(dpy,scr)->root)
```
Confirmed with `nm -D /usr/lib/libX11.so.6.4.0`: **zero** of those five are
exported symbols. Fixed by declaring the `Screen` extern struct and using the real
exported functions `XDefaultScreenOfDisplay()` / `XScreenOfDisplay()`.

**This is the pattern to remember for the rest of the port:** any C API written as
a macro has no symbol to link against. Check with `nm -D` before declaring.

### 6. **XImage `data` was at the wrong offset — live heap-corruption bug**
Original code:
```zig
const img_data: [*][*]u8 = @ptrCast(@alignCast(self.img));
img_data[1] = null;   // WRONG
```
Real `XImage` (`<X11/Xlib.h>`):
```c
int width, height;   // 0, 4
int xoffset;         // 8   <-- index 1 wrote HERE
int format;          // 12
char *data;          // 16  <-- index 2, the intended target
```
Index 1 is `xoffset`, not `data`. So `data` was left pointing at our caller-owned
pixel buffer and `XDestroyImage()` called `XFree()` on memory it did not own.
That is heap corruption on every shutdown — it may not crash immediately, which is
exactly the kind of bug that would have shown up much later as a mysterious abort.

Replaced with a declared `XImagePrefix` struct so the offset is explicit and
compiler-checked.

### 7. **libc was not linked — segfault inside `XOpenDisplay`**
```text
Program received signal SIGSEGV
#0 tcache_try_malloc (...) at ./malloc/malloc.c:3361
#1 __libc_calloc (...)
#2 XOpenDisplay ()
```
Looked like heap corruption in our code. It was not. The build linked `-lX11`
without `-lc`, so glibc's malloc was never initialized by Zig's startup, and the
first `calloc` from inside libX11 walked an uninitialized arena.

Minimal repro that pinned it down:
```text
zig run -lc -lX11 x.zig   -> works
zig run      -lX11 x.zig   -> segfault in XOpenDisplay
```
Fixed with `mod.linkSystemLibrary("c", .{})` in `build.zig` (which sets
`Module.link_libc`). **Every platform branch needs this**, not just Linux — macOS
and Windows system libs allocate through the C allocator too.

### 8. `while (XPending(dpy) > 0)` violated the repo style rule
Global AGENTS.md forbids `>` / `>=`. Rewritten to `while (0 < XPending(self.dpy))`.
There are many more of these in `microui.c` / `renderer.c` — expect to rewrite
constantly during Phases 2–6.

### 9. C's `DefaultVisual(dpy, 0)` vs root from the default screen
The C original takes the root window from `DefaultScreen(f->dpy)` but the visual
from hard-coded screen **0**. On a multi-screen setup those can disagree. The Zig
port uses the default screen for both. Identical on any normal single-screen
machine; strictly safer. Deliberate divergence, recorded here.

---

## Verified behavior (matters for later phases)

- **`loop()` always returns `true` on Linux.** Matches C (`fenster_loop` returns 0
  and the C app ignores it). Quit is driven by the application noticing ESC, not
  by the loop. Do not write `while (fenster.loop(&f))` expecting ESC to end it —
  `main.c` breaks on `r_key_down(0x1b)` explicitly.
- **`keys[]` is 0/1 only.** fenster sets `keys[code] = (type == KeyPress)`. The
  "was it down last frame" edge detection lives in `renderer.c` (`r_key_down`
  increments to 2), *not* in fenster. Phase 6 must reproduce that counter.
- **Key mapping quirk, preserved from C:** `FENSTER_KEYCODES_LIN` maps lowercase
  keysyms to *uppercase* ASCII — `XK_a` (0x61) → `keys[65]`. And `shift+a`
  produces keysym `0x41`, which is **not in the table**, so shifted letters
  generate no key event at all. Confirmed in the smoke run: `xdotool key a`
  → `key[65] = 1`. This is C behavior; keep it for parity.
- **`mod` bit layout** matches `renderer.c`'s expectations: bit0 ctrl, bit1 shift,
  bit2 alt, bit3 super. Verified: ctrl → `mod=1`, shift → `mod=2`.
- **`x`/`y` are window-local** (from `ev.xmotion.x/y`), not screen coords.
  Verified: moved to window+120,+90 → reported `x=120 y=90`.

---

## Environment limitation (not a code bug)

**This X server drops XTEST fake *button* events.** Motion fakes arrive fine, but
`xdotool mousedown` / `xdotool click` produce nothing:

```text
$ xinput test "Virtual core XTEST pointer"   # while running: xdotool mousemove, click, mousedown
motion a[0]=400 a[1]=400
motion a[0]=500 a[1]=500
                                              # <-- no button events at all
```

Tested buttons 1–5, with and without `--window`, `--clearmodifiers`, after
`windowactivate --sync`, with the pointer confirmed inside the window
(`xdotool getmouselocation` reported our window id). `xinput test-xi2 --root`
shows `RawButtonPress` but no transformed `ButtonPress` reaches any client.

Consequence: `tools/smoke_input.sh` cannot verify the button path. The smoke test
now **self-injects** `ButtonPress`/`ButtonRelease` via `XSendEvent` to its own
window instead, which does exercise `fenster.loop()`'s dispatch.

Two things this forced into the open that are worth remembering:

1. **Press+release in one `loop()` call is invisible to level-diffing.** `loop()`
   drains *all* pending events per call, so a fast click leaves `mouse` back at 0
   and a frame-to-frame diff sees no change. The injection is deliberately split
   across frames 5 and 12 for this reason. The same applies to keys (frames 20/27).
2. **A killed `xdotool key Escape` can latch the key down in XKB state.** We did
   this and the server then auto-repeated Escape into every new window, killing each
   smoke run at frame 1–2 and looking exactly like a fenster bug. Cleared with
   `xdotool keyup Escape`. If a fresh window dies instantly on Escape with nobody
   touching the keyboard, check for a latched key before suspecting the code.

---

## Files added

- `src/smoke_fenster.zig` — self-verifying smoke test. `SMOKE_FRAMES` env var
  controls run length. Prints every input-field transition and a final
  `observed:` line; a channel still `0` after injection means fenster never
  writes it.
- `tools/smoke_input.sh` — optional xdotool driver that adds real motion +
  modifier + key events on top of the self-injection.
- `build.zig` — `zig build smoke` step; smoke exe is also installed to
  `zig-out/bin/smoke_fenster`.

## Final run

```text
f   5  mouse btn  1
f  12  mouse btn  0
f  20  key[83] = 1  ('S')
f  27  key[83] = 0  ('S')
f  46  mouse pos  x=120 y=90
f  89  mouse pos  x=400 y=300
f 110  mod        1 (ctrl=1 shift=0 alt=0 super=0)
f 121  mod        2 (ctrl=0 shift=1 alt=0 super=0)
f 121  key[65] = 1  ('A')
f 132  key[10] = 1  ('?')

observed: mouse_move=1 mouse_btn=1 modifier=1 key=1
```

**Phase 0 gate passed. Safe to build on `fenster.zig`.**

Not yet exercised: the macOS and Windows code paths. They compile (Windows
cross-compiles) but the same "never analyzed" class of bug could still be hiding —
`zig build -Dtarget=...` only type-checks, it cannot run them. Tracked as task 9.3.

---

## Windows path — 5 more latent bugs (found by cross-compiling)

Once Linux worked, `zig build -Dtarget=x86_64-windows-gnu` started analyzing the
Windows branch for the first time and produced **14 errors across 5 distinct
causes**. All fixed.

### 10. `callconv(.C)` → `callconv(.c)`
```text
error: union 'builtin.CallingConvention' has no member named 'C'
```
4 sites. Renamed to lowercase in 0.16.

### 11. `@memset` on a single-item pointer
```text
error: type '*fenster.WNDCLASSEX' is not an indexable pointer
```
0.16 `@memset` requires an indexable pointer. Replaced with
`std.mem.zeroes(WNDCLASSEX)`.

### 12. `SetWindowLongPtr` used where C used `GetWindowLongPtr`
```zig
// was: 2 args to a 3-arg function
@ptrCast(@alignCast(@as(*Fenster, @ptrFromInt(SetWindowLongPtr(hwnd, GWLP_USERDATA)))))
```
The C original is `GetWindowLongPtr(hwnd, GWLP_USERDATA)`. `GetWindowLongPtrA`
was never even declared. Fixed — and the redundant double cast removed.

### 13. **LLP64 type model: `c_long` is 32 bits on 64-bit Windows**
```text
error: @bitCast size mismatch: destination type 'usize' has 64 bits
      but source type 'c_long' has 32 bits
```
`LPARAM`, `WPARAM`, `LRESULT`, `LONG_PTR` were all `c_long`/`c_ulong`. On Win64
those must be **pointer-width**, but `long` stays 32-bit. Every pointer round-trip
through them would have been silently truncated. Now `isize`/`usize`, which are
correct on both win32 and win64.

This was the most dangerous of the set: a 32-bit truncation of a 64-bit pointer
compiles fine and corrupts memory at runtime.

### 14. **A/W macro functions have no plain-name symbol**
```text
lld-link: undefined symbol: PeekMessage
lld-link: undefined symbol: DispatchMessage
lld-link: undefined symbol: GetModuleHandle
lld-link: undefined symbol: RegisterClassEx
lld-link: undefined symbol: CreateWindowEx
lld-link: undefined symbol: DefWindowProc
lld-link: undefined symbol: GetWindowLongPtr
lld-link: undefined symbol: SetWindowLongPtr
```
Same class of problem as the X11 macros in bug 5: Windows headers `#define
PeekMessage PeekMessageA`. Fixed by binding the `...A` exports and aliasing them
back to the plain names, so call sites still read like the C.

Also: `GetModuleHandle` lives in **kernel32**, not user32.

### macOS
Cannot be verified here — no macOS SDK on this machine:
```text
error: unable to find framework 'AudioToolbox'. searched paths: none
```
The macOS branch of `fenster.zig` has therefore **never been type-checked**. Task
9.3 stays open. Expect the same categories of bug (0.16 `callconv`, `@memset`,
framework-vs-symbol) when someone with a Mac runs it.

---

## Updated totals

**14 distinct defects** fixed in Phase 0: 9 Linux/generic + 5 Windows.
None were visible to `zig build` before the smoke test existed.

**Lesson carried into Phases 2–6:** compile-clean means nothing for code the
compiler never looked at. Every phase now needs a step that actually *analyzes*
the new code (a reference from a built target), not just `zig build` on a tree
where nothing imports it.
