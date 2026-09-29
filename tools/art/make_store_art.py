#!/usr/bin/env python3
"""Store art, composed from the game rather than drawn for the store.

Every shop wants its own rectangle: itch.io a 630x500 cover, Google Play a
1024x500 feature graphic, and both of them shrink it to a thumbnail the
moment anybody browses. A cover that only reads at full size is a cover
nobody reads.

So the rule here is the same as the web loading page's: no new art. The
backdrop is `graveyard_moon_wide`, the figure is Elian's own idle frame, and
the title is Forum, the face the menu is set in. What changes per rectangle
is the crop and where the figure stands — a wide graphic wants him off to one
side with the graveyard running past him, a squarer one wants him centred.

    python3 tools/art/make_store_art.py

Deterministic: same art in, byte-identical PNGs out. Pillow's zlib build can
differ between machines, which tools/check_generators.py reports as a
recompression rather than a change.
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "docs", "store")

BACKDROP = os.path.join(ROOT, "assets", "levels", "graveyard_moon_wide.png")
SPRITE = os.path.join(ROOT, "assets", "sprites", "elian_idle.png")
TITLE_FONT = os.path.join(ROOT, "assets", "fonts", "Forum-Regular.ttf")

GOLD = (232, 200, 122)
BONE = (207, 199, 184)
ASH = (13, 12, 11)

TITLE = "ASHES OF EDEN"
TAGLINE = "They hanged him. He got up anyway."

## (file, width, height, where the figure stands across the frame, his height
## as a fraction of the frame, title size, tagline size or 0 for none).
## A thumbnail drops the tagline before it drops the name.
SHEETS = [
    ("itch_cover.png", 630, 500, 0.50, 0.46, 58, 19),
    ("play_feature.png", 1024, 500, 0.74, 0.52, 76, 26),
]


def backdrop(width, height, focus_x):
    """The panel, cover-cropped, centred on the part we want kept."""
    art = Image.open(BACKDROP).convert("RGB")
    scale = max(width / art.width, height / art.height)
    art = art.resize((round(art.width * scale), round(art.height * scale)),
                     Image.LANCZOS)
    # Keep the moon in frame: it sits in the panel's right third, and a
    # centre crop of a 2.2:1 panel into a 1.26:1 cover throws it away.
    left = round((art.width - width) * focus_x)
    top = (art.height - height) // 2
    return art.crop((left, top, left + width, top + height))


def veil(img, figure_x):
    """Darken for legibility: a band at the top for the name, a floor at the
    bottom for the figure, and a soft hole where the figure actually is so he
    does not come out as dark as the ground he stands on."""
    w, h = img.size
    yy, xx = np.mgrid[0:h, 0:w]
    top = np.interp(yy / h, [0, .34, .62, 1], [.80, .34, .30, .86])
    edge = np.interp(np.abs(xx / w - figure_x), [0, .18, .55], [0, .06, .30])
    a = np.clip(top + edge, 0, .92)[..., None]
    px = np.asarray(img).astype(np.float32)
    out = px * (1 - a) + np.array(ASH, np.float32) * a
    return Image.fromarray(out.astype(np.uint8))


def hero(height):
    """One idle frame, trimmed and enlarged by a whole number."""
    frame = Image.open(SPRITE).crop((0, 0, 128, 64))
    frame = frame.crop(frame.getbbox())
    scale = max(1, round(height / frame.height))
    return frame.resize((frame.width * scale, frame.height * scale), Image.NEAREST)


def tracked(draw, text, font, tracking, cx, y, fill, shadow=True):
    """Pillow has no letter-spacing, and the menu's title has plenty."""
    widths = [draw.textlength(c, font=font) for c in text]
    total = sum(widths) + tracking * (len(text) - 1)
    x = cx - total / 2
    for char, width in zip(text, widths):
        if shadow:
            draw.text((x + 2, y + 2), char, font=font, fill=(0, 0, 0))
        draw.text((x, y), char, font=font, fill=fill)
        x += width + tracking


def compose(name, w, h, figure_x, figure_h, title_px, tagline_px):
    img = veil(backdrop(w, h, figure_x), figure_x)

    man = hero(round(h * figure_h))
    foot = round(h * 0.90)
    at = (round(w * figure_x - man.width / 2), foot - man.height)

    # Something to stand on. The panel behind him is a place; he is a cut-out.
    shade = Image.new("L", (man.width, max(6, man.height // 12)), 0)
    ImageDraw.Draw(shade).ellipse((0, 0, shade.width - 1, shade.height - 1), fill=150)
    shade = shade.filter(ImageFilter.GaussianBlur(shade.height / 2))
    img.paste(ASH, (at[0], foot - shade.height // 2), shade)
    img.paste(man, at, man)

    draw = ImageDraw.Draw(img)
    title = ImageFont.truetype(TITLE_FONT, title_px)
    tracked(draw, TITLE, title, title_px * 0.14, w / 2, round(h * 0.09), GOLD)
    if tagline_px:
        small = ImageFont.truetype(TITLE_FONT, tagline_px)
        tracked(draw, TAGLINE, small, tagline_px * 0.06, w / 2,
                round(h * 0.09) + round(title_px * 1.5), BONE)

    path = os.path.join(OUT, name)
    img.save(path, "PNG", optimize=True)
    return path, os.path.getsize(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, w, h, fx, fh, title_px, tagline_px in SHEETS:
        path, size = compose(name, w, h, fx, fh, title_px, tagline_px)
        print("%s — %dx%d, %d KB" % (os.path.relpath(path, ROOT), w, h, size // 1024))


if __name__ == "__main__":
    main()
