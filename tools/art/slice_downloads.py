#!/usr/bin/env python3
"""One-off: turns the generated concept images into game assets.

    python3 tools/art/slice_downloads.py <folder with the ChatGPT pngs>

- hero sheet (transparent, 2x4 figures)      -> assets/sprites/elian.png   40x48 x 8
- concept atlas (figures on a dark panel)    -> assets/sprites/possessed.png, shade.png  24x28 x 4
- landscape paintings                        -> assets/backgrounds/*.png   640x360

Kept so the process is reproducible and so contributors can see how the
prototype art was made. Requires Pillow and numpy.
"""
import glob, os, sys
import numpy as np
from PIL import Image, ImageFilter

SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Downloads")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SPRITES = os.path.join(ROOT, "assets", "sprites")
BACKGROUNDS = os.path.join(ROOT, "assets", "backgrounds")
os.makedirs(SPRITES, exist_ok=True)
os.makedirs(BACKGROUNDS, exist_ok=True)


def by_time(stamp):
    hits = glob.glob(os.path.join(SRC, f"*{stamp}.png"))
    if not hits:
        sys.exit(f"missing source image *{stamp}.png in {SRC}")
    return hits[0]


def harden(frame, threshold=110):
    arr = np.array(frame)
    arr[:, :, 3] = np.where(arr[:, :, 3] > threshold, 255, 0)
    return Image.fromarray(arr)


def paste_bottom_center(sheet, frame, index, cell_w, cell_h):
    sheet.paste(frame, ((cell_w - frame.width) // 2 + index * cell_w, cell_h - frame.height - 1), frame)


def hero():
    im = Image.open(by_time("16_50_11")).convert("RGBA")
    alpha = np.array(im)[:, :, 3] > 10

    def runs(v):
        out, start = [], None
        for i, x in enumerate(v):
            if x and start is None:
                start = i
            if not x and start is not None:
                out.append((start, i)); start = None
        if start is not None:
            out.append((start, len(v)))
        return out

    cw, ch = 40, 48
    boxes = []
    for y0, y1 in runs(alpha.any(axis=1)):
        for x0, x1 in runs(alpha[y0:y1].any(axis=0)):
            boxes.append((x0, y0, x1, y1))
    sheet = Image.new("RGBA", (cw * len(boxes), ch), (0, 0, 0, 0))
    for i, box in enumerate(boxes):
        fr = im.crop(box)
        scale = (ch - 2) / fr.height
        fr = harden(fr.resize((max(1, round(fr.width * scale)), ch - 2), Image.LANCZOS))
        paste_bottom_center(sheet, fr, i, cw, ch)
    sheet.save(os.path.join(SPRITES, "elian.png"))
    print("elian.png", sheet.size, len(boxes), "frames")


def atlas_enemies():
    atlas = Image.open(by_time("16_55_42")).convert("RGB")
    A = np.array(atlas).astype(int)
    bg = np.array([54, 48, 47])  # the panel colour
    mask = np.sqrt(((A - bg) ** 2).sum(axis=2)) > 45

    def extract(region, name, cell=(24, 28)):
        x0, y0, x1, y1 = region
        m = mask[y0:y1, x0:x1]
        cols = m.sum(axis=0) > 1
        runs, start, gap = [], None, 0
        for i, c in enumerate(cols):
            if c:
                if start is None:
                    start = i
                gap = 0
            elif start is not None:
                gap += 1
                if gap > 5:
                    runs.append((start, i - gap)); start = None; gap = 0
        if start is not None:
            runs.append((start, len(cols)))
        runs = [r for r in runs if r[1] - r[0] > 10][1:]  # first run is the row label
        cw, ch = cell
        out = Image.new("RGBA", (cw * len(runs), ch), (0, 0, 0, 0))
        for i, (cx0, cx1) in enumerate(runs):
            ys = np.where(m[:, cx0:cx1].sum(axis=1) > 1)[0]
            box = (x0 + cx0 - 1, y0 + ys.min() - 1, x0 + cx1 + 1, y0 + ys.max() + 2)
            fr = atlas.crop(box).convert("RGBA")
            fm = Image.fromarray((mask[box[1]:box[3], box[0]:box[2]] * 255).astype("uint8")).filter(ImageFilter.MaxFilter(3))
            fr.putalpha(fm)
            scale = min((ch - 2) / fr.height, (cw - 2) / fr.width)
            fr = harden(fr.resize((max(1, round(fr.width * scale)), max(1, round(fr.height * scale))), Image.LANCZOS), 120)
            paste_bottom_center(out, fr, i, cw, ch)
        out.save(os.path.join(SPRITES, f"{name}.png"))
        print(f"{name}.png", out.size, len(runs), "frames")

    extract((718, 38, 940, 97), "possessed")
    extract((962, 38, 1200, 97), "shade")


def backgrounds():
    names = {"16_57_26": "graveyard", "16_58_24": "village_dawn", "16_59_18": "village_night",
             "17_02_50": "dead_bridge", "17_04_23": "desert_angel"}
    for stamp, name in names.items():
        im = Image.open(by_time(stamp)).convert("RGB")
        w, h = im.size
        tw = int(h * 16 / 9)
        if tw < w:
            im = im.crop(((w - tw) // 2, 0, (w - tw) // 2 + tw, h))
        im.resize((640, 360), Image.LANCZOS).save(os.path.join(BACKGROUNDS, f"{name}.png"), optimize=True)
        print(f"{name}.png")


if __name__ == "__main__":
    hero()
    atlas_enemies()
    backgrounds()
