"""Process the painted water kit (ChatGPT, art_sources/2_5d/raw/water) into runtime assets.

Usage: python3 tools/process_water_kit.py
- lake_plate.png / shore_plate.png -> resources/art/2_5d/water/ (copied as is)
- caustic_tile.png -> seamless grayscale high-contrast tile (cross-blend, like make_detail_tile.py)
- ripples_sheet.png (2x2) and foam_sheet.png (3x2), drawn on pure black for additive blending ->
  RGBA sprites whose alpha is the brightness, cropped, in resources/art/2_5d/water/fx/
"""
import os
import shutil

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "art_sources", "2_5d", "raw", "water")
OUT = os.path.join(ROOT, "resources", "art", "2_5d", "water")
FX = os.path.join(OUT, "fx")
UW = os.path.join(OUT, "uw")
GR = os.path.join(OUT, "gr")
LG = os.path.join(OUT, "legend")
os.makedirs(LG, exist_ok=True)
os.makedirs(GR, exist_ok=True)
os.makedirs(FX, exist_ok=True)
os.makedirs(UW, exist_ok=True)

for n in ("lake_plate", "shore_plate", "gr_floor_plate", "gr_transition_plate"):
    shutil.copy(os.path.join(RAW, n + ".png"), os.path.join(OUT, n + ".png"))


def seamless(a):
    """Cross-blend a wrapped copy so the edges meet (a is HxW float)."""
    h, w = a.shape
    sx = np.roll(a, w // 2, axis=1)
    sy = np.roll(a, h // 2, axis=0)
    sxy = np.roll(sx, h // 2, axis=0)
    wx = np.minimum(np.arange(w), w - 1 - np.arange(w)) / (w / 2.0)
    wy = np.minimum(np.arange(h), h - 1 - np.arange(h)) / (h / 2.0)
    mx = np.clip(wx * 1.0, 0, 1)[None, :]
    my = np.clip(wy * 1.0, 0, 1)[:, None]
    top = a * mx + sx * (1 - mx)
    bot = sy * mx + sxy * (1 - mx)
    return top * my + bot * (1 - my)


c = Image.open(os.path.join(RAW, "caustic_tile.png")).convert("L").resize((512, 512), Image.LANCZOS)
a = np.asarray(c).astype(np.float32) / 255.0
a = seamless(a)
lo, hi = np.percentile(a, 20), np.percentile(a, 99.5)
a = np.clip((a - lo) / (hi - lo), 0, 1) ** 1.6   # keep the bright light lines, drop the flat water body
Image.fromarray((a * 255).astype(np.uint8), "L").save(os.path.join(OUT, "caustic_tile_painted.png"))


def cut_additive(sheet, cols, rows, names, gain=1.6, pad=6, outdir=None):
    outdir = outdir or FX
    im = Image.open(os.path.join(RAW, sheet)).convert("RGB")
    arr = np.asarray(im).astype(np.float32) / 255.0
    h, w, _ = arr.shape
    for i, name in enumerate(names):
        cx, cy = i % cols, i // cols
        cell = arr[cy * h // rows:(cy + 1) * h // rows, cx * w // cols:(cx + 1) * w // cols]
        lum = cell.max(axis=2)
        alpha = np.clip(lum * gain, 0, 1)
        ys, xs = np.where(lum > 0.06)
        if len(xs) == 0:
            continue
        box = (max(xs.min() - pad, 0), max(ys.min() - pad, 0), min(xs.max() + pad + 1, cell.shape[1]), min(ys.max() + pad + 1, cell.shape[0]))
        # un-premultiply colour so additive blending with alpha gives the painted brightness
        rgb = cell / np.maximum(alpha[..., None], 0.05)
        rgb = np.clip(rgb, 0, 1)
        out = np.dstack([rgb, alpha])[box[1]:box[3], box[0]:box[2]]
        Image.fromarray((out * 255).astype(np.uint8), "RGBA").save(os.path.join(outdir, name + ".png"))
        print(name, out.shape[1], out.shape[0])


cut_additive("ripples_sheet.png", 2, 2, ["ripple_small", "ripple_medium", "ripple_large", "splash_ring"])
cut_additive("foam_sheet.png", 3, 2, ["wake_curve", "wake_v", "splash_crown", "bubbles", "foam_patch", "glints"])


# underwater kit (step 3): additive roots, light rays and glowing creatures on black; seabed plate -> seamless tile
cut_additive("uw_roots_sheet.png", 3, 2, ["uw_roots_violet_web", "uw_roots_cyan_web", "uw_root_loop", "uw_root_fan", "uw_spores", "uw_root_knot"], outdir=UW)
cut_additive("uw_rays_sheet.png", 3, 2, ["uw_ray_wide", "uw_ray_narrow", "uw_rays_three", "uw_light_patch", "uw_particles", "uw_ray_fan"], gain=1.3, outdir=UW)
cut_additive("uw_jelly_sheet.png", 3, 2, ["uw_jelly_big", "uw_jelly_cyan", "uw_jelly_pink_pair", "uw_plankton", "uw_snail", "uw_spirit"], outdir=UW)

sb = Image.open(os.path.join(RAW, "seabed_plate.png")).convert("RGB")
sa = np.asarray(sb).astype(np.float32) / 255.0
chs = [seamless(sa[..., c]) for c in range(3)]
Image.fromarray((np.clip(np.dstack(chs), 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, "seabed_tile.png"))

# flooded grove (step 4): additive fireflies on black
cut_additive("gr_fireflies_sheet.png", 3, 2, ["gr_fireflies_yellow", "gr_fireflies_cyan", "gr_sparks_gold", "gr_fireflies_pink", "gr_wisp_violet", "gr_moth_cyan"], outdir=GR)

# legends (rare spirits, auras, Lunar Nova): additive sheets on black
for sheet, names, gain in [
    ("lg_aura_sheet.png", ["lg_aura_moon", "lg_aura_flame", "lg_aura_prism", "lg_aura_star", "lg_aura_aurora", "lg_aura_pearl"], 1.4),
    ("lg_nova_sheet.png", ["lg_nova_ring", "lg_nova_burst", "lg_nova_vortex", "lg_nova_cracks", "lg_nova_column", "lg_nova_crescent"], 1.3),
    ("lg_spirit_sheet.png", ["lg_spirit_moth", "lg_spirit_sun", "lg_spirit_glass", "lg_spirit_loom", "lg_spirit_ribbon", "lg_spirit_pearl"], 1.5),
]:
    if os.path.exists(os.path.join(RAW, sheet)):
        cut_additive(sheet, 3, 2, names, gain=gain, outdir=LG)
