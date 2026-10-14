#!/usr/bin/env python3
"""The weapons' icons (data/weapons, docs/WEAPONS.md).

The realm gear icons the game started with had a sword, an axe, a staff and a
knife — close, but the Headsman's Blade showed an axe and the spear a staff.
So the three weapons that are not the sword have pictures of their own, drawn
by an image model (Codex's image generation) as one sheet on a magenta key:

    tools/art/weapons/weapon_icons_raw.png   spear · headsman's blade · knives

This cuts the sheet into its three shapes (left to right), keys the magenta
out, and brings each down to the realm icons' size — 24 px tall, at most 30
wide, hard-edged alpha — so it sits beside them in the gift list and on the
floor as a WeaponDrop.

    python3 tools/art/make_weapon_icons.py

Writes assets/icons/weapons/<id>.png. Deterministic.
"""
import os

from PIL import Image
from studio_overrides import patched  # the art studio's edits of what this writes (tools/studio/overrides)

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
RAW = os.path.join(os.path.dirname(__file__), "weapons", "weapon_icons_raw.png")
OUT = os.path.join(ROOT, "assets", "icons", "weapons")
## Left to right on the sheet.
IDS = ["spear", "headsman", "daggers"]
H, MAX_W = 24, 30
## The realm icons' outline, and how much brighter than the model drew them they
## must be to stand beside the realm sword on a dark panel.
OUTLINE = (20, 14, 16, 255)
LIFT = 1.25


def keyed(img):
    """Magenta (and the pinkish fringe a model leaves round it) made clear."""
    img = img.convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if r > 90 and b > 90 and r - g > 50 and b - g > 50:
                px[x, y] = (0, 0, 0, 0)
    return img


def columns(img):
    """The x-spans holding something, split on empty columns; the three widest."""
    alpha = img.getchannel("A")
    filled = [alpha.crop((x, 0, x + 1, img.height)).getbbox() is not None for x in range(img.width)]
    spans, start = [], None
    for x, on in enumerate(filled + [False]):
        if on and start is None:
            start = x
        elif not on and start is not None:
            spans.append((start, x))
            start = None
    spans = sorted(sorted(spans, key=lambda s: s[1] - s[0], reverse=True)[:len(IDS)])
    if len(spans) != len(IDS):
        raise SystemExit("expected %d shapes on %s, found %d" % (len(IDS), RAW, len(spans)))
    return spans


def shrink(piece):
    """Down to the icon size by area average, then alpha cut hard."""
    piece = piece.crop(piece.getbbox())
    scale = min((H - 2) / piece.height, (MAX_W - 2) / piece.width)  # room for the outline
    w, h = max(1, round(piece.width * scale)), max(1, round(piece.height * scale))
    small = piece.resize((w, h), Image.BOX)
    px = small.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 110:
                px[x, y] = (0, 0, 0, 0)
            else:  # Pillow averages premultiplied: no key in the colour
                px[x, y] = tuple(min(255, round(c * LIFT)) for c in (r, g, b)) + (255,)
    return outlined(small)


def outlined(small):
    """A one-pixel dark line round the shape, the way the realm icons have one."""
    out = Image.new("RGBA", (small.width + 2, small.height + 2), (0, 0, 0, 0))
    out.paste(small, (1, 1))
    src, px = out.copy().load(), out.load()
    for y in range(out.height):
        for x in range(out.width):
            if src[x, y][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < out.width and 0 <= ny < out.height and src[nx, ny][3]:
                    px[x, y] = OUTLINE
                    break
    return out


def main():
    sheet = keyed(Image.open(RAW))
    os.makedirs(OUT, exist_ok=True)
    for wid, (x0, x1) in zip(IDS, columns(sheet)):
        icon = shrink(sheet.crop((x0, 0, x1, sheet.height)))
        path = os.path.join(OUT, wid + ".png")
        patched(path, icon).save(path, optimize=True)
        print("wrote", os.path.relpath(path, ROOT), icon.size)


if __name__ == "__main__":
    main()
