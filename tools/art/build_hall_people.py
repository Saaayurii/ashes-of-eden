#!/usr/bin/env python3
"""The Heavenly Hall's people (chapter VII): strips cut from their generated sheets.

    python3 tools/art/build_hall_people.py

Each sheet in assets/sprites/people_sheets/<id>.png (Codex CLI image
generation, assets/CREDITS.md) is a 6 x 4 grid, every figure facing left
(turned to face right in the strip, like every other person's):
idle, walk, interact, special. Every frame is cut to its figure, scaled by one
factor per sheet (the tallest idle figure fills HEIGHT[id]), stood on the
bottom row of a 48 x 48 cell and centred on the idle row's middle, so the body
does not swim between frames. Written as <id>_v2_<row>.png beside the other
people's strips (docs/CHAPTER7_ART.md §3).
"""
from pathlib import Path
from statistics import median

from PIL import Image, ImageOps

from studio_overrides import patched  # the art studio's edits of what this writes

ROOT = Path(__file__).resolve().parents[2]
SHEETS = ROOT / "assets" / "sprites" / "people_sheets"
SPRITES = ROOT / "assets" / "sprites"
CELL = (48, 48)
COLUMNS, ROWS = 6, 4
ROW_NAMES = ["idle", "walk", "interact", "special"]
# How tall the idle figure stands, in game pixels (Elian is 44): the elders and
# Enoch are drawn seated, so they are shorter than a man on his feet.
HEIGHT = {"elders": 38, "enoch": 36, "lucifer": 45}


def _figures(sheet: Image.Image) -> list[list[tuple[Image.Image, tuple[int, int, int, int]]]]:
    cell_w, cell_h = sheet.width // COLUMNS, sheet.height // ROWS
    rows = []
    for row in range(ROWS):
        found = []
        for column in range(COLUMNS):
            cell = sheet.crop((column * cell_w, row * cell_h, (column + 1) * cell_w, (row + 1) * cell_h))
            alpha = cell.getchannel("A").point(lambda a: a if a > 16 else 0)
            cell.putalpha(alpha)
            found.append((cell, alpha.getbbox() or (0, 0, 1, 1)))
        rows.append(found)
    return rows


def build(name: str) -> None:
    sheet = Image.open(SHEETS / f"{name}.png").convert("RGBA")
    rows = _figures(sheet)
    idle = rows[0]
    scale = HEIGHT[name] / max(box[3] - box[1] for _, box in idle)
    middle = median((box[0] + box[2]) / 2 for _, box in idle)
    for row_name, found in zip(ROW_NAMES, rows):
        out = Image.new("RGBA", (CELL[0] * COLUMNS, CELL[1]))
        for index, (cell, box) in enumerate(found):
            # the figure keeps its place in its cell: only its feet are moved to the bottom row
            figure = cell.crop((0, box[1], cell.width, box[3]))
            figure = figure.resize((max(1, round(figure.width * scale)), max(1, round(figure.height * scale))),
                                   Image.Resampling.LANCZOS)
            x = round(CELL[0] / 2 - middle * scale)
            # drawn on a margin first: alpha_composite takes no negative offsets
            frame = Image.new("RGBA", (CELL[0] + 2 * figure.width, CELL[1]))
            frame.alpha_composite(figure, (x + figure.width, CELL[1] - figure.height))
            frame = ImageOps.mirror(frame.crop((figure.width, 0, figure.width + CELL[0], CELL[1])))
            out.alpha_composite(frame, (index * CELL[0], 0))
        path = SPRITES / f"{name}_v2_{row_name}.png"
        patched(path, out).save(path, optimize=True)


def main() -> None:
    for name in HEIGHT:
        build(name)


if __name__ == "__main__":
    main()
