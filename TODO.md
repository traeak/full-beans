# TODO — Continue the C → Zig port to demo parity

## Goal
Make `zig build run` render the same three-window microui demo as the C build
(`main.c`: Demo Window / Log Window / Style Editor, with working buttons, textbox,
sliders, tree, popups, scrolling, live style editing), using the existing
`src/fenster.zig` windowing layer.

## Decisions (agreed)
- **2c — Hybrid Zig.** Keep microui's on-wire byte layout *exactly* as C: the
  256 KB `command_list` arena, variable-size records, `base.size` pointer
  walking, and absolute `jump.dst` pointers rewritten by `mu_end`. Use idiomatic
  Zig (`[]const u8`, `bool`, error sets) only at the public API boundary where it
  is free. Rationale: a Zig tagged union must size to its largest variant, and
  `mu_TextCommand` carries an inline variable-length string — so a tagged union
  either inflates the hottest structure ~10x or forces a heap alloc per text
  command. Both lose a deliberate zero-allocation property of the original.
- **3b — Renderer as a struct, batch retained.** `Renderer` holds `*Fenster` plus
  the three SoA staging arrays. No module globals. Plus two cheap fast paths:
  greyscale LUT and opaque-alpha row fill.
- **4a — Atlas via `@embedFile`.** Convert `atlas.inl` to raw binary assets at
  build time; no 1000-line Zig literal arrays.
- **Parity bar: visual.** Must look and behave like the C demo on X11.
- **`fenster_audio` is out of scope** for demo parity (the C demo never calls it).
  It stays as-is.

## Risk register
- **R1: `src/fenster.zig` has never been executed.** It compiles for Linux and
  Windows cross, but no window has ever opened. Biggest unknown in the port.
  Mitigated by Phase 0 before anything is built on top.
- **R2: `mu_end` depends on absolute intra-arena pointers surviving a `qsort`.**
  Zig's `std.sort` is stable/block-based; must sort the *pointer array*, not the
  containers. Verify jump chain by walking it and comparing command count vs C.
- **R3: `Stack(T, n)` in `microui.zig` may not expose `.items` as a raw
  contiguous buffer** usable for byte-level arena arithmetic. Check in Phase 2.1.
- **R4: `ReleaseSafe` bounds checks in the per-pixel rasterizer** are the one
  place a real regression can hide. Measure, don't guess (Phase 8).

---

## Tasks

### 0. Fenster smoke test (de-risk R1) — do this first
- [ ] 0.1 Write `src/smoke_fenster.zig`: open an 800×600 `Fenster`, fill the
      `[*]u32] buf` with a left-to-right RGB ramp using `pixel()`, run `loop()`
      for ~120 frames, exit when `loop()` returns false.
- [ ] 0.2 Add a `zig build smoke` step that runs it.
- [ ] 0.3 Run it on `DISPLAY=:0`. Confirm: window appears with title, ramp is
      visible, ESC/close quits cleanly, no crash, no X error.
- [ ] 0.4 Confirm `keys[]`, `mod`, `x`, `y`, `mouse` fields actually get written
      by the Linux `loop()` — print one sample per input event and eyeball that
      mouse coords track the pointer and `mouse` flips on button press.
- [ ] 0.5 Fix whatever Phase 0.3/0.4 breaks. **Do not proceed until the window
      opens, paints, and reports input.**
- [ ] 0.6 Record findings in `NOTES_fenster_smoke.md` (esp. any field whose
      semantics differ from `fenster.h`).

### 1. Atlas → binary assets (decision 4a)
- [ ] 1.1 Write `tools/gen_atlas.py` that parses `atlas.inl` and emits
      `assets/atlas_texture.bin` = exactly 128×128 = 16384 bytes, row-major,
      from the `atlas_texture[]` initializer.
- [ ] 1.2 Emit `assets/atlas_rects.bin` = packed little-endian `i32[4]` records
      `{x, y, w, h}` in index order from the `static mu_Rect atlas[]`
      designated-initializer table, length = highest index + 1.
- [ ] 1.3 Verify: `atlas_texture.bin` is 16384 bytes; `atlas_rects.bin` length
      is a multiple of 16; spot-check `ATLAS_WHITE`, `ATLAS_FONT+32` (space),
      `ATLAS_FONT+65` ('A') against the `.inl` source by hand.
- [ ] 1.4 Write `src/atlas.zig`: `@embedFile` both blobs; expose
      `texture: *const [16384]u8`, `rectAt(i: usize) Rect` (reads 16-byte
      record), `width = 128`, `height = 128`, `ATLAS_WHITE`, `ATLAS_FONT`,
      `fontRect(chr: u8) Rect`.
- [ ] 1.5 Add comptime asserts: `@sizeOf(Rect) == 16`, blob sizes match
      expectations, `ATLAS_FONT + 127` is within `atlas_rects.bin`.
- [ ] 1.6 Wire `atlas` into `build.zig` install/step so `zig build` regenerates
      assets when `atlas.inl` changes (or document the manual `make atlas` step).

### 2. microui core plumbing
- [ ] 2.1 Audit `Stack(T, n)` in `src/microui.zig`: confirm `.items` is a
      contiguous fixed array and `.idx` is the C-equivalent write cursor. Add
      comptime asserts on `@sizeOf(Stack(u8, COMMANDLIST_SIZE))`.
- [ ] 2.2 Port `unclipped_rect`, `default_style` constants.
- [ ] 2.3 Port `expandRect`, `intersectRects`, `rectOverlapsVec2` (pure, no ctx).
- [ ] 2.4 Port `drawFrame` (the default `draw_frame` callback).
- [ ] 2.5 Port `init` / `begin` / `setFocus`.
- [ ] 2.6 Port `fnvHash` + `getId` + `pushId` + `popId`.
      Must produce **byte-identical ids to C** — hash over the same bytes.
- [ ] 2.7 Port `pushClipRect` / `popClipRect` / `getClipRect` / `checkClip`.
- [ ] 2.8 Port `getCurrentContainer` / `getContainer` / `bringToFront`.
- [ ] 2.9 Port pool fns: `poolInit` / `poolGet` / `poolUpdate` (LRU by
      `last_update`).
- [ ] 2.10 Port input handlers: `inputMousemove` / `inputMousedown` /
      `inputMouseup` / `inputScroll` / `inputKeydown` / `inputKeyup` /
      `inputText`.
- [ ] 2.11 Port command layer: `pushCommand`, `pushJump`, `setClip`,
      `drawRect`, `drawBox`, `drawText`, `drawIcon` — writing into the raw
      `command_list` byte arena via `@ptrCast`/`@alignCast`.
- [ ] 2.12 Port `nextCommand` (the `base.size` walk + JUMP-follow loop).
      **Critical:** must terminate at the arena end sentinel exactly like C.
- [ ] 2.13 Port `end` including the zindex sort + jump-chain patch-up (R2).
- [ ] 2.14 Unit test: id stability. Feed a fixed sequence of
      `pushId`/`getId` calls, assert exact expected u32 values.
- [ ] 2.15 Unit test: command round-trip. Emit a known sequence of
      drawRect/drawText/drawIcon/setClip, then walk with `nextCommand` and
      assert the decoded stream matches, including jump ordering.

### 3. microui layout
- [ ] 3.1 Port `layoutBeginColumn` / `layoutEndColumn`.
- [ ] 3.2 Port `layoutRow` (widths array incl. negative-width semantics).
- [ ] 3.3 Port `layoutWidth` / `layoutHeight` / `layoutSetNext`.
- [ ] 3.4 Port `layoutNext` — the largest layout function; preserve
      `next_row` / `next_type` / indent / max-width bookkeeping exactly.
- [ ] 3.5 Unit test: drive a fixed sequence of `layoutRow` + `layoutNext` calls
      and assert the emitted rects match C output (generate the C expectations
      by running the C binary with a trace, or hand-compute).

### 4. microui simple widgets
- [ ] 4.1 Port `drawControlFrame` / `drawControlText` / `mouseOver` /
      `updateControl`.
- [ ] 4.2 Port `text` and `label`.
- [ ] 4.3 Port `buttonEx` + `button` wrapper.
- [ ] 4.4 Port `checkbox`.
- [ ] 4.5 Manual check in a scratch app: button highlights on hover, fires on
      click, checkbox toggles.

### 5. microui interactive widgets + containers
- [ ] 5.1 Port `textboxRaw` (cursor, selection-free editing, RETURN/BACKSPACE
      handling, focus). Biggest single function in the file (~73 lines).
- [ ] 5.2 Port `textboxEx` / `textbox`.
- [ ] 5.3 Port `sliderEx` + `slider`.
- [ ] 5.4 Port `numberEx` + `number` (uses `number_edit_buf`, `REAL_FMT` /
      `SLIDER_FMT` formatting).
- [ ] 5.5 Port `headerEx` / `beginTreenodeEx` / `endTreenode`.
- [ ] 5.6 Port `beginWindowEx` / `beginWindow` / `endWindow` (drag, resize,
      close, scroll, content_size).
- [ ] 5.7 Port `openPopup` / `beginPopup` / `endPopup`.
- [ ] 5.8 Port `beginPanelEx` / `beginPanel` / `endPanel`.
- [ ] 5.9 Re-export `microui` from `src/root.zig`.

### 6. Renderer (`src/renderer.zig`, decision 3b)
- [ ] 6.1 Define `Renderer` struct: owns `*Fenster`, `tex_buf`/`src_buf`/
      `color_buf` staging arrays (16384 entries each), `buf_idx`, `clip_rect`.
      No module-level mutable state.
- [ ] 6.2 Port `within` / `withinRect` / `sameSize` / `textureColor` helpers.
- [ ] 6.3 Port `rColor` (Color→u32 ARGB) and `muColorArgb` (u32→Color).
- [ ] 6.4 Add **greyscale LUT**: `const grey_lut: [256]u32` precomputed from
      `greyscale(c)`, replacing 3 shifts + 3 ors per pixel with one load.
- [ ] 6.5 Port `blendPixel`, plus **opaque fast path**: when `src.a == 255`,
      write the constant color across the row instead of blending per pixel.
- [ ] 6.6 Port `flush` — clip-intersect once per quad (hoist `ystart/yend/
      xstart/xend` out of the inner loops, as C does), then textured or blend
      path.
- [ ] 6.7 Port `pushQuad` with the full-buffer flush-on-overflow.
- [ ] 6.8 Port `drawRect` / `drawText` / `drawIcon` / `getTextWidth` /
      `getTextHeight` / `setClipRect` / `clear` / `present`.
- [ ] 6.9 Keep the C quirk: `r_draw_text` skips UTF-8 continuation bytes
      (`(*p & 0xc0) == 0x80`) and clamps to 127.
- [ ] 6.10 Unit test: render a white-rect quad and a text quad into a small
      offscreen buffer, assert exact pixel values against hand-computed C
      results.

### 7. App wiring (`src/main.zig`)
- [ ] 7.1 Replace the `zig init` boilerplate entirely.
- [ ] 7.2 Port `writeLog` + `logbuf` (64000 B) state.
- [ ] 7.3 Port `testWindow` — Demo Window: headers, buttons, popup, tree,
      columns, lorem text, min-size clamp (`w >= 240`, `h >= 300`).
- [ ] 7.4 Port `logWindow` — output panel with scroll-to-bottom on update,
      textbox + Submit, `MU_RES_SUBMIT` handling, `setFocus(ctx.last_id)`.
- [ ] 7.5 Port `uint8Slider` helper (pushId by pointer, temp float, `%.0f`).
- [ ] 7.6 Port `styleWindow` — 15-color × RGBA slider grid + live swatch.
- [ ] 7.7 Port `processFrame` (begin → style/log/test windows → end).
- [ ] 7.8 Port `textWidth` / `textHeight` callbacks into the renderer.
- [ ] 7.9 Port the main loop: input mapping from `Fenster` fields →
      `mu_input_*`, ESC quits, command dispatch to renderer, 60 fps
      frame-budget sleep.
- [ ] 7.10 Wire `main` to `std.process.Init` (arena + io) and construct
      `Renderer` + `Context`.

### 8. Parity + performance verification
- [ ] 8.1 Run C build (`make && ./main`) and Zig build side by side. Screenshot
      both. Compare window layout, fonts, colors, widget metrics.
- [ ] 8.2 Interaction parity checklist — exercise and confirm each: drag window,
      resize window, close/reopen window, hover states, button press → log line,
      popup open + click items, tree expand/collapse, checkbox toggle, textbox
      type + Enter submit, slider drag (bg color changes), style editor sliders
      change live colors, panel scroll with mouse wheel, ESC quits.
- [ ] 8.3 Add frame-time instrumentation (reuse `fenster_time`) printing
      avg/max ms per frame every 60 frames, behind a `zig build run -- --timing`
      flag or env var.
- [ ] 8.4 Measure C vs Zig in the same conditions. Record in `NOTES_perf.md`.
      If Zig `ReleaseSafe` is materially slower, confirm `ReleaseFast` closes the
      gap and note which loop dominates.
- [ ] 8.5 Long-run check: 5+ minutes, confirm no leak growth, no command-list
      overflow, no stack overflow on the id/clip stacks.

### 9. Cross-platform compile gates
- [ ] 9.1 `zig build` for native Linux — clean.
- [ ] 9.2 `zig build -Dtarget=x86_64-windows-gnu` — clean.
- [ ] 9.3 `zig build -Dtarget=aarch64-macos` (or x86_64-macos) — clean, if the
      toolchain/SDK is available here. If not, record it as unverified rather
      than silently skipped.
- [ ] 9.4 `zig build test` — all tests pass.
- [ ] 9.5 Update `TODO_microui.md` checkboxes to reflect reality (currently
      0/111 checked despite the types being done — stale).

---

## Notes
- Style: TigerStyle — PascalCase types, camelCase functions, 2-space indent,
  76-col limit, explicit error handling.
- Never use `>` or `>=` in conditionals — swap operands to `<` / `<=`
  (global AGENTS.md rule). Note `microui.c` and `renderer.c` are full of `>`;
  each one gets rewritten during port.
- `@cImport` is deprecated in Zig 0.16 — keep using `extern` declarations as
  `fenster.zig` does.
- Commit after each phase completes and passes its verification step.
- If a phase reveals unlisted required work, stop and add it under
  `## Discovered Tasks` before continuing.
