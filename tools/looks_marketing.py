"""Marketing renders of the six looks for the website.

Starts from the app's real looks (lab/retro.py Engine) and pushes each one further for the page:
more strength, plus grain, halation, bloom, flash falloff or digicam crispness. The app itself stays subtle;
these are only for showing the character of each look at a glance.

usage: python website/tools/looks_marketing.py <source photo> [out_dir]
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lab"))
from retro import Engine  # noqa: E402

rng = np.random.default_rng(7)


def arr(im): return np.asarray(im.convert("RGB"), dtype=np.float32) / 255
def img(x): return Image.fromarray((np.clip(x, 0, 1) * 255 + .5).astype(np.uint8))
def luma(x): return x[..., 0] * .2126 + x[..., 1] * .7152 + x[..., 2] * .0722
def blur(x, r): return arr(img(x).filter(ImageFilter.GaussianBlur(r)))


def amplify(src, look, k):            # push the app's look further in the same direction
    return np.clip(src + k * (look - src), 0, 1)


def grain(x, amt, size=1.0):
    h, w = x.shape[:2]
    n = rng.normal(0, 1, (int(h / size), int(w / size))).astype(np.float32)
    n = np.asarray(Image.fromarray(n).resize((w, h), Image.BILINEAR))
    mid = 1 - np.abs(luma(x) - .5) * 1.4          # grain shows most in the midtones, like film
    return np.clip(x + (n * amt * mid)[..., None], 0, 1)


def halation(x, amt, r, thr=.72, color=(1., .42, .2)):
    m = np.clip((luma(x) - thr) / (1 - thr), 0, 1)
    glow = blur(np.repeat(m[..., None], 3, 2), r)
    return np.clip(x + glow * np.array(color) * amt, 0, 1)


def bloom(x, amt, r):
    b = blur(x, r)
    return 1 - (1 - x) * (1 - b * amt)            # screen blend


def vignette(x, amt, power=2.2):
    h, w = x.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2) / np.sqrt(2)
    return x * (1 - amt * d ** power)[..., None]


def curve(x, lift=0., contrast=0., gamma=1.):
    x = lift + (1 - lift) * x
    x = np.clip(x, 1e-4, 1) ** gamma
    if contrast:
        x = x + contrast * (x - .5) * (1 - np.abs(2 * x - 1))   # soft S curve
    return np.clip(x, 0, 1)


def flash(x, amt):                                  # on-camera flash: bright centre, fast falloff
    h, w = x.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.sqrt(((xx - w * .5) / (w * .55)) ** 2 + ((yy - h * .45) / (h * .6)) ** 2)
    f = np.clip(1.25 - d, 0, 1) ** 1.5
    return np.clip(x * (1 - amt * .45) + x * f[..., None] * amt * .9, 0, 1)


def sharpen(x, amt, r=1.2):
    return np.clip(x + amt * (x - blur(x, r)), 0, 1)


def neutralise(x, amount=.55):
    """Pull a strongly tinted photo part-way to neutral so each look shows its own colour."""
    m = x.reshape(-1, 3).mean(0)
    gain = (m.mean() / m) ** amount
    return np.clip(x * gain, 0, 1)


def render(src_im):
    eng = Engine()
    s0 = arr(src_im)
    s = neutralise(s0)
    base = img(s)
    L = lambda k: arr(eng.process(base, k, None, seed=7))
    out = {"original": s0}

    x = amplify(s, L("portra"), 1.6) * np.array([1.03, 1.0, .95])
    x = curve(x, lift=.035, contrast=.06)
    x = halation(x, .12, 14); x = grain(x, .014, 1.2); out["portra"] = vignette(x, .15)

    x = amplify(s, L("gold200"), 1.6) * np.array([1.05, 1.0, .88])
    x = halation(x, .16, 18, thr=.68); x = bloom(x, .12, 22)
    x = curve(x, contrast=.08); x = grain(x, .015, 1.3); out["gold200"] = vignette(x, .2)

    x = amplify(s, L("glow"), 1.5)
    x = bloom(x, .38, 30); x = curve(x, lift=.07, contrast=-.08) * np.array([1.02, .99, 1.04])
    out["glow"] = grain(x, .01, 1.1)

    x = L("trix400")
    x = curve(x, contrast=.28, gamma=1.03)
    x = grain(x, .035, 1.4); out["trix400"] = vignette(x, .25)

    # Flash is built from the clean photo: the app's preset adds heavy grain to night scenes
    x = s * np.array([.95, 1.0, 1.06])                                   # cool, clean flash white
    g = luma(x)[..., None]; x = g + (x - g) * 1.12                       # a little punchier colour
    x = curve(x, gamma=.8); x = flash(x, .32)                            # lift the subject, quick falloff
    x = curve(x, contrast=.2); x = sharpen(x, .35)
    x = halation(x, .08, 8); x = grain(x, .01, 1.1); out["disposable"] = vignette(x, .24, 1.8)

    x = amplify(s, L("y2k_ccd"), 1.6) * np.array([.86, .99, 1.16])
    g = luma(x)[..., None]; x = g + (x - g) * .85                      # thinner CCD colour
    x = curve(x, contrast=.12, gamma=.9); x = sharpen(x, .8)
    out["y2k_ccd"] = grain(x, .008, .8)
    return {k: img(v) for k, v in out.items()}


if __name__ == "__main__":
    src = Image.open(sys.argv[1]).convert("RGB")
    out_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "website/assets/looks"
    if src.width > 1920:
        src = src.resize((1920, round(src.height * 1920 / src.width)), Image.LANCZOS)
    th = round(src.width * 9 / 16); top = (src.height - th) // 2
    src = src.crop((0, top, src.width, top + th))
    out_dir.mkdir(parents=True, exist_ok=True)
    for k, im in render(src).items():
        im.save(out_dir / f"look_{k}.webp", "WEBP", quality=82, method=6)
        im.resize((400, round(400 * im.height / im.width)), Image.LANCZOS).save(out_dir / f"look_{k}-sm.webp", "WEBP", quality=78, method=6)
        print(k)
