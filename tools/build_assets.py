"""Copies and resizes every image the site uses into website/assets. Re-run after swapping a source file.
Run from anywhere: python website/tools/build_assets.py"""
from pathlib import Path
from PIL import Image
import json, shutil, sys

ROOT = Path(__file__).resolve().parents[2]          # KeyChain_Cam
OUT = ROOT / "website" / "assets"
SP = ROOT / "social-posts" / "assets"

def save(src, dst, width, quality=80, crop=None):
    im = Image.open(src)
    im = im.convert("RGBA") if im.mode in ("RGBA", "LA", "P") else im.convert("RGB")
    if crop:  # trim transparent margins
        bbox = im.getbbox() if im.mode == "RGBA" else None
        if bbox: im = im.crop(bbox)
    if im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    dst = OUT / dst
    dst.parent.mkdir(parents=True, exist_ok=True)
    im.save(dst, "WEBP", quality=quality, method=6)
    return im.size

sizes = {}
# Cameras: back-view cut-outs (no supplier print on the front)
cams = {"black": "black-4", "white": "white-3", "red": "red-4", "yellow": "yellow-4",
        "blue": "blue-4", "lime": "green-4", "teal": "dark_green-4", "grey": "gray-4"}
for name, f in cams.items():
    sizes[f"cam/{name}"] = save(SP / "cam" / f"{f}.png", f"cam/{name}.webp", 1000, 85, crop=True)
    save(SP / "cam" / f"{f}.png", f"cam/{name}-sm.webp", 320, 82, crop=True)
for f in ["off-white-back-on", "black-back-on", "off-white-bottom"]:
    sizes[f"cam/{f}"] = save(SP / "cam" / f"{f}.png", f"cam/{f}.webp", 1200, 85, crop=True)

# Sample photos (stock photos through the app's look; illustrative only)
samples = json.loads((ROOT / "app/assets/samples/samples.json").read_text())
for s in samples:
    n = s["file"][:-4]
    save(ROOT / "app/assets/samples" / s["file"], f"photos/{n}.webp", 1280, 78)
    save(ROOT / "app/assets/samples" / s["file"], f"photos/{n}-sm.webp", 640, 76)
(OUT / "photos/samples.json").write_text(json.dumps(samples, indent=1))

# Looks: one sample photo through each look
for k in ["c3", "c3_portra", "c3_gold200", "c3_glow", "c3_trix400", "c3_disposable", "c3_y2k_ccd"]:
    src = SP / ("photos/c3.jpg" if k == "c3" else f"looks/{k}.jpg")
    save(src, f"looks/{k}.webp", 1280, 80)
    save(src, f"looks/{k}-sm.webp", 400, 76)

# App pages rendered by the app's own templates
for p in ["journal_three_note", "journal_solo_note", "us_distance", "us_days", "baby_firstYear", "baby_month",
          "trip_stamps", "trip_photo", "collage_polaroids", "collage_filmStrip", "cafe_stampCard"]:
    sizes[f"app/{p}"] = save(SP / "pages" / f"{p}.png", f"app/{p}.webp", 800, 82)

# Plug-in illustration and ports
save(ROOT / "shopify-images/09-ports.jpg", "misc/ports.webp", 1000, 82)

# Brand
b = OUT / "brand"; b.mkdir(parents=True, exist_ok=True)
for f in ["svg/glimp-wordmark-on-light.svg", "svg/glimp-wordmark-on-dark.svg", "svg/glimp-mark-on-light.svg", "svg/glimp-mark-on-dark.svg",
          "web/favicon.svg", "web/favicon.ico", "web/apple-touch-icon.png", "web/icon-192.png", "web/icon-512.png"]:
    shutil.copy(ROOT / "glimp-brand" / f, b / Path(f).name)

(OUT / "sizes.json").write_text(json.dumps(sizes, indent=1))
print(json.dumps(sizes))

# Hero: the beach-shack sample without the burned-in stamp (the stamp would sit under the headline)
HERO = ROOT / "KeyCam_India_Mini/keycam_look_nostamp/trips/trips__trip_goa__ulKjTA6MaHM.jpg"
save(HERO, "photos/hero.webp", 1920, 80)
save(HERO, "photos/hero-sm.webp", 900, 78)

# Social share image 1200x630: hero photo + white camera
og = Image.open(HERO).convert("RGB")
og = og.resize((1200, round(og.height * 1200 / og.width)), Image.LANCZOS)
top = max(0, (og.height - 630) // 2); og = og.crop((0, top, 1200, top + 630))
cam = Image.open(SP / "cam/off-white-back-on.png").convert("RGBA"); cam = cam.crop(cam.getbbox())
cam = cam.resize((620, round(cam.height * 620 / cam.width)), Image.LANCZOS).rotate(5, expand=True, resample=Image.BICUBIC)
og.paste(cam, (1200 - cam.width - 40, 630 - cam.height - 50), cam)
og.save(OUT / "og-image.jpg", quality=86)

# ── Round 2 (2026-11-13) ─────────────────────────────────────────────
# Every angle of every colour, from the X1 renders (3840 px transparent PNGs).
X1 = ROOT / "X1"
ANGLES = {   # site colour: (X1 folder, file indexes in sorted order)
    # 1 = flat lens side (the default everywhere, user's pick 2026-11-13), then lens 3/4, top,
    # screen side 3/4, screen flat, ports (6), other side, the rest
    "black":  ("black",      [2, 0, 1, 5, 3, 6, 4, 7, 8, 9]),
    "white":  ("off-white",  [2, 0, 1, 5, 3, 6, 4, 7, 8, 9]),
    "red":    ("red",        [2, 0, 1, 5, 3, 6, 4, 7, 8, 9]),
    "yellow": ("yellow",     [2, 0, 1, 5, 3, 6, 4, 7, 8, 9]),
    "blue":   ("blue",       [1, 9, 4, 2, 5, 3, 7, 6, 8]),
    "lime":   ("green",      [2, 0, 1, 6, 3, 7, 5, 8, 10]),
    "teal":   ("dark green", [1, 9, 0, 4, 2, 5, 3, 6, 7, 8]),
    "grey":   ("dark gray",  [2, 0, 1, 5, 3, 6, 4, 7, 8, 9]),
}
gallery = {}
for name, (folder, idx) in ANGLES.items():
    files = sorted((X1 / folder).glob("*.png"))
    gallery[name] = []
    for n, i in enumerate(idx, 1):
        save(files[i], f"gallery/{name}/{n}.webp", 1100, 84, crop=True)
        save(files[i], f"gallery/{name}/{n}-sm.webp", 240, 80, crop=True)
        gallery[name].append(n)
(OUT / "gallery/angles.json").write_text(json.dumps({k: len(v) for k, v in gallery.items()}))

# Candid group photo for the hero (stock photo through the app's look, no stamp)
CANDID = ROOT / "KeyCam_Candid_and_AdRefs/KeyCam_Candid_Friends_India"
HERO2 = ROOT / "KeyCam_Film_Candid/original/UEjjO-aJtZ8.jpg"   # Unsplash, candlelit dinner
save(HERO2, "photos/hero-group.webp", 1600, 80)
save(HERO2, "photos/hero-group-sm.webp", 820, 78)

# Six looks: marketing renders (tools/looks_marketing.py) on two friends at a bar (Unsplash rwrfDpT3qk0)
import subprocess as _sp
_sp.run([sys.executable, str(ROOT / "website/tools/looks_marketing.py"), str(ROOT / "KeyCam_Film_Candid/original/rwrfDpT3qk0.jpg")], check=True)
print("round 2 done")

# ── Round 3 (2026-11-13): the app's new minimal templates, rendered by app/test/chapter_pages_test.dart
TPL = ROOT / "app/build/chapter_pages_test"
for f in sorted(TPL.glob("*_*.png")):
    code = f.stem.split("_")[0]
    if code[0] in "SJTLBCM" and code[1:].isdigit() or code[:2] in ("TR", "LD"):
        save(f, f"templates/{code}.webp", 720, 80)
        save(f, f"templates/{code}-sm.webp", 300, 76)
print("templates done")
