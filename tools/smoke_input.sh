#!/usr/bin/env bash
# Phase 0.4 driver: inject synthetic X events into the fenster smoke window and
# show which Fenster input fields actually got written.
#
# Requires: xdotool, a running X server.
#
# Uses XTEST-based input (no `--window` flag) so events look real to the server,
# and holds the button down across several frames -- `xdotool click` does
# press+release fast enough that both land inside one fenster.loop() call, and
# since loop() sets `mouse = (type == ButtonPress)` the field is back to 0 before
# the frame-to-frame diff can observe it.
set -u

BIN="${1:-zig-out/bin/smoke_fenster}"
OUT="/tmp/smoke_out.txt"
TRACE="/tmp/smoke_trace.txt"
FRAMES="${SMOKE_FRAMES:-400}"

if [ ! -x "$BIN" ]; then
  echo "missing $BIN -- run 'zig build' first" >&2
  exit 1
fi

SMOKE_FRAMES="$FRAMES" "$BIN" >"$OUT" 2>"$TRACE" &
PID=$!

WID=$(xdotool search --sync --name "fenster smoke" 2>/dev/null | head -1)
if [ -z "${WID:-}" ]; then
  echo "window never appeared" >&2
  kill "$PID" 2>/dev/null
  exit 1
fi

xdotool windowactivate --sync "$WID"
sleep 0.4
eval "$(xdotool getwindowgeometry --shell "$WID")"
echo "window at $X,$Y" >&2

# --- mouse: move, hold button down across frames, release ---------------------
xdotool mousemove --sync "$((X + 120))" "$((Y + 90))"
sleep 0.2
xdotool mousedown 1
sleep 0.5
xdotool mouseup 1
sleep 0.2
xdotool mousemove --sync "$((X + 400))" "$((Y + 300))"
sleep 0.2

# --- keyboard ---------------------------------------------------------------
xdotool key a
sleep 0.2
xdotool keydown ctrl
xdotool key s
xdotool keyup ctrl
sleep 0.2
xdotool keydown shift
xdotool key a
xdotool keyup shift
sleep 0.2
xdotool key Return
sleep 0.2
xdotool key BackSpace
sleep 0.3

xdotool key Escape
wait "$PID"
RC=$?

echo "=== raw button/key events seen by fenster (stderr) ==="
grep -E "type=(2|3|4|5) " "$TRACE" | head -40
echo
echo "=== smoke report (stdout, exit $RC) ==="
cat "$OUT"
