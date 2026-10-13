"""Rooms put together from several paintings (docs/ROOM_COMPOSER.md).

A painted room is one 1280x720 panel, widened by a band or two. That is as big
as one picture from an image model gets, so a room composed here is a grid of
such panels instead — four in a row, two by two, an L — and the generator
paints them into one picture, stitching every seam the way it stitches a
widened band: a path through the pixels where the two neighbours already
agree, with the difference between them bent away on either side.

The art studio's «Конструктор» writes tools/rooms/composed_rooms.json:

    {"graveyard_cross": {
        "live": false,
        "cells": [{"painting": "graveyard_cross", "col": 0, "row": 0},
                  {"painting": "panels/graveyard_hill", "col": 1, "row": 0}],
        "ground": [[x, y, w, h]], "ledges": [...], "platforms": [...],
        "ramps": [[x0, y0, x1, y1]], "hazards": [[x, y, w, h]],
        "player": [x, y], "door": [x, y],
        "spawns": [[id, x, y]], "props": [[id, x, y]], "npcs": [[id, x, y]]}}

Every coordinate is in the finished room's pixels: cell (col, row) starts at
(col * 1280, row * 720). The key is the painted room it is made for, whose
weather, fog, light, music and cutscenes it keeps. A draft ("live": false)
is written to scenes/rooms/composed/<name>.tscn, beside the room it may
replace, and opened with `room=<name> --composed`; once "live", it is the room
the night walks through and check_reach must prove it.
"""
import json
import os
import re

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TABLE = os.path.join(ROOT, "tools", "rooms", "composed_rooms.json")
LEVELS = os.path.join(ROOT, "assets", "levels")
## One cell of the grid: the size every painted panel is traced at.
CELL = (1280, 720)
## The widest a grid may grow, in cells: a room is walked, not toured.
MAX_COLS, MAX_ROWS = 6, 4
## How far each side of a seam the stitch may reach.
SEAM = 96
## What the room keeps of the painted room it is made for.
ATMOSPHERE = ("ambient", "fog", "intro", "music", "weather", "intro_cutscene", "outro_cutscene")
RECTS = ("ground", "ledges", "platforms", "hazards")
PLACED = ("spawns", "props", "npcs")
PAINTING = re.compile(r"^(panels/)?[a-z0-9_]+$")


def load():
    if not os.path.exists(TABLE):
        return {}
    with open(TABLE, encoding="utf-8") as f:
        return json.load(f)


def painting_path(stem):
    return os.path.join(LEVELS, stem + ".png")


def grid(entry):
    cells = entry.get("cells", [])
    return (max(c["col"] for c in cells) + 1, max(c["row"] for c in cells) + 1)


def validate(name, entry):
    """Everything a composed room must hold before it is painted or built."""
    where = f"tools/rooms/composed_rooms.json: {name}"
    cells = entry.get("cells")
    if not isinstance(cells, list) or not cells:
        raise SystemExit(f"{where}: no cells")
    seen = set()
    for cell in cells:
        stem = str(cell.get("painting", ""))
        col, row = cell.get("col"), cell.get("row")
        if not isinstance(col, int) or not isinstance(row, int) or not (0 <= col < MAX_COLS and 0 <= row < MAX_ROWS):
            raise SystemExit(f"{where}: a cell at {col},{row} is outside the {MAX_COLS}x{MAX_ROWS} grid")
        if (col, row) in seen:
            raise SystemExit(f"{where}: two cells at {col},{row}")
        seen.add((col, row))
        if not PAINTING.match(stem) or not os.path.exists(painting_path(stem)):
            raise SystemExit(f"{where}: no painting assets/levels/{stem}.png")
        with Image.open(painting_path(stem)) as picture:
            size = picture.size
        if size != CELL:
            raise SystemExit(f"{where}: {stem}.png is {size[0]}x{size[1]}, a cell is {CELL[0]}x{CELL[1]}")
    width, height = grid(entry)[0] * CELL[0], grid(entry)[1] * CELL[1]
    for key in RECTS:
        for rect in entry.get(key, []):
            x, y, w, h = rect
            if w <= 0 or h <= 0 or x < 0 or y < 0 or x + w > width or y + h > height:
                raise SystemExit(f"{where}: {key} {rect} is not inside the {width}x{height} room")
    for x0, y0, x1, y1 in entry.get("ramps", []):
        if not all(0 <= v <= lim for v, lim in ((x0, width), (x1, width), (y0, height), (y1, height))):
            raise SystemExit(f"{where}: ramp {[x0, y0, x1, y1]} leaves the room")
    for key in ("player", "door"):
        at = entry.get(key)
        if not (isinstance(at, list) and len(at) == 2 and 0 <= at[0] <= width and 0 <= at[1] <= height):
            raise SystemExit(f"{where}: no {key} inside the room")
    for key in PLACED:
        for item in entry.get(key, []):
            if len(item) != 3 or not (0 <= item[1] <= width and 0 <= item[2] <= height):
                raise SystemExit(f"{where}: {key} {item} is not inside the room")
            folder = {"spawns": "enemies", "props": "props", "npcs": "npcs"}[key]
            if not os.path.exists(os.path.join(ROOT, "data", folder, str(item[0]) + ".json")):
                raise SystemExit(f"{where}: no data/{folder}/{item[0]}.json")


def _stitch(first, second, lo, hi, feather=8):
    """One band from two pictures of it: `first` holds at the left edge,
    `second` at the right, and they hand over along the cheapest vertical path
    between columns lo and hi (generate_rooms._quilt_band, for two pictures
    that are not copies of one)."""
    height, amount = first.shape[:2]
    cost = np.abs(first[..., :3] - second[..., :3]).sum(axis=2)
    padded = np.pad(cost, 3, mode="edge")
    smooth = np.zeros_like(cost)
    for dy in range(7):
        for dx in range(7):
            smooth += padded[dy:dy + height, dx:dx + amount]
    smooth[:, :lo] = np.inf
    smooth[:, hi:] = np.inf
    total = smooth.copy()
    step = np.zeros((height, amount), dtype=np.int64)
    for y in range(1, height):
        above = total[y - 1]
        options = np.stack([np.roll(above, 1), above, np.roll(above, -1)])
        options[0, 0] = np.inf
        options[2, -1] = np.inf
        choice = options.argmin(axis=0)
        total[y] += options[choice, np.arange(amount)]
        step[y] = np.arange(amount) + choice - 1
    path = np.zeros(height, dtype=np.int64)
    path[-1] = int(total[-1].argmin())
    for y in range(height - 1, 0, -1):
        path[y - 1] = step[y, path[y]]
    # Two paintings rarely share a light: each bends by half the difference at
    # the path, fading out towards its own edge, so the edges stay exact and the
    # change of light is spread across the whole band instead of a line.
    rows = np.arange(height)
    near = np.clip(path[:, None] + np.arange(-2, 3)[None, :], 0, amount - 1)
    gap = (first[rows[:, None], near] - second[rows[:, None], near]).mean(axis=1)
    kernel = np.ones(31, dtype=np.float32) / 31.0
    gap = np.stack([np.convolve(np.pad(gap[:, c], 15, mode="edge"), kernel, mode="valid")
                    for c in range(gap.shape[1])], axis=1)
    gap[:, 3] = 0.0
    columns = np.arange(amount, dtype=np.float32)[None, :]
    toward_left = np.clip(columns / np.maximum(path[:, None], 1), 0.0, 1.0)
    toward_right = np.clip((amount - 1 - columns) / np.maximum(amount - 1 - path[:, None], 1), 0.0, 1.0)
    first = first - 0.5 * gap[:, None, :] * toward_left[..., None]
    second = second + 0.5 * gap[:, None, :] * toward_right[..., None]
    weight = np.clip((columns - path[:, None] + feather) / (2 * feather), 0.0, 1.0)[..., None]
    return first * (1.0 - weight) + second * weight


def _join(left, right, seam=SEAM):
    """`left` and `right` side by side, the seam between them stitched. Each is
    carried past the seam by its own mirror, so the stitch has both pictures
    over the same band; the path keeps to the middle half of it."""
    x = left.shape[1]
    a = left[:, x - seam:]
    b = right[:, :seam]
    first = np.concatenate([a, a[:, ::-1]], axis=1)
    second = np.concatenate([b[:, ::-1], b], axis=1)
    band = _stitch(first, second, seam // 2, seam + seam // 2)
    return np.concatenate([left[:, :x - seam], band, right[:, seam:]], axis=1)


def _join_below(top, bottom, seam=SEAM):
    return _join(top.transpose(1, 0, 2), bottom.transpose(1, 0, 2), seam).transpose(1, 0, 2)


def compose_picture(entry):
    """The grid as one picture. A hole in the grid is the night: the darkest
    tenth of the paintings around it, stitched like any neighbour."""
    cols, rows = grid(entry)
    tiles = {(c["col"], c["row"]): np.asarray(Image.open(painting_path(c["painting"])).convert("RGBA"), dtype=np.float32)
             for c in entry["cells"]}
    stack = np.stack(list(tiles.values()))
    lum = stack[..., :3].mean(axis=3)
    dark = stack[lum <= np.percentile(lum, 10)].mean(axis=0)
    hole = np.broadcast_to(dark, (CELL[1], CELL[0], 4)).astype(np.float32)
    strips = []
    for row in range(rows):
        strip = tiles.get((0, row), hole)
        for col in range(1, cols):
            strip = _join(strip, tiles.get((col, row), hole))
        strips.append(strip)
    picture = strips[0]
    for strip in strips[1:]:
        picture = _join_below(picture, strip)
    return Image.fromarray(np.clip(picture + 0.5, 0, 255).astype(np.uint8), "RGBA")


def lights(entry):
    """Each panel's candles where its cell is: the tracer's own file beside a
    painting the game already has, the tracer itself for a new one."""
    from trace_panel import lights as trace_lights
    out = []
    for cell in entry["cells"]:
        stem = cell["painting"]
        ox, oy = cell["col"] * CELL[0], cell["row"] * CELL[1]
        found = painting_path(stem)[:-4] + ".lights.json"
        if os.path.exists(found):
            with open(found) as f:
                found = [tuple(light) for light in json.load(f)]
        else:
            found = trace_lights(Image.open(painting_path(stem)).convert("RGB"))
        out += [(x + ox, y + oy, tint, radius, energy, flicker) for x, y, tint, radius, energy, flicker in found]
    return out


def room_table(name, entry, base):
    """The room for generate_rooms.build: the composed geometry under the
    painted room's own sky."""
    cols, rows = grid(entry)
    room = {key: base[key] for key in ATMOSPHERE if key in base}
    room.update(
        composed=True,
        painting_wide="composed/" + name,
        width=cols * CELL[0], height=rows * CELL[1],
        void_kill_y=rows * CELL[1] - 30,
        ramps=[tuple(r) for r in entry.get("ramps", [])],
        player=tuple(entry["player"]), door=tuple(entry["door"]),
        decor=[],
        lights=lights(entry),
        light_cap=26 * min(2, len(entry["cells"])),
    )
    for key in RECTS:
        room[key] = [tuple(r) for r in entry.get(key, [])]
    for key in PLACED:
        room[key] = [tuple(item) for item in entry.get(key, [])]
    return room
