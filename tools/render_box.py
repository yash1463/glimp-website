"""'In the box' render: an open Glimp box, top-down, with the camera, micro SD card, cable and phone
converter sitting in a felt tray. Transparent background so it sits on the page in light and dark mode.

usage: python website/tools/render_box.py  →  website/assets/misc/in-the-box.webp (+ -sm)
"""
from pathlib import Path
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "website/assets/misc"
SS = 2                                    # supersample
W, H = 2400 * SS, 1800 * SS


def s(v): return int(round(v * SS))


def layer(): return Image.new("RGBA", (W, H), (0, 0, 0, 0))


def rrect(d, box, r, **kw): d.rounded_rectangle([s(v) for v in box], radius=s(r), **kw)


def shadow(mask, blur, offset, alpha):
    a = mask.split()[-1].filter(ImageFilter.GaussianBlur(s(blur)))
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sh.putalpha(a.point(lambda v: int(v * alpha)))
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.paste(sh, (s(offset[0]), s(offset[1])), sh)
    return out


def inner_shadow(base, box, r, depth=18, alpha=.75):
    """Darken the inside edge of a recessed slot (light from the top left)."""
    m = Image.new("L", (W, H), 0)
    rrect(ImageDraw.Draw(m), box, r, fill=255)
    edge = Image.new("L", (W, H), 0)
    rrect(ImageDraw.Draw(edge), [box[0] + depth * .6, box[1] + depth * .8, box[2] + depth * .2, box[3] + depth * .3], r, fill=255)
    ring = ImageChops.subtract(m, edge).filter(ImageFilter.GaussianBlur(s(depth * .55)))
    ring = ImageChops.multiply(ring, m)
    dark = Image.new("RGBA", (W, H), (0, 0, 0, 0)); dark.putalpha(ring.point(lambda v: int(v * alpha)))
    base.alpha_composite(dark)


def paste_obj(canvas, obj, xy, rot=0, sh=(22, (10, 16), .55)):
    o = obj.rotate(rot, resample=Image.BICUBIC, expand=True) if rot else obj
    lay = layer(); lay.paste(o, (s(xy[0]) - o.width // 2, s(xy[1]) - o.height // 2), o)
    canvas.alpha_composite(shadow(lay, sh[0], sh[1], sh[2]))
    canvas.alpha_composite(lay)


# ---------- objects ----------
def micro_sd(w=120, h=164):
    im = Image.new("RGBA", (s(w), s(h)), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    poly = [(0, s(18)), (s(14), 0), (s(w), 0), (s(w), s(h)), (0, s(h)), (0, s(70)), (s(8), s(62)), (s(8), s(46)), (0, s(40))]
    d.polygon(poly, fill=(26, 26, 28, 255))
    for i in range(8):                                       # gold contacts
        x = s(18 + i * 12)
        d.rounded_rectangle([x, s(8), x + s(8), s(34)], radius=s(2), fill=(205, 170, 92, 255))
    d.rectangle([s(14), s(64), s(w - 12), s(h - 14)], fill=(42, 42, 46, 255))
    d.rectangle([s(14), s(118), s(w - 12), s(128)], fill=(227, 162, 26, 255))   # stripe label in brand colours
    d.rectangle([s(14), s(128), s(w - 12), s(138)], fill=(224, 102, 42, 255))
    d.rectangle([s(14), s(138), s(w - 12), s(148)], fill=(199, 55, 42, 255))
    return im


def usb_c_plug(d, x, y, w=56, h=26):                         # metal type-C tip, centred vertically on y
    rrect(d, [x, y - h / 2, x + w, y + h / 2], h / 2, fill=(188, 190, 195, 255))
    rrect(d, [x + h * .35, y - h * .1, x + w - h * .35, y + h * .1], h * .1, fill=(96, 98, 103, 255))
    d.line([s(x + 2), s(y - h / 2 + 3), s(x + w - 4), s(y - h / 2 + 3)], fill=(235, 236, 238, 255), width=s(2))


def converter(w=320, h=120):
    im = Image.new("RGBA", (s(w), s(h)), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    rrect(d, [0, 8, w - 84, h - 8], 18, fill=(236, 235, 231, 255))             # white body
    rrect(d, [4, 10, w - 88, h - 30], 16, fill=(250, 249, 247, 255))
    rrect(d, [18, 30, 46, h - 30], 4, fill=(46, 46, 50, 255))                 # USB-A socket
    d.rectangle([s(26), s(38), s(36), s(h - 38)], fill=(238, 238, 238, 255))
    rrect(d, [w - 90, 24, w - 78, h - 24], 4, fill=(220, 219, 214, 255))     # collar
    usb_c_plug(d, w - 80, h / 2, 76, 40)
    return im


def cable():
    w, h = 470, 380
    im = Image.new("RGBA", (s(w), s(h)), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    cx, cy = 235, 200
    for i, (rx, ry, a0) in enumerate([(150, 118, 0), (138, 108, 25), (126, 98, 50)]):   # three loose loops
        pts = [(cx + rx * math.cos(math.radians(t + a0)) + i * 6, cy + ry * math.sin(math.radians(t + a0)) - i * 4) for t in range(0, 361, 4)]
        d.line([(s(x), s(y)) for x, y in pts], fill=(214, 212, 207, 255), width=s(15), joint="curve")
        d.line([(s(x), s(y)) for x, y in pts], fill=(246, 245, 242, 255), width=s(10), joint="curve")
    # USB-A end
    rrect(d, [cx + 100, 40, cx + 170, 92], 10, fill=(246, 245, 242, 255))
    rrect(d, [cx + 170, 44, cx + 228, 88], 3, fill=(196, 198, 202, 255))
    d.rectangle([s(cx + 184), s(56), s(cx + 194), s(64)], fill=(120, 122, 126, 255))
    d.rectangle([s(cx + 208), s(56), s(cx + 218), s(64)], fill=(120, 122, 126, 255))
    d.line([s(cx + 70), s(90), s(cx + 105), s(66)], fill=(246, 245, 242, 255), width=s(10))
    # type-C end
    rrect(d, [cx - 210, 290, cx - 150, 330], 12, fill=(246, 245, 242, 255))
    usb_c_plug(d, cx - 262, 310, 54, 24)
    d.line([s(cx - 150), s(310), s(cx - 110), s(290)], fill=(246, 245, 242, 255), width=s(10))
    return im


def strap():
    w, h = 220, 360
    im = Image.new("RGBA", (s(w), s(h)), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    pts = [(110 + 62 * math.sin(math.radians(t)), 150 + 120 * math.cos(math.radians(t))) for t in range(0, 361, 3)]
    d.line([(s(x), s(y)) for x, y in pts], fill=(122, 118, 112, 255), width=s(15), joint="curve")   # grey cord loop
    d.line([(s(x - 2), s(y - 2)) for x, y in pts[20:70]], fill=(170, 166, 160, 255), width=s(3))     # sheen
    rrect(d, [92, 262, 128, 304], 8, fill=(28, 28, 30, 255))                                        # crimp
    d.ellipse([s(80), s(296), s(140), s(356)], outline=(190, 192, 197, 255), width=s(7))            # split ring
    d.arc([s(84), s(300), s(136), s(352)], 200, 320, fill=(240, 241, 243, 255), width=s(2))
    return im


def camera(colour="white", width=760):
    src = Image.open(ROOT / "website/assets/gallery" / colour / "1.webp").convert("RGBA")
    return src.resize((s(width), s(round(width * src.height / src.width))), Image.LANCZOS)


def logo_card(w, h, r, fill, mark_w, at=None):
    im = Image.new("RGBA", (s(w), s(h)), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    rrect(d, [0, 0, w, h], r, fill=fill)
    mark = Image.open(ROOT / "glimp-brand/png/glimp-wordmark-on-light@2x.png").convert("RGBA")
    mark = mark.resize((s(mark_w), s(round(mark_w * mark.height / mark.width))), Image.LANCZOS)
    pos = ((im.width - mark.width) // 2, (im.height - mark.height) // 2) if at is None else (s(at[0]), s(at[1]))
    im.alpha_composite(mark, pos)
    return im


# ---------- scene ----------
def render(colour="white"):
    c = layer()
    # lid, lying open behind the tray
    lid = logo_card(1240, 860, 22, (239, 234, 225, 255), 380, at=(780, 70))
    ld = ImageDraw.Draw(lid)
    rrect(ld, [0, 0, 1240, 860], 22, outline=(222, 215, 203, 255), width=s(6))
    paste_obj(c, lid, (1560, 640), rot=-7, sh=(30, (14, 22), .45))

    # tray: outer wall + felt floor
    tx0, ty0, tx1, ty1 = 210, 560, 1590, 1500
    tray = layer(); td = ImageDraw.Draw(tray)
    rrect(td, [tx0, ty0, tx1, ty1], 26, fill=(239, 234, 225, 255))            # box wall (same paper as the lid)
    rrect(td, [tx0 + 26, ty0 + 26, tx1 - 26, ty1 - 26], 14, fill=(30, 28, 27, 255))   # felt insert
    c.alpha_composite(shadow(tray, 34, (16, 26), .6)); c.alpha_composite(tray)
    inner_shadow(c, [tx0 + 26, ty0 + 26, tx1 - 26, ty1 - 26], 14, depth=26, alpha=.55)

    # recessed slots
    slots = {"cam": [270, 640, 1110, 1000], "sd": [1170, 640, 1320, 840], "conv": [1170, 880, 1530, 1000],
             "cable": [270, 1060, 790, 1440], "strap": [850, 1060, 1110, 1440], "card": [1170, 1060, 1530, 1440]}
    sl = layer(); sd_ = ImageDraw.Draw(sl)
    for k, b in slots.items():
        rrect(sd_, b, 12, fill=(21, 20, 19, 255))
    c.alpha_composite(sl)
    for b in slots.values():
        inner_shadow(c, b, 12, depth=16, alpha=.8)

    # objects in their slots
    paste_obj(c, camera(colour, 780), (690, 820), sh=(16, (6, 10), .7))
    paste_obj(c, micro_sd(), (1245, 740), rot=0, sh=(8, (3, 5), .7))
    paste_obj(c, converter(), (1350, 940), sh=(8, (3, 5), .7))
    paste_obj(c, strap(), (980, 1250), rot=-6, sh=(8, (3, 5), .7))
    paste_obj(c, cable(), (530, 1250), sh=(10, (4, 6), .6))
    note = logo_card(320, 340, 8, (247, 244, 238, 255), 220)
    nd = ImageDraw.Draw(note)
    for i, col in enumerate([(227, 162, 26, 255), (224, 102, 42, 255), (199, 55, 42, 255)]):
        nd.rectangle([s(30), s(270 + i * 12), s(290), s(278 + i * 12)], fill=col)
    paste_obj(c, note, (1350, 1250), rot=1.5, sh=(8, (3, 5), .6))

    bbox = c.getbbox(); c = c.crop(bbox)
    return c.resize((c.width // SS, c.height // SS), Image.LANCZOS)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    im = render("white")
    im.save(OUT / "in-the-box.webp", "WEBP", quality=88, method=6)
    im.resize((900, round(900 * im.height / im.width)), Image.LANCZOS).save(OUT / "in-the-box-sm.webp", "WEBP", quality=86, method=6)
    print(im.size)
