"""Seamless caustic tile for the lake water prototype (code-made placeholder, not painted art).

Usage: python3 tools/make_caustic_tile.py [out.png] [size]
Periodic Worley noise: caustics are the bright network where two nearest feature points are almost
equally far (F2 - F1 small). Two scales are summed so the lines are not too regular.
"""
import sys

import numpy as np
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "resources/art/2_5d/water/caustic_tile.png"
SIZE = int(sys.argv[2]) if len(sys.argv) > 2 else 256


def worley_edges(size, cells, seed):
    rng = np.random.default_rng(seed)
    pts = rng.random((cells, cells, 2))
    ys, xs = np.mgrid[0:size, 0:size] / size * cells
    f1 = np.full((size, size), 9.0)
    f2 = np.full((size, size), 9.0)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            for cy in range(cells):
                for cx in range(cells):
                    px = cx + ox * cells + pts[cy, cx, 0]
                    py = cy + oy * cells + pts[cy, cx, 1]
                    d = np.hypot(xs - px, ys - py)
                    new_f2 = np.minimum(f2, np.maximum(f1, d))
                    f1 = np.minimum(f1, d)
                    f2 = new_f2
    edge = np.clip(1.0 - (f2 - f1) * 3.2, 0.0, 1.0)
    return edge ** 1.6


a = worley_edges(SIZE, 7, 11)
b = worley_edges(SIZE, 11, 23)
img = np.clip(a * 0.7 + b * 0.5, 0.0, 1.0)
img = img / img.max()
Image.fromarray((img * 255).astype(np.uint8), "L").save(OUT)
print("saved", OUT, SIZE)
