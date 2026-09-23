#!/usr/bin/env python3
"""Batch 9: the platform sheet -> assets/decor/platforms/*.png + manifest.json

    python3 tools/art/slice_batch9.py ~/Downloads

  21_39_03  ruined-stone platforms on transparent background

Families (what the room generator picks from, tools/rooms/generate_rooms.py):
  ground   grass-topped earth blocks, wide: the floor, laid side by side
  cap      a broken-off ground end, jagged on the right (mirrored for the left)
  earth    grass-topped earth blocks, squarer: thick ledges
  ledge    stone shelves with hanging moss, arched undersides: thin platforms
  float    small mossy chunks with a hanging root ball: tiny platforms
  wall     mossy stone wall segments: the room's side boundaries
  pillar   free-standing columns and pedestals: decor
  rock     low rock steps and rubble: decor

Every piece is downscaled by SCALE so a brick course is ~10 px, like
ground_tiles.png, and the alpha is hardened to keep the pixel look. The
manifest stores each piece's size and "top": the row where the solid surface
starts (grass tufts stick up above it), which is where the collider goes.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sheet  # noqa: E402

OUT = os.path.join(sheet.ROOT, "assets", "decor", "platforms")
SCALE = 0.36

# family -> [(row, col), ...] on the detected grid (see sheet.rows)
FAMILIES = {
    "ground": [(0, 0), (0, 1), (0, 2), (0, 5), (0, 6), (0, 7)],
    "cap": [(0, 3), (0, 4)],
    "earth": [(3, 0), (3, 1), (3, 2), (3, 3), (3, 4), (3, 5)],
    "ledge": [(2, 0), (2, 1), (2, 2), (2, 4), (2, 5), (2, 6), (2, 8), (2, 9)],
    "float": [(3, 6), (3, 7), (3, 8)],
    "wall": [(1, 6), (1, 7), (1, 8), (1, 9), (1, 11)],
    "pillar": [(5, 0), (5, 1), (5, 2), (5, 3), (5, 10), (5, 11), (5, 12)],
    "rock": [(5, 4), (5, 5), (5, 6), (5, 7), (5, 8), (5, 9)],
}


def harden(frame, threshold=100):
    arr = np.array(frame)
    arr[:, :, 3] = np.where(arr[:, :, 3] > threshold, 255, 0)
    return Image.fromarray(arr)


def shrink(frame):
    size = (max(1, round(frame.width * SCALE)), max(1, round(frame.height * SCALE)))
    small = frame.resize(size, Image.LANCZOS).filter(ImageFilter.UnsharpMask(radius=1, percent=60, threshold=2))
    return harden(small)


def surface(frame, fraction=0.6):
    """First row where most of the width is opaque: the walkable top."""
    alpha = np.array(frame)[:, :, 3] > 0
    width = alpha.any(axis=0).sum()
    for y, row in enumerate(alpha):
        if row.sum() >= fraction * width:
            return y
    return 0


def main():
    image = sheet.source("21_39_03")
    mask = sheet.alpha_mask(image, 60)
    rows = sheet.rows(sheet.blobs(mask, step=6, min_size=6, pad=2), 0.3)
    os.makedirs(OUT, exist_ok=True)
    manifest = {}
    for family, cells in FAMILIES.items():
        for index, (row, col) in enumerate(cells, 1):
            frame = shrink(sheet.cut(image, mask, rows[row][col]))
            name = f"{family}_{index}"
            frame.save(os.path.join(OUT, name + ".png"))
            manifest[name] = {"family": family, "w": frame.width, "h": frame.height, "top": surface(frame)}
            print(name, frame.size, "top", manifest[name]["top"])
    with open(os.path.join(OUT, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
