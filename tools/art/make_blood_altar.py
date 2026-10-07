#!/usr/bin/env python3
"""The blood altar (data/props/blood_altar.json): a trade, not a chest.

A prop strip for scripts/props/prop.gd, four 40x40 frames: a squat stone font
with a bowl of dark blood in it (the blood catching a little light), then the
bowl lit as the hand is cut over it, then the blood drunk down to a red stain.
Drawn here pixel by pixel in the crypts' palette — grey stone, black blood,
the ember red of the cult — so it stands on a painted floor without a stock
cutout over the painting.

    python3 tools/art/make_blood_altar.py

Writes assets/props/blood_altar.png. Deterministic (no randomness at all).
"""
import os

from PIL import Image
from studio_overrides import patched  # the art studio's edits of what this writes (tools/studio/overrides)

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "assets", "props", "blood_altar.png")

W, H, FRAMES = 40, 40, 4
STONE = (92, 88, 96, 255)
STONE_DARK = (58, 54, 62, 255)
STONE_LIGHT = (128, 122, 130, 255)
MOSS = (64, 78, 58, 255)
BLOOD = (70, 8, 14, 255)
BLOOD_LIT = (150, 22, 30, 255)
BLOOD_GLINT = (230, 90, 80, 255)
STAIN = (96, 30, 34, 255)
EMBER = (255, 120, 80, 255)


def rect(img, x0, y0, x1, y1, colour):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if 0 <= x < img.width and 0 <= y < img.height:
                img.putpixel((x, y), colour)


def font(img, ox):
    """The stone: a stepped foot on the floor line, a narrow stem, a wide bowl."""
    rect(img, ox + 9, 36, ox + 30, 39, STONE_DARK)      # the foot
    rect(img, ox + 10, 35, ox + 29, 35, STONE)
    rect(img, ox + 15, 24, ox + 24, 34, STONE)          # the stem
    rect(img, ox + 15, 24, ox + 15, 34, STONE_DARK)
    rect(img, ox + 24, 24, ox + 24, 34, STONE_DARK)
    rect(img, ox + 19, 26, ox + 20, 32, STONE_LIGHT)    # a worn edge catching light
    rect(img, ox + 6, 17, ox + 33, 23, STONE)           # the bowl
    rect(img, ox + 6, 23, ox + 33, 23, STONE_DARK)
    rect(img, ox + 7, 17, ox + 32, 17, STONE_LIGHT)
    for x in (ox + 9, ox + 14, ox + 26, ox + 30):        # chisel marks
        img.putpixel((x, 20), STONE_DARK)
    for x in range(ox + 10, ox + 14):                    # moss in the foot's shadow
        img.putpixel((x, 38), MOSS)
    for x in range(ox + 27, ox + 30):
        img.putpixel((x, 37), MOSS)


def blood(img, ox, colour, glint, level):
    """The blood in the bowl, [level] pixels deep from its rim."""
    rect(img, ox + 8, 18, ox + 31, 18 + level, colour)
    if glint:
        img.putpixel((ox + 13, 18), glint)
        img.putpixel((ox + 14, 18), glint)


def drips(img, ox):
    """The cut: drops falling into the bowl, an ember spark over it."""
    for y in (9, 12, 15):
        img.putpixel((ox + 20, y), BLOOD_LIT)
    img.putpixel((ox + 19, 6), EMBER)
    img.putpixel((ox + 21, 4), EMBER)


def main():
    img = Image.new("RGBA", (W * FRAMES, H), (0, 0, 0, 0))
    for frame in range(FRAMES):
        font(img, frame * W)
    blood(img, 0, BLOOD, BLOOD_GLINT, 2)          # idle: dark, a glint
    blood(img, W, BLOOD_LIT, BLOOD_GLINT, 2)      # the hand over it
    drips(img, W)
    blood(img, W * 2, BLOOD_LIT, EMBER, 1)        # drinking it down
    drips(img, W * 2)
    rect(img, W * 3 + 9, 18, W * 3 + 30, 18, STAIN)  # spent: a stain on the rim
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    patched(OUT, img).save(OUT)
    print("wrote", os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()
