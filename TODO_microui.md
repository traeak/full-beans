# TODO — Convert microui.c to microui.zig, atlas.inl to atlas.zig

> **STATUS: COMPLETE.** Every item below is implemented and verified. This file was
> left at 0/111 while the work landed; it is now marked up to date.
>
> The authoritative, current tracker is `TODO.md` (phases 0-9, discovered items
> D1-D40). Two notes on items as originally worded:
>
> - `Mouse` / `Key` are **bitmask constants** (`MOUSE_LEFT`, `KEY_RETURN`, ...),
>   not Zig enums, because C defines them as `#define` bit flags that get OR'd
>   into `mouse_down` / `key_down` ints. An enum would have lost that.
> - `Stack(T, n)` is a `pub fn` returning a generated struct type, not a
>   `pub const`, since it is generic over both type and length.
> - `Command` is an `extern union` over a `type` tag with variable-size records
>   in a 256 KB arena (decision 2c), not a Zig tagged union — see D20 for why.
>
> Parity is verified pixel-exact against the C demo: `magick compare -metric AE`
> returns 0 for both the idle frame and after an injected click.

## Goal
Convert `microui.c` + `microui.h` to `src/microui.zig` and `atlas.inl` to `src/atlas.zig`,
preserving all public API surface and internal behavior. Re-export from `src/root.zig`.

## Tasks

### 1. `src/microui.zig` — types, constants, enums
- [x] Define all enums: `Clip`, `CommandType`, `ColorId`, `IconId`, `Result`, `Option`, `Mouse`, `Key`
- [x] Define all constants: `COMMANDLIST_SIZE`, `ROOTLIST_SIZE`, `CONTAINERSTACK_SIZE`, `CLIPSTACK_SIZE`, `IDSTACK_SIZE`, `LAYOUTSTACK_SIZE`, `CONTAINERPOOL_SIZE`, `TREENODEPOOL_SIZE`, `MAX_WIDTHS`, `MAX_FMT`, format strings
- [x] Define `Stack(comptime T: type, comptime n: comptime_int)` generic (replaces `mu_stack` macro)
- [x] Define `Vec2` (extern struct, fields: x, y as c_int)
- [x] Define `Rect` (extern struct, fields: x, y, w, h as c_int)
- [x] Define `Color` (extern struct, fields: r, g, b, a as u8)
- [x] Define `PoolItem` (extern struct, fields: id as u32, last_update as c_int)
- [x] Define `Font` as `*const anyopaque`
- [x] Define `Real` as `f32`
- [x] Define `Id` as `u32`
- [x] Define `BaseCommand`, `JumpCommand`, `ClipCommand`, `RectCommand`, `TextCommand`, `IconCommand`
- [x] Define `Command` as an extern union tagged by `type` field
- [x] Define `Layout` struct (body, next, position, size, max, widths array, items, item_index, next_row, next_type, indent)
- [x] Define `Container` struct (head, tail, rect, body, content_size, scroll, zindex, open)
- [x] Define `Style` struct (font, size, padding, spacing, indent, title_height, scrollbar_size, thumb_size, colors array)
- [x] Define `Context` struct with all fields (callbacks, core state, stacks, pools, input state)
- [x] Define inline constructors: `vec2(x, y)`, `rect(x, y, w, h)`, `color(r, g, b, a)`
- [x] Add `comptime` assertions for struct sizes matching C layout

### 2. `src/microui.zig` — core functions
- [x] `unclipped_rect` constant
- [x] `default_style` constant
- [x] `expandRect(rect, n)` — expand rect by n pixels
- [x] `intersectRects(r1, r2)` — compute intersection of two rects
- [x] `rectOverlapsVec2(r, p)` — check if point is inside rect
- [x] `drawFrame(ctx, rect, colorid)` — default draw_frame callback
- [x] `init(ctx: *Context)` — zero-init, set callbacks and default style
- [x] `begin(ctx: *Context)` — reset command list, root list, frame counter
- [x] `end(ctx: *Context)` — sort roots by zindex, set jump commands, reset input
- [x] `setFocus(ctx, id)` — set focused control
- [x] `fnvHash(hash: *Id, data: []const u8)` — FNV-1a hash function
- [x] `getId(ctx, data: []const u8)` — generate ID from data + parent ID stack
- [x] `pushId(ctx, data: []const u8)` — push ID onto stack
- [x] `popId(ctx)` — pop ID from stack
- [x] `pushClipRect(ctx, rect)` — push clipped rect
- [x] `popClipRect(ctx)` — pop clip rect
- [x] `getClipRect(ctx)` — get current clip rect
- [x] `checkClip(ctx, r)` — check if rect is clipped (none/partial/all)
- [x] `getCurrentContainer(ctx)` — get top of container stack
- [x] `getContainer(ctx, name: []const u8)` — get container by name
- [x] `bringToFront(ctx, cnt)` — set container zindex to front

### 3. `src/microui.zig` — pool functions
- [x] `poolInit(ctx, items: []PoolItem, len: comptime_int, id)` — init pool item (LRU)
- [x] `poolGet(ctx, items: []PoolItem, len: comptime_int, id)` — find pool item by ID
- [x] `poolUpdate(ctx, items: []PoolItem, idx)` — mark pool item as used this frame

### 4. `src/microui.zig` — input handlers
- [x] `inputMousemove(ctx, x, y)` — update mouse position
- [x] `inputMousedown(ctx, x, y, btn)` — set mouse down + pressed
- [x] `inputMouseup(ctx, x, y, btn)` — clear mouse down
- [x] `inputScroll(ctx, x, y)` — add to scroll delta
- [x] `inputKeydown(ctx, key)` — set key down + pressed
- [x] `inputKeyup(ctx, key)` — clear key down
- [x] `inputText(ctx, text: []const u8)` — append to input text buffer

### 5. `src/microui.zig` — command list functions
- [x] `pushCommand(ctx, type, size)` — push command onto command list (byte-level)
- [x] `nextCommand(ctx, cmd: **Command)` — iterate commands, skipping jumps
- [x] `pushJump(ctx, dst)` — push jump command
- [x] `setClip(ctx, rect)` — push clip command
- [x] `drawRect(ctx, rect, color)` — push rect draw command
- [x] `drawBox(ctx, rect, color)` — draw hollow box (4 edge rects)
- [x] `drawText(ctx, font, str: []const u8, len, pos, color)` — push text command
- [x] `drawIcon(ctx, id, rect, color)` — push icon command

### 6. `src/microui.zig` — layout functions
- [x] `pushLayout(ctx, body, scroll)` — push new layout onto stack
- [x] `getLayout(ctx)` — get current layout
- [x] `popContainer(ctx)` — pop container, layout, and ID
- [x] `layoutBeginColumn(ctx)` — start nested column layout
- [x] `layoutEndColumn(ctx)` — end nested column, inherit max back to parent
- [x] `layoutRow(ctx, items, widths: ?[]const c_int, height)` — set row layout
- [x] `layoutWidth(ctx, width)` — set current item width
- [x] `layoutHeight(ctx, height)` — set current item height
- [x] `layoutSetNext(ctx, r, relative)` — set next rect explicitly
- [x] `layoutNext(ctx)` — get next layout rect (handles row wrapping, sizing)

### 7. `src/microui.zig` — control helpers
- [x] `inHoverRoot(ctx)` — check if current container is in hover root
- [x] `drawControlFrame(ctx, id, rect, colorid, opt)` — draw control with hover/focus state
- [x] `drawControlText(ctx, str: []const u8, rect, colorid, opt)` — draw text with alignment
- [x] `mouseOver(ctx, rect)` — check if mouse is over rect
- [x] `updateControl(ctx, id, rect, opt)` — update hover/focus state for a control

### 8. `src/microui.zig` — UI controls
- [x] `text(ctx, text: []const u8)` — multi-line text with word wrapping
- [x] `label(ctx, text: []const u8)` — single-line label
- [x] `buttonEx(ctx, label: ?[]const u8, icon, opt)` — button with optional icon
- [x] `checkbox(ctx, label: []const u8, state: *c_int)` — checkbox control
- [x] `textboxRaw(ctx, buf: []u8, bufsz, id, rect, opt)` — raw textbox with given ID/rect
- [x] `textboxEx(ctx, buf: []u8, bufsz, opt)` — textbox control
- [x] `numberTextbox(ctx, value: *Real, rect, id)` — shift-click to edit number as text
- [x] `sliderEx(ctx, value: *Real, low, high, step, fmt: []const u8, opt)` — slider control
- [x] `numberEx(ctx, value: *Real, step, fmt: []const u8, opt)` — number control

### 9. `src/microui.zig` — header / treenode
- [x] `header(ctx, label: []const u8, isTreeNode, opt)` — shared header logic
- [x] `headerEx(ctx, label: []const u8, opt)` — collapsible header
- [x] `beginTreeNodeEx(ctx, label: []const u8, opt)` — begin tree node (with indent)
- [x] `endTreeNode(ctx)` — end tree node (remove indent)

### 10. `src/microui.zig` — scrollbar
- [x] `scrollbar(ctx, cnt, body, contentSize)` — vertical scrollbar (convert C macro to function)
- [x] `scrollbars(ctx, cnt, body)` — both horizontal and vertical scrollbars

### 11. `src/microui.zig` — window / popup / panel
- [x] `pushContainerBody(ctx, cnt, body, opt)` — push container body with scrollbars
- [x] `beginRootContainer(ctx, cnt)` — begin root container (push to root list)
- [x] `endRootContainer(ctx)` — end root container (pop, set tail jump)
- [x] `beginWindowEx(ctx, title: []const u8, rect, opt)` — begin window with title bar, close, resize
- [x] `endWindow(ctx)` — end window
- [x] `openPopup(ctx, name: []const u8)` — open popup at mouse position
- [x] `beginPopup(ctx, name: []const u8)` — begin popup (auto-sized window)
- [x] `endPopup(ctx)` — end popup
- [x] `beginPanelEx(ctx, name: []const u8, opt)` — begin panel
- [x] `endPanel(ctx)` — end panel

### 12. `src/microui.zig` — convenience wrappers (from header macros)
- [x] `button(ctx, label: []const u8)` — calls buttonEx with ALIGNCENTER
- [x] `textbox(ctx, buf: []u8, bufsz)` — calls textboxEx
- [x] `slider(ctx, value: *Real, lo, hi)` — calls sliderEx with defaults
- [x] `number(ctx, value: *Real, step)` — calls numberEx with defaults
- [x] `header(ctx, label: []const u8)` — calls headerEx
- [x] `beginTreeNode(ctx, label: []const u8)` — calls beginTreeNodeEx
- [x] `beginWindow(ctx, title: []const u8, rect)` — calls beginWindowEx
- [x] `beginPanel(ctx, name: []const u8)` — calls beginPanelEx

### 13. `src/atlas.zig` — atlas data
- [x] Define constants: `WHITE` (IconId.MAX), `FONT`, `WIDTH` (128), `HEIGHT` (128)
- [x] Define `pub const texture: [WIDTH * HEIGHT]u8` with full hex data from atlas.inl
- [x] Define `pub const rects: []Rect` (or array) with all icon + font glyph rectangles
- [x] Import `Rect` from `microui.zig`

### 14. Wire up — `src/root.zig` + `build.zig`
- [x] Re-export `microui` from `src/root.zig`
- [x] Re-export `atlas` from `src/root.zig`

## Notes
- `mu_stack(T, n)` macro becomes a Zig generic `Stack(T, n)` struct with `idx: usize` and `items: [n]T`.
- `mu_Real` = `f32`, `mu_Id` = `u32`.
- `mu_Font` = `*const anyopaque` (opaque font handle passed through to callbacks).
- Command list uses byte-level pointer arithmetic — use `@ptrAdd` / `@ptrCast` in Zig.
- `mu_TextCommand.str[1]` is a flexible array member — allocate `sizeof(TextCommand) + len` bytes.
- C `expect()` macro becomes `std.debug.assert()`.
- C `sprintf` becomes `std.fmt.bufPrint`.
- C `strlen` becomes `.len` on slices.
- C `memset(ctx, 0, sizeof(*ctx))` becomes explicit zero-init or `@memset`.
- C `qsort` becomes `std.sort.block` or `std.sort.pdq`.
- C `strtod` becomes `std.fmt.parseFloat(f32)`.
- The `scrollbar` C macro uses stringification (`"!scrollbar" #y`) — convert to a function.
- The `scrollbars` function uses parameter-swapping via the macro — convert to explicit calls.
- Follow TigerStyle: PascalCase types, camelCase functions, 76-col limit, explicit errors.
- Zig 0.16: use `std.c` types (c_int, etc.), no `@cImport`.
