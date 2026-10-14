#!/usr/bin/env python3
"""The garden's small things (docs/CHAPTER5.md §2, §4): the fruit Elian may
pick, the broken ropes under Ahithophel's fig, the key of the pit.

Prop strips for scripts/props/prop.gd, drawn here pixel by pixel in the
garden's palette so they sit on the paintings without a stock cutout:

    engedi_fig.png          2 frames 24x24: a sprig of figs, swaying
    engedi_grapes.png       2 frames 24x24: a hanging cluster
    engedi_pomegranate.png  2 frames 24x24: two pomegranates on a twig
    engedi_feast_dish.png   2 frames 40x24: a laden dish, its glint moving
    engedi_pit_key.png      2 frames 24x16: a copper key, its glint moving (the
                            finale's scripted "npc" pit_key)

and assets/decor/engedi_broken_ropes.png (48x12), cut ropes lying on the
ground under the fig — decor in the room's table, never hanging, no hitbox.

    python3 tools/art/make_engedi_props.py

Deterministic (no randomness at all).
"""
import os

from PIL import Image
from studio_overrides import patched  # the art studio's edits of what this writes (tools/studio/overrides)

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "assets", "props")

LEAF = (78, 112, 52, 255)
LEAF_DARK = (48, 76, 34, 255)
LEAF_LIGHT = (122, 156, 74, 255)
TWIG = (88, 62, 40, 255)
FIG = (106, 58, 90, 255)
FIG_DARK = (70, 36, 62, 255)
FIG_LIGHT = (150, 96, 128, 255)
GRAPE = (90, 58, 106, 255)
GRAPE_DARK = (56, 34, 72, 255)
GRAPE_LIGHT = (146, 112, 168, 255)
POM = (176, 48, 58, 255)
POM_DARK = (116, 28, 38, 255)
POM_LIGHT = (226, 112, 100, 255)
CROWN = (210, 160, 90, 255)
DISH = (186, 140, 70, 255)
DISH_DARK = (120, 84, 40, 255)
DISH_LIGHT = (240, 210, 140, 255)
BREAD = (200, 160, 100, 255)
ROPE = (164, 136, 92, 255)
ROPE_DARK = (110, 88, 58, 255)
ROPE_END = (196, 176, 136, 255)
COPPER = (184, 112, 56, 255)
COPPER_DARK = (116, 64, 30, 255)
COPPER_LIGHT = (246, 196, 124, 255)


def put(img, x, y, colour):
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), colour)


def rect(img, x0, y0, x1, y1, colour):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            put(img, x, y, colour)


def disc(img, cx, cy, r, colour, dark, light):
    """A round fruit: shaded on the lower right, a glint on the upper left."""
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            dx, dy = x - cx, y - cy
            if dx * dx + dy * dy <= r * r + r * 0.6:
                c = colour
                if dx + dy >= r * 0.9:
                    c = dark
                put(img, x, y, c)
    put(img, cx - max(1, r // 2), cy - max(1, r // 2), light)


def leaf(img, x, y, flip):
    """A three-row leaf, its tip toward [flip]."""
    d = -1 if flip else 1
    for i in range(5):
        put(img, x + i * d, y, LEAF if i < 4 else LEAF_LIGHT)
    for i in range(1, 4):
        put(img, x + i * d, y - 1, LEAF_LIGHT)
        put(img, x + i * d, y + 1, LEAF_DARK)


def fig(img, ox, sway):
    rect(img, ox + 11, 2, ox + 12, 7, TWIG)
    leaf(img, ox + 10, 5, True)
    leaf(img, ox + 13, 4, False)
    for cx, cy in [(8, 13), (15, 12), (12, 18)]:
        x = ox + cx + sway
        rect(img, x, cy - 5, x, cy - 3, TWIG)
        disc(img, x, cy, 3, FIG, FIG_DARK, FIG_LIGHT)
        put(img, x, cy + 3, FIG_DARK)  # the eye at the foot of a fig


def grapes(img, ox, sway):
    rect(img, ox + 12, 1, ox + 12, 5, TWIG)
    leaf(img, ox + 11, 3, True)
    leaf(img, ox + 13, 2, False)
    rows = [(6, [8, 11, 14, 17]), (9, [9, 12, 15]), (12, [8, 11, 14, 17]), (15, [10, 13, 16]), (18, [11, 14]), (21, [12])]
    for y, xs in rows:
        for x in xs:
            disc(img, ox + x + sway * (y // 8), y, 1, GRAPE, GRAPE_DARK, GRAPE_LIGHT)
            put(img, ox + x + sway * (y // 8) + 1, y + 1, GRAPE_DARK)


def pomegranate(img, ox, sway):
    rect(img, ox + 4, 3, ox + 19, 3, TWIG)
    leaf(img, ox + 6, 2, False)
    leaf(img, ox + 18, 4, True)
    for cx, cy, r in [(8, 13, 5), (17, 15, 4)]:
        x = ox + cx + sway
        rect(img, x, 4, x, cy - r, TWIG)
        disc(img, x, cy, r, POM, POM_DARK, POM_LIGHT)
        for dx in (-1, 0, 1):
            put(img, x + dx, cy + r + 1, CROWN)  # the calyx crown
        put(img, x, cy + r + 2, CROWN)


def feast_dish(img, ox, glint):
    rect(img, ox + 3, 20, ox + 36, 21, DISH)
    rect(img, ox + 5, 22, ox + 34, 22, DISH_DARK)
    rect(img, ox + 2, 19, ox + 37, 19, DISH_LIGHT)
    for cx, cy, r, c, d, l in [(10, 15, 4, POM, POM_DARK, POM_LIGHT), (18, 14, 4, FIG, FIG_DARK, FIG_LIGHT),
                               (26, 15, 4, BREAD, DISH_DARK, DISH_LIGHT), (32, 16, 3, FIG, FIG_DARK, FIG_LIGHT)]:
        disc(img, ox + cx, cy, r, c, d, l)
    for x, y in [(13, 11), (15, 10), (14, 12), (22, 10), (23, 12), (21, 11)]:
        disc(img, ox + x, y, 1, GRAPE, GRAPE_DARK, GRAPE_LIGHT)
    put(img, ox + (8 if glint == 0 else 30), 19, (255, 244, 210, 255))


def ropes(img):
    """Three cut lengths of rope on the ground — lying, never hanging."""
    for x0, x1, y in [(2, 20, 9), (16, 36, 10), (30, 45, 8)]:
        for x in range(x0, x1 + 1):
            put(img, x, y, ROPE)
            put(img, x, y + 1, ROPE_DARK)
            if x % 3 == 0:
                put(img, x, y, ROPE_DARK)  # the lay of the strands
        for e in (x0, x1):
            put(img, e, y - 1, ROPE_END)  # frayed ends
            put(img, e + (1 if e == x1 else -1), y, ROPE_END)


def key(img, ox, glint):
    for y in range(4, 13):
        for x in range(2, 11):
            dx, dy = x - 6, y - 8
            if 9 <= dx * dx + dy * dy <= 18:
                put(img, ox + x, y, COPPER)
    rect(img, ox + 10, 7, ox + 21, 8, COPPER)
    rect(img, ox + 10, 9, ox + 21, 9, COPPER_DARK)
    rect(img, ox + 17, 10, ox + 18, 12, COPPER)
    rect(img, ox + 20, 10, ox + 21, 13, COPPER)
    put(img, ox + (4 if glint == 0 else 15), 7 if glint == 0 else 7, COPPER_LIGHT)
    put(img, ox + (5 if glint == 0 else 16), 6 if glint == 0 else 7, COPPER_LIGHT)


def strip(name, w, h, frames, draw, out=OUT):
    img = Image.new("RGBA", (w * frames, h), (0, 0, 0, 0))
    for f in range(frames):
        draw(img, f * w, f)
    path = os.path.join(out, name)
    patched(path, img).save(path)
    print("wrote", os.path.relpath(path, ROOT))


def main():
    strip("engedi_fig.png", 24, 24, 2, lambda img, ox, f: fig(img, ox, f))
    strip("engedi_grapes.png", 24, 24, 2, lambda img, ox, f: grapes(img, ox, f))
    strip("engedi_pomegranate.png", 24, 24, 2, lambda img, ox, f: pomegranate(img, ox, f))
    strip("engedi_feast_dish.png", 40, 24, 2, lambda img, ox, f: feast_dish(img, ox, f))
    strip("engedi_broken_ropes.png", 48, 12, 1, lambda img, ox, f: ropes(img),
          os.path.join(ROOT, "assets", "decor"))
    strip("engedi_pit_key.png", 24, 16, 2, lambda img, ox, f: key(img, ox, f))


if __name__ == "__main__":
    main()
