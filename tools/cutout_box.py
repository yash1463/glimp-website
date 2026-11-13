"""Cut the outer black background off the packaging render so it sits on the page in light and dark mode.
Only black connected to the image edges is removed, so the dark felt inside the box stays solid.

usage: python website/tools/cutout_box.py "Retro Camera Box with Silver Chain.png"
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
src = Image.open(sys.argv[1]).convert("RGB")
a = np.asarray(src, dtype=np.int16)
dark = Image.fromarray(np.where(a.max(axis=2) < 34, 255, 0).astype(np.uint8)).copy()   # near-black pixels (copy: writable)
h, w = a.shape[:2]
for x, y in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)] + [(x, 0) for x in range(0, w, 64)] + [(x, h - 1) for x in range(0, w, 64)]         + [(0, y) for y in range(0, h, 64)] + [(w - 1, y) for y in range(0, h, 64)]:
    if dark.getpixel((x, y)) == 255:
        ImageDraw.floodfill(dark, (x, y), 128)              # black that touches the border = background
bg = np.asarray(dark) == 128
alpha = np.where(bg, 0, 255).astype(np.uint8)
alpha = Image.fromarray(alpha).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.2))   # clean, soft edge
im = src.convert("RGBA"); im.putalpha(alpha)
im = im.crop(im.getbbox())
out = ROOT / "website/assets/misc"
im.save(out / "in-the-box.webp", "WEBP", quality=88, method=6)
im.resize((900, round(900 * im.height / im.width)), Image.LANCZOS).save(out / "in-the-box-sm.webp", "WEBP", quality=86, method=6)
print(im.size)
