#!/usr/bin/env python3
"""The lamp of Tyre (data/props/tyre_lamp.json, docs/CHAPTER4.md §2): bought light.

A prop strip for scripts/props/prop.gd and scripts/rooms/lamp.gd, two 24x56
frames: a bronze oil lamp hanging from the hook of an iron post, cold (an
empty wick, green patina), then lit (a small flame and the bronze warmed by
it). The light itself is the game's (a GlowLight, Lamp.RADIUS); this is only
what it hangs on. Drawn pixel by pixel in Tyre's palette — black iron, bronze
gone green at the seams, gold flame — so it stands on a painted floor without
a stock cutout over the painting.

    python3 tools/art/make_tyre_lamp.py

Writes assets/props/tyre_lamp.png. Deterministic (no randomness at all).
"""
import os

from PIL import Image
from studio_overrides import patched  # the art studio's edits of what this writes (tools/studio/overrides)

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "assets", "props", "tyre_lamp.png")

W, H, FRAMES = 24, 56, 2
IRON = (34, 32, 38, 255)
IRON_LIGHT = (66, 62, 70, 255)
BRONZE = (128, 92, 46, 255)
BRONZE_DARK = (84, 58, 30, 255)
BRONZE_LIT = (214, 158, 78, 255)
PATINA = (70, 116, 98, 255)
WICK = (40, 30, 24, 255)
FLAME_OUT = (255, 170, 60, 255)
FLAME = (255, 214, 112, 255)
FLAME_CORE = (255, 246, 214, 255)


def rect(img, x0, y0, x1, y1, colour):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if 0 <= x < img.width and 0 <= y < img.height:
                img.putpixel((x, y), colour)


def post(img, ox):
    """The iron post: a foot on the floor line, a shaft, an arm with a hook."""
    rect(img, ox + 7, 53, ox + 16, 55, IRON)           # the foot
    rect(img, ox + 8, 52, ox + 15, 52, IRON_LIGHT)
    rect(img, ox + 11, 12, ox + 12, 51, IRON)          # the shaft
    rect(img, ox + 11, 12, ox + 11, 51, IRON_LIGHT)
    rect(img, ox + 9, 30, ox + 14, 31, IRON)           # a collar halfway up
    rect(img, ox + 12, 10, ox + 19, 11, IRON)          # the arm
    rect(img, ox + 18, 12, ox + 18, 14, IRON)          # the hook
    rect(img, ox + 10, 9, ox + 13, 9, IRON_LIGHT)      # a finial


def lamp(img, ox, lit):
    """The bronze lamp on the hook: a bowl with a spout, patina in its seams."""
    body = BRONZE_LIT if lit else BRONZE
    rect(img, ox + 15, 15, ox + 21, 15, BRONZE_DARK)   # the chain plate
    rect(img, ox + 14, 16, ox + 22, 19, body)          # the bowl
    rect(img, ox + 14, 19, ox + 22, 19, BRONZE_DARK)
    rect(img, ox + 15, 20, ox + 21, 20, BRONZE_DARK)
    rect(img, ox + 22, 16, ox + 23, 17, body)          # the spout
    for x in (ox + 15, ox + 19):
        img.putpixel((x, 18), PATINA)
    img.putpixel((ox + 17, 20), PATINA)
    img.putpixel((ox + 23, 15), WICK)
    if lit:
        rect(img, ox + 22, 11, ox + 23, 14, FLAME_OUT)
        rect(img, ox + 23, 10, ox + 23, 13, FLAME)
        img.putpixel((ox + 23, 12), FLAME_CORE)
        img.putpixel((ox + 22, 13), FLAME)
        for x in range(ox + 14, ox + 23):              # the bronze warmed from above
            img.putpixel((x, 16), FLAME)


def build():
    img = Image.new("RGBA", (W * FRAMES, H), (0, 0, 0, 0))
    for frame in range(FRAMES):
        ox = frame * W
        post(img, ox)
        lamp(img, ox, frame == 1)
    return img


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    patched(OUT, build()).save(OUT)
    print("wrote", os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()
