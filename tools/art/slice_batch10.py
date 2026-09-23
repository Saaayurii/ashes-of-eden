#!/usr/bin/env python3
"""Batch 10: the catalogue sheets -> decor, icons, props

    python3 tools/art/slice_batch10.py [~/Downloads] [family ...]
    python3 tools/art/slice_batch10.py --contact 17_37_21      # debug view of a sheet

  17_37_21  "Graveyard Props"  tombstones, crosses, monuments, railings, crypts,
            coffins, candles, dead wood, angels, bones, ground  -> decor/graveyard/
  17_35_16  "Dead Trees"       medium and small trees, fallen trunks, stumps,
            undergrowth, ground                                 -> decor/wilds/
  17_39_39  "Dark Realms"      resources, potions, gear, marks, banners,
            documents, relics, weather, trophies, runes         -> icons/realm/
  18_50_45  "Quest Items"      keys, letters, relics, essence, herbs, tools,
            ritual things, keepsakes, emblems, curios           -> icons/quest/
  18_46_57  chests and clutter  iron chest, box of goods, barrel of apples,
            brazier and altar, static clutter                   -> props/, decor/clutter/
  18_45_04  destructibles       a rubble heap that breaks       -> props/

These sheets are catalogues: labelled boxes of loose objects. A band below is a
rectangle in fractions of the sheet and the height its sprites end up at; every
blob inside becomes one png, read left to right, top to bottom. The fractions
come off a gridded view of the sheet. A strip is the same, but its blobs are
animation frames: the chosen ones go into one cell-sized strip, the way
data/props/*.json expects (Fx.add_strip / Prop).

Heights follow what is already in assets/ (tombstone 40, monument 56, railing
44, crypt 72, tree 110, icon 24, prop cell 48x40) so a new piece stands next to
an old one without looking like it came from another game. Everything goes into
its own folder, so nothing here can overwrite an asset an earlier batch made.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sheet  # noqa: E402

ASSETS = os.path.join(sheet.ROOT, "assets")
GRAVEYARD = os.path.join(sheet.DECOR, "graveyard")
WILDS = os.path.join(sheet.DECOR, "wilds")
CLUTTER = os.path.join(sheet.DECOR, "clutter")
REALM = os.path.join(sheet.ICONS, "realm")
QUEST = os.path.join(sheet.ICONS, "quest")
CONTACT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "contact")

# Options a band can carry:
#   close  how wide a gap in an outline is bridged before the inside is filled
#          (5). Railings and flames want 1, or the gaps between the bars and the
#          dark around a flame are filled in with the stone.
#   label  captions are dropped when shorter than this many sheet pixels (22).
#          Icon sheets draw some icons barely taller than their captions.
#   skip   indices (1-based, after sorting) that are not sprites at all.
#   step   how far apart two parts may sit and still be one sprite (5). Tightly
#          packed rows (letters, keepsakes) want 3, or neighbours fuse.
#   ink    how far from the band's own background a pixel must be to count (24).
#          Where soft drop shadows join neighbouring items, raise it.
#   wide   drop anything wider than this many times its height: on an icon row
#          that is two or three items fused into one, never a real icon.
SHEETS = {
    "17_37_21": [
        (GRAVEYARD, "tomb", (0.22, 0.02, 1.00, 0.185), 40, 900, {}),
        (GRAVEYARD, "cross", (0.22, 0.19, 0.60, 0.380), 56, 900, {}),
        (GRAVEYARD, "monument", (0.60, 0.19, 1.00, 0.380), 64, 900, {}),
        (GRAVEYARD, "railing", (0.22, 0.385, 0.68, 0.555), 44, 900, {"close": 1}),
        (GRAVEYARD, "crypt", (0.68, 0.385, 1.00, 0.555), 72, 1400, {}),
        (GRAVEYARD, "coffin", (0.22, 0.56, 0.52, 0.690), 26, 700, {}),
        (GRAVEYARD, "grave", (0.52, 0.56, 0.72, 0.690), 22, 500, {"close": 1}),   # bones, a spade, a lantern
        (GRAVEYARD, "yard", (0.72, 0.56, 1.00, 0.690), 40, 500, {"close": 1}),    # candles, a cart, a raven
        (GRAVEYARD, "deadwood", (0.22, 0.69, 0.52, 0.820), 72, 900, {"skip": (5,)}),   # 5: a slab, not wood
        (GRAVEYARD, "angel", (0.52, 0.69, 0.81, 0.820), 64, 700, {"skip": (1, 6)}),   # a slab, a stray wing
        (GRAVEYARD, "bones", (0.81, 0.69, 1.00, 0.820), 22, 400, {}),
        (GRAVEYARD, "ground", (0.01, 0.82, 0.32, 0.960), 32, 900, {}),
    ],
    "17_35_16": [
        (WILDS, "tree", (0.285, 0.345, 0.675, 0.500), 84, 1500, {}),
        (WILDS, "sapling", (0.700, 0.345, 0.995, 0.500), 60, 1200, {}),
        (WILDS, "fallen", (0.285, 0.515, 0.700, 0.615), 30, 900, {}),
        (WILDS, "stump", (0.700, 0.515, 0.995, 0.615), 34, 900, {}),
        (WILDS, "brush", (0.285, 0.650, 0.700, 0.765), 30, 600, {}),
        (WILDS, "ground", (0.010, 0.810, 0.405, 0.925), 32, 900, {}),
    ],
    "17_39_39": [
        (REALM, "resource", (0.195, 0.180, 0.465, 0.350), 24, 250, {"label": 16}),
        (REALM, "potion", (0.470, 0.180, 0.750, 0.350), 24, 250, {"label": 16}),
        (REALM, "gear", (0.755, 0.180, 0.995, 0.350), 24, 250, {"label": 16}),
        (REALM, "status", (0.195, 0.395, 0.380, 0.490), 24, 200, {"label": 16}),
        (REALM, "marker", (0.380, 0.395, 0.700, 0.490), 24, 200, {"label": 16}),
        (REALM, "banner", (0.700, 0.395, 0.995, 0.495), 24, 300, {"label": 16}),
        (REALM, "document", (0.260, 0.535, 0.490, 0.605), 24, 250, {"label": 16}),
        (REALM, "relic", (0.495, 0.535, 0.750, 0.605), 24, 250, {"label": 16}),
        (REALM, "trinket", (0.755, 0.535, 0.995, 0.605), 24, 150, {"label": 14}),
        (REALM, "weather", (0.655, 0.645, 0.855, 0.705), 24, 150, {"label": 14}),
        (REALM, "trophy", (0.010, 0.745, 0.265, 0.805), 24, 250, {"label": 16}),
        (REALM, "loot", (0.790, 0.745, 0.995, 0.805), 24, 250, {"label": 16}),
        (REALM, "badge", (0.550, 0.855, 0.740, 0.905), 24, 150, {"label": 14}),
        (REALM, "rune", (0.745, 0.855, 0.995, 0.905), 24, 250, {"label": 16}),
    ],
    "18_50_45": [
        (QUEST, "key", (0.010, 0.085, 0.340, 0.200), 24, 600, {}),
        (QUEST, "letter", (0.350, 0.085, 0.680, 0.200), 24, 600, {"step": 3, "ink": 44, "wide": 1.9}),
        (QUEST, "relic", (0.690, 0.085, 0.995, 0.200), 24, 600, {}),
        (QUEST, "essence", (0.010, 0.280, 0.340, 0.400), 24, 600, {}),
        (QUEST, "remedy", (0.350, 0.280, 0.680, 0.400), 24, 600, {}),
        (QUEST, "gatekey", (0.690, 0.280, 0.995, 0.400), 24, 600, {}),
        (QUEST, "tool", (0.010, 0.455, 0.340, 0.575), 24, 600, {}),
        (QUEST, "material", (0.350, 0.455, 0.680, 0.575), 24, 600, {}),
        (QUEST, "ritual", (0.690, 0.455, 0.995, 0.575), 24, 600, {}),
        (QUEST, "keepsake", (0.010, 0.625, 0.340, 0.740), 24, 600, {"step": 3, "ink": 44, "wide": 1.9}),
        (QUEST, "emblem", (0.350, 0.625, 0.680, 0.740), 24, 600, {}),
        (QUEST, "flask", (0.690, 0.625, 0.995, 0.740), 24, 600, {}),
        (QUEST, "trophy", (0.010, 0.805, 0.340, 0.910), 24, 600, {"step": 3, "ink": 44, "wide": 1.9}),
        (QUEST, "curio", (0.350, 0.805, 0.680, 0.910), 24, 600, {}),
    ],
    "18_46_57": [
        (CLUTTER, "clutter", (0.655, 0.455, 0.995, 0.560), 30, 700, {}),
    ],
}

# Animation strips: name, band, frames to keep (1-based, left to right), cell, folder.
# A brazier or an altar is also worth having lit and standing still, as plain
# decor a room table can place: those get their last frame saved as <name>_lit.
STRIPS = {
    "18_46_57": [
        ("chest_iron", (0.255, 0.050, 0.500, 0.128), [1, 2, 3, 4, 5, 6], (40, 32), sheet.PROPS),
        ("barrel_apples", (0.255, 0.265, 0.500, 0.375), [1, 2, 4, 5], (48, 40), sheet.PROPS),
        ("box_goods", (0.460, 0.455, 0.645, 0.560), [1, 2, 3, 4], (48, 40), sheet.PROPS),
        ("brazier", (0.010, 0.830, 0.195, 0.910), [1, 2, 3, 4], (32, 40), CLUTTER),
        ("altar", (0.200, 0.830, 0.395, 0.910), [1, 2, 3, 4], (32, 40), CLUTTER),
    ],
    "18_45_04": [
        ("rubble", (0.000, 0.870, 0.560, 0.995), [1, 2, 3, 4], (48, 40), sheet.PROPS),
    ],
}


def mask_for(image):
    """Alpha where the sheet has it, otherwise everything off the panel colour.

    Returns the mask and whether it came from a painted panel (see solid_piece).
    """
    a = np.array(image)
    # A real cut-out has a large, fully transparent background. Several of
    # these sheets are instead a painted panel exported with a slightly
    # translucent, noisy alpha (244..252 across the whole panel), which says
    # nothing about where the sprites are: those are read from colour.
    if a.shape[2] == 4 and (a[:, :, 3] < 10).mean() > 0.40:
        return sheet.alpha_mask(image, 60), False
    corner = tuple(int(v) for v in a[4, 4, :3])
    return sheet.denoise(sheet.panel_mask(image, corner, 46), 4), True


def is_label(box, label=22):
    """A sheet caption, not a sprite.

    Captions are one line of lettering: short and much wider than tall. Colour
    does not tell them apart, because the lettering has a dark outline and
    spreads as much as carved stone does.
    """
    x0, y0, x1, y1 = box
    h = y1 - y0
    aspect = (x1 - x0) / max(1, h)
    return h < label or (aspect > 4.5 and h < 40)


def solid_piece(image, box, tolerance=16, close=5):
    """One sprite off a dark painted panel, cut as a solid silhouette.

    These sheets put near-black stone on a near-black panel, and each section
    sits on its own slightly lighter box, so neither a global colour mask nor
    flooding in from the edges works: the stone's inside reads as background
    and the flood pours in through every gap in its outline. Instead: take the
    background from this crop's own border, mark whatever differs from it,
    bridge the small gaps, and keep everything the border cannot reach.
    """
    crop = image.crop(box).convert("RGBA")
    rgb = np.array(crop)[:, :, :3].astype(int)
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    background = np.median(border, axis=0)
    ink = np.sqrt(((rgb - background) ** 2).sum(axis=2)) > tolerance
    closed = Image.fromarray((ink * 255).astype(np.uint8))
    if close > 1:
        closed = closed.filter(ImageFilter.MaxFilter(close)).filter(ImageFilter.MinFilter(close))
    solid = np.array(closed) > 0
    h, w = solid.shape
    outside = np.zeros_like(solid)
    stack = [(y, x) for y in range(h) for x in (0, w - 1) if not solid[y, x]]
    stack += [(y, x) for x in range(w) for y in (0, h - 1) if not solid[y, x]]
    for y, x in stack:
        outside[y, x] = True
    while stack:
        cy, cx = stack.pop()
        for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
            if 0 <= ny < h and 0 <= nx < w and not solid[ny, nx] and not outside[ny, nx]:
                outside[ny, nx] = True
                stack.append((ny, nx))
    rgba = np.array(crop)
    rgba[:, :, 3] = np.where(outside, 0, 255)
    return Image.fromarray(rgba)


def harden(frame, threshold=100):
    arr = np.array(frame)
    arr[:, :, 3] = np.where(arr[:, :, 3] > threshold, 255, 0)
    return Image.fromarray(arr)


def trim(frame):
    box = frame.getbbox()
    return frame.crop(box) if box else frame


def to_height(frame, height):
    """Down to the target height, sharpened, with a hard pixel edge."""
    frame = trim(frame)
    scale = height / frame.height
    small = sheet.resize(frame, (max(1, round(frame.width * scale)), height), 110)
    return harden(small.filter(ImageFilter.UnsharpMask(radius=1, percent=55, threshold=2)))


def band_mask(image, mask, panel, box, tolerance=24):
    """The ink inside one band.

    On a painted panel every section sits on its own box, lighter than the page
    corner, so the page's mask would mark the whole section as one blob. Judge
    each band against its own border instead.
    """
    h, w = mask.shape
    x0, y0, x1, y1 = int(box[0] * w), int(box[1] * h), int(box[2] * w), int(box[3] * h)
    out = np.zeros_like(mask)
    if not panel:
        out[y0:y1, x0:x1] = mask[y0:y1, x0:x1]
        return out
    rgb = np.array(image.convert("RGB"))[y0:y1, x0:x1].astype(int)
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    background = np.median(border, axis=0)
    ink = np.sqrt(((rgb - background) ** 2).sum(axis=2)) > tolerance
    out[y0:y1, x0:x1] = sheet.denoise(ink, 4)
    return out


def band_blobs(image, mask, panel, box, min_area, label, step=5, ink=24, wide=99.0):
    """Blobs inside a fraction box, captions and frame lines dropped, read
    left to right line by line."""
    sub = band_mask(image, mask, panel, box, ink)
    found = [b for b in sheet.blobs(sub, step=step, min_size=2, pad=2)
             if (b[2] - b[0]) * (b[3] - b[1]) >= min_area and min(b[2] - b[0], b[3] - b[1]) >= 10
             and not is_label(b, label) and (b[2] - b[0]) <= wide * (b[3] - b[1])]
    lines = sheet.rows(found, 0.3)
    return [b for line in lines for b in line]


def piece(image, mask, panel, b, close):
    if not panel:
        return sheet.cut(image, mask, b)
    # a few pixels of margin so the crop's border is panel, not stone
    b = (max(0, b[0] - 4), max(0, b[1] - 4), min(image.width, b[2] + 4), min(image.height, b[3] + 4))
    return solid_piece(image, b, close=close)


def slice_bands(stamp, image, mask, panel, only):
    made = []
    for folder, name, box, height, min_area, opts in SHEETS.get(stamp, []):
        if only and name not in only:
            continue
        os.makedirs(folder, exist_ok=True)
        for old in os.listdir(folder):  # a family that shrank must not keep its old tail
            stem = old[:-len(".png.import")] if old.endswith(".png.import") else old[:-len(".png")]
            if old.endswith((".png", ".png.import")) and stem.startswith(name + "_") \
                    and stem[len(name) + 1:].isdigit():
                os.remove(os.path.join(folder, old))
        boxes = band_blobs(image, mask, panel, box, min_area, opts.get("label", 22), opts.get("step", 5),
                           opts.get("ink", 24), opts.get("wide", 99.0))
        index = 0
        for n, b in enumerate(boxes, 1):
            if n in opts.get("skip", ()):
                continue
            index += 1
            frame = to_height(piece(image, mask, panel, b, opts.get("close", 5)), height)
            path = os.path.join(folder, f"{name}_{index}.png")
            frame.save(path)
            made.append(path)
        print(f"  {os.path.relpath(folder, ASSETS)}/{name}_*  x{index}")
    return made


def slice_strips(stamp, image, mask, panel, only):
    made = []
    for name, box, keep, cell, folder in STRIPS.get(stamp, []):
        if only and name not in only:
            continue
        boxes = band_blobs(image, mask, panel, box, 400, 22)
        if len(boxes) < max(keep):
            print(f"  !! {name}: found {len(boxes)} frames, wanted {max(keep)}")
            continue
        frames = [trim(piece(image, mask, panel, boxes[i - 1], 5)) for i in keep]
        # one scale for the whole strip, set by its tallest frame, so an
        # opening lid or a burst barrel does not grow or shrink while it plays
        scale = min((cell[1] - 2) / max(f.height for f in frames), (cell[0] - 2) / max(f.width for f in frames))
        cells = []
        for f in frames:
            size = (max(1, round(f.width * scale)), max(1, round(f.height * scale)))
            small = harden(sheet.resize(f, size, 110))
            out = Image.new("RGBA", cell, (0, 0, 0, 0))
            out.alpha_composite(small, ((cell[0] - small.width) // 2, cell[1] - small.height - 1))
            cells.append(out)
        sheet.strip(cells, name, folder)
        made.append(os.path.join(folder, f"{name}.png"))
        if folder == CLUTTER:
            still = trim(cells[-1])
            still.save(os.path.join(folder, f"{name}_lit.png"))
            made.append(os.path.join(folder, f"{name}_lit.png"))
    return made


def montage(paths, out, cols=14, cell=110):
    """Everything a run produced in one picture, on a light ground so dark
    stone and hollow cut-outs are easy to spot."""
    os.makedirs(os.path.dirname(out), exist_ok=True)
    rows = max(1, (len(paths) + cols - 1) // cols)
    canvas = Image.new("RGB", (cols * cell, rows * cell), (176, 184, 194))
    draw = ImageDraw.Draw(canvas)
    for i, path in enumerate(paths):
        im = Image.open(path).convert("RGBA")
        zoom = max(1, min((cell - 8) // max(1, im.width), (cell - 22) // max(1, im.height)))
        im = im.resize((im.width * zoom, im.height * zoom), Image.NEAREST)
        im.thumbnail((cell - 8, cell - 22), Image.NEAREST)
        x, y = (i % cols) * cell, (i // cols) * cell
        canvas.paste(im, (x + (cell - im.width) // 2, y + 18 + (cell - 18 - im.height) // 2), im)
        draw.text((x + 3, y + 3), os.path.basename(path)[:-4], fill=(40, 20, 20))
    canvas.save(out)
    print("wrote", os.path.relpath(out, sheet.ROOT), canvas.size)


def main() -> None:
    args = sys.argv[1:]
    if args and args[0] == "--contact":
        src = args[2] if len(args) > 2 else os.path.expanduser("~/Downloads")
        image = sheet.source(args[1], src)
        os.makedirs(CONTACT, exist_ok=True)
        sheet.contact_sheet(image, mask_for(image)[0], os.path.join(CONTACT, f"{args[1]}.png"), 0.62)
        return
    src = os.path.expanduser("~/Downloads")
    if args and os.path.isdir(os.path.expanduser(args[0])):
        src = os.path.expanduser(args.pop(0))
    only = set(args) or None
    made = []
    for stamp in sorted(set(SHEETS) | set(STRIPS)):
        print(stamp)
        image = sheet.source(stamp, src)
        mask, panel = mask_for(image)
        made += slice_bands(stamp, image, mask, panel, only)
        made += slice_strips(stamp, image, mask, panel, only)
    montage(made, os.path.join(CONTACT, "batch10.png"))
    print(f"{len(made)} files")


if __name__ == "__main__":
    main()
