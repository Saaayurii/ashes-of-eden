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
import os
import sys
from statistics import median

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
    body = body.resize((w, h), Image.Resampling.LANCZOS)
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
