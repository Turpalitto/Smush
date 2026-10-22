#!/usr/bin/env python3
"""Cut a FLUX creature render out of its magenta backdrop and export a game sprite.

FLUX.1-schnell cannot emit alpha, so creatures are generated on a saturated magenta
backdrop. Two properties of those renders drive the key:

* the backdrop hue is not fixed. Measured across one batch it drifts between 314 and
  343 degrees, so the key band is centred on the hue actually measured on this
  image's border instead of a hard-coded constant;
* interior colours can land inside that band (a hot-pink eye, a magenta core), so
  alpha is only cleared for backdrop pixels *connected to the frame edge*. A flood
  fill from the border removes the backdrop and its baked drop shadow in one pass
  while every enclosed detail stays opaque.

Usage:
    python3 tools/process_creature_art.py RAW_DIR OUT_DIR [--size 256]
    python3 tools/process_creature_art.py --icons-from ART_DIR OUT_DIR [--size 128]

The second form derives the small UI icons (bestiary cards, collection list) from
already-processed sprites, so both sizes always come from the same render.
"""

from __future__ import annotations

import argparse
import colorsys
import json
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter

# Half-width of the hue band around the measured backdrop hue. Wide enough to absorb
# the gradient across a single frame, narrow enough that warm creature reds (~0-20)
# stay clear of a ~335 degree backdrop.
KEY_HUE_TOL = 22.0
# Saturation floor for "this pixel is backdrop". Grey/white highlights on the
# creature are below it, so they are never treated as background.
KEY_SAT_MIN = 0.45


def _hue_distance(a: float, b: float) -> float:
    d = abs(a - b) % 360.0
    return min(d, 360.0 - d)


def measure_backdrop_hue(rgb: Image.Image) -> float:
    """Median hue of the saturated border pixels — the colour FLUX actually painted."""
    w, h = rgb.size
    px = rgb.load()
    hues = []
    step = max(1, min(w, h) // 96)
    for x in range(0, w, step):
        for y in (0, 1, 2, h - 3, h - 2, h - 1):
            hues.append(px[x, y])
    for y in range(0, h, step):
        for x in (0, 1, 2, w - 3, w - 2, w - 1):
            hues.append(px[x, y])

    sat_hues = []
    for r, g, b in hues:
        hh, ss, _vv = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
        if ss >= 0.35:
            sat_hues.append(hh * 360.0)
    if not sat_hues:
        return 335.0
    sat_hues.sort()
    return sat_hues[len(sat_hues) // 2]


def cutout(img: Image.Image) -> Image.Image:
    rgb = img.convert("RGB")
    w, h = rgb.size
    px = rgb.load()

    bg_hue = measure_backdrop_hue(rgb)

    # 1. Which pixels *could* be backdrop, ignoring position.
    candidate = bytearray(w * h)
    for y in range(h):
        row = y * w
        for x in range(w):
            r, g, b = px[x, y]
            hh, ss, _vv = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if ss >= KEY_SAT_MIN and _hue_distance(hh * 360.0, bg_hue) <= KEY_HUE_TOL:
                candidate[row + x] = 1

    # 2. Keep only what is reachable from the frame edge, so enclosed hot-pink eyes
    #    and cores survive while the backdrop and its shadow are cleared.
    alpha = Image.new("L", (w, h), 255)
    ap = alpha.load()
    seen = bytearray(w * h)
    queue: deque[int] = deque()

    def push(idx: int) -> None:
        if candidate[idx] and not seen[idx]:
            seen[idx] = 1
            queue.append(idx)

    for x in range(w):
        push(x)
        push((h - 1) * w + x)
    for y in range(h):
        push(y * w)
        push(y * w + w - 1)

    while queue:
        idx = queue.popleft()
        ap[idx % w, idx // w] = 0
        x = idx % w
        if x > 0:
            push(idx - 1)
        if x < w - 1:
            push(idx + 1)
        if idx >= w:
            push(idx - w)
        if idx < (h - 1) * w:
            push(idx + w)

    # 3. Kill the 1px magenta fringe JPEG leaves on the silhouette, then soften the
    #    cut so the sprite does not look like a sticker pasted on the arena floor.
    alpha = alpha.filter(ImageFilter.MinFilter(3))
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.9))

    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    return out


def autocrop(img: Image.Image, pad_ratio: float = 0.04) -> Image.Image:
    # Threshold well above the noise floor: the requested neon rim light leaves a
    # faint halo around the silhouette, and counting it as subject would shrink the
    # creature inside its square and make every enemy read smaller than its hitbox.
    bbox = img.getchannel("A").point(lambda v: 255 if v > 96 else 0).getbbox()
    if not bbox:
        return img
    l, t, r, b = bbox
    side = max(r - l, b - t)
    pad = int(side * pad_ratio)
    side += pad * 2
    cx, cy = (l + r) // 2, (t + b) // 2
    left = cx - side // 2
    top = cy - side // 2
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, (-left, -top), img)
    return canvas


def derive_icons(art_dir: Path, icon_dir: Path, size: int) -> int:
    """Downscale finished sprites into UI icons (bestiary cards are 58 px wide)."""
    icon_dir.mkdir(parents=True, exist_ok=True)
    report = []
    for src in sorted(art_dir.glob("*.png")):
        img = Image.open(src).convert("RGBA")
        # Icons are drawn small; pre-shrink in two LANCZOS steps so thin antennae
        # and legs stay visible instead of dissolving into the arena background.
        while img.width > size * 2:
            img = img.resize((img.width // 2, img.height // 2), Image.LANCZOS)
        img = img.resize((size, size), Image.LANCZOS)
        dst = icon_dir / src.name
        img.save(dst)
        hist = img.getchannel("A").histogram()
        report.append((src.stem, round(sum(hist[200:]) / float(size * size), 3)))

    for name, coverage in report:
        flag = "OK " if 0.10 <= coverage <= 0.92 else "CHECK"
        print(f"  [{flag}] icon {name:<18} opaque={coverage}")
    return len(report)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("raw_dir", nargs="?")
    ap.add_argument("out_dir")
    ap.add_argument("--size", type=int, default=256)
    ap.add_argument("--manifest", default="", help="JSON mapping raw filename -> sprite id")
    ap.add_argument("--icons-from", default="", help="Derive UI icons from this sprite dir")
    args = ap.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.icons_from:
        count = derive_icons(Path(args.icons_from), out_dir, args.size)
        print(f"icons: {count} written to {out_dir} at {args.size}px")
        return 0

    if not args.raw_dir:
        ap.error("raw_dir is required unless --icons-from is used")

    raw_dir = Path(args.raw_dir)

    names = {}
    if args.manifest:
        names = json.loads(Path(args.manifest).read_text(encoding="utf-8"))

    report = []
    for src in sorted(raw_dir.glob("*.jpg")) + sorted(raw_dir.glob("*.png")):
        if src.stem.endswith("_cut"):
            continue
        target = names.get(src.name, src.stem)
        img = cutout(Image.open(src))
        img = autocrop(img)
        img = img.resize((args.size, args.size), Image.LANCZOS)
        dst = out_dir / f"{target}.png"
        img.save(dst)
        # Coverage tells us whether the key ate the creature or left the backdrop.
        hist = img.getchannel("A").histogram()
        opaque = sum(hist[200:]) / float(args.size * args.size)
        report.append((target, round(opaque, 3), dst.stat().st_size))

    for target, coverage, size in report:
        flag = "OK " if 0.10 <= coverage <= 0.92 else "CHECK"
        print(f"  [{flag}] {target:<18} opaque={coverage:<6} {size // 1024} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
