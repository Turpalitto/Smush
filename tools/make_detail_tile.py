"""Turn a generated 'seamless' texture into a true seamless high-pass detail tile.

Usage: python3 tools/make_detail_tile.py <in.png> <out.png> [size]
1. cross-blend the image with itself shifted by half the size (hides AI seams),
2. subtract a wrap-around blur (keeps only fine detail, zero-mean),
3. store as 0.5-centred RGB so a shader can add (tex - 0.5) on top of a macro plate.
"""
import sys

import numpy as np
from PIL import Image, ImageFilter


def seamless(img):
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    h, w, _ = a.shape
    shifted = np.roll(np.roll(a, h // 2, 0), w // 2, 1)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    # weight is 1 at the centre of the original, 0 on its borders (where the seam is)
    wy = 1.0 - np.abs(yy / (h - 1) * 2.0 - 1.0)
    wx = 1.0 - np.abs(xx / (w - 1) * 2.0 - 1.0)
    m = (np.minimum(wx, wy) ** 0.7)[..., None]
    out = a * m + shifted * (1.0 - m)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def wrap_blur(img, radius):
    pad = int(radius * 3)
    big = Image.fromarray(np.pad(np.asarray(img), ((pad, pad), (pad, pad), (0, 0)), mode="wrap"))
    big = big.filter(ImageFilter.GaussianBlur(radius))
    return big.crop((pad, pad, pad + img.width, pad + img.height))


def main():
    src, dst = sys.argv[1], sys.argv[2]
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
    img = Image.open(src).convert("RGB").resize((size, size), Image.LANCZOS)
    img = seamless(img)
    low = wrap_blur(img, size / 24.0)
    hp = np.asarray(img).astype(np.float32) - np.asarray(low).astype(np.float32)
    out = np.clip(128.0 + hp * 1.0, 0, 255).astype(np.uint8)
    Image.fromarray(out).save(dst)
    print("detail tile", dst, size)


main()
