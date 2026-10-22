#!/usr/bin/env python3
"""Cut a FLUX creature render out of its magenta backdrop and export a game sprite.

FLUX.1-schnell cannot emit alpha, so creatures are generated on a saturated magenta
backdrop (hue ~335). The backdrop is uniform across the whole frame, including the
baked drop shadow, which means a hue-band key removes the background and the shadow
in one step while leaving the creature's own reds/oranges untouched (the cap sits at
hue ~2, a good 25 degrees away from the key band).

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
from pathlib import Path

from PIL import Image, ImageFilter

# Backdrop hue measured on real renders; the band is deliberately narrow so warm
# creature colours (red cap, amber glow) survive the key.
KEY_HUE = 335.0
KEY_HUE_TOL = 18.0
KEY_SAT_MIN = 0.55
# No brightness limit: FLUX renders the backdrop anywhere between V=0.82 and V=0.99
# depending on the subject, and an upper bound silently kept the bright magenta
# frames fully opaque (the umbral_alpha and poison_toad renders).


def _hue_distance(a: float, b: float) -> float:
    d = abs(a - b) % 360.0
    return min(d, 360.0 - d)


def cutout(img: Image.Image) -> Image.Image:
    rgb = img.convert("RGB")
    w, h = rgb.size
    px = rgb.load()

    alpha = Image.new("L", (w, h), 255)
    ap = alpha.load()

    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            hh, ss, vv = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if ss >= KEY_SAT_MIN and _hue_distance(hh * 360.0, KEY_HUE) <= KEY_HUE_TOL:
                ap[x, y] = 0

    # Kill the 1px magenta fringe JPEG leaves on the silhouette, then soften the cut
    # so the sprite does not look like a sticker pasted on the arena floor.
    alpha = alpha.filter(ImageFilter.MinFilter(3))
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.9))

    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    return out


def autocrop(img: Image.Image, pad_ratio: float = 0.04) -> Image.Image:
    bbox = img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
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
