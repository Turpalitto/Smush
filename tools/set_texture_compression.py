"""Switch Godot texture import compression for 2.5D art (dry run by default).

Usage: python3 tools/set_texture_compression.py [--apply] [--mode 0|1|2|3] [dir ...]
Modes (Godot 4 compress/mode): 0 Lossless, 1 Lossy, 2 VRAM Compressed, 3 VRAM Uncompressed.
For phones use 2 (ASTC/ETC2). The project must also enable
  rendering/textures/vram_compression/import_etc2_astc=true
for the mobile variants to be generated. Not applied automatically: ASTC changes the look of smooth
gradients (banding) and must be judged on a device; run with --apply only after that check.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = sys.argv[1:]
apply = "--apply" in args
mode = 2
if "--mode" in args:
    mode = int(args[args.index("--mode") + 1])
dirs = [a for a in args if not a.startswith("--") and not a.isdigit()] or ["resources/art/2_5d"]
changed = 0
for d in dirs:
    for base, _, files in os.walk(os.path.join(ROOT, d)):
        for f in files:
            if not f.endswith(".png.import"):
                continue
            p = os.path.join(base, f)
            s = open(p).read()
            if re.search(r"^compress/mode=%d$" % mode, s, re.M):
                continue
            changed += 1
            if apply:
                open(p, "w").write(re.sub(r"^compress/mode=\d+$", "compress/mode=%d" % mode, s, flags=re.M))
print(("applied" if apply else "would change"), changed, ".import files to compress/mode=%d" % mode)
