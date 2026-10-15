#!/usr/bin/env python3
"""The chain ring (data/props/chain.json, docs/CHAPTER6.md §9): what a chained
body in the monastery on the Euphrates is held to.

A prop strip for scripts/props/prop.gd, three 32x32 frames: an iron ring
leaded into a block of floor stone with the chain's first links lying from it
(the rest of the chain is drawn by scripts/enemies/tether.gd, to the body);
the same with a spark off the iron where a blade rang on it; and the ring
opened by the abbot's keys, the shackle sprung and the links slack on the
stone. Drawn here pixel by pixel in the abbey's palette — river-grey stone,
dark wet iron with a cold glint — so it stands on a painted floor without a
stock cutout over the painting.

    python3 tools/art/make_chain_ring.py

Writes assets/props/chain_ring.png. Deterministic (no randomness at all).
"""
import os

from PIL import Image
from studio_overrides import patched  # the art studio's edits of what this writes (tools/studio/overrides)

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "assets", "props", "chain_ring.png")

W, H, FRAMES = 32, 32, 3
STONE = (96, 98, 104, 255)
STONE_DARK = (60, 62, 70, 255)
STONE_LIGHT = (132, 134, 140, 255)
LEAD = (78, 80, 92, 255)
IRON = (90, 90, 98, 255)       # the chain's own colour in tether.gd (#5a5a62)
IRON_DARK = (44, 44, 52, 255)
GLINT = (207, 214, 230, 255)   # tether.gd's GLINT
SPARK = (255, 236, 180, 255)
RUST = (112, 70, 50, 255)


def px(img, x, y, colour):
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), colour)


def rect(img, x0, y0, x1, y1, colour):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px(img, x, y, colour)


def block(img, ox):
    """A squat block of floor stone, its foot on the bottom row, lead poured round the staple."""
    rect(img, ox + 6, 25, ox + 25, 31, STONE)
    rect(img, ox + 6, 31, ox + 25, 31, STONE_DARK)
    rect(img, ox + 6, 25, ox + 6, 31, STONE_DARK)
    rect(img, ox + 25, 25, ox + 25, 31, STONE_DARK)
    rect(img, ox + 7, 25, ox + 24, 25, STONE_LIGHT)
    for x in (ox + 9, ox + 21):                     # chisel marks
        px(img, x, 28, STONE_DARK)
    rect(img, ox + 13, 24, ox + 18, 25, LEAD)       # the lead the staple is set in


def ring(img, ox, open_):
    """The ring on its staple: an iron hoop 8 px across standing up off the block."""
    cx, top = ox + 15, 14
    hoop = [(0, 0), (1, 0), (2, 0), (-1, 1), (3, 1), (-2, 2), (4, 2), (-2, 3), (4, 3),
            (-2, 4), (4, 4), (-2, 5), (4, 5), (-1, 6), (3, 6), (0, 7), (1, 7), (2, 7)]
    for dx, dy in hoop:
        if open_ and dx >= 3 and dy <= 4:
            continue                                # sprung: the right side of the hoop is gone
        px(img, cx + dx - 1, top + dy, IRON)
        px(img, cx + dx - 1, top + dy + 1, IRON_DARK)
    px(img, cx - 2, top + 1, GLINT)
    rect(img, cx, top + 8, cx + 1, 24, IRON_DARK)   # the staple down into the lead
    rect(img, cx, top + 8, cx, 23, IRON)
    if open_:
        px(img, cx + 3, top + 5, RUST)              # where the bolt sat


def links(img, ox, slack):
    """The chain's first links off the ring, lying toward the body (to the right)."""
    x, y = ox + 18, 20 if not slack else 23
    for i in range(4):
        lx, ly = x + i * 3, y + (i if slack else i // 2)
        if i % 2 == 0:
            rect(img, lx, ly, lx + 2, ly, IRON)
            rect(img, lx, ly + 1, lx + 2, ly + 1, IRON_DARK)
        else:
            px(img, lx + 1, ly - 1, IRON)
            px(img, lx + 1, ly, IRON_DARK)
            px(img, lx + 1, ly + 1, IRON)
    px(img, x + 1, y, GLINT)


def spark(img, ox):
    """A blade rang on it: a star of sparks off the hoop."""
    cx, cy = ox + 13, 13
    for dx, dy in [(0, 0), (-2, -1), (2, -2), (-3, 1), (3, 0), (0, -3), (1, 2)]:
        px(img, cx + dx, cy + dy, SPARK)
    px(img, cx, cy, (255, 255, 255, 255))


def main():
    img = Image.new("RGBA", (W * FRAMES, H), (0, 0, 0, 0))
    for frame in range(FRAMES):
        ox = frame * W
        block(img, ox)
        ring(img, ox, frame == 2)
        links(img, ox, frame == 2)
    spark(img, W)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    patched(OUT, img).save(OUT)
    print("wrote", os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()
