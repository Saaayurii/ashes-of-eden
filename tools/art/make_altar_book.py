#!/usr/bin/env python3
"""The book under the church altar (docs/CHAPTER1.md, Matthew's book).

A prop strip for scripts/props/prop.gd, four 40x32 frames: the book shut on
its cloth (with a glint on the clasp), the cover lifting, half open, open on
the page of names. Drawn here pixel by pixel in the church's palette — old
leather, tarnished brass, vellum gone the colour of tallow — so it sits
beside the altar without a stock cutout over the painting.

    python3 tools/art/make_altar_book.py

Writes assets/props/altar_book.png. Deterministic (no randomness at all).
"""
import math
import os

from PIL import Image
from studio_overrides import patched  # the art studio's edits of what this writes (tools/studio/overrides)

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "assets", "props", "altar_book.png")

W, H, FRAMES = 40, 32, 4
CLOTH = (92, 28, 34, 255)
CLOTH_DARK = (62, 18, 24, 255)
CLOTH_EDGE = (150, 116, 60, 255)
LEATHER = (74, 44, 30, 255)
LEATHER_DARK = (48, 28, 20, 255)
LEATHER_LIGHT = (104, 66, 42, 255)
BRASS = (178, 140, 70, 255)
BRASS_LIGHT = (236, 206, 130, 255)
PAGE = (222, 204, 162, 255)
PAGE_SHADE = (186, 166, 124, 255)
INK = (70, 52, 44, 255)
RED_INK = (140, 36, 30, 255)


def rect(img, x0, y0, x1, y1, colour):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if 0 <= x < img.width and 0 <= y < img.height:
                img.putpixel((x, y), colour)


def cloth(img, ox):
    """The altar cloth the book lies on: a fringed runner on the floor line."""
    rect(img, ox + 6, 27, ox + 33, 30, CLOTH)
    rect(img, ox + 6, 30, ox + 33, 30, CLOTH_DARK)
    for x in range(ox + 6, ox + 34, 2):
        img.putpixel((x, 27), CLOTH_EDGE)  # the embroidered hem
    for x in range(ox + 7, ox + 33, 3):
        img.putpixel((x, 31 - 1), CLOTH_EDGE)  # the fringe


def shut(img, ox, glint):
    """The book closed: a thick leather block, a brass clasp and corners."""
    rect(img, ox + 9, 20, ox + 30, 26, LEATHER)
    rect(img, ox + 9, 26, ox + 30, 26, LEATHER_DARK)
    rect(img, ox + 10, 21, ox + 29, 21, LEATHER_LIGHT)
    rect(img, ox + 31, 21, ox + 31, 26, PAGE_SHADE)  # the page edges at the fore-edge
    for corner in [(ox + 9, 20), (ox + 30, 20), (ox + 9, 26), (ox + 30, 26)]:
        img.putpixel(corner, BRASS)
    rect(img, ox + 18, 22, ox + 21, 24, BRASS)  # the boss on the cover
    img.putpixel((ox + 19, 23), BRASS_LIGHT if glint else BRASS)
    rect(img, ox + 29, 22, ox + 32, 23, BRASS)  # the clasp
    if glint:
        img.putpixel((ox + 31, 22), BRASS_LIGHT)
        img.putpixel((ox + 32, 21), BRASS_LIGHT)


def lifting(img, ox, angle):
    """The lower board and the pages, the cover swung up [angle] degrees on
    its spine (the left edge), drawn as a two-pixel board."""
    rect(img, ox + 9, 24, ox + 30, 26, LEATHER_DARK)
    rect(img, ox + 10, 23, ox + 29, 24, PAGE)
    rect(img, ox + 10, 24, ox + 29, 24, PAGE_SHADE)
    length = 21
    rad = math.radians(angle)
    for step in range(length * 3 + 1):
        t = step / 3.0
        x = ox + 9 + t * math.cos(rad)
        y = 22 - t * math.sin(rad)
        img.putpixel((round(x), round(y)), LEATHER)
        img.putpixel((round(x), round(y) + 1), LEATHER_DARK)
    tip = (round(ox + 9 + length * math.cos(rad)), round(22 - length * math.sin(rad)))
    img.putpixel(tip, BRASS)


def open_book(img, ox):
    """Open on the page of names: two leaves, lines of ink, one name in red."""
    rect(img, ox + 6, 24, ox + 33, 26, LEATHER_DARK)  # the boards, flat
    rect(img, ox + 7, 21, ox + 19, 24, PAGE)
    rect(img, ox + 20, 21, ox + 32, 24, PAGE)
    rect(img, ox + 19, 21, ox + 20, 24, PAGE_SHADE)  # the gutter
    rect(img, ox + 7, 24, ox + 32, 24, PAGE_SHADE)
    for y in (22, 23):
        for x in range(ox + 8, ox + 18):
            if (x + y) % 3:
                img.putpixel((x, y), INK)
    for x in range(ox + 21, ox + 31):
        if x % 3:
            img.putpixel((x, 22), INK)
    for x in range(ox + 21, ox + 27):
        img.putpixel((x, 23), RED_INK)  # the name written last
    for corner in [(ox + 6, 26), (ox + 33, 26)]:
        img.putpixel(corner, BRASS)


def main():
    img = Image.new("RGBA", (W * FRAMES, H), (0, 0, 0, 0))
    for frame in range(FRAMES):
        cloth(img, frame * W)
    shut(img, 0, glint=True)
    lifting(img, W * 1, 22)
    lifting(img, W * 2, 62)
    open_book(img, W * 3)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    patched(OUT, img).save(OUT)
    print("wrote", os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()
