"""WhatsApp thank-you cards: one link-preview image + one tiny page per colour.

The admin's thank-you WhatsApp message ends with https://glimp.in/c/<colour>.
WhatsApp turns that link into a preview showing assets/wa/<colour>.jpg, so the
customer sees the camera they ordered above the message.
Run: python website/tools/build_wa_cards.py
"""
from pathlib import Path
from PIL import Image, ImageFilter

SITE = Path(__file__).resolve().parents[1]
COLOURS = {"white": "White", "red": "Red", "yellow": "Yellow", "teal": "Teal", "grey": "Grey"}
W, H = 1200, 630                 # 1.91:1, the size WhatsApp shows as a large preview
BG = (242, 239, 232)             # warm paper

(SITE / "assets/wa").mkdir(parents=True, exist_ok=True)
for key, name in COLOURS.items():
    cam = Image.open(SITE / f"assets/gallery/{key}/1.webp").convert("RGBA")
    cam = cam.crop(cam.getbbox())
    s = min(W * 0.66 / cam.width, H * 0.58 / cam.height)
    cam = cam.resize((round(cam.width * s), round(cam.height * s)), Image.LANCZOS)
    x, y = (W - cam.width) // 2, (H - cam.height) // 2 - 6

    card = Image.new("RGBA", (W, H), BG + (255,))
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    a = cam.getchannel("A").point(lambda v: v * 0.28)
    shadow.paste((40, 30, 20, 255), (x, y + 22), a)
    card = Image.alpha_composite(card, shadow.filter(ImageFilter.GaussianBlur(22)))
    card.alpha_composite(cam, (x, y))
    card.convert("RGB").save(SITE / f"assets/wa/{key}.jpg", "JPEG", quality=86, optimize=True, progressive=True)

    page = SITE / f"c/{key}/index.html"
    page.parent.mkdir(parents=True, exist_ok=True)
    page.write_text(f"""<!doctype html>
<html lang="en-IN">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Your Glimp · {name}</title>
<meta name="robots" content="noindex">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Glimp">
<meta property="og:title" content="Your Glimp · {name}">
<meta property="og:description" content="Core memories, the old-school way.">
<meta property="og:url" content="https://glimp.in/c/{key}/">
<meta property="og:image" content="https://glimp.in/assets/wa/{key}.jpg">
<meta property="og:image:type" content="image/jpeg">
<meta property="og:image:width" content="{W}"><meta property="og:image:height" content="{H}">
<meta name="twitter:card" content="summary_large_image">
<meta http-equiv="refresh" content="0; url=/">
<link rel="icon" href="/assets/brand/favicon.svg" type="image/svg+xml">
</head>
<body><a href="/">glimp.in</a></body>
</html>
""", encoding="utf-8")
    print(key, (SITE / f"assets/wa/{key}.jpg").stat().st_size // 1024, "KB")
