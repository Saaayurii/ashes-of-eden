#!/usr/bin/env python3
"""Every hero strip in assets/sprites/elian_*.png (+ the sword effects) from
the generated sheets in ~/Downloads.

    python3 tools/art/slice_hero.py [~/Downloads]
    python3 tools/art/slice_hero.py --contact      # also writes tools/art/contact/hero.png

Sheets:
  17_48_31  base: idle, walk, run, the short swing (guard borrows two frames), roll, death
  17_50_34  civilian: wake, talk (the intro)
  02_59_35  unarmed idle ("rest") and a talking shrug
  03_05_31  drawing the sword: rest -> armed idle
  02_57_22  six swings: slash, overhead, rising, thrust, slam, dash strike
  02_54_54  hurt, and crouching after a landing
  03_01_57  jump, fall
  03_04_04  knocked off the feet
  03_24_05  climbing: pulling himself up onto a ledge
  02_50_03  sword effects: slash arcs in four colours, a hit spark, a blood burst

The sheets are drawn at different sizes, so every one has its own scale, chosen
so the standing body is STANDING px tall in all of them. All strips share one 128x64
cell and one anchor: the feet stand at FEET_X, 4 px right of the cell centre
(the cape hangs left), on the bottom row, which is where the player scene
expects them (Body sits 20 px above the collision centre: feet 4 px clear of the floor, like the enemies). The cell is wide
so the longest swing keeps its arc, and tall so a body tumbling through the
air keeps its head. Strips whose feet are not a fixed point — a run, a body
lying down — are centred on their bounding box instead ("center"); airborne
strips ("air": jump, fall, knockback, climb, waking) on their centre of mass,
so a cape spread wide does not push the body off the collision box. The roll
and the dash strike trail long grey speed lines, so they are anchored on the
red cloth alone ("cloth"): the hood and cape are always on the body.

Frames are found as connected blobs, not cut as rectangles: a slash arc that
hangs over the next figure's cape stays with the figure that swung it, and the
cape with the one wearing it. Where a sword tip touches a neighbour's cape the
two blobs are pried apart by a small ERASE box (a few pixels lost at 4x
downscale). A blob with no body of its own — an arc, a spark, a drop of blood
— goes to the figure whose box it overlaps most, otherwise to the nearest
figure on its left (the hero faces right; his effects fly right).
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sheet  # noqa: E402

CELL = (128, 64)
FEET_X = 68
FX_CELL = (80, 48)
STANDING = 43.0  # the knight in the village is 44 px tall; Elian stands a hair under him
CONTACT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "contact", "hero.png")

# One entry per sheet. "rows" lists the strips in reading order (top to
# bottom, left to right) with their frame counts; a row of the sheet can hold
# several strips back to back. "black" sheets have no alpha: the background is
# black. "erase" boxes cut the bridges between figures that touch; a "seam"
# box is for a sword drawn across the next figure's cape: inside it, the
# red/not-red boundary is cut, so the grey blade stays with its hand and the
# red cloth with its wearer.
SHEETS = [
    dict(stamp="17_48_31", scale=STANDING / 163, rows=[[("elian_idle", 4), ("elian_walk", 8)], [("elian_run", 5)],
         [("elian_attack", 5)], [(None, 4)], [("elian_roll", 5)], [("elian_death", 5)]],
         center=["elian_run", "elian_walk", "elian_death"], cloth=["elian_roll"], min_body=3500, crop=1000),  # below 1000: the old slash row, superseded
    dict(stamp="17_50_34", scale=STANDING / 155, min_body=2500,
         # the civilian sheet is a page of poses; pick by hand (see slice_batch5)
         pick={"elian_wake": [(659, 830, 898, 940), (445, 830, 638, 940), (258, 830, 418, 940), (92, 830, 231, 940),
                              (97, 941, 207, 1059), (264, 941, 382, 1059), (434, 941, 563, 1059),
                              (541, 656, 639, 812), (324, 656, 441, 812), (106, 656, 226, 812), (101, 27, 188, 182)],
               "elian_talk": [(95, 368, 185, 507), (263, 368, 383, 507), (432, 368, 550, 507), (591, 368, 678, 507)]},
         air=["elian_wake"]),
    dict(stamp="02_59_35", scale=STANDING / 261, rows=[[("elian_rest", 8)], [("elian_talk2", 8)]]),
    dict(stamp="03_05_31", black=True, scale=STANDING / 252, rows=[[("elian_draw", 8)]]),
    dict(stamp="02_57_22", scale=STANDING / 176, seam=[(636, 70, 716, 160)],
         rows=[[("elian_slash", 6)], [("elian_overhead", 6)], [("elian_rising", 5)], [("elian_thrust", 5)],
               [("elian_slam", 5)], [("elian_dash_strike", 5)]], cloth=["elian_dash_strike"]),
    dict(stamp="02_54_54", scale=STANDING / 298, rows=[[("elian_hurt", 4)], [("elian_land", 4)]]),
    dict(stamp="03_01_57", scale=STANDING / 298, rows=[[("elian_jump", 4)], [("elian_fall", 4)]],
         air=["elian_jump", "elian_fall"]),
    dict(stamp="03_04_04", black=True, scale=STANDING / 298, rows=[[("elian_knockback", 4)], [("elian_knockback", 4)]],
         air=["elian_knockback"]),
    dict(stamp="03_24_05", black=True, scale=STANDING / 298, rows=[[("elian_climb", 4)], [("elian_climb", 4)]],
         air=["elian_climb"]),
    dict(stamp="02_50_03", scale=0.29, cell=FX_CELL, fx=True, min_body=300, row_gap=90,
         rows=[[("slash_white", 5)], [("slash_heavy", 6)], [("slash_gold", 6)], [("slash_red", 6)],
               [("hit_spark", 5)], [("hit_blood", 5)]]),
]


def load(spec, src):
    image = sheet.source(spec["stamp"], src)
    if spec.get("black"):
        mask = np.array(image)[:, :, :3].astype(int).sum(axis=2) > 60
        rgba = np.array(image)
        rgba[:, :, 3] = np.where(mask, 255, 0)
        image = Image.fromarray(rgba)
    else:
        mask = sheet.alpha_mask(image)
    for x0, y0, x1, y1 in spec.get("erase", []):
        mask[y0:y1, x0:x1] = False
    for x0, y0, x1, y1 in spec.get("seam", []):
        rgb = np.array(image)[y0:y1, x0:x1, :3].astype(int)
        red = (rgb[:, :, 0] > rgb[:, :, 1] * 1.35) & (rgb[:, :, 0] > rgb[:, :, 2] * 1.35) & mask[y0:y1, x0:x1]
        grey = mask[y0:y1, x0:x1] & ~red
        edge = np.zeros_like(red)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            shifted = np.roll(red, (dy, dx), axis=(0, 1))
            edge |= grey & shifted  # a grey pixel next to a red one, and the red one itself
            edge |= red & np.roll(grey, (dy, dx), axis=(0, 1))
        # two pixels deep on both sides: the labeler joins anything closer than that
        grown = edge.copy()
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            grown |= np.roll(edge, (dy, dx), axis=(0, 1))
        mask[y0:y1, x0:x1] &= ~grown
    if "crop" in spec:
        mask[spec["crop"]:] = False
    return image, mask


def figures(spec, mask, expected):
    """[(body box, [labels])] per row, reading order, with loose bits attached.

    [expected] is the number of figures per row; when a row has more, the
    smallest extras (a big sparkle, a flying boot) are loose bits after all.
    """
    labels, info = sheet.components(mask, connect=1)
    min_body = spec.get("min_body", 6000)
    bodies = {k: v for k, v in info.items() if v[4] >= min_body}
    loose = {k: v for k, v in info.items() if v[4] < min_body}
    for row, count in zip(_rows(spec, bodies), expected):
        for label, box in sorted(row, key=lambda kv: kv[1][4])[:max(0, len(row) - count)]:
            loose[label] = bodies.pop(label)
    rows = _rows(spec, bodies)
    members = {label: [label] for label in bodies}
    for label, box in loose.items():
        best, best_overlap = None, 0
        for body, bbox in bodies.items():
            ox = min(box[2], bbox[2]) - max(box[0], bbox[0])
            oy = min(box[3], bbox[3]) - max(box[1], bbox[1])
            if ox > 0 and oy > 0 and ox * oy > best_overlap:
                best, best_overlap = body, ox * oy
        if best is None:
            cx = (box[0] + box[2]) / 2
            cy = (box[1] + box[3]) / 2
            lefts = [(cx - (b[0] + b[2]) / 2, k) for k, b in bodies.items()
                     if b[1] - 60 < cy < b[3] + 60 and (b[0] + b[2]) / 2 < cx]
            if not lefts:
                continue
            best = min(lefts)[1]
        members[best].append(label)
    return labels, [[(box, members[label]) for label, box in row] for row in rows]


def _rows(spec, bodies):
    """Bodies grouped by baseline (their bottoms), top to bottom, left to right."""
    ordered = sorted(bodies.items(), key=lambda kv: kv[1][3])
    rows = []
    row_gap = spec.get("row_gap", 40)
    for label, box in ordered:
        if rows and abs(box[3] - rows[-1][-1][1][3]) < row_gap:
            rows[-1].append((label, box))
        else:
            rows.append([(label, box)])
    rows = [sorted(row, key=lambda kv: kv[1][0]) for row in rows]
    rows.sort(key=lambda row: row[0][1][3])
    return rows


def render(image, labels, keep, box=None):
    """The pixels of these blobs only, cropped to their union."""
    chosen = np.isin(labels, keep)
    if box is None:
        ys, xs = np.nonzero(chosen)
        box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    x0, y0, x1, y1 = box
    rgba = np.array(image.crop((x0, y0, x1, y1)))
    rgba[:, :, 3] = np.where(chosen[y0:y1, x0:x1], rgba[:, :, 3], 0)
    return Image.fromarray(rgba), box


def mass_x(mask, box):
    """Centre of mass of the pixels in the box, relative to its left edge."""
    xs = np.nonzero(mask[box[1]:box[3], box[0]:box[2]])[1]
    return float(xs.mean()) if len(xs) else (box[2] - box[0]) / 2.0


## Where the front of the hood sits, right of the body's centre, in cell pixels.
HOOD_LEAD = 8.0


def cloth_x(image, mask, box, scale):
    """The body's centre guessed from the red cloth: the hood is the rightmost
    red thing on a hero facing right, the cape trails behind. Relative to the
    box's left edge."""
    rgb = np.array(image)[box[1]:box[3], box[0]:box[2], :3].astype(int)
    red = mask[box[1]:box[3], box[0]:box[2]] & (rgb[:, :, 0] > rgb[:, :, 1] * 1.6) & (rgb[:, :, 0] > rgb[:, :, 2] * 1.6)
    xs = np.nonzero(red)[1]
    return xs.max() - HOOD_LEAD / scale if len(xs) else (box[2] - box[0]) / 2.0


def anchor_for(spec, name, mask, box, body_box, image=None):
    if spec.get("fx"):
        return None
    if name in spec.get("cloth", []):
        return ("center", cloth_x(image, mask, box, spec["scale"]))
    if name in spec.get("air", []):
        return ("center", mass_x(mask, box))
    if name in spec.get("center", []):
        return ("center", (box[2] - box[0]) / 2.0)
    return ("feet", feet_x(mask, box, body_box))


def feet_x(mask, box, body_box):
    """Horizontal centre of the lowest 8 % of the body: where it stands."""
    bx0, by0, bx1, by1 = body_box[:4]
    band = mask[max(by0, by1 - max(4, int((by1 - by0) * 0.08))):by1, bx0:bx1]
    xs = np.nonzero(band.any(axis=0))[0]
    return bx0 + (xs.min() + xs.max()) / 2.0 - box[0]


def place(frame, scale, cell, anchor=None):
    """Scale, then set into the cell on the bottom row: ("feet", x) puts that
    source x at FEET_X, ("center", x) at the cell's centre; None (effects)
    centres the frame both ways."""
    cw, ch = cell
    scaled = sheet.resize(frame, (max(1, round(frame.width * scale)), max(1, round(frame.height * scale))))
    out = Image.new("RGBA", cell, (0, 0, 0, 0))
    if anchor is None:
        x = (cw - scaled.width) // 2
        y = (ch - scaled.height) // 2
    else:
        kind, anchor_x = anchor
        x = int(round((FEET_X if kind == "feet" else cw / 2.0) - anchor_x * scale))
        y = ch - scaled.height - 1
    # A wide swing keeps its feet where they are and runs its tip to the edge.
    out.alpha_composite(scaled.crop((max(0, -x), max(0, -y), min(scaled.width, cw - x), min(scaled.height, ch - y))),
                        (max(0, x), max(0, y)))
    return out


def slice_sheet(spec, src, strips):
    image, mask = load(spec, src)
    scale = spec["scale"]
    cell = spec.get("cell", CELL)
    if "pick" in spec:
        for name, boxes in spec["pick"].items():
            cells = []
            for box in boxes:
                tight = sheet.tighten(mask, [box])[0]
                frame = sheet.cut(image, mask, tight)
                cells.append(place(frame, scale, cell, anchor_for(spec, name, mask, tight, tight)))
            strips[name] = cells
        return
    wanted = spec["rows"]
    labels, rows = figures(spec, mask, [sum(n for _, n in plan) for plan in wanted])
    if len(rows) != len(wanted):
        sys.exit(f"{spec['stamp']}: found {len(rows)} rows, expected {len(wanted)}: "
                 + str([len(r) for r in rows]))
    for row, plan in zip(rows, wanted):
        expected = sum(n for _, n in plan)
        if len(row) != expected:
            sys.exit(f"{spec['stamp']}: a row has {len(row)} figures, expected {expected} "
                     f"({[(b[0], b[2]) for b, _ in row]})")
        index = 0
        for name, count in plan:
            for body_box, keep in row[index:index + count]:
                if name is None:
                    continue
                frame, box = render(image, labels, keep)
                strips.setdefault(name, []).append(place(frame, scale, cell, anchor_for(spec, name, mask, box, body_box, image)))
            index += count


def contact(strips):
    """Every strip at 3x, one per line, so a bad cut is obvious at a glance."""
    names = sorted(strips)
    width = max(len(cells) * cells[0].width for cells in strips.values()) * 3 + 120
    height = sum(strips[n][0].height * 3 + 8 for n in names)
    page = Image.new("RGBA", (width, height), (40, 40, 48, 255))
    draw = ImageDraw.Draw(page)
    y = 0
    for name in names:
        cells = strips[name]
        draw.text((4, y + 4), name, fill=(255, 230, 120, 255))
        for i, cell in enumerate(cells):
            big = cell.resize((cell.width * 3, cell.height * 3), Image.NEAREST)
            x = 120 + i * big.width
            draw.rectangle((x, y, x + big.width - 1, y + big.height - 1), outline=(80, 80, 90, 255))
            page.alpha_composite(big, (x, y))
        y += cells[0].height * 3 + 8
    os.makedirs(os.path.dirname(CONTACT), exist_ok=True)
    page.save(CONTACT)
    print("contact sheet:", os.path.relpath(CONTACT, sheet.ROOT))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    src = args[0] if args else os.path.expanduser("~/Downloads")
    strips = {}
    for spec in SHEETS:
        slice_sheet(spec, src, strips)
    for name, cells in strips.items():
        sheet.strip(cells, name)
    if "--contact" in sys.argv:
        contact(strips)


if __name__ == "__main__":
    main()
