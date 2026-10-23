#!/usr/bin/env python3
"""Capture the fifteen growth stages and build the labelled contact sheet.

This is the artefact the ladder is judged on: fifteen captures of the real game,
same world seed, same camera, mass set through the game's own _sync_mass_metrics,
then a 5x3 montage with the stage number and the mass printed on each cell.

Usage:
    python tools/growth_ladder_sheet.py                 # capture what is missing, montage
    python tools/growth_ladder_sheet.py --force         # re-capture all fifteen
    python tools/growth_ladder_sheet.py --montage-only  # re-frame existing frames

Why a script and not a shell loop: the previous sheet was assembled by hand in a
throwaway /tmp one-liner, so it could not be reproduced when the ornaments changed
and had to be re-derived from the transcript. The ladder is the main visual claim
of the growth pass, so it must be one command.

The frames are cached in --frames (default /tmp/smush_ladder_frames) so that
re-framing or re-montaging after a montage tweak costs nothing, and so that a
before/after comparison can reuse the "before" run instead of re-rendering it.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

GODOT = "/Users/turpal/godot45/Godot.app/Contents/MacOS/Godot"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STAGES_GD = os.path.join(REPO, "systems", "EvolutionStages.gd")


def read_mass_keys() -> list:
    """Parse MASS_KEYS out of EvolutionStages.gd.

    This list used to be copied here by hand with a comment saying it must match.
    A comment is not a constraint: the moment the ladder is retuned, the sheet
    keeps capturing the old masses and prints the old numbers on the cells, so the
    evidence quietly disagrees with the game. Read the real table instead.
    """
    with open(STAGES_GD, "r", encoding="utf-8") as fh:
        src = fh.read()
    m = re.search(r"const MASS_KEYS[^=]*=\s*\[(.*?)\]", src, re.S)
    if not m:
        raise SystemExit("could not find MASS_KEYS in %s" % STAGES_GD)
    keys = [float(x) for x in re.findall(r"[-+]?\d*\.?\d+", m.group(1))]
    if len(keys) != 15:
        raise SystemExit("expected 15 MASS_KEYS, parsed %d" % len(keys))
    return keys


MASS_KEYS = read_mass_keys()

CELL_W, CELL_H = 260, 400
LABEL_H = 22
COLS, ROWS = 5, 3

# Crop window on the 720x1280 capture, centred on the player. The first version
# kept the full frame width and shrank it into the cell, which turned every
# character into a 30 px dot and made the sheet useless for judging ornaments.
CROP_W, CROP_H = 330, 508
CROP_CX, CROP_CY = 360, 610


def font(size: int):
    for path in (
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def capture(mass: float, seed: int, out_path: str) -> bool:
    env = dict(os.environ)
    env.update({
        "QUICK_CAPTURE_OUT": out_path,
        "QUICK_CAPTURE_STAGE": "arena",
        "QUICK_CAPTURE_SECONDS": "3.0",
        "QUICK_CAPTURE_SIZE": "720x1280",
        "QUICK_CAPTURE_SEED": str(seed),
        "QUICK_CAPTURE_MASS": str(mass),
    })
    proc = subprocess.run(
        [GODOT, "--path", REPO, "tools/QuickCapture.tscn"],
        env=env, capture_output=True, text=True, timeout=180,
    )
    ok = os.path.exists(out_path) and os.path.getsize(out_path) > 20000
    for line in proc.stdout.splitlines():
        if line.startswith("QUICK_CAPTURE mass"):
            print("   ", line)
    if not ok:
        print("    FAILED exit=%d" % proc.returncode)
        for line in (proc.stderr or "").splitlines()[-8:]:
            print("      " + line)
    return ok


def montage(frames_dir: str, out_path: str) -> None:
    sheet = Image.new(
        "RGB", (COLS * CELL_W, ROWS * (CELL_H + LABEL_H)), (16, 22, 20)
    )
    draw = ImageDraw.Draw(sheet)
    f = font(16)
    for idx, mass in enumerate(MASS_KEYS):
        path = os.path.join(frames_dir, "stage_%02d.png" % (idx + 1))
        im = Image.open(path).convert("RGB")
        w, h = im.size
        left = max(0, min(w - CROP_W, CROP_CX - CROP_W // 2))
        top = max(0, min(h - CROP_H, CROP_CY - CROP_H // 2))
        im = im.crop((left, top, left + CROP_W, top + CROP_H))
        im = im.resize((CELL_W, CELL_H), Image.LANCZOS)
        col, row = idx % COLS, idx // COLS
        x = col * CELL_W
        y = row * (CELL_H + LABEL_H)
        sheet.paste(im, (x, y + LABEL_H))
        draw.text((x + 8, y + 3), "%d   m=%.1f" % (idx + 1, mass),
                  fill=(232, 240, 226), font=f)
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    sheet.save(out_path)
    print("wrote %s (%dx%d)" % (out_path, sheet.width, sheet.height))


def montage_ab(frames_dir: str, out_path: str) -> None:
    """Two frames, same seed, mass 10 vs mass 104, side by side at full height.

    This is the environment claim: the ladder has to change the world, not just the
    character, and the only honest way to show that is the same seed twice.
    """
    cell_w, cell_h = 360, 640
    sheet = Image.new("RGB", (cell_w * 2 + 8, cell_h + 26), (16, 22, 20))
    draw = ImageDraw.Draw(sheet)
    f = font(15)
    top_mass = MASS_KEYS[-1]
    for idx, (mass, label) in enumerate(((MASS_KEYS[0], "mass %.0f  (stage 1)" % MASS_KEYS[0]),
                                         (top_mass, "mass %.0f  (stage 15)" % top_mass))):
        path = os.path.join(frames_dir, "ab_%.1f.png" % mass)
        im = Image.open(path).convert("RGB")
        im = im.resize((cell_w, cell_h), Image.LANCZOS)
        x = idx * (cell_w + 8)
        sheet.paste(im, (x, 26))
        draw.text((x + 8, 5), label, fill=(232, 240, 226), font=f)
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    sheet.save(out_path)
    print("wrote %s (%dx%d)" % (out_path, sheet.width, sheet.height))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(REPO, "reports", "growth-ladder.png"))
    ap.add_argument("--seed", type=int, default=4242)
    ap.add_argument("--frames", default="/tmp/smush_ladder_frames")
    ap.add_argument("--force", action="store_true", help="re-capture every stage")
    ap.add_argument("--montage-only", action="store_true")
    ap.add_argument("--ab", metavar="OUT", default=None,
                    help="capture mass 10 vs 104 at this seed and write a side-by-side sheet")
    args = ap.parse_args()

    os.makedirs(args.frames, exist_ok=True)
    if args.ab:
        for mass in (MASS_KEYS[0], MASS_KEYS[-1]):
            path = os.path.join(args.frames, "ab_%.1f.png" % mass)
            print("ab mass=%.1f" % mass)
            if not capture(mass, args.seed, path):
                print("aborting: mass %.1f did not capture" % mass)
                return 1
        montage_ab(args.frames, args.ab)
        return 0
    if not args.montage_only:
        for i, mass in enumerate(MASS_KEYS):
            stage = i + 1
            path = os.path.join(args.frames, "stage_%02d.png" % stage)
            if os.path.exists(path) and not args.force:
                print("stage %d/%d  cached" % (stage, len(MASS_KEYS)))
                continue
            print("stage %d/%d  mass=%.1f" % (stage, len(MASS_KEYS), mass))
            if not capture(mass, args.seed, path):
                print("aborting: stage %d did not capture" % stage)
                return 1
    montage(args.frames, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
