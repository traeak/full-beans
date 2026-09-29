#!/usr/bin/env python3
"""Convert atlas.inl into raw binary assets for @embedFile (plan decision 4a).

Reads the C single-header atlas and emits:

  src/assets/atlas_texture.bin  128*128 = 16384 bytes, row-major greyscale
  src/assets/atlas_rects.bin    N * 16 bytes, little-endian int32 {x, y, w, h}

Notes on the C source that the generator has to reproduce:

  * `atlas_texture` is declared as [ATLAS_WIDTH * ATLAS_HEIGHT] but only lists
    10584 initializers. C zero-fills the remainder, so we pad to 16384.
  * `atlas[]` uses designated initializers ([ MU_ICON_CLOSE ] = {...}), so the
    symbol names must be resolved to indices. Gaps are zero-filled, again per C.
  * The enum order in microui.h is CLOSE=1, CHECK=2, COLLAPSED=3, EXPANDED=4,
    MAX=5 -- note that atlas.inl lists EXPANDED before COLLAPSED, which only
    works because the initializers are designated, not positional.
"""

import argparse
import os
import re
import struct
import sys

# Symbol values mirrored from microui.h and atlas.inl.
ICONS = {
    "MU_ICON_NONE": 0,
    "MU_ICON_CLOSE": 1,
    "MU_ICON_CHECK": 2,
    "MU_ICON_COLLAPSED": 3,
    "MU_ICON_EXPANDED": 4,
    "MU_ICON_MAX": 5,
}
SYMBOLS = dict(ICONS)
SYMBOLS["ATLAS_WHITE"] = SYMBOLS["MU_ICON_MAX"]  # 5
SYMBOLS["ATLAS_FONT"] = SYMBOLS["ATLAS_WHITE"] + 1  # 6


def eval_index(expr):
    """Evaluate a designated-initializer index like 'ATLAS_FONT+32'."""
    total = 0
    for term in expr.strip().split("+"):
        term = term.strip()
        if re.fullmatch(r"-?\d+", term):
            total += int(term)
        elif term in SYMBOLS:
            total += SYMBOLS[term]
        else:
            raise ValueError(f"unknown symbol {term!r} in index {expr!r}")
    return total


def parse_texture(src):
    m = re.search(
        r"static\s+unsigned\s+char\s+atlas_texture\s*\[[^\]]*\]\s*=\s*\{(.*?)\n\};",
        src,
        re.S,
    )
    if not m:
        raise SystemExit("could not find atlas_texture[] in atlas.inl")
    vals = [int(t, 16) for t in re.findall(r"0[xX][0-9a-fA-F]+", m.group(1))]

    wm = re.search(
        r"enum\s*\{\s*ATLAS_WIDTH\s*=\s*(\d+)\s*,\s*ATLAS_HEIGHT\s*=\s*(\d+)", src
    )
    if not wm:
        raise SystemExit("could not find ATLAS_WIDTH / ATLAS_HEIGHT")
    w, h = int(wm.group(1)), int(wm.group(2))
    want = w * h

    if len(vals) > want:
        raise SystemExit(f"atlas_texture has {len(vals)} bytes but declared size is {want}")
    if len(vals) != want:
        print(
            f"note: atlas_texture lists {len(vals)} of {want} bytes; zero-filling the "
            f"last {want - len(vals)} (matches C's implicit padding)"
        )
        vals = vals + [0] * (want - len(vals))
    return w, h, bytes(vals)


def parse_rects(src):
    m = re.search(r"static\s+mu_Rect\s+atlas\[\]\s*=\s*\{(.*?)\n\};", src, re.S)
    if not m:
        raise SystemExit("could not find static mu_Rect atlas[] in atlas.inl")

    entry = re.compile(
        r"\[\s*([A-Za-z_][A-Za-z_0-9+\s]*)\s*\]\s*=\s*\{\s*"
        r"(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*\}",
    )
    rects = {}
    for mm in entry.finditer(m.group(1)):
        idx = eval_index(mm.group(1))
        if idx in rects:
            raise SystemExit(f"duplicate atlas index {idx}")
        rects[idx] = tuple(int(g) for g in mm.groups()[1:])

    if not rects:
        raise SystemExit("no atlas[] entries parsed")

    hi = max(rects)
    out = [struct.pack("<iiii", *rects.get(i, (0, 0, 0, 0))) for i in range(hi + 1)]
    return hi, b"".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", default="atlas.inl")
    ap.add_argument("--outdir", default="src/assets")
    args = ap.parse_args()

    try:
        with open(args.inp) as f:
            src = f.read()
    except OSError as exc:
        raise SystemExit(f"cannot read {args.inp}: {exc}") from None

    w, h, texture = parse_texture(src)
    hi, rects = parse_rects(src)

    try:
        os.makedirs(args.outdir, exist_ok=True)
        tex_path = os.path.join(args.outdir, "atlas_texture.bin")
        rect_path = os.path.join(args.outdir, "atlas_rects.bin")
        with open(tex_path, "wb") as f:
            f.write(texture)
        with open(rect_path, "wb") as f:
            f.write(rects)
    except OSError as exc:
        raise SystemExit(f"cannot write assets: {exc}") from None

    print(f"wrote {tex_path} ({len(texture)} bytes, {w}x{h})")
    print(f"wrote {rect_path} ({len(rects)} bytes, {hi + 1} rects)")
    print(f"  ATLAS_WHITE(5)      = {struct.unpack_from('<iiii', rects, 5 * 16)}")
    print(f"  ATLAS_FONT+32 (sp) = {struct.unpack_from('<iiii', rects, (6 + 32) * 16)}")
    print(f"  ATLAS_FONT+65 ('A')= {struct.unpack_from('<iiii', rects, (6 + 65) * 16)}")


if __name__ == "__main__":
    sys.exit(main())
