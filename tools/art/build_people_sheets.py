#!/usr/bin/env python3
"""The people of chapter IV as NPC strips (docs/CHAPTER4_ART.md §3), cut from
sheets drawn by the Codex CLI's image generation and kept in
assets/sprites/people_sheets/<id>.png: a grid of 4 columns x 3 rows (idle,
walk, interact), one person facing the way their NPC faces, on a transparent
(or smooth, near-black) ground.

Each frame is cut to its body (alpha), every frame of a person scaled by the
one factor that brings the tallest idle frame to its height in the game, and
laid in a 48x48 cell with the feet on the bottom row, centred — the same cells
as assets/sprites/villager_v2_*. A row becomes assets/sprites/<id>_<row>.png.
Also cuts the two dogs at the rich gate (assets/decor/tyre_dogs.png, 2 frames
48x24) from their own sheet.

    python3 tools/art/build_people_sheets.py

Deterministic. Writes through `patched()` (the art studio's edits).
"""
import os
import sys

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
# id -> how tall the tallest idle frame stands in the cell (the hero is 43)
PEOPLE = {"zacchaeus": 34, "lydia": 41}
DOGS = ("tyre_dogs", 2, (48, 24))


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


def _place(frame: Image.Image, scale: float, size: tuple[int, int]) -> Image.Image:
    box = frame.getbbox()
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    if box is None:
        return out
    body = frame.crop(box)
    w, h = max(1, round(body.width * scale)), max(1, round(body.height * scale))
    body = body.resize((w, h), Image.Resampling.LANCZOS)
    body.putalpha(body.getchannel("A").point(lambda a: 255 if a > 110 else 0))
    # centred on the cell, feet on its bottom row; the frame's own offset from
    # the sheet cell's centre is kept, so a step forward stays a step
    centre = (box[0] + box[2]) / 2 - frame.width / 2
    x = round(size[0] / 2 - w / 2 + centre * scale)
    out.alpha_composite(body, (max(0, min(size[0] - w, x)), size[1] - h))
    return out


def build_person(person: str, height: int) -> None:
    path = os.path.join(SHEETS, person + ".png")
    if not os.path.exists(path):
        print("no sheet for", person, "- the stand-in stays")
        return
    grid = _cut(Image.open(path), 4, 3)
    tallest = max(f.getbbox()[3] - f.getbbox()[1] for f in grid[0] if f.getbbox())
    scale = height / tallest
    for row, frames in zip(ROWS, grid):
        strip = Image.new("RGBA", (CELL * len(frames), CELL), (0, 0, 0, 0))
        for i, frame in enumerate(frames):
            strip.alpha_composite(_place(frame, scale, (CELL, CELL)), (i * CELL, 0))
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
    for person, height in PEOPLE.items():
        build_person(person, height)
    build_dogs()


if __name__ == "__main__":
    main()
