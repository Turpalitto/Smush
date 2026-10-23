#!/usr/bin/env python3
"""Generate the seamless enchanted-forest floor tile used under the arena.

The creatures are painted, but the ground they stand on was a flat two-colour
gradient, which is what made the arena read as empty. This script draws a real
floor instead: moss cushions, bare soil patches, fibrous moss streaks, lichen
speckles, pebbles and root veins.

Everything here is *periodic by construction*: every noise field is sampled from
a wrapping lattice, and every stamped blob is wrapped with a modulo, so the tile
can be repeated by the shader with no visible grid. The script measures that
claim instead of trusting it (see `seam_report`) — the same way the music
generator measures its loop seam.

Colours stay dark and low-contrast on purpose: the floor must sit behind the
gameplay, not compete with the sprites.

Usage:
    python3 tools/generate_floor_texture.py [output.png] [--size 1024] [--seed 7]
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image

# Palette (linear-ish sRGB values, kept dark so sprites stay readable).
SOIL = np.array([0.062, 0.086, 0.076], dtype=np.float32)
MOSS_DARK = np.array([0.082, 0.150, 0.118], dtype=np.float32)
MOSS_LIGHT = np.array([0.175, 0.300, 0.225], dtype=np.float32)
LICHEN = np.array([0.255, 0.470, 0.390], dtype=np.float32)
PEBBLE = np.array([0.190, 0.200, 0.215], dtype=np.float32)
ROOT = np.array([0.030, 0.038, 0.034], dtype=np.float32)


def _smoothstep(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
    """Smoothstep that also works with edge0 > edge1 (a descending ramp).

    The usual `(x-e0)/(e1-e0)` form silently inverts when the edges are passed in
    the other order, which is how the first version of this script stamped every
    pebble as a bright square with a hole in it.
    """
    denom = edge1 - edge0
    if abs(denom) < 1e-6:
        return (x >= edge1).astype(np.float32)
    t = np.clip((x - edge0) / denom, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def periodic_value_noise(size: int, cells_x: int, cells_y: int, rng: np.random.Generator) -> np.ndarray:
    """Bilinear value noise on a lattice that wraps at `size` pixels."""
    lattice = rng.random((cells_y, cells_x)).astype(np.float32)

    xs = (np.arange(size, dtype=np.float32) * cells_x) / size
    ys = (np.arange(size, dtype=np.float32) * cells_y) / size
    x0 = np.floor(xs).astype(np.int32) % cells_x
    y0 = np.floor(ys).astype(np.int32) % cells_y
    x1 = (x0 + 1) % cells_x
    y1 = (y0 + 1) % cells_y
    fx = xs - np.floor(xs)
    fy = ys - np.floor(ys)
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)

    v00 = lattice[np.ix_(y0, x0)]
    v10 = lattice[np.ix_(y0, x1)]
    v01 = lattice[np.ix_(y1, x0)]
    v11 = lattice[np.ix_(y1, x1)]
    top = v00 + (v10 - v00) * fx[np.newaxis, :]
    bottom = v01 + (v11 - v01) * fx[np.newaxis, :]
    return top + (bottom - top) * fy[:, np.newaxis]


def fbm(size: int, base_cells: int, octaves: int, rng: np.random.Generator,
        aspect: float = 1.0, gain: float = 0.5) -> np.ndarray:
    """Sum of wrapping octaves; `aspect` stretches the lattice on X."""
    total = np.zeros((size, size), dtype=np.float32)
    amplitude = 1.0
    norm = 0.0
    cells = max(1, int(base_cells))
    for _ in range(octaves):
        cx = max(1, int(round(cells * aspect)))
        total += amplitude * periodic_value_noise(size, cx, cells, rng)
        norm += amplitude
        amplitude *= gain
        cells = min(size, cells * 2)
    return total / max(1e-6, norm)


def stamp_wrapped(buf: np.ndarray, cx: float, cy: float, patch: np.ndarray) -> None:
    """Add `patch` centred at (cx, cy), wrapping across both tile edges.

    Works for both scalar and RGB patches (2D or 3D).
    """
    n = buf.shape[0]
    ph, pw = patch.shape[:2]
    y0 = int(round(cy)) - ph // 2
    x0 = int(round(cx)) - pw // 2
    ys = (np.arange(ph) + y0) % n
    xs = (np.arange(pw) + x0) % n
    buf[np.ix_(ys, xs)] += patch


def soft_disc(radius: float, feather: float = 0.45) -> np.ndarray:
    r = int(math.ceil(radius)) + 1
    yy, xx = np.mgrid[-r:r + 1, -r:r + 1].astype(np.float32)
    d = np.sqrt(xx * xx + yy * yy)
    inner = radius * (1.0 - feather)
    return _smoothstep(radius, inner, d).astype(np.float32)


def draw_pebbles(buf_rgb: np.ndarray, height: np.ndarray, rng: np.random.Generator, count: int) -> None:
    n = buf_rgb.shape[0]
    for _ in range(count):
        cx, cy = rng.uniform(0, n), rng.uniform(0, n)
        rx = rng.uniform(8.0, 20.0)
        ry = rx * rng.uniform(0.55, 0.9)
        r = int(math.ceil(rx)) + 2
        yy, xx = np.mgrid[-r:r + 1, -r:r + 1].astype(np.float32)
        # Slight rotation keeps the stones from all pointing the same way.
        ang = rng.uniform(0, math.pi)
        xr = xx * math.cos(ang) + yy * math.sin(ang)
        yr = -xx * math.sin(ang) + yy * math.cos(ang)
        d = (xr / rx) ** 2 + (yr / ry) ** 2
        mask = _smoothstep(1.0, 0.45, d) * rng.uniform(0.55, 0.95)
        if mask.max() <= 0.01:
            continue
        shade = rng.uniform(0.8, 1.1)
        # Lit from above-left: brighten the top edge, darken the bottom.
        lift = np.clip(-yr / max(1e-3, ry), -1.0, 1.0) * 0.18
        colour = np.clip(PEBBLE * shade + lift[..., np.newaxis], 0.0, 1.0)
        stamp_wrapped(buf_rgb, cx, cy, mask[..., np.newaxis] * colour)
        # A stone is a dome, not a disc: height follows sqrt(1 - d) so the normal
        # map gets a rounded top instead of a flat plateau with a cliff edge.
        dome = np.sqrt(np.clip(1.0 - d, 0.0, 1.0)) * mask
        stamp_wrapped(height, cx, cy, dome * 0.9)


def draw_lichen(buf_rgb: np.ndarray, height: np.ndarray, rng: np.random.Generator, count: int) -> None:
    """Sparse soft spores. Kept dim: bright specks read as dirt or snow at 1:1."""
    n = buf_rgb.shape[0]
    for _ in range(count):
        cx, cy = rng.uniform(0, n), rng.uniform(0, n)
        radius = rng.uniform(4.0, 10.0)
        mask = soft_disc(radius, feather=0.95) * rng.uniform(0.12, 0.30)
        stamp_wrapped(buf_rgb, cx, cy, mask[..., np.newaxis] * LICHEN)
        stamp_wrapped(height, cx, cy, mask * 0.12)


def draw_roots(ridge: np.ndarray, strength: float = 0.55) -> np.ndarray:
    """Thin dark veins where the ridged noise peaks."""
    line = _smoothstep(0.86, 0.995, ridge) * strength
    return line


def generate(size: int = 1024, seed: int = 7, grain: float = 0.8) -> tuple[np.ndarray, np.ndarray, dict]:
    """Return (albedo, height, stats).

    Height is built from the same fields as the colour, so the relief lines up with
    what the eye reads as a stone, a moss cushion or a root groove. It is what the
    normal map and Blender's ambient-occlusion bake are made from.
    """
    rng = np.random.default_rng(seed)

    # --- Macro layout: where the moss grows and where bare soil shows through.
    # Large cells on purpose: the player sees roughly 1.5 tiles across a phone
    # screen, so anything finer than ~80 px is just noise at that scale.
    # `warp` is drawn before anything else and used as a low-frequency swell, which
    # keeps the noise sequence (and therefore the approved colour) stable.
    warp = fbm(size, 2, 2, rng) - 0.5
    macro = fbm(size, 3, 3, rng)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    patch = _smoothstep(0.34, 0.66, macro * 0.75 + fbm(size, 6, 2, rng) * 0.25)

    # Gentle fibres: moss grows in strands, but strong anisotropy turns into
    # horizontal banding once the tile repeats, so this stays a soft accent.
    fibres = fbm(size, 11, 3, rng, aspect=0.55, gain=0.5)
    fibres = _smoothstep(0.42, 0.78, fibres)

    # --- Fine grain. Everything above this line is deliberately large-scale, and
    # the first version stopped here: the tile measured a respectable 34% relative
    # contrast, but all of it was in soft ~200 px patches, so at 1:1 on a phone the
    # floor read as a smooth teal gradient with a few pebbles on it. These two
    # fields are the missing band: clumps of moss roughly 20 px across and a finer
    # speckle at ~10 px, which is what the eye actually recognises as moss.
    clumps = _smoothstep(0.28, 0.74, fbm(size, 46, 3, rng, gain=0.55))
    speck = _smoothstep(0.30, 0.70, fbm(size, 96, 2, rng, gain=0.6))

    # --- Base colour: soil -> dark moss -> lit moss.
    col = SOIL[None, None, :] * (1.0 - patch[..., None])
    col += MOSS_DARK[None, None, :] * patch[..., None]
    col += (MOSS_LIGHT - MOSS_DARK)[None, None, :] * (patch * fibres)[..., None] * 0.85

    # A little large-scale luminance drift so tiled repeats don't read as a grid.
    drift = fbm(size, 2, 2, rng)
    col *= (0.86 + 0.26 * drift)[..., None]

    # --- Grain, applied multiplicatively so the hue survives: adding a fraction of
    # MOSS_LIGHT-MOSS_DARK instead pushed dark soil up as much as it pushed moss,
    # which turned the tile into camouflage. Biased below 1.0 because the gaps
    # between clumps are shadowed, not lit.
    shade = 1.0 + ((clumps - 0.58) * 0.85 + (speck - 0.58) * 0.38) * grain
    col *= (1.0 + (shade - 1.0) * patch)[..., None]

    # --- Height: moss cushions sit proud of bare soil, and the fibres ripple.
    height = 0.30 * patch + 0.16 * fibres * patch
    # The same grain in relief, so the normal map and the AO bake agree with the
    # colour instead of leaving it looking painted on.
    height += ((clumps - 0.5) * 0.075 + (speck - 0.5) * 0.035) * grain
    height += (fbm(size, 14, 3, rng) - 0.5) * 0.10
    height += (drift - 0.5) * 0.10
    height += warp * 0.10

    # --- Root veins: a groove in the floor and a dark line in the colour.
    ridge = 1.0 - np.abs(2.0 * fbm(size, 4, 3, rng) - 1.0)
    ridge2 = 1.0 - np.abs(2.0 * fbm(size, 7, 2, rng) - 1.0)
    root_line = draw_roots(ridge, 0.26) + draw_roots(ridge2, 0.14)
    col *= (1.0 - root_line)[..., None]
    height -= root_line * 0.55

    # --- Pebbles and lichen.
    draw_pebbles(col, height, rng, count=14)
    draw_lichen(col, height, rng, count=70)

    # --- Grain: per-pixel dither keeps gradients from banding after scaling.
    grain = (rng.random((size, size, 1)).astype(np.float32) - 0.5) * 0.006
    col = col + grain

    col = np.clip(col, 0.0, 1.0)
    # Rescale instead of clipping: a pebble that saturates at 1.0 bakes a flat
    # plateau into the normal map, and a clipped groove loses its dark line.
    lo, hi = float(height.min()), float(height.max())
    height = (height - lo) / max(1e-6, hi - lo) * 0.92 + 0.04
    stats = {
        "mean": float(col.mean()),
        "std": float(col.std()),
        "max": float(col.max()),
        "patch_coverage": float((patch > 0.5).mean()),
        "fibre_contrast": float(fibres.std()),
        "height_mean": float(height.mean()),
        "height_range": float(height.max() - height.min()),
    }
    return col, height, stats


def height_to_normal(height: np.ndarray, strength: float = 26.0) -> np.ndarray:
    """Tangent-space normal map from a height field, wrapping at the tile edges.

    Godot's canvas space has +Y pointing down, so the screen-space light in the
    shader points up-left as (-x, -y) — the gradient is negated to match.
    """
    # Central differences on a wrapped grid: roll() is what keeps the tile seamless.
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5 * strength
    nz = np.ones_like(height)
    length = np.sqrt(dx * dx + dy * dy + nz * nz)
    normal = np.stack([-dx / length, -dy / length, nz / length], axis=-1)
    return (normal * 0.5 + 0.5).astype(np.float32)


def seam_report(rgb: np.ndarray) -> dict:
    """Compare the wrap seam against ordinary neighbour differences.

    A tile is seamless when the step across the border is statistically the same
    as the step between two adjacent interior pixels. Comparing against the p99
    interior step (not the mean) keeps one busy patch from masking a seam.
    """
    n = rgb.shape[0]
    lum = rgb.mean(axis=2)

    h_steps = np.abs(np.diff(lum, axis=1))
    v_steps = np.abs(np.diff(lum, axis=0))
    interior = np.concatenate([h_steps.ravel(), v_steps.ravel()])
    p99 = float(np.percentile(interior, 99.0))
    mean = float(interior.mean())

    seam_h = float(np.abs(lum[:, 0] - lum[:, -1]).mean())
    seam_v = float(np.abs(lum[0, :] - lum[-1, :]).mean())
    return {
        "seam_h": seam_h,
        "seam_v": seam_v,
        "interior_mean": mean,
        "interior_p99": p99,
        "ratio": max(seam_h, seam_v) / max(1e-9, p99),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", nargs="?", default="resources/art/environment/forest_floor.png")
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--preview", default="", help="write a 2x2 tiled, screen-scale preview here")
    parser.add_argument("--normal-strength", type=float, default=26.0)
    parser.add_argument("--grain", type=float, default=0.8,
                        help="amplitude of the fine moss grain, 0 disables it")
    args = parser.parse_args()

    rgb, height, stats = generate(args.size, args.seed, args.grain)
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)

    img = Image.fromarray((rgb * 255.0 + 0.5).astype(np.uint8), mode="RGB")
    img.save(out, optimize=True)

    # Height and normal share the albedo's tile grid, so all three can be
    # sampled with the same world-space UV. The normal map ships; the height map
    # is build-time input for the Blender AO bake and would only bloat the pack,
    # so it goes into a `_source` folder that carries a .gdignore.
    source_dir = out.parent / "_source"
    source_dir.mkdir(parents=True, exist_ok=True)
    (source_dir / ".gdignore").write_text("", encoding="utf-8")
    height_png = source_dir / (out.stem + "_height.png")
    Image.fromarray((height * 255.0 + 0.5).astype(np.uint8), mode="L").save(height_png)

    normal = height_to_normal(height, args.normal_strength)
    normal_png = out.with_name(out.stem + "_normal.png")
    Image.fromarray((normal * 255.0 + 0.5).astype(np.uint8), mode="RGB").save(normal_png)

    seam = seam_report(rgb)
    print(f"wrote {out}  {args.size}x{args.size}  {out.stat().st_size / 1024:.0f} KiB")
    print(f"  mean luminance {stats['mean']:.4f}  std {stats['std']:.4f}  max {stats['max']:.3f}  "
          f"moss coverage {stats['patch_coverage'] * 100:.0f}%")
    print(f"  height mean {stats['height_mean']:.3f}  range {stats['height_range']:.3f}  "
          f"-> {height_png.name}, {normal_png.name}")
    print(f"  seam: h {seam['seam_h']:.4f}  v {seam['seam_v']:.4f}  "
          f"interior mean {seam['interior_mean']:.4f}  p99 {seam['interior_p99']:.4f}  "
          f"ratio {seam['ratio']:.2f}")

    if args.preview:
        # What the player actually sees: two tiles across, downsampled to phone width.
        tiled = np.tile(rgb, (2, 2, 1))
        target = 620
        img2 = Image.fromarray((tiled * 255.0 + 0.5).astype(np.uint8), mode="RGB")
        img2 = img2.resize((target, target), Image.LANCZOS)
        pv = Path(args.preview)
        pv.parent.mkdir(parents=True, exist_ok=True)
        img2.save(pv)
        print(f"  preview {pv}")

    if seam["ratio"] > 1.0:
        print("  ! seam is larger than the p99 interior step — the tile will show a grid")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
