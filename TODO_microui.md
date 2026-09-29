# TODO — Convert microui.c to microui.zig, atlas.inl to atlas.zig

## Goal
Convert `microui.c` + `microui.h` to `src/microui.zig` and `atlas.inl` to `src/atlas.zig`,
preserving all public API surface and internal behavior. Re-export from `src/root.zig`.

## Tasks

### 1. `src/microui.zig` — types, constants, enums
- [ ] Define all enums: `Clip`, `CommandType`, `ColorId`, `IconId`, `Result`, `Option`, `Mouse`, `Key`
- [ ] Define all constants: `COMMANDLIST_SIZE`, `ROOTLIST_SIZE`, `CONTAINERSTACK_SIZE`, `CLIPSTACK_SIZE`, `IDSTACK_SIZE`, `LAYOUTSTACK_SIZE`, `CONTAINERPOOL_SIZE`, `TREENODEPOOL_SIZE`, `MAX_WIDTHS`, `MAX_FMT`, format strings
- [ ] Define `Stack(comptime T: type, comptime n: comptime_int)` generic (replaces `mu_stack` macro)
- [ ] Define `Vec2` (extern struct, fields: x, y as c_int)
- [ ] Define `Rect` (extern struct, fields: x, y, w, h as c_int)
- [ ] Define `Color` (extern struct, fields: r, g, b, a as u8)
- [ ] Define `PoolItem` (extern struct, fields: id as u32, last_update as c_int)
- [ ] Define `Font` as `*const anyopaque`
- [ ] Define `Real` as `f32`
- [ ] Define `Id` as `u32`
- [ ] Define `BaseCommand`, `JumpCommand`, `ClipCommand`, `RectCommand`, `TextCommand`, `IconCommand`
- [ ] Define `Command` as an extern union tagged by `type` field
- [ ] Define `Layout` struct (body, next, position, size, max, widths array, items, item_index, next_row, next_type, indent)
- [ ] Define `Container` struct (head, tail, rect, body, content_size, scroll, zindex, open)
- [ ] Define `Style` struct (font, size, padding, spacing, indent, title_height, scrollbar_size, thumb_size, colors array)
- [ ] Define `Context` struct with all fields (callbacks, core state, stacks, pools, input state)
- [ ] Define inline constructors: `vec2(x, y)`, `rect(x, y, w, h)`, `color(r, g, b, a)`
- [ ] Add `comptime` assertions for struct sizes matching C layout

### 2. `src/microui.zig` — core functions
- [ ] `unclipped_rect` constant
- [ ] `default_style` constant
- [ ] `expandRect(rect, n)` — expand rect by n pixels
- [ ] `intersectRects(r1, r2)` — compute intersection of two rects
- [ ] `rectOverlapsVec2(r, p)` — check if point is inside rect
- [ ] `drawFrame(ctx, rect, colorid)` — default draw_frame callback
- [ ] `init(ctx: *Context)` — zero-init, set callbacks and default style
- [ ] `begin(ctx: *Context)` — reset command list, root list, frame counter
- [ ] `end(ctx: *Context)` — sort roots by zindex, set jump commands, reset input
- [ ] `setFocus(ctx, id)` — set focused control
- [ ] `fnvHash(hash: *Id, data: []const u8)` — FNV-1a hash function
- [ ] `getId(ctx, data: []const u8)` — generate ID from data + parent ID stack
- [ ] `pushId(ctx, data: []const u8)` — push ID onto stack
- [ ] `popId(ctx)` — pop ID from stack
- [ ] `pushClipRect(ctx, rect)` — push clipped rect
- [ ] `popClipRect(ctx)` — pop clip rect
- [ ] `getClipRect(ctx)` — get current clip rect
- [ ] `checkClip(ctx, r)` — check if rect is clipped (none/partial/all)
- [ ] `getCurrentContainer(ctx)` — get top of container stack
- [ ] `getContainer(ctx, name: []const u8)` — get container by name
- [ ] `bringToFront(ctx, cnt)` — set container zindex to front

### 3. `src/microui.zig` — pool functions
- [ ] `poolInit(ctx, items: []PoolItem, len: comptime_int, id)` — init pool item (LRU)
- [ ] `poolGet(ctx, items: []PoolItem, len: comptime_int, id)` — find pool item by ID
- [ ] `poolUpdate(ctx, items: []PoolItem, idx)` — mark pool item as used this frame

### 4. `src/microui.zig` — input handlers
- [ ] `inputMousemove(ctx, x, y)` — update mouse position
- [ ] `inputMousedown(ctx, x, y, btn)` — set mouse down + pressed
- [ ] `inputMouseup(ctx, x, y, btn)` — clear mouse down
- [ ] `inputScroll(ctx, x, y)` — add to scroll delta
- [ ] `inputKeydown(ctx, key)` — set key down + pressed
- [ ] `inputKeyup(ctx, key)` — clear key down
- [ ] `inputText(ctx, text: []const u8)` — append to input text buffer

### 5. `src/microui.zig` — command list functions
- [ ] `pushCommand(ctx, type, size)` — push command onto command list (byte-level)
- [ ] `nextCommand(ctx, cmd: **Command)` — iterate commands, skipping jumps
- [ ] `pushJump(ctx, dst)` — push jump command
- [ ] `setClip(ctx, rect)` — push clip command
- [ ] `drawRect(ctx, rect, color)` — push rect draw command
- [ ] `drawBox(ctx, rect, color)` — draw hollow box (4 edge rects)
- [ ] `drawText(ctx, font, str: []const u8, len, pos, color)` — push text command
- [ ] `drawIcon(ctx, id, rect, color)` — push icon command

### 6. `src/microui.zig` — layout functions
- [ ] `pushLayout(ctx, body, scroll)` — push new layout onto stack
- [ ] `getLayout(ctx)` — get current layout
- [ ] `popContainer(ctx)` — pop container, layout, and ID
- [ ] `layoutBeginColumn(ctx)` — start nested column layout
- [ ] `layoutEndColumn(ctx)` — end nested column, inherit max back to parent
- [ ] `layoutRow(ctx, items, widths: ?[]const c_int, height)` — set row layout
- [ ] `layoutWidth(ctx, width)` — set current item width
- [ ] `layoutHeight(ctx, height)` — set current item height
- [ ] `layoutSetNext(ctx, r, relative)` — set next rect explicitly
- [ ] `layoutNext(ctx)` — get next layout rect (handles row wrapping, sizing)

### 7. `src/microui.zig` — control helpers
- [ ] `inHoverRoot(ctx)` — check if current container is in hover root
- [ ] `drawControlFrame(ctx, id, rect, colorid, opt)` — draw control with hover/focus state
- [ ] `drawControlText(ctx, str: []const u8, rect, colorid, opt)` — draw text with alignment
- [ ] `mouseOver(ctx, rect)` — check if mouse is over rect
- [ ] `updateControl(ctx, id, rect, opt)` — update hover/focus state for a control

### 8. `src/microui.zig` — UI controls
- [ ] `text(ctx, text: []const u8)` — multi-line text with word wrapping
- [ ] `label(ctx, text: []const u8)` — single-line label
- [ ] `buttonEx(ctx, label: ?[]const u8, icon, opt)` — button with optional icon
- [ ] `checkbox(ctx, label: []const u8, state: *c_int)` — checkbox control
- [ ] `textboxRaw(ctx, buf: []u8, bufsz, id, rect, opt)` — raw textbox with given ID/rect
- [ ] `textboxEx(ctx, buf: []u8, bufsz, opt)` — textbox control
- [ ] `numberTextbox(ctx, value: *Real, rect, id)` — shift-click to edit number as text
- [ ] `sliderEx(ctx, value: *Real, low, high, step, fmt: []const u8, opt)` — slider control
- [ ] `numberEx(ctx, value: *Real, step, fmt: []const u8, opt)` — number control

### 9. `src/microui.zig` — header / treenode
- [ ] `header(ctx, label: []const u8, isTreeNode, opt)` — shared header logic
- [ ] `headerEx(ctx, label: []const u8, opt)` — collapsible header
- [ ] `beginTreeNodeEx(ctx, label: []const u8, opt)` — begin tree node (with indent)
- [ ] `endTreeNode(ctx)` — end tree node (remove indent)

### 10. `src/microui.zig` — scrollbar
- [ ] `scrollbar(ctx, cnt, body, contentSize)` — vertical scrollbar (convert C macro to function)
- [ ] `scrollbars(ctx, cnt, body)` — both horizontal and vertical scrollbars

### 11. `src/microui.zig` — window / popup / panel
- [ ] `pushContainerBody(ctx, cnt, body, opt)` — push container body with scrollbars
- [ ] `beginRootContainer(ctx, cnt)` — begin root container (push to root list)
- [ ] `endRootContainer(ctx)` — end root container (pop, set tail jump)
- [ ] `beginWindowEx(ctx, title: []const u8, rect, opt)` — begin window with title bar, close, resize
- [ ] `endWindow(ctx)` — end window
- [ ] `openPopup(ctx, name: []const u8)` — open popup at mouse position
- [ ] `beginPopup(ctx, name: []const u8)` — begin popup (auto-sized window)
- [ ] `endPopup(ctx)` — end popup
- [ ] `beginPanelEx(ctx, name: []const u8, opt)` — begin panel
- [ ] `endPanel(ctx)` — end panel

### 12. `src/microui.zig` — convenience wrappers (from header macros)
- [ ] `button(ctx, label: []const u8)` — calls buttonEx with ALIGNCENTER
- [ ] `textbox(ctx, buf: []u8, bufsz)` — calls textboxEx
- [ ] `slider(ctx, value: *Real, lo, hi)` — calls sliderEx with defaults
- [ ] `number(ctx, value: *Real, step)` — calls numberEx with defaults
- [ ] `header(ctx, label: []const u8)` — calls headerEx
- [ ] `beginTreeNode(ctx, label: []const u8)` — calls beginTreeNodeEx
- [ ] `beginWindow(ctx, title: []const u8, rect)` — calls beginWindowEx
- [ ] `beginPanel(ctx, name: []const u8)` — calls beginPanelEx

### 13. `src/atlas.zig` — atlas data
- [ ] Define constants: `WHITE` (IconId.MAX), `FONT`, `WIDTH` (128), `HEIGHT` (128)
- [ ] Define `pub const texture: [WIDTH * HEIGHT]u8` with full hex data from atlas.inl
- [ ] Define `pub const rects: []Rect` (or array) with all icon + font glyph rectangles
- [ ] Import `Rect` from `microui.zig`

### 14. Wire up — `src/root.zig` + `build.zig`
- [ ] Re-export `microui` from `src/root.zig`
- [ ] Re-export `atlas` from `src/root.zig`

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
