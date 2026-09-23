#!/usr/bin/env python3
"""Batch 8: the character sheets and the room fixtures.

    python3 tools/art/slice_batch8.py ~/Downloads

  18_20_46  green spectre  -> assets/sprites/wraith_*.png   72x56  (re-skins the wraith)
  18_22_38  red knight     -> assets/sprites/ash_knight_*.png 96x72 (the new mid-boss)
  18_31_51  Mara           -> assets/sprites/mara_idle.png     32x44 x 8
  18_33_27  Matthew        -> assets/sprites/matthew_idle.png  32x44 x 6
  18_24_15  blind preacher -> assets/sprites/preacher_*.png  56x64  (adds attack + death)
  18_35_01  doors & gates  -> assets/decor/door_gate.png    48x64 x 5
  18_53_26  arena barrier  -> assets/decor/barrier.png       64x80 x 8
  17_53_32  angel shrine   -> assets/decor/shrine.png       48x64 x 8

Every strip of one character keeps a single scale, and every frame is anchored
on the figure (alpha-weighted centre, feet on the bottom row), so the body does
not jump around while a sword or a scythe sweeps out of the frame.
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sheet

WRAITH_CELL = (72, 56)
KNIGHT_CELL = (96, 72)


def anchor_x(frame):
    """Alpha-weighted centre: the body outweighs the thin effects around it."""
    alpha = np.array(frame)[:, :, 3].astype(np.float32)
    weight = alpha.sum(axis=0)
    if weight.sum() == 0:
        return frame.width / 2.0
    return float((np.arange(frame.width) * weight).sum() / weight.sum())


def character(image, mask, rows, cell, scale, name, animations, folder=sheet.SPRITES):
    cw, ch = cell
    print(f"{name}:")
    for anim, picks in animations.items():
        cells = []
        for row, index in picks:
            box = rows[row][index]
            frame = sheet.cut(image, mask, box)
            size = (max(1, round(frame.width * scale)), max(1, round(frame.height * scale)))
            small = sheet.resize(frame, size)
            out = Image.new("RGBA", cell, (0, 0, 0, 0))
            out.alpha_composite(small, (round(cw / 2.0 - anchor_x(small)), ch - small.height - 1))
            cells.append(out)
        sheet.strip(cells, f"{name}_{anim}", folder)


def wraith():
    image = sheet.source("18_20_46")
    mask = sheet.alpha_mask(image, 70)
    rows = sheet.rows(sheet.blobs(mask, min_size=14))
    scale = 46.0 / (rows[0][0][3] - rows[0][0][1])
    character(image, mask, rows, WRAITH_CELL, scale, "wraith", {
        "idle": [(0, i) for i in range(4)],
        "walk": [(1, i) for i in range(6)],
        "attack": [(4, i) for i in range(3)],  # hands up, gathering, release
        "death": [(5, i) for i in (6, 7, 8, 9, 10)],
    })


def knight():
    image = sheet.source("18_22_38")
    mask = sheet.alpha_mask(image, 70)
    rows = sheet.rows(sheet.blobs(mask, min_size=14))
    scale = 62.0 / (rows[0][0][3] - rows[0][0][1])
    character(image, mask, rows, KNIGHT_CELL, scale, "ash_knight", {
        "idle": [(0, i) for i in range(5)],
        "walk": [(1, i) for i in range(6)],
        # frame 0 is held through the wind-up: the sword goes up and stays up
        "attack": [(3, 1), (3, 2), (3, 3), (3, 4)],
        "death": [(5, i) for i in (1, 3, 5, 6, 7)],
    })


def npcs():
    """The two story NPCs, on their painted sheets: only the idle row is used."""
    for stamp, name, count in (("18_31_51", "mara", 8), ("18_33_27", "matthew", 6)):
        image = sheet.source(stamp)
        mask = sheet.denoise(sheet.panel_mask(image, (41, 38, 36), 30) & (np.array(image)[:, :, 3] > 60))
        rows = sheet.rows(sheet.blobs(mask, min_size=20))
        # the first row band that holds full figures rather than title and labels
        # a figure is tall and narrow; the title block and the palette swatches are not
        figures = next(f for f in ([b for b in row if b[3] - b[1] > 120 and b[2] - b[0] < 110] for row in rows)
                       if len(f) >= count)
        scale = 44.0 / (figures[0][3] - figures[0][1])
        print(f"{name}:")
        cells = []
        for box in figures[:count]:
            frame = sheet.solid_cut(image, mask, box)
            small = sheet.resize(frame, (max(1, round(frame.width * scale)), max(1, round(frame.height * scale))))
            out = Image.new("RGBA", (32, 44), (0, 0, 0, 0))
            out.alpha_composite(small, (round(16 - anchor_x(small)), 44 - small.height))
            cells.append(out)
        sheet.strip(cells, f"{name}_idle")


def preacher():
    """The labelled mid-boss sheet: a censer swing and a proper collapse."""
    image = sheet.source("18_24_15")
    mask = sheet.denoise(sheet.alpha_mask(image, 170))  # the sheet has a faint panel wash
    rows = [[b for b in row if b[3] - b[1] > 40] for row in sheet.rows(sheet.blobs(mask, min_size=16))]
    scale = 56.0 / (rows[1][1][3] - rows[1][1][1])
    character(image, mask, rows, (56, 64), scale, "preacher", {
        "idle": [(1, i) for i in range(1, 7)],       # [0] of that row is the sheet's title block
        "walk": [(1, i) for i in range(7, 13)],
        "attack": [(4, 6), (4, 7), (4, 8), (4, 10), (4, 13)],  # censer up, then the swing
        "death": [(8, i) for i in (4, 5, 6, 7, 8)],
    })


def gate():
    """The room exit: chained shut while enemies live, then it swings open."""
    image = sheet.source("18_35_01")
    mask = sheet.alpha_mask(image, 90)
    rows = sheet.rows(sheet.blobs(mask, min_size=12))
    row = rows[12]  # ornate iron gate: 0-7 open/close cycle, 8-10 locked, 11+ broken
    print("gate:")
    cells = [sheet.fit(sheet.cut(image, mask, row[i]), (48, 64), "center") for i in (10, 1, 2, 3, 4)]
    sheet.strip(cells, "door_gate", sheet.DECOR)


def barrier():
    """The boss arena wall. The walls touch each other on the sheet, so the idle
    row is cut on its own geometry: one frame per bay, pillar to pillar."""
    image = sheet.source("18_53_26")
    top, bottom = 302, 404  # below the panel's haze, down to the bases
    pixels = np.array(image).astype(np.int32)
    band = pixels[top:bottom, :800]
    # the pillars are grey stone, the wall between them is blue light
    stone = ((band[:, :, 2] - band[:, :, 0]) < 12) & (band[:, :, :3].max(axis=2) > 45)
    columns = stone.sum(axis=0) > 40
    centres, run = [], None
    for x, lit in enumerate(columns):
        if lit and run is None:
            run = x
        elif not lit and run is not None:
            if x - run > 2:
                centres.append((run + x) // 2)
            run = None
    merged = []
    for centre in centres:  # a pillar's silhouette breaks into two runs at its waist
        if merged and centre - merged[-1] < 40:
            merged[-1] = (merged[-1] + centre) // 2
        else:
            merged.append(centre)
    centres = merged
    print("barrier:")
    cells = []
    for left, right in zip(centres, centres[1:]):
        frame = image.crop((left - 14, top, right + 14, bottom)).convert("RGBA")
        rgba = np.array(frame)
        lit = rgba[:, :, :3].max(axis=2).astype(np.int32)
        # the blue light fades out; the stone pillars are dark but never panel-dark
        pillar = ((rgba[:, :, 2].astype(np.int32) - rgba[:, :, 0]) < 12) & (lit > 24)
        rgba[:, :, 3] = np.maximum(np.clip((lit - 34) * 6, 0, 255), pillar * 255)
        cells.append(sheet.fit(Image.fromarray(rgba), (64, 80), "bottom", margin=0, threshold=100))
    sheet.strip(cells, "barrier", sheet.DECOR)


def shrine():
    """The angel shrine: dark while the room is dangerous, lit once it is not."""
    image = sheet.source("17_53_32")
    mask = sheet.alpha_mask(image, 70)
    rows = sheet.rows(sheet.blobs(mask, min_size=14))
    row = rows[0]  # the same statue, its halo and candles coming up frame by frame
    print("shrine:")
    scale = 64.0 / (row[0][3] - row[0][1])
    cells = []
    for box in row[:8]:
        frame = sheet.cut(image, mask, box)
        small = sheet.resize(frame, (max(1, round(frame.width * scale)), max(1, round(frame.height * scale))))
        out = Image.new("RGBA", (48, 64), (0, 0, 0, 0))
        out.alpha_composite(small, ((48 - small.width) // 2, 64 - small.height))
        cells.append(out)
    sheet.strip(cells, "shrine", sheet.DECOR)


if __name__ == "__main__":
    wraith()
    knight()
    npcs()
    preacher()
    gate()
    barrier()
    shrine()
