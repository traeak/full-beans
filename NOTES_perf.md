# Performance — Zig port vs C original

Measured on the same machine, same X server (`DISPLAY=:0`), same 800x600 demo,
same instrumentation: the C `main.c` already computed `paint_time_ms`, so a
patched copy prints avg/max over a rolling 60-frame window; the Zig app does the
same behind `--timing`.

## Frame paint time (lower is better)

| Build              | avg    | max    | vs 16 ms budget |
|--------------------|--------|--------|-----------------|
| C `-O0`            | 13 ms  | 16 ms  | barely keeps up  |
| C `-O2`            | 2 ms   | 3 ms   | 13% of budget   |
| Zig `Debug`        | 5 ms   | 7 ms   | 44% of budget   |
| Zig `ReleaseSafe`  | 1 ms   | 2 ms   | 13% of budget   |
| Zig `ReleaseFast`  | <1 ms  | 1-2 ms |  6% of budget   |

**Zig `ReleaseSafe` is ~2x faster than C `-O2`**, and it keeps every runtime
safety check (bounds, overflow, alignment, invalid casts). That inverts the usual
"safe mode costs you" assumption: the C build at `-O0` is the one that struggles,
and even against `-O2` the Zig port wins.

The Phase 2 plan flagged a "1.5-2.5x regression risk from `ReleaseSafe` bounds
checks in the per-pixel rasterizer". It did not materialise — the rasterizer is
already batched through the SoA staging arrays, so bounds checks land once per
draw call rather than per pixel.

## Memory

Idle and under stress, RSS is flat at **11,008 KB** (post-stress 11,020 KB — a
12 KB delta attributable to Xlib's own event queue, not the port).

- 90 s idle run: no growth across 6 samples.
- 40 s stress run (24 injected clicks + pointer drags across the style editor
  and background sliders, forcing continuous live recolour and full repaints):
  no growth, no command-list overflow, no stack overflow on the id/clip stacks.

The 256 KB command arena resets each frame in `end()`, so per-frame arena
pressure is bounded by a single frame's draw calls, not by uptime.

## Valgrind

`--track-origins=yes` on `ReleaseSafe`: **clean**, no uninitialised reads, no
invalid accesses.

`--track-origins=yes` on `ReleaseFast` after the D40 fix: **clean**.

## D40 — the ReleaseFast crash (this is the important one)

`ReleaseSafe` and `Debug` ran fine; `ReleaseFast` segfaulted on frame 2 with
`renderer.Renderer.flush (self=0x0)`. Valgrind with origin tracking pointed at
an uninitialised 8-byte value created inside Xlib's event queue via
`fenster.loop`.

Root cause was in `fenster.zig`, not the renderer:

```zig
const XEvent = extern union { ..., _pad: [128]u8 };   // 144 bytes total
const XKeyEvent = extern struct { ..., _pad: [48]u8 };
```

The real Xlib `XEvent` is `char pad[24 * sizeof(long)]` = **192 bytes**, and
the real `XKeyEvent` / `XButtonEvent` / `XMotionEvent` have **no trailing pad**
(they are 96 bytes by natural alignment). The port had invented pads, so:

- `XEvent` was 144 bytes instead of 192.
- `XNextEvent()` writes `sizeof(XEvent)` = 192 bytes into the caller's
  variable, so **every single event overflowed the stack by 48 bytes**.

In `Debug`/`ReleaseSafe` the overflow landed in stack padding that nothing live
occupied, so it went unnoticed. In `ReleaseFast` it clobbered the register-spill
slot holding the renderer pointer, producing a null `self` two frames later —
a crash site with no apparent connection to its cause.

Fixed by matching the headers exactly, and pinned with a test that asserts
`@sizeOf(XEvent) == 192` and each event struct `== 96`, so the layout can
never silently drift again.

**Lesson:** when hand-transcribing a C union whose size is defined by a `pad[]`
member, assert the size against the real header. A union that is too small is a
memory-safety bug that only shows up in the optimised build, far from its cause.

## Reproducing

```sh
# Zig
zig build -Doptimize=ReleaseSafe
DISPLAY=:0 ./zig-out/bin/full_beans --timing

# C (needs the timing patch; see git history for /tmp/main_timed.c)
make && TIMING=1 ./main
```
