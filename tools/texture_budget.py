"""Estimate GPU texture memory of the 2.5D art (no device needed).

Usage: python3 tools/texture_budget.py [dir ...]
Per PNG: uncompressed RGBA8 with mipmaps (x1.33), ASTC 6x6 (3.56 bits/px) and ASTC 4x4 (8 bits/px) estimates, ETC2 RGBA (8 bits/px).
Godot's Mobile renderer keeps textures VRAM-compressed only if the import mode is "VRAM Compressed" and the project enables
ETC2/ASTC import (rendering/textures/vram_compression/import_etc2_astc); this tool only reports what each choice would cost.
"""
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
dirs = sys.argv[1:] or ["resources/art/2_5d"]
MIP = 4.0 / 3.0


def mb(b):
    return b / (1024.0 * 1024.0)


groups = {}
for d in dirs:
    for base, _, files in os.walk(os.path.join(ROOT, d)):
        for f in files:
            if not f.endswith(".png"):
                continue
            p = os.path.join(base, f)
            rel = os.path.relpath(base, os.path.join(ROOT, d))
            top = rel.split(os.sep)[0] if rel != "." else "(root)"
            w, h = Image.open(p).size
            raw = w * h * 4 * MIP
            astc6 = w * h * (3.56 / 8.0) * MIP
            astc4 = w * h * 1.0 * MIP
            g = groups.setdefault(top, [0, 0.0, 0.0, 0.0])
            g[0] += 1
            g[1] += raw
            g[2] += astc6
            g[3] += astc4
tot = [0, 0.0, 0.0, 0.0]
print("%-12s %5s %10s %10s %10s" % ("group", "files", "RGBA8 MB", "ASTC6x6", "ASTC4x4"))
for k, g in sorted(groups.items(), key=lambda kv: -kv[1][1]):
    print("%-12s %5d %10.1f %10.1f %10.1f" % (k, g[0], mb(g[1]), mb(g[2]), mb(g[3])))
    for i in range(4):
        tot[i] += g[i]
print("%-12s %5d %10.1f %10.1f %10.1f" % ("TOTAL", tot[0], mb(tot[1]), mb(tot[2]), mb(tot[3])))
