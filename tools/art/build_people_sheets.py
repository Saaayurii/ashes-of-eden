#!/usr/bin/env python3
"""The people of chapters II-VI as NPC strips (docs/CHAPTER<N>_ART.md §3), cut
from sheets drawn by the Codex CLI's image generation and kept in
assets/sprites/people_sheets/<id>.png: a grid of 4 columns x 3 rows (idle,
walk, interact), one person facing right (an NPC's `face` turns it), on a
transparent ground (drawn on flat magenta, keyed to alpha before it is kept).

Each frame is cut to its body (alpha), every frame of a person scaled by the
one factor that brings the tallest idle frame to its height in the game (a
body lying down is measured by its length instead), and
laid in a 48x48 cell with the feet on the bottom row, centred — the same cells
as assets/sprites/villager_v2_*. A row becomes assets/sprites/<id>_<row>.png.
Also cuts the two dogs at the rich gate (assets/decor/tyre_dogs.png, 2 frames
48x24) from their own sheet.

    python3 tools/art/build_people_sheets.py [id ...]

Deterministic. Writes through `patched()` (the art studio's edits).
"""
import math
import os
import sys
from statistics import median

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from build_bestiary_assets import _remove_smooth_backdrop  # noqa: E402
from studio_overrides import patched  # noqa: E402  the art studio's edits of what this writes

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
SHEETS = os.path.join(ROOT, "assets", "sprites", "people_sheets")
SPRITES = os.path.join(ROOT, "assets", "sprites")
DECOR = os.path.join(ROOT, "assets", "decor")

ROWS = ["idle", "walk", "interact"]
CELL = 48
# id -> how tall the tallest idle frame stands in the cell (the hero is 43);
# ("long", n): a body lying down, its longest idle frame n pixels from head to foot
PEOPLE = {
    # Seir (chapter II): Lazarus lies by the road and sits on the quay (and at the rich gate in Tyre)
    "lazarus": ("long", 40), "lazarus_sit": 31, "jonah": 32, "naomi": 32,
    # Marah (chapter III)
    "malchus": 42, "malchus_hanged": 36, "marah_scout": 44, "rizpah": 30,
    "parley_bannerbearer": 36, "parley_centurion": 34,
    # Tyre (chapter IV)
    "zacchaeus": 28, "lydia": 41,
    # the Euphrates (chapter VI)
    "saul": 45, "euphrates_reveller": 41, "witness": ("long", 41),
}
DOGS = ("tyre_dogs", 2, (48, 24))
# a body that hangs: the image generator will not draw a rope at a neck, so the
# rope is a line drawn here, from the cell's top down into the bowed head
HANGED = {"malchus_hanged"}
ROPE = (58, 44, 30, 255)
LIFT = 5
ROPE_LIGHT = (92, 72, 50, 255)
# Pillow's own fixed-point resampling (Resample.c), so the cut does not move
# when Pillow does: 13.0 changed its Lanczos and drew these people a few
# hundred pixels apart. Same numbers as Pillow 12, byte for byte.
PRECISION_BITS = 22


def _lanczos_coeffs(in_size: int, out_size: int) -> tuple[np.ndarray, np.ndarray]:
    scale = in_size / out_size
    filterscale = max(scale, 1.0)
    support = 3.0 * filterscale
    kk = np.zeros((out_size, int(math.ceil(support)) * 2 + 1), dtype=np.int64)
    first = np.zeros(out_size, dtype=np.int64)
    for xx in range(out_size):
        centre = (xx + 0.5) * scale
        xmin = max(int(centre - support + 0.5), 0)
        xmax = min(int(centre + support + 0.5), in_size) - xmin
        weights = []
        for x in range(xmax):
            t = (x + xmin - centre + 0.5) / filterscale
            w = 0.0
            if -3.0 <= t < 3.0:  # sinc(t) * sinc(t / 3)
                w = 1.0 if t == 0 else math.sin(t * math.pi) / (t * math.pi) * (math.sin(t / 3 * math.pi) / (t / 3 * math.pi))
            weights.append(w)
        total = sum(weights)
        for x, w in enumerate(weights):
            if total != 0.0:
                w /= total
            kk[xx, x] = int((-0.5 if w < 0 else 0.5) + w * (1 << PRECISION_BITS))
        first[xx] = xmin
    return kk, first


def _resample_rows(a: np.ndarray, out_size: int) -> np.ndarray:
    """(h, w, c) uint8 -> (h, out_size, c), along the rows."""
    kk, first = _lanczos_coeffs(a.shape[1], out_size)
    src = np.pad(a.astype(np.int64), ((0, 0), (0, kk.shape[1]), (0, 0)))
    out = np.full((a.shape[0], out_size, a.shape[2]), 1 << (PRECISION_BITS - 1), dtype=np.int64)
    for x in range(kk.shape[1]):
        out += src[:, first + x, :] * kk[:, x][None, :, None]
    return np.clip(out >> PRECISION_BITS, 0, 255).astype(np.uint8)


def _lanczos(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    """`image.resize(size, LANCZOS)` as Pillow 12 did it: premultiplied, rows then columns."""
    a = np.asarray(image.convert("RGBA")).astype(np.int64)
    alpha = a[..., 3:4]
    t = a[..., :3] * alpha + 128
    pm = np.concatenate([((t >> 8) + t) >> 8, alpha], axis=2).astype(np.uint8)
    if size[0] != pm.shape[1]:
        pm = _resample_rows(pm, size[0])
    if size[1] != pm.shape[0]:
        pm = _resample_rows(pm.transpose(1, 0, 2), size[1]).transpose(1, 0, 2)
    pm = pm.astype(np.int64)
    alpha = pm[..., 3:4]
    rgb = np.where((alpha == 0) | (alpha == 255), pm[..., :3], np.clip(255 * pm[..., :3] // np.maximum(alpha, 1), 0, 255))
    return Image.fromarray(np.concatenate([rgb, alpha], axis=2).astype(np.uint8), "RGBA")


def _rope(cell: Image.Image) -> None:
    alpha = cell.getchannel("A")
    box = alpha.getbbox()
    if box is None:
        return
    top = box[1]
    xs = [x for x in range(cell.width) if alpha.getpixel((x, top))]
    x = round(sum(xs) / len(xs))
    for y in range(0, top + 3):
        if alpha.getpixel((x, y)) == 0 or y < top:
            cell.putpixel((x, y), ROPE)
            if y % 3 == 0:  # the lay of the strands
                cell.putpixel((x, y), ROPE_LIGHT)


def _body(frame: Image.Image) -> Image.Image:
    frame = frame.convert("RGBA")
    corners = [frame.getpixel(p) for p in ((0, 0), (frame.width - 1, 0), (0, frame.height - 1))]
    if all(c[3] > 200 for c in corners):  # drawn opaque: lift the ground off
        frame = _remove_smooth_backdrop(frame)
    alpha = frame.getchannel("A").point(lambda a: 255 if a > 40 else 0)
    frame.putalpha(alpha)
    return frame


def _cut(sheet: Image.Image, cols: int, rows: int) -> list[list[Image.Image]]:
    w, h = sheet.width // cols, sheet.height // rows
    return [[_body(sheet.crop((c * w, r * h, (c + 1) * w, (r + 1) * h))) for c in range(cols)] for r in range(rows)]


def _place(frame: Image.Image, scale: float, size: tuple[int, int], middle: float | None = None) -> Image.Image:
    box = frame.getbbox()
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    if box is None:
        return out
    body = frame.crop(box)
    w, h = max(1, round(body.width * scale)), max(1, round(body.height * scale))
    body = _lanczos(body, (w, h))
    body.putalpha(body.getchannel("A").point(lambda a: 255 if a > 110 else 0))
    # centred on the cell, feet on its bottom row; the frame's own offset from
    # the person's middle (the idle row's, else the sheet cell's centre) is
    # kept, so a step forward stays a step and a figure drawn off-centre is not
    centre = (box[0] + box[2]) / 2 - (frame.width / 2 if middle is None else middle)
    x = round(size[0] / 2 - w / 2 + centre * scale)
    out.alpha_composite(body, (max(0, min(size[0] - w, x)), size[1] - h))
    return out


def build_person(person: str, height: int | tuple[str, int]) -> None:
    path = os.path.join(SHEETS, person + ".png")
    if not os.path.exists(path):
        print("no sheet for", person, "- the stand-in stays")
        return
    grid = _cut(Image.open(path), 4, 3)
    if isinstance(height, tuple):  # lying down: measured head to foot
        longest = max(f.getbbox()[2] - f.getbbox()[0] for f in grid[0] if f.getbbox())
        scale = height[1] / longest
    else:
        tallest = max(f.getbbox()[3] - f.getbbox()[1] for f in grid[0] if f.getbbox())
        scale = height / tallest
    middle = median((f.getbbox()[0] + f.getbbox()[2]) / 2 for f in grid[0] if f.getbbox())
    for row, frames in zip(ROWS, grid):
        strip = Image.new("RGBA", (CELL * len(frames), CELL), (0, 0, 0, 0))
        for i, frame in enumerate(frames):
            cell = _place(frame, scale, (CELL, CELL), middle)
            if person in HANGED:  # the feet a hand above the ground, then the rope
                lifted = Image.new("RGBA", cell.size, (0, 0, 0, 0))
                lifted.alpha_composite(cell.crop((0, LIFT, CELL, CELL)), (0, 0))
                cell = lifted
                _rope(cell)
            strip.alpha_composite(cell, (i * CELL, 0))
        out = os.path.join(SPRITES, "%s_%s.png" % (person, row))
        patched(out, strip).save(out)
        print("wrote", os.path.relpath(out, ROOT))


def build_dogs() -> None:
    name, count, size = DOGS
    path = os.path.join(SHEETS, name + ".png")
    if not os.path.exists(path):
        print("no sheet for", name)
        return
    frames = _cut(Image.open(path), count, 1)[0]
    widest = max(f.getbbox()[2] - f.getbbox()[0] for f in frames if f.getbbox())
    scale = size[0] / widest
    strip = Image.new("RGBA", (size[0] * count, size[1]), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        strip.alpha_composite(_place(frame, scale, size), (i * size[0], 0))
    os.makedirs(DECOR, exist_ok=True)
    out = os.path.join(DECOR, name + ".png")
    patched(out, strip).save(out)
    print("wrote", os.path.relpath(out, ROOT))


def main() -> None:
    only = set(sys.argv[1:])  # names on the command line build only those
    for person, height in PEOPLE.items():
        if not only or person in only:
            build_person(person, height)
    if not only or DOGS[0] in only:
        build_dogs()


if __name__ == "__main__":
    main()
