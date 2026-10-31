#!/usr/bin/env python3
"""Crop the centre of a lab frame and upscale for inspection: claude_crop.py in out [half=170] [scale=2]"""
import sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
half = int(sys.argv[3]) if len(sys.argv) > 3 else 170
scale = int(sys.argv[4]) if len(sys.argv) > 4 else 2
im = Image.open(src).convert("RGB")
w, h = im.size
c = im.crop((w // 2 - half, h // 2 - half, w // 2 + half, h // 2 + half))
c = c.resize((c.width * scale, c.height * scale), Image.LANCZOS)
c.save(dst)
