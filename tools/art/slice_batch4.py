#!/usr/bin/env python3
"""Batch 4: the possessed sheet. (The hero sheet of the same batch, 17_48_31,
is cut by slice_hero.py together with every later hero sheet.)

    python3 tools/art/slice_batch4.py ~/Downloads
"""
import glob, os, sys
import numpy as np
from PIL import Image, ImageFilter

SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Downloads")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "sprites")


def by_time(stamp):
    hits = glob.glob(os.path.join(SRC, f"*{stamp}.png"))
    if not hits:
        sys.exit(f"missing *{stamp}.png")
    return Image.open(hits[0])


def harden(fr, t=110):
    a = np.array(fr)
    a[:, :, 3] = np.where(a[:, :, 3] > t, 255, 0)
    return Image.fromarray(a)


def split(x0, x1, n):
    w = (x1 - x0) / n
    return [(int(x0 + i * w), int(x0 + (i + 1) * w)) for i in range(n)]


def tight(mask, box):
    x0, y0, x1, y1 = box
    m = mask[y0:y1, x0:x1]
    ys = np.where(m.sum(axis=1) > 2)[0]
    xs = np.where(m.sum(axis=0) > 2)[0]
    return (x0 + xs.min(), y0 + ys.min(), x0 + xs.max() + 1, y0 + ys.max() + 1)


def strip(img, mask, boxes, scale, cell, name, anchor="center", left_pad=22):
    cw, ch = cell
    out = Image.new("RGBA", (cw * len(boxes), ch), (0, 0, 0, 0))
    for i, box in enumerate(boxes):
        bb = tight(mask, box)
        fr = img.convert("RGBA").crop(bb)
        fm = Image.fromarray((mask[bb[1]:bb[3], bb[0]:bb[2]] * 255).astype("uint8")).filter(ImageFilter.MaxFilter(3))
        fr.putalpha(fm)
        fr = harden(fr.resize((max(1, round(fr.width * scale)), max(1, round(fr.height * scale))), Image.LANCZOS))
        if fr.width > cw:
            fr = fr.crop((0, 0, cw, fr.height)) if anchor == "left" else fr.crop(((fr.width - cw) // 2, 0, (fr.width - cw) // 2 + cw, fr.height))
        x = left_pad if anchor == "left" else (cw - fr.width) // 2
        out.paste(fr, (i * cw + x, ch - fr.height - 1), fr)
    out.save(os.path.join(OUT, f"{name}.png"))
    print(name, out.size, len(boxes), "frames")


## The hero rows of this sheet are cut by slice_hero.py now (one 128x64 cell
## shared with the later hero sheets); only the possessed remain here.


def possessed():
    im = by_time("17_42_00").convert("RGB")
    A = np.array(im).astype(int)
    mask = np.sqrt(((A - np.array([18, 20, 23])) ** 2).sum(axis=2)) > 60
    scale = 34 / 153
    cell = (40, 36)
    strip(im, mask, [(x0, 158, x1, 311) for x0, x1 in [(33, 90), (114, 175), (201, 264), (298, 357)]], scale, cell, "possessed_idle")
    strip(im, mask, [(x0, 158, x1, 311) for x0, x1 in [(419, 475), (493, 551)] + split(566, 711, 2) + split(723, 855, 2)], scale, cell, "possessed_walk")
    strip(im, mask, [(x0, 387, x1, 539) for x0, x1 in [(13, 114)] + split(132, 349, 2) + split(362, 600, 2)], scale, cell, "possessed_attack", anchor="left", left_pad=6)
    strip(im, mask, [(x0, 616, x1, 775) for x0, x1 in [(27, 86), (102, 164)] + split(179, 313, 2)], scale, cell, "possessed_hurt")
    strip(im, mask, [(x0, 616, x1, 775) for x0, x1 in [(352, 427)] + split(444, 631, 2) + [(648, 740), (756, 834), (844, 931)]], scale, cell, "possessed_death")


if __name__ == "__main__":
    possessed()
