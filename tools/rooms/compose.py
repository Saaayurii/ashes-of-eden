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
        "crumbling_platforms": [[x, y, w], [x, y, w, "timber"]],
        "ramps": [[x0, y0, x1, y1]], "hazards": [[x, y, w, h]],
        "player": [x, y], "door": [x, y],
        "spawns": [[id, x, y]], "props": [[id, x, y]], "npcs": [[id, x, y]],
        "windows": [{"points": [[x, y], ...], "depth": 0.84, "sky": true}],
        "front": [piece, ...],          # tools/rooms/front.py
        "lights": [[x, y, tint, radius, energy, flicker]]}}

Every coordinate is in the finished room's pixels: cell (col, row) starts at
(col * 1280, row * 720). The key is the painted room it is made for, whose
weather, fog, light, music and cutscenes it keeps. A draft ("live": false)
is written to scenes/rooms/composed/<name>.tscn, beside the room it may
replace, and opened with `room=<name> --composed`; once "live", it is the room
the night walks through and check_reach must prove it.

A crumbling platform (scripts/rooms/crumbling_platform.gd) is [x, y, w] or
[x, y, w, kind]: a foothold that gives way under the hero and grows back, the
same as a painted room's `crumbling_platforms`. Like there, the route never
counts on it (check_reach, the studio's composeReach and reach_test.gd all
leave it out): it is a shortcut over a gap, not the way.
"""
import json
import math
import os
import re

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TABLE = os.path.join(ROOT, "tools", "rooms", "composed_rooms.json")
LEVELS = os.path.join(ROOT, "assets", "levels")
# A game pack laid over the engine (docs/GAME_PACKS.md) brings its own panels
# and composes its own rooms: content/rooms/composed_rooms.json, its pictures
# in content/assets/levels. A panel it names is its own first, else the engine's.
PACK = os.path.join(ROOT, "content")
PACK_TABLE = os.path.join(PACK, "rooms", "composed_rooms.json")
PACK_LEVELS = os.path.join(PACK, "assets", "levels")
## One cell of the grid: the size every painted panel is traced at.
CELL = (1280, 720)
## The widest a grid may grow, in cells: a room is walked, not toured.
MAX_COLS, MAX_ROWS = 6, 4
## How far each side of a seam the stitch may reach.
SEAM = 96
## How far each side of a seam its light is evened out (`_tone`): wide and soft,
## so two paintings of another light (a torch-lit vault beside a cold crypt)
## meet at one light without a line, and keep their own beyond it.
TONE = 320
## The rows a seam's light is averaged over: the light, not the things in it.
TONE_ROWS = 48
## How far apart two lights may be evened out; past it, a seam keeps the rest.
TONE_LIMIT = 2.0
## What the room keeps of the painted room it is made for.
ATMOSPHERE = ("ambient", "fog", "intro", "music", "weather", "intro_cutscene", "outro_cutscene", "quiet_outro")
RECTS = ("ground", "ledges", "platforms", "hazards")
PLACED = ("spawns", "props", "npcs")
## What a crumbling platform may be drawn as: crumbling_platform.gd's surface_kind.
CRUMBLING_KINDS = ("stone", "timber")
PAINTING = re.compile(r"^(panels/)?[a-z0-9_]+$")
## The far openings of each painted room (scripts/rooms/room_layers.gd), read
## from the script so the two never disagree.
ROOM_LAYERS = os.path.join(ROOT, "scripts", "rooms", "room_layers.gd")
## How far a window may lie behind the painting (RoomLayers' clamp).
WINDOW_DEPTH = (0.0, 1.6)


def load(table=TABLE):
    if not os.path.exists(table):
        return {}
    with open(table, encoding="utf-8") as f:
        return json.load(f)


def painting_path(stem):
    own = os.path.join(PACK_LEVELS, stem + ".png")
    return own if os.path.exists(own) else os.path.join(LEVELS, stem + ".png")


def grid(entry):
    cells = entry.get("cells", [])
    return (max(c["col"] for c in cells) + 1, max(c["row"] for c in cells) + 1)


def validate(name, entry, where_file="tools/rooms/composed_rooms.json"):
    """Everything a composed room must hold before it is painted or built."""
    where = f"{where_file}: {name}"
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
    for piece in entry.get("crumbling_platforms", []):
        if not (isinstance(piece, list) and len(piece) in (3, 4)
                and all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in piece[:3])):
            raise SystemExit(f"{where}: crumbling platform {piece} is not [x, y, w] or [x, y, w, kind]")
        x, y, w = piece[:3]
        if w <= 0 or x < 0 or y < 0 or x + w > width or y >= height:
            raise SystemExit(f"{where}: crumbling platform {piece} is not inside the {width}x{height} room")
        if len(piece) == 4 and piece[3] not in CRUMBLING_KINDS:
            raise SystemExit(f"{where}: crumbling platform {piece} is not one of {', '.join(CRUMBLING_KINDS)}")
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
            if not any(os.path.exists(os.path.join(root, "data", folder, str(item[0]) + ".json")) for root in (ROOT, PACK)):
                raise SystemExit(f"{where}: no data/{folder}/{item[0]}.json")
    for i, wave in enumerate(entry.get("waves", []), 1):
        if not isinstance(wave, list) or not wave:
            raise SystemExit(f"{where}: wave {i} is not a non-empty list of spawns")
        for item in wave:
            if len(item) != 3 or not (0 <= item[1] <= width and 0 <= item[2] <= height):
                raise SystemExit(f"{where}: wave {i} spawn {item} is not inside the room")
            if not os.path.exists(os.path.join(ROOT, "data", "enemies", str(item[0]) + ".json")):
                raise SystemExit(f"{where}: no data/enemies/{item[0]}.json")
    for i, window in enumerate(entry.get("windows", []), 1):
        points = window.get("points") if isinstance(window, dict) else None
        if not (isinstance(points, list) and len(points) >= 3
                and all(len(p) == 2 and 0 <= p[0] <= width and 0 <= p[1] <= height for p in points)):
            raise SystemExit(f"{where}: window {i} is not a polygon inside the room")
        if not WINDOW_DEPTH[0] <= float(window.get("depth", 0.84)) <= WINDOW_DEPTH[1]:
            raise SystemExit(f"{where}: window {i} depth is not within {WINDOW_DEPTH[0]}..{WINDOW_DEPTH[1]}")
    for i, light in enumerate(entry.get("lights", []), 1):
        if len(light) != 6 or not (0 <= light[0] <= width and 0 <= light[1] <= height):
            raise SystemExit(f"{where}: light {i} {light} is not inside the room")
    import front
    front.validate(where, entry.get("front", []), width, height)


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


def _tone(left, right, tone):
    """`left`'s last and `right`'s first `tone` columns bent toward one light:
    row by row (averaged over TONE_ROWS), each side is multiplied halfway to
    the other's, fully at the seam and not at all `tone` px away. A gain, not
    an offset, so a dark stays dark."""
    k = TONE_ROWS
    kernel = np.ones(2 * k + 1) / (2 * k + 1)

    def light(part):
        mean = part[..., :3].astype(np.float64).mean(axis=1)
        return np.stack([np.convolve(np.pad(mean[:, c], k, mode="edge"), kernel, mode="valid")
                         for c in range(3)], axis=1)

    ratio = np.clip((light(left[:, -tone:]) + 8.0) / (light(right[:, :tone]) + 8.0), 1.0 / TONE_LIMIT, TONE_LIMIT)
    ramp = np.arange(1, tone + 1, dtype=np.float64) / tone
    ramp = ramp * ramp * (3.0 - 2.0 * ramp)
    left, right = left.copy(), right.copy()
    left[:, -tone:, :3] *= (ratio[:, None, :] ** (-0.5 * ramp[None, :, None])).astype(np.float32)
    right[:, :tone, :3] *= (ratio[:, None, :] ** (0.5 * ramp[::-1][None, :, None])).astype(np.float32)
    return left, right


def _join(left, right, seam=SEAM):
    """`left` and `right` side by side, the seam between them stitched. Their
    light is evened out first (`_tone`), then each is carried past the seam by
    its own mirror, so the stitch has both pictures over the same band; the
    path keeps to the middle half of it."""
    x = left.shape[1]
    tone = min(TONE, x // 2, right.shape[1] // 2)
    left, right = _tone(left, right, tone)
    a = left[:, x - seam:]
    b = right[:, :seam]
    first = np.concatenate([a, a[:, ::-1]], axis=1)
    second = np.concatenate([b[:, ::-1], b], axis=1)
    band = _stitch(first, second, seam // 2, seam + seam // 2)
    return np.concatenate([left[:, :x - seam], band, right[:, seam:]], axis=1)


def _join_below(top, bottom, seam=SEAM):
    return _join(top.transpose(1, 0, 2), bottom.transpose(1, 0, 2), seam).transpose(1, 0, 2)


## How far into a hole its neighbour's mirror reaches before it is all night.
HOLE_FADE = 360


def night(tiles):
    """The darkest tenth of the paintings, averaged: what a hole is made of.
    Counted on r+g+b, an integer, so the studio's port finds the same edge."""
    counts = np.zeros(766, dtype=np.int64)
    for tile in tiles:
        counts += np.bincount(tile[..., :3].sum(axis=-1).astype(np.int64).ravel(), minlength=766)
    edge = int(np.searchsorted(np.cumsum(counts), 0.1 * counts.sum()))
    total = np.zeros(4, dtype=np.float64)
    for tile in tiles:
        total += tile[tile[..., :3].sum(axis=-1) <= edge].astype(np.float64).sum(axis=0)
    return (total / max(1, int(counts[:edge + 1].sum()))).astype(np.float32)


def hole(tiles, col, row, dark):
    """A hole in the grid: the first neighbour's mirror (left, right, above,
    below) fading into the night, so the picture runs on into the dark instead
    of stopping at a black wall."""
    height, width = CELL[1], CELL[0]
    for dc, dr in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        near = tiles.get((col + dc, row + dr))
        if near is None:
            continue
        if dc:
            mirror = near[:, ::-1]
            distance = np.arange(width, dtype=np.float32)[None, :]
            if dc > 0:
                distance = distance[:, ::-1]
        else:
            mirror = near[::-1]
            distance = np.arange(height, dtype=np.float32)[:, None]
            if dr > 0:
                distance = distance[::-1]
        weight = np.clip(distance / HOLE_FADE, 0.0, 1.0)
        weight = (weight * weight * (3.0 - 2.0 * weight))[..., None]
        return mirror * (1.0 - weight) + dark * weight
    return np.broadcast_to(dark, (height, width, 4)).astype(np.float32)


def compose_tiles(tiles, cols, rows):
    """`tiles` {(col, row): float32 RGBA} as one picture, every seam stitched."""
    dark = night(list(tiles.values()))
    strips = []
    for row in range(rows):
        cells = [tiles[(col, row)] if (col, row) in tiles else hole(tiles, col, row, dark) for col in range(cols)]
        strip = cells[0]
        for cell in cells[1:]:
            strip = _join(strip, cell)
        strips.append(strip)
    picture = strips[0]
    for strip in strips[1:]:
        picture = _join_below(picture, strip)
    return picture


def _tile(path):
    with Image.open(path) as picture:
        return np.asarray(picture.convert("RGBA"), dtype=np.float32)


def compose_picture(entry):
    """The grid as one picture. A hole in the grid runs on from its neighbour
    into the night (`hole`)."""
    cols, rows = grid(entry)
    tiles = {(c["col"], c["row"]): _tile(painting_path(c["painting"])) for c in entry["cells"]}
    return Image.fromarray(np.clip(compose_tiles(tiles, cols, rows) + 0.5, 0, 255).astype(np.uint8), "RGBA")


def far_windows():
    """{room: [index, ...]}: the openings RoomLayers lets slide."""
    with open(ROOM_LAYERS, encoding="utf-8") as f:
        text = f.read()
    block = text[text.index("const FAR_WINDOWS"):]
    block = block[:block.index("\n}")]
    return {name: [int(i) for i in re.findall(r"\d+", indices)]
            for name, indices in re.findall(r'"(\w+)":\s*\[([^\]]*)\]', block)}


def window_depth(index):
    """RoomLayers' own depth for an opening's number: the sky is farthest."""
    return round(min(1.16, max(0.68, 0.68 + 0.16 * (index - 1))), 2)


def owners(painted, depth_windows):
    """{painting stem: (strength, [(index, polygon)])} for every painted room
    whose openings look out: what a cell of that painting brings along."""
    far = far_windows()
    out = {}
    for name, room in painted.items():
        if "painting" not in room or name not in depth_windows:
            continue
        strength, polygons = depth_windows[name]
        keep = far.get(name, list(range(1, len(polygons) + 1)))
        out[room["painting"]] = (strength, [(i, polygon) for i, polygon in enumerate(polygons, 1) if i in keep])
    return out


def windows(entry, owned):
    """The room's openings onto its far plate: the studio's own when it drew
    them, otherwise every far opening of each cell's room, moved into its cell."""
    if "windows" in entry:
        return [{"points": [list(p) for p in w["points"]], "depth": float(w.get("depth", 0.84)),
                 "sky": bool(w.get("sky", False))} for w in entry["windows"]]
    out = []
    for cell in entry["cells"]:
        ox, oy = cell["col"] * CELL[0], cell["row"] * CELL[1]
        for index, polygon in owned.get(cell["painting"], (0, []))[1]:
            out.append({"points": [[x + ox, y + oy] for x, y in polygon], "depth": window_depth(index), "sky": index == 1})
    return out


def depth_parallax(entry, owned):
    strengths = [owned[c["painting"]][0] for c in entry["cells"] if c["painting"] in owned]
    # fsum: exact on every Python (3.12's sum() compensates, 3.11's does not,
    # and 0.085 / 4 sits on the rounding edge)
    return round(math.fsum(strengths) / len(strengths), 4) if strengths else 0.025


def plate_path(stem):
    """What lies behind a painting's openings: its inpainted backfill, or for a
    new painting the painting itself."""
    backfill = next((p for p in (os.path.join(PACK_LEVELS, "depth", stem + "_backfill.png"),
                                  os.path.join(LEVELS, "depth", stem + "_backfill.png")) if os.path.exists(p)), "")
    return backfill if os.path.exists(backfill) else painting_path(stem)


def compose_plate(entry):
    cols, rows = grid(entry)
    tiles = {(c["col"], c["row"]): _tile(plate_path(c["painting"])) for c in entry["cells"]}
    return Image.fromarray(np.clip(compose_tiles(tiles, cols, rows) + 0.5, 0, 255).astype(np.uint8), "RGBA")


def lights(entry):
    """The studio's candles when it placed them; otherwise each panel's own
    where its cell is: the tracer's file beside a painting the game already
    has, the tracer itself for a new one."""
    if "lights" in entry:
        return [tuple(light) for light in entry["lights"]]
    return auto_lights(entry)


def auto_lights(entry):
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


def room_table(name, entry, base, owned=None):
    """The room for generate_rooms.build: the composed geometry under the
    painted room's own sky, with its openings onto the far plate."""
    cols, rows = grid(entry)
    owned = owned or {}
    room = {key: base[key] for key in ATMOSPHERE if key in base}
    room.update(
        composed=True,
        painting_wide="composed/" + name,
        width=cols * CELL[0], height=rows * CELL[1],
        ramps=[tuple(r) for r in entry.get("ramps", [])],
        player=tuple(entry["player"]), door=tuple(entry["door"]),
        decor=[],
        lights=lights(entry),
        light_cap=26 * min(2, len(entry["cells"])),
        windows=windows(entry, owned),
        depth_parallax=depth_parallax(entry, owned),
        front=entry.get("front", []),
    )
    for key in RECTS:
        room[key] = [tuple(r) for r in entry.get(key, [])]
    # as generate_rooms.widen hands a painted room's to build: (x, y, w, kind)
    room["crumbling_platforms"] = [(p[0], p[1], p[2], p[3] if len(p) > 3 else "stone")
                                   for p in entry.get("crumbling_platforms", [])]
    for key in PLACED:
        room[key] = [tuple(item) for item in entry.get(key, [])]
    # reinforcements (room.gd), each wave awake once the one before is down
    room["waves"] = [[list(item) for item in wave] for wave in entry.get("waves", [])]
    return room
