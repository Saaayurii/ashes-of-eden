#!/usr/bin/env python3
"""Batch 7: props — breakable containers, chests and the item icons.

    python3 tools/art/slice_batch7.py ~/Downloads

Sources (all transparent PNGs, sprites found by connected blobs, see sheet.py):
  18_48_20  barrels / crates / pots / sacks, 5 states each
            -> assets/props/<prop>.png   48x40 x 4  (whole, cracked, breaking, debris)
  18_37_39  chests, 8 states each        -> assets/props/chest_*.png 40x32 x 4
  18_48_41  loose items                  -> assets/icons/*.png       (single sprites)

One scale per row, taken from the intact frame, so a barrel does not grow while
it breaks. Frames are bottom-anchored: the prop sits on the ground in the room.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sheet

DESTRUCTIBLE_CELL = (48, 40)
CHEST_CELL = (40, 32)

# row in the sheet -> (name, height of the intact frame in game pixels)
DESTRUCTIBLES = {
    0: ("barrel", 26),
    1: ("barrel_iron", 26),
    2: ("crate", 24),
    3: ("crate_large", 30),
    4: ("crates_stacked", 34),
    5: ("pot", 22),
    6: ("sack", 20),
}
CHESTS = {0: ("chest_wooden", 22), 2: ("chest_cursed", 22), 3: ("chest_gold", 22)}


def main_boxes(boxes, keep=0.2):
    """Drop the loose splinters and dust puffs: the states are the big blobs."""
    area = (boxes[0][2] - boxes[0][0]) * (boxes[0][3] - boxes[0][1])
    return [b for b in boxes if (b[2] - b[0]) * (b[3] - b[1]) >= area * keep]


def row_strip(image, mask, boxes, name, cell, height, folder=sheet.PROPS):
    """One scale for the whole row: the intact frame decides it."""
    cw, ch = cell
    scale = height / (boxes[0][3] - boxes[0][1])
    scale = min(scale, min((cw - 2) / (b[2] - b[0]) for b in boxes))
    cells = []
    for box in boxes:
        frame = sheet.cut(image, mask, box)
        frame = sheet.resize(frame, (max(1, round(frame.width * scale)), max(1, round(frame.height * scale))))
        out = sheet.Image.new("RGBA", cell, (0, 0, 0, 0))
        out.alpha_composite(frame, ((cw - frame.width) // 2, ch - frame.height - 1))
        cells.append(out)
    sheet.strip(cells, name, folder)


def destructibles():
    image = sheet.source("18_48_20")
    mask = sheet.alpha_mask(image)
    rows = sheet.rows(sheet.blobs(mask))
    print("destructibles:")
    for index, (name, height) in DESTRUCTIBLES.items():
        # 0 whole, 1-2 cracking, 3 broken open, 4 bursting, 5 debris on the ground;
        # the engine only needs whole -> cracked -> bursting -> debris.
        boxes = main_boxes(rows[index])
        row_strip(image, mask, [boxes[0], boxes[2], boxes[4], boxes[5]], name, DESTRUCTIBLE_CELL, height)


def chests():
    image = sheet.source("18_37_39")
    mask = sheet.alpha_mask(image, 170)
    rows = sheet.rows(sheet.blobs(mask, min_size=12))
    print("chests:")
    for index, (name, height) in CHESTS.items():
        boxes = rows[index][:4]  # closed, lid ajar, lid up, open and lit
        row_strip(image, mask, boxes, name, CHEST_CELL, height)


def icons():
    """The loose items: a single png each, for UI and pickups."""
    image = sheet.source("18_48_41")
    mask = sheet.alpha_mask(image, 120)
    rows = sheet.rows(sheet.blobs(mask, min_size=10))
    print("icons:")
    # (row, column) -> name, kept to the few the game actually shows
    wanted = {
        (0, 2): "potion_red", (1, 2): "crystal_blue", (3, 2): "key_iron",
        (3, 6): "key_gold", (4, 3): "scroll", (4, 6): "cross_gold",
        (6, 1): "coins", (6, 5): "gem_red",
    }
    for (r, c), name in wanted.items():
        if r >= len(rows) or c >= len(rows[r]):
            continue
        sheet.single(sheet.cut(image, mask, rows[r][c]), name, height=24, folder=sheet.ICONS)


if __name__ == "__main__":
    destructibles()
    chests()
    icons()
