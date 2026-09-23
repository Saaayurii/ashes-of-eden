#!/usr/bin/env python3
"""Batch 5: NPC sheet + tileset (17_52_18), Elian's civilian poses (17_50_34).

    python3 tools/art/slice_batch5.py ~/Downloads
"""
import glob, os, sys
import numpy as np
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Downloads")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SPR = os.path.join(ROOT, "assets", "sprites")
DEC = os.path.join(ROOT, "assets", "decor")


def by_time(stamp):
    hits = glob.glob(os.path.join(SRC, f"*{stamp}.png"))
    if not hits:
        sys.exit(f"missing *{stamp}.png")
    return Image.open(hits[0]).convert("RGBA")


def harden(fr, t=100):
    a = np.array(fr)
    a[:, :, 3] = np.where(a[:, :, 3] > t, 255, 0)
    return Image.fromarray(a)


def tight(mask, box):
    x0, y0, x1, y1 = box
    m = mask[y0:y1, x0:x1]
    ys = np.where(m.sum(axis=1) > 1)[0]
    xs = np.where(m.sum(axis=0) > 1)[0]
    return (x0 + xs.min(), y0 + ys.min(), x0 + xs.max() + 1, y0 + ys.max() + 1)


def strip(img, mask, boxes, scale, cell, name):
    cw, ch = cell
    out = Image.new("RGBA", (cw * len(boxes), ch), (0, 0, 0, 0))
    for i, box in enumerate(boxes):
        fr = img.crop(tight(mask, box))
        fr = harden(fr.resize((max(1, round(fr.width * scale)), max(1, round(fr.height * scale))), Image.LANCZOS))
        if fr.width > cw:
            fr = fr.crop(((fr.width - cw) // 2, 0, (fr.width - cw) // 2 + cw, fr.height))
        out.paste(fr, (i * cw + (cw - fr.width) // 2, ch - fr.height - 1), fr)
    out.save(os.path.join(SPR, f"{name}.png"))
    print(name, out.size, len(boxes))


def single(img, mask, box, height, name, folder=DEC, width=None):
    fr = img.crop(tight(mask, box))
    s = height / fr.height if width is None else min(height / fr.height, width / fr.width)
    fr = harden(fr.resize((max(1, round(fr.width * s)), max(1, round(fr.height * s))), Image.LANCZOS), 90)
    fr.save(os.path.join(folder, f"{name}.png"))
    print(name, fr.size)


def npcs_and_tiles():
    im = by_time("17_52_18")
    mask = np.array(im)[:, :, 3] > 40
    strip(im, mask, [(x0, 7, x1, 113) for x0, x1 in [(23, 93), (129, 190), (205, 258), (279, 334), (347, 413), (432, 478)]], 44 / 106, (40, 48), "knight_idle")
    strip(im, mask, [(x0, 476, x1, 585) for x0, x1 in [(31, 70), (97, 136), (161, 201), (228, 274)]], 40 / 109, (32, 44), "nun_idle")
    strip(im, mask, [(x0, 598, x1, 688) for x0, x1 in [(27, 70), (100, 143), (170, 230), (258, 320)]], 36 / 90, (32, 40), "villager_idle")
    # tiles: a wide ground slab and a wide wall become horizontal strips 32 px tall
    single(im, mask, (187, 700, 360, 792), 32, "ground_tiles")
    single(im, mask, (113, 800, 313, 900), 32, "wall_tiles")
    single(im, mask, (687, 800, 747, 900), 64, "pillar")
    single(im, mask, (1173, 800, 1320, 900), 72, "arch")
    single(im, mask, (11, 927, 80, 1000), 18, "rocks")
    single(im, mask, (213, 927, 287, 1000), 22, "grass_1")
    single(im, mask, (513, 927, 593, 1000), 22, "grass_2")
    single(im, mask, (400, 927, 480, 1000), 26, "bush")
    single(im, mask, (800, 927, 933, 1000), 40, "ruin_stumps")


def elian_civilian():
    """Intro: Elian wakes after his own execution — flat on the ground, pushes up,
    sits, kneels, stands. One scale for every frame so he does not grow."""
    im = by_time("17_50_34")
    mask = np.array(im)[:, :, 3] > 40
    scale = 46 / 155  # standing row height -> 46 px, same as the armoured hero
    cell = (72, 48)
    lying = [(x0, 830, x1, 940) for x0, x1 in [(659, 898), (445, 638), (258, 418), (92, 231)]]
    sitting = [(x0, 941, x1, 1059) for x0, x1 in [(97, 207), (264, 382), (434, 563)]]
    rising = [(x0, 656, x1, 812) for x0, x1 in [(541, 639), (324, 441), (106, 226)]]
    standing = [(x0, 27, x1, 182) for x0, x1 in [(101, 188)]]
    strip(im, mask, lying + sitting + rising + standing, scale, cell, "elian_wake")
    strip(im, mask, [(x0, 368, x1, 507) for x0, x1 in [(95, 185), (263, 383), (432, 550), (591, 678)]], scale, cell, "elian_talk")


if __name__ == "__main__":
    npcs_and_tiles()
    elian_civilian()
