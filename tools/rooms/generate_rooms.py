#!/usr/bin/env python3
"""Generates scenes/rooms/*.tscn from the ROOMS table below.

Rooms are hand-made levels; this script is just a faster way to write the
first versions than clicking rectangles in the editor. Once a room is tuned by
hand in Godot, delete it from ROOMS so this script never overwrites it.

    python3 tools/rooms/generate_rooms.py
"""
import hashlib
import json
import os
import random
import filecmp
import sys
from copy import deepcopy

import numpy as np
from PIL import Image, ImageOps
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "art"))
from studio_overrides import patched  # the art studio's edits of what this writes (tools/studio/overrides)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DECOR_DIR = os.path.join(ROOT, "assets", "decor")
PLATFORM_DIR = os.path.join(DECOR_DIR, "platforms")
## Piece sizes and walkable tops, written by tools/art/slice_batch9.py.
with open(os.path.join(PLATFORM_DIR, "manifest.json")) as _f:
    PIECES = json.load(_f)

from painted_rooms import PAINTED, check_reach  # noqa: E402  (rooms drawn as one panel each)

# Each room gets two expansion seams in different places. Unlike global x
# scaling, seams add real traversal space without fattening characters,
# masonry, trees and props in the painted panel.
ROOM_EXPANSION_CUTS = {
    "village_night": (625, 950), "graveyard_cross": (765,),
    "graveyard_arches": (440, 770), "graveyard_tree": (250, 1050),
    "swamp_moon": (200, 1057), "swamp_red": (180, 1137),
    "swamp_crypt": (260, 700), "catacombs_1": (390, 750),
    "catacombs_2": (260, 1020), "catacombs_3": (420, 960),
    "crypt_skulls": (390, 870), "crypt_lava": (400, 780),
    "hell_gate": (460, 650), "church": (320, 640), "preacher_nave": (300, 660),
}

# Small, authored corrections to widened paintings. These are transparent
# overlays over the generated seam, never over the gameplay collision layer.
# Keep them separate from *_wide.png so regeneration does not erase the edit.
AUTHORED_WIDE_OVERLAYS = {
    "swamp_crypt": [
        ("seam_overlays/swamp_crypt_tree.png", 710, 5),
        ("seam_overlays/swamp_crypt_roots_upper.png", 790, 320),
        ("seam_overlays/swamp_crypt_roots_lower.png", 790, 485),
    ],
}

# Keep one-off landmarks out of the mirrored sample. Their exact screen
# positions are part of the painting, not candidates for background tiling.
FOCAL_RANGES = {
    "village_night": ((815, 925),),            # moon
    "swamp_red": ((310, 520), (660, 765), (850, 1110)),  # castle, moon, old tree
}

TRAVERSAL_PATCHES = {
    "graveyard_cross": [(1220, 338, 80, 10)],
    # The lower graveyard route needs a way back onto its old upper gallery.
    # This short shelf hangs from the gallery instead of floating in the gap.
    "graveyard_arches": [(1450, 430, 72, 10), (750, 420, 80, 12, "BridgeReturn")],
    "swamp_moon": [(1250, 413, 90, 14)],  # trace the painted middle pier, no floating art
    "swamp_crypt": [(310, 375, 60, 10)],  # two-way route to the entrance pier
    "catacombs_3": [(480, 225, 80, 10)],
    "crypt_skulls": [(400, 285, 80, 10)],
    # a fifth field names the patch in the scene (<name>Shape, <name>Cornice)
    # for the tests that look for it
    "crypt_lava": [(730, 610, 100, 12, "LowerReturn"), (700, 315, 85, 12, "GalleryReturn")],  # treasure terrace and gallery return
    "hell_gate": [(1525, 563, 75, 12, "Return1"), (1550, 493, 50, 12, "Return2"),
                  (265, 315, 125, 12, "LeftReturn"), (225, 405, 65, 12, "LeftReturnLower")],  # upper left lip clears the stair underside
}

# One visual thought per new seam, not another random barrel on the route.
# The large painted landmarks are intentionally left alone; these small pieces
# give the added walking space a place-specific foreground rhythm.
SEAM_STORIES = {
    "village_night": ("wilds/brush_2", ""),  # leave the exit bridge clear
    "graveyard_cross": ("",),  # painted crosses already frame the bridge; don't stamp another over its stair
    "graveyard_arches": ("", "graveyard/bones_1"),  # no loose coffin at the bridge seam
    "graveyard_tree": ("", ""),  # keep the painted chapel and its roots unobstructed
    "swamp_moon": ("", ""),  # the painted roots are enough at the entrance; the pier stays clear
    "swamp_red": ("wilds/fallen_2", ""),  # leave the gate's stone cap clear
    "swamp_crypt": ("wilds/brush_3", ""),  # the crypt sprite hovered above this painted gallery
    "catacombs_1": ("graveyard/bones_2", "clutter/clutter_3"),
    "catacombs_2": ("graveyard/coffin_1", "graveyard/bones_1"),
    "catacombs_3": ("clutter/clutter_4", "graveyard/bones_2"),
    "crypt_skulls": ("graveyard/bones_1", "graveyard/coffin_3"),
    "crypt_lava": ("graveyard/bones_2", "clutter/brazier_lit"),
    "hell_gate": ("graveyard/cross_4", ""),  # the second seam is distant scenery, not a floor
    "preacher_nave": ("clutter/brazier_lit", "graveyard/coffin_4"),
    "church": ("graveyard/coffin_1", "clutter/altar_lit"),
}

# These two tall, asymmetric silhouettes break specific mirrored joins in the
# painted middle distance. Coordinates are in the expanded 1600-pixel room;
# unlike floor clutter they sit behind the player and have no collision.
SEAM_SILHOUETTES = {
    "graveyard_cross": ("graveyard/blue_dead_tree", 845, 417, 0.12, "Color(0.63, 0.69, 0.79, 0.58)"),
    "swamp_red": ("wilds/red_swamp_fence", 1377, 425, 0.11, "Color(0.82, 0.77, 0.78, 0.92)"),
}

# Ordinary breakables should explain where they are. Reward chests are never
# replaced. This also stops medieval storage crates from filling every crypt.
ROOM_PROP_MOTIFS = {
    "village_night": {"box_goods": "village_supplies"},
    "graveyard_cross": {"barrel": "rubble", "crate": "rubble", "sack": "funeral_offering"},
    "graveyard_arches": {"barrel": "rubble", "box_goods": "funeral_offering", "sack": "rubble"},
    "graveyard_tree": {"barrel": "rubble", "crate": "rubble"},
    "swamp_moon": {"barrel": "swamp_bundle", "box_goods": "swamp_bundle", "sack": "swamp_bundle"},
    "swamp_red": {"barrel": "swamp_bundle", "crate": "rubble", "sack": "swamp_bundle"},
    "swamp_crypt": {"barrel": "swamp_bundle", "box_goods": "bone_reliquary"},
    "catacombs_1": {"barrel": "bone_reliquary", "crate": "rubble", "sack": "bone_reliquary"},
    "catacombs_2": {"barrel": "bone_reliquary", "box_goods": "rubble", "sack": "bone_reliquary"},
    "catacombs_3": {"barrel": "bone_reliquary", "crate": "rubble"},
    "crypt_skulls": {"barrel": "bone_reliquary", "box_goods": "bone_reliquary", "sack": "rubble"},
    "crypt_lava": {"barrel": "rubble", "crate": "rubble", "sack": "bone_reliquary"},
    "hell_gate": {"barrel": "rubble", "box_goods": "bone_reliquary"},
    "preacher_nave": {"pot": "funeral_offering"},
    "church": {},
    "graveyard": {"barrel": "funeral_offering", "crates_stacked": "rubble", "sack": "funeral_offering"},
    "dead_bridge": {"crate": "rubble", "crate_large": "rubble"},
    "fallen_knight": {"barrel": "rubble", "box_goods": "funeral_offering"},
    "church_ophanim": {"pot": "funeral_offering", "barrel": "rubble", "crate": "funeral_offering"},
}

# Hand-placed openings in each original 1280x720 painting. Coordinates stay
# away from playable stone silhouettes: only the hidden landscape / recesses
# are replaced by each room's inpainted plate. They are mapped through the
# same insertion seams as the artwork, then remain fixed to collision space.
# A polygon is a mask, not another walkable surface.
DEPTH_WINDOWS = {
    "village_night": (0.025, [
        [(235, 8), (1050, 8), (1045, 174), (945, 205), (770, 202), (600, 205), (400, 182), (235, 165)],
        [(342, 241), (414, 240), (430, 307), (377, 336), (333, 317)],
        [(622, 282), (821, 268), (819, 365), (672, 374), (626, 355)],
    ]),
    "graveyard_cross": (0.025, [
        [(190, 8), (1080, 8), (1065, 173), (915, 189), (750, 195), (592, 190), (386, 195), (190, 180)],
        [(573, 217), (787, 205), (788, 325), (696, 339), (568, 321)],
        [(593, 365), (797, 355), (793, 477), (592, 472)],
    ]),
    "graveyard_arches": (0.028, [
        [(220, 8), (937, 8), (905, 155), (764, 165), (575, 160), (390, 180), (224, 183)],
        [(437, 187), (801, 176), (805, 303), (700, 323), (556, 305), (440, 310)],
        [(733, 353), (887, 342), (880, 465), (748, 483), (733, 447)],
    ]),
    "graveyard_tree": (0.024, [
        [(200, 8), (1030, 8), (1015, 167), (802, 174), (611, 178), (400, 177), (203, 174)],
        [(377, 191), (622, 184), (628, 304), (540, 333), (379, 318)],
        [(388, 344), (550, 344), (549, 395), (390, 397)],
    ]),
    "swamp_moon": (0.019, [
        [(392, 8), (855, 8), (847, 167), (735, 182), (522, 177), (399, 172)],
        [(542, 199), (700, 189), (711, 320), (589, 310)],
        [(753, 446), (903, 437), (904, 532), (820, 543), (754, 528)],
    ]),
    "swamp_red": (0.022, [
        [(231, 8), (838, 8), (837, 172), (657, 191), (463, 188), (234, 178)],
        [(351, 212), (635, 210), (675, 320), (501, 329), (353, 306)],
        [(704, 434), (790, 429), (789, 479), (713, 486), (704, 465)],
    ]),
    "swamp_crypt": (0.020, [
        [(168, 8), (580, 8), (572, 173), (405, 188), (172, 180)],
        [(174, 210), (456, 206), (468, 240), (283, 246), (174, 240)],
        [(242, 432), (389, 427), (389, 468), (287, 474), (240, 459)],
    ]),
    "catacombs_1": (0.010, [
        [(433, 78), (514, 74), (518, 195), (435, 205)],
        [(636, 68), (758, 62), (761, 187), (635, 196)],
        [(365, 293), (493, 288), (489, 385), (368, 394)],
        [(1090, 305), (1219, 301), (1212, 385), (1090, 395)],
    ]),
    "catacombs_2": (0.009, [
        [(99, 85), (347, 83), (349, 255), (251, 275), (106, 257)],
        [(554, 281), (731, 277), (726, 387), (561, 396)],
        [(855, 293), (969, 289), (966, 389), (855, 398)],
        [(974, 549), (1102, 545), (1097, 620), (979, 625)],
    ]),
    "catacombs_3": (0.011, [
        [(899, 60), (1168, 52), (1165, 232), (990, 242), (907, 222)],
        [(790, 428), (992, 423), (986, 520), (805, 529)],
        [(1018, 540), (1167, 534), (1164, 598), (1020, 608)],
    ]),
    "crypt_skulls": (0.032, [
        [(432, 87), (816, 82), (821, 228), (692, 249), (529, 240), (432, 215)],
        [(649, 297), (821, 286), (823, 417), (721, 443), (649, 420)],
        [(548, 514), (693, 507), (695, 610), (549, 613)],
    ]),
    "crypt_lava": (0.035, [
        [(419, 37), (675, 32), (674, 192), (595, 202), (427, 198)],
        [(532, 298), (669, 286), (670, 338), (545, 344)],
        [(752, 514), (808, 510), (811, 629), (754, 635)],
    ]),
    "hell_gate": (0.036, [
        [(456, 19), (751, 15), (750, 163), (647, 185), (460, 176)],
        [(470, 288), (588, 281), (586, 407), (505, 423), (473, 408)],
        [(585, 515), (686, 510), (688, 552), (588, 552)],
    ]),
}


def _map_x(x, inserts):
    return round(x + sum(amount for cut, amount in inserts if x >= cut))


def _point_in_polygon(x, y, polygon):
    inside = False
    for start, end in zip(polygon, polygon[1:] + polygon[:1]):
        if (start[1] > y) != (end[1] > y):
            crossing = (end[0] - start[0]) * (y - start[1]) / (end[1] - start[1]) + start[0]
            if x < crossing:
                inside = not inside
    return inside


def _validate_depth_windows(name):
    """Keep painted depth openings off the original walkable collision art."""
    if name not in DEPTH_WINDOWS:
        raise ValueError(f"{name}: painted room has no authored depth windows")
    _, windows = DEPTH_WINDOWS[name]
    room = PAINTED[name]
    for kind in ("ground", "ledges", "platforms"):
        for x, y, width, height in room.get(kind, []):
            for number, polygon in enumerate(windows, 1):
                if any(_point_in_polygon(px, py, polygon)
                       for px in range(int(x) + 2, int(x + width), 4)
                       for py in range(int(y) + 2, int(y + height), 4)):
                    raise ValueError(f"{name}: depth window {number} overlaps {kind} at {(x, y, width, height)}")


def _validate_expansion_cuts(name, room):
    cuts = ROOM_EXPANSION_CUTS[name]
    if tuple(sorted(cuts)) != cuts or cuts[0] <= 0 or cuts[-1] >= room["width"]:
        raise ValueError(f"{name}: expansion cuts must be sorted and inside the painting")
    sample_radius = min(max(16, (120 if room.get("interior") else 160) // 2),
                        room["width"] - cuts[-1])
    for cut in cuts:
        for x0, _, x1, _ in room.get("ramps", []):
            if min(x0, x1) < cut < max(x0, x1):
                raise ValueError(f"{name}: expansion at {cut} cuts through painted stairs")
        for x, _, width, _ in room.get("platforms", []):
            if x < cut < x + width:
                raise ValueError(f"{name}: expansion at {cut} stretches a small platform")
        for left, right in FOCAL_RANGES.get(name, ()):
            if cut < right and cut + sample_radius > left:
                raise ValueError(f"{name}: expansion at {cut} repeats focal art {left}..{right}")


def _painted_floors(room):
    """Walkable tops the painting itself must show: (x, y, w), widened coordinates."""
    drawn = set(room.get("platforms", [])) - set(room.get("painted_platforms", []))
    return [(x, y, w) for key in ("ground", "ledges", "painted_platforms", "platforms")
            for x, y, w, _ in room.get(key, []) if key != "platforms" or (x, y, w, _) not in drawn]


def _quilt_band(source, cut, amount, a_limit=None, focal=()):
    """The band inserted at `cut`: no mirror, no stretch.

    A mirrored band paints a Rorschach blot on the seam: every gallows, tree
    and crypt front near a cut gets a symmetrical twin, which is the first
    thing an eye finds. Instead the band is two ordinary copies stitched
    together (image quilting): its left part continues the painting from the
    right of the cut, its right part the painting from the left of it, so
    both edges meet their neighbours exactly. Where one copy gives way to the
    other is a vertical path that runs, row by row, through the pixels where
    the two copies already agree most — through fog and dark stone rather
    than across a window or a railing — with a few pixels of feather.
    `a_limit` keeps the right-hand copy narrower than that, for a cut whose
    right side holds something that must not be seen twice; `focal` are
    source spans (a moon, a castle) neither copy may repeat.
    """
    pixels = np.asarray(source, dtype=np.float32)
    height = pixels.shape[0]
    right = pixels[:, cut:cut + amount]   # continues the left edge
    if right.shape[1] < amount:
        # a cut near the panel's edge: only that much can be copied from the right
        a_limit = min(a_limit or amount, right.shape[1] - 5)
        right = np.pad(right, ((0, 0), (0, amount - right.shape[1]), (0, 0)), mode="edge")
    left = pixels[:, cut - amount:cut]    # continues the right edge
    cost = np.abs(right[..., :3] - left[..., :3]).sum(axis=2)
    # judge a neighbourhood, not a pixel: a path through noise is still a seam
    padded = np.pad(cost, 3, mode="edge")
    smooth = np.zeros_like(cost)
    for dy in range(7):
        for dx in range(7):
            smooth += padded[dy:dy + height, dx:dx + amount]
    margin = 24
    feather = 8
    hi = amount - margin if a_limit is None else min(amount - margin, a_limit)
    lo = margin
    for left_x, right_x in focal:
        if right_x > cut and left_x < cut + amount:   # in the right-hand copy
            hi = min(hi, max(lo + 1, left_x - cut - feather))
        if left_x < cut and right_x > cut - amount:   # in the left-hand copy
            lo = max(lo, min(hi - 1, right_x - (cut - amount) + feather))
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
    # Meet halfway where they still differ (a sky a shade lighter on one side):
    # each copy bends by half the difference at the path, the bend fading out
    # towards its own edge, so the edges stay exact and the path leaves no line.
    rows = np.arange(height)
    near = np.clip(path[:, None] + np.arange(-2, 3)[None, :], 0, amount - 1)
    gap = (right[rows[:, None], near] - left[rows[:, None], near]).mean(axis=1)
    kernel = np.ones(9, dtype=np.float32) / 9.0
    gap = np.stack([np.convolve(np.pad(gap[:, c], 4, mode="edge"), kernel, mode="valid")
                    for c in range(gap.shape[1])], axis=1)
    gap[:, 3] = 0.0  # never bend alpha
    columns = np.arange(amount, dtype=np.float32)[None, :]
    toward_left = np.clip(columns / np.maximum(path[:, None], 1), 0.0, 1.0)
    toward_right = np.clip((amount - 1 - columns) / np.maximum(amount - 1 - path[:, None], 1), 0.0, 1.0)
    right = right - 0.5 * gap[:, None, :] * toward_left[..., None]
    left = left + 0.5 * gap[:, None, :] * toward_right[..., None]
    weight = np.clip((columns - path[:, None] + feather) / (2 * feather), 0.0, 1.0)[..., None]
    band = right * (1.0 - weight) + left * weight
    return Image.fromarray(np.clip(band + 0.5, 0, 255).astype(np.uint8), "RGBA")


def _mirror_band(source, cut, amount, radius):
    """The old band: the strip right of the cut, then that strip mirrored."""
    sample = source.crop((cut, 0, cut + radius, source.height))
    half = sample.resize((amount // 2, source.height), Image.Resampling.LANCZOS)
    loop = Image.new("RGBA", (amount, source.height))
    loop.paste(half, (0, 0))
    loop.paste(ImageOps.mirror(half), (amount - half.width, 0))
    return loop


def _floor_fit(band, y, x0, x1):
    """How much of [x0, x1) of the band shows a lit stone top within 5 px of y."""
    lum = np.asarray(band.convert("L"), dtype=np.float32)
    top, bottom = max(0, y - 5), min(lum.shape[0] - 9, y + 6)
    if bottom <= top or x1 <= x0:
        return 1.0
    below = sum(lum[top + dy:bottom + dy, x0:x1] for dy in range(2, 9)) / 7.0
    edge = lum[top:bottom, x0:x1] - below
    edge[lum[top:bottom, x0:x1] < 40] = 0
    return float((edge.max(axis=0) > 20).mean())


def _keep_floors(quilted, mirrored, floors, seam_x, amount):
    """A floor collider across a seam needs its stone painted across it too.

    The quilted band can end a ledge where the copy it came from ends; the
    mirrored one repeats the ledge right of the cut both ways. Where a floor
    crosses the band and the mirror carries its stone better, that floor's
    rows are taken from the mirror, faded in and out over a few rows: a
    symmetric strip of ledge reads as masonry, a symmetric gallows does not.
    """
    out = np.asarray(quilted, dtype=np.float32).copy()
    mirror = np.asarray(mirrored, dtype=np.float32)
    for x, y, w in floors:
        x0, x1 = max(0, int(x) - seam_x), min(amount, int(x + w) - seam_x)
        if x1 - x0 < 8:
            continue
        if _floor_fit(mirrored, int(y), x0, x1) <= _floor_fit(quilted, int(y), x0, x1) + 0.15:
            continue
        top, bottom, fade = int(y) - 20, int(y) + 24, 6
        for row in range(max(0, top - fade), min(out.shape[0], bottom + fade)):
            t = min(1.0, (row - (top - fade)) / fade, ((bottom + fade) - row) / fade)
            out[row] = out[row] * (1.0 - t) + mirror[row] * t
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), "RGBA")


def _expand_panel(painting, inserts, focal=(), floors=()):
    """Insert quilted local bands (_quilt_band); preserve every original pixel."""
    source_path = os.path.join(ROOT, "assets", "levels", painting + ".png")
    output_name = painting + "_wide"
    output_path = os.path.join(ROOT, "assets", "levels", output_name + ".png")
    source = Image.open(source_path).convert("RGBA")
    target = Image.new("RGBA", (source.width + sum(v for _, v in inserts), source.height))
    src_x = 0
    dst_x = 0
    for cut, amount in inserts:
        segment = source.crop((src_x, 0, cut, source.height))
        target.paste(segment, (dst_x, 0))
        dst_x += segment.width
        a_limit = None
        if cut == 625 and painting.endswith("graveyard_moon"):
            # The return step begins at x=690. Copying through it would
            # stamp a second, collidable-looking balcony into the seam even
            # though only the authored copy has a platform collider.
            a_limit = 60
        band = _quilt_band(source, cut, amount, a_limit, focal)
        if floors:
            radius = min(max(16, amount // 2), source.width - cut, 64 if a_limit else amount)
            band = _keep_floors(band, _mirror_band(source, cut, amount, radius), floors, dst_x, amount)
        target.paste(band, (dst_x, 0))
        dst_x += amount
        src_x = cut
    target.paste(source.crop((src_x, 0, source.width, source.height)), (dst_x, 0))
    for art, x, y in AUTHORED_WIDE_OVERLAYS.get(painting, ()):
        overlay_path = os.path.join(ROOT, "assets", "levels", art)
        overlay = Image.open(overlay_path).convert("RGBA")
        if x < 0 or y < 0 or x + overlay.width > target.width or y + overlay.height > target.height:
            raise ValueError(f"{painting}: authored seam overlay exceeds the painting")
        target.alpha_composite(overlay, (x, y))
    # her repaint from the art studio, laid over the widened painting (tools/studio/overrides)
    target = patched(output_path, target)
    pending_path = output_path + ".pending.png"
    target.save(pending_path)
    # Do not invalidate Godot's imported texture when the painting has not
    # changed. Replacing identical PNGs could leave a stale valid=false remap
    # while a run was already loading the next room.
    if os.path.exists(output_path) and filecmp.cmp(pending_path, output_path, shallow=False):
        os.unlink(pending_path)
    else:
        os.replace(pending_path, output_path)
    return output_name


def expand_painted_room(name, room):
    """Return a wider copy, inserting space rather than stretching every gap."""
    _validate_expansion_cuts(name, room)
    out = deepcopy(room)
    amount = 120 if room.get("interior") else 160
    inserts = [(cut, amount) for cut in ROOM_EXPANSION_CUTS[name]]
    out["_x_inserts"] = inserts
    out["width"] = room["width"] + sum(value for _, value in inserts)
    if "painting" in room:
        out["painting_wide"] = room["painting"] + "_wide"
    for key in ("ground", "ledges", "platforms", "painted_platforms", "hazards"):
        out[key] = [(_map_x(x, inserts), y, _map_x(x + w, inserts) - _map_x(x, inserts), h)
                    for x, y, w, h in room.get(key, [])]
    out["crumbling_platforms"] = [(_map_x(piece[0], inserts), piece[1],
                                    _map_x(piece[0] + piece[2], inserts) - _map_x(piece[0], inserts),
                                    piece[3] if len(piece) > 3 else "stone")
                                   for piece in room.get("crumbling_platforms", [])]
    out["ramps"] = [(_map_x(x0, inserts), y0, _map_x(x1, inserts), y1)
                    for x0, y0, x1, y1 in room.get("ramps", [])]
    # ("rubble", 1130, 583, "wide") is already in the widened room: the only
    # way to stand something inside an inserted seam, which no panel x maps to.
    for key in ("spawns", "props", "npcs"):
        out[key] = [(item[0], item[1] if item[3:] == ("wide",) else _map_x(item[1], inserts), item[2])
                    for item in room.get(key, [])]
    out["npc_paths"] = []
    for npc_id, x, _ in room.get("npcs", []):
        with open(os.path.join(ROOT, "data", "npcs", npc_id + ".json")) as source:
            points = json.load(source).get("path", [])
        # A path is local to the NPC. Remap each world-space stop separately:
        # otherwise a stop beyond an inserted seam stays on the old x and
        # the NPC fades or walks into empty air beside the widened masonry.
        mapped = [(_map_x(x + dx, inserts) - _map_x(x, inserts), dy) for dx, dy in points]
        # Only a path the seams actually moved needs overriding in the scene.
        out["npc_paths"].append(mapped if mapped != [tuple(p) for p in points] else [])
    out["decor"] = [(item_id, _map_x(x, inserts), y, layer)
                    for item_id, x, y, layer in room.get("decor", [])]
    for key in ("player", "door", "shrine", "bell"):
        if key in room:
            x, y = room[key]
            out[key] = (_map_x(x, inserts), y)
    out["pillars"] = [(_map_x(x, inserts), y) for x, y in room.get("pillars", [])]
    if isinstance(room.get("lights"), list):
        out["lights"] = [(_map_x(x, inserts), y, tint, radius, energy, flicker)
                         for x, y, tint, radius, energy, flicker in room["lights"]]
    for patch in TRAVERSAL_PATCHES.get(name, []):
        if len(patch) > 4:
            out.setdefault("platform_names", {})[len(out["platforms"]) + 1] = patch[4]
        out["platforms"].append(tuple(patch[:4]))
    if name == "village_night":
        # The widening creates two distinct bridge caps. Trace their actual
        # painted ends: a single stretched collider stopped 61 px too early
        # on the right and floated above the stair on the left.
        out["ground"][7] = (1063, 520, 117, 60)
        out["ground"].append((1198, 520, 143, 60))
    if name == "graveyard_cross":
        out["painted_cornices"] = True
    if name == "hell_gate":
        out["painted_cornices"] = True
        out["hell_cornice_art"] = True
        out["cornice_crop"] = (1000, 482)  # this room's stone bridge cap, not the lava shelf; clear of the seams
        # The two left return treads used to read as isolated horizontal lines.
        # Extend their underside with stone sampled from this room's bridge,
        # tapering into the existing cliff instead of adding foreign columns.
        out["cornice_supports"] = {
            3: [(0, 8), (125, 8), (125, 16), (102, 30), (70, 43), (18, 33), (0, 23)],
            4: [(0, 8), (65, 8), (65, 18), (43, 32), (0, 29)],
        }
        out["ramp_treads"] = {2: [(270, 176), (282, 176), (282, 188),
                                  (295, 188), (295, 200), (308, 200),
                                  (308, 212), (328, 212), (328, 223),
                                  (344, 223), (344, 231), (364, 231), (364, 239)]}
    if name == "crypt_lava":
        out["painted_cornices"] = True
        out["cornice_crop"] = (860, 458)
        # The return route is necessary, but bare stone shelves over lava
        # looked pasted on. Tie each to the room's overhead masonry.
        out["hanging_supports"] = {1: (295, 160), 2: (315, 315)}
        out["cornice_supports"] = {
            1: [(0, 10), (100, 10), (100, 20), (15, 40), (0, 60), (-25, 60), (-25, 52)],
            2: [(-55, 10), (85, 10), (85, 18), (24, 43), (-55, 48)],
        }
        # the terrace's masonry is sampled two rows lower: its top row showed the lava lip
        out["cornice_support_shift"] = {1: (0, 2)}
        # Short intermediate treads let the hero walk over the painting's
        # taller risers without globally increasing step-up height.
        out["ramp_treads"] = {2: ((1460,208),(1460,201),(1468,201),(1468,194),(1486,194),(1486,188),(1494,188),(1494,181),(1518,181),(1518,171),(1524,171),(1524,164),(1532,164),(1532,157),(1542,157),(1542,149),(1550,149),(1550,140),(1564,140),(1564,131),(1574,131),(1574,122),(1582,122),(1582,115),(1592,115),(1592,108),(1600,108))}
    if name in ("graveyard_arches", "graveyard_tree"):
        out["painted_cornices"] = True
        out["cornice_crop"] = (1220, 316) if name == "graveyard_arches" else (1418, 241)
        if name == "graveyard_arches":
            # Both chain heads disappear into the gallery's stone underside.
            out["hanging_supports"] = {4: (68, 68)}
    if name in ("swamp_moon", "swamp_red"):
        out["painted_cornices"] = True
        out["cornice_crop"] = (1000, 420) if name == "swamp_moon" else (1480, 255)
    if name == "swamp_moon":
        out["painted_platforms"].append((1250, 413, 90, 14))
        # A narrow crossbeam is already painted between the old arch's piers.
        # Its collision completes the return climb from the swamp to the entry
        # terrace without drawing another unsupported platform over the water.
        arch_rail = (490, 304, 62, 8)
        out.setdefault("platform_names", {})[len(out["platforms"]) + 1] = "ArchRail"
        out["platforms"].append(arch_rail)
        out["painted_platforms"].append(arch_rail)
        # The added return tread sits directly below the exit dock. Timber
        # braces tie it to that dock instead of leaving a plank in mid-air.
        out["hanging_supports"] = {1: (65, 65, "timber")}
    if name == "catacombs_1":
        out["painted_cornices"] = True
        out["cornice_crop"] = (1160, 234)
    if name in ("catacombs_2", "catacombs_3", "crypt_skulls"):
        out["painted_cornices"] = True
        out["cornice_crop"] = {"catacombs_2": (580, 228),
                               "catacombs_3": (620, 242),
                               "crypt_skulls": (100, 254)}[name]
    if name == "crypt_skulls":
        # Both short return treads hang directly beneath the old gallery.
        # The chains end at its uneven 256/268 px underside, like the cages
        # already present in this chamber, instead of leaving bare bars in air.
        out["hanging_supports"] = {1: (42, 38), 2: (31, 18)}
    if name == "swamp_crypt":
        out["painted_cornices"] = True
        out["cornice_crop"] = (150, 319)
        out["cornice_post"] = (150, 332, 18, 82)
    _place_expansion_accents(name, out)
    return out


def _place_expansion_accents(name, room):
    """Dress the two added spans with authored, non-colliding visual beats."""
    for index, (cut, amount) in enumerate(room["_x_inserts"]):
        center_x = _map_x(cut, room["_x_inserts"]) - amount // 2
        asset = SEAM_STORIES[name][index]
        if not asset:
            continue
        art_w, art_h = Image.open(os.path.join(DECOR_DIR, asset + ".png")).size
        # The tallest surface under the accent becomes its physical baseline.
        # Mid/front pieces don't parallax away from the floor as the camera moves.
        placed = False
        for x in (center_x, center_x - 24, center_x + 24, center_x - 48, center_x + 48):
            surfaces = [(sy, sx, sw) for sx, sy, sw, _ in
                        room.get("ground", []) + room.get("ledges", []) + room.get("platforms", [])
                        if sx + art_w / 2 + 8 <= x <= sx + sw - art_w / 2 - 8
                        and sy <= room["height"] - (30 if room.get("interior") else 50)]
            for y, _, _ in sorted(surfaces):
                occupied = any(abs(px - x) < max(36, art_w / 2 + 18) and abs(py - y) < 35
                               for _, px, py in room["props"] + room["npcs"])
                occupied |= any(abs(px - x) < max(48, art_w / 2 + 24) and abs(py + 12 - y) < 40
                                for _, px, py in room["spawns"])
                occupied |= any(abs(px - x) < 62 and abs(py + dy - y) < 45
                                for key, dy in (("player", 20), ("door", 32), ("shrine", 0))
                                for px, py in [room.get(key, (-1000, -1000))])
                occupied |= any(abs(px - x) < (art_w + 20) / 2 and abs(py - y) < 25
                                for _, px, py, _ in room["decor"])
                if not occupied:
                    room["decor"].append((asset, x, y, "front" if art_h <= 30 else "mid"))
                    placed = True
                    break
            if placed:
                break


def contextual_props(name, props):
    """Replace obvious copy-paste clutter with props belonging to this place.

    Chests and their rewards stay untouched. The replacement is deterministic,
    so generation produces authored layouts rather than runtime dice.
    """
    if "swamp" in name:
        replacements = {"barrel_apples": "swamp_bundle"}
    elif any(word in name for word in ("catacombs", "crypt", "hell")):
        replacements = {"barrel_apples": "bone_reliquary"}
    elif "village" in name:
        replacements = {"barrel_apples": "village_supplies", "box_goods": "village_supplies"}
    else:
        replacements = {"barrel_apples": "funeral_offering"}
    motif = ROOM_PROP_MOTIFS.get(name, {})
    return [(motif.get(prop_id, replacements.get(prop_id, prop_id)), x, y)
            for prop_id, x, y in props]

ROOMS = {
    # Every room but the boss arenas is two screens tall. Floors are jump-through
    # ledges (layer 5) 65-70 px apart with a small step ledge between two tiers,
    # so a tier is one double jump or two single ones; "ground" is solid.
    # Coordinates: enemies stand at floor-12, the player at floor-20, props,
    # decor and shrines at the floor, the door at floor-32.
    "graveyard": dict(
        # The hill at the top, the crypts at the bottom: a descent, with a pit
        # under the middle of the ground.
        backdrop="graveyard", width=1280, height=720, weather="rain", fog=0.55, intro="", music="graveyard",
        ground=[(0, 680, 540, 40), (600, 680, 680, 40), (540, 716, 60, 4)],
        platforms=[(0, 290, 380, 20), (470, 290, 200, 16), (760, 290, 520, 20),
                   (380, 355, 90, 12), (1180, 355, 100, 12),
                   (80, 420, 240, 16), (420, 420, 180, 16), (700, 420, 160, 16), (960, 420, 320, 16),
                   (330, 485, 80, 12), (880, 485, 70, 12),
                   (0, 550, 260, 16), (350, 550, 220, 16), (660, 550, 240, 16), (1000, 550, 280, 16),
                   (280, 615, 70, 12), (920, 615, 80, 12),
                   (560, 190, 120, 12), (1080, 200, 100, 12)],
        spawns=[("cultist", 900, 278), ("zealot", 1150, 408), ("possessed_villager", 200, 408),
                ("cultist", 480, 538), ("possessed_villager", 1100, 538),
                ("fallen_guard", 800, 668), ("cultist", 1100, 668),
                ("wraith", 300, 620), ("shade", 600, 380), ("raven", 900, 160), ("wraith", 1050, 260)],
        props=[("pot", 330, 290), ("barrel", 460, 680), ("crates_stacked", 700, 680), ("sack", 880, 680),
               ("chest_gold", 1130, 200), ("pot", 150, 420), ("barrel_apples", 1150, 550)],
        decor=[("tree_2", 90, 680, "back"), ("tree_4", 700, 680, "back"), ("crypt_1", 1010, 680, "back"),
               ("crypt_2", 470, 680, "back"), ("monument_1", 640, 680, "back"), ("monument_6", 820, 680, "back"),
               ("monument_9", 1230, 680, "back"), ("monument_8", 250, 290, "back"), ("tree_5", 1000, 290, "back"),
               ("tombstone_1", 150, 680, "mid"), ("tombstone_2", 210, 680, "mid"), ("tombstone_4", 350, 680, "mid"),
               ("tombstone_5", 620, 680, "mid"), ("tombstone_7", 760, 680, "mid"), ("tombstone_8", 960, 680, "mid"),
               ("fence_1", 880, 680, "mid"), ("fence_3", 1150, 680, "mid"), ("monument_3", 1090, 680, "mid"),
               ("grass_2", 210, 290, "front"), ("rocks", 620, 290, "front"), ("grass_1", 830, 290, "front"),
               ("bush", 1040, 420, "front"), ("tombstone_3", 120, 420, "mid"), ("tombstone_6", 560, 550, "mid"),
               ("fence_2", 1100, 550, "mid")],
        npcs=[("nun", 170, 290), ("mara", 1180, 260)],
        ambient="#a0a4b4", lights=[(1246, 621, "#ffb877", 60, 0.6, 0.3), (470, 250, "#8fd0ff", 70, 0.45, 0.1),
                                    (570, 630, "#7fd8b8", 60, 0.4, 0.1)],
        player=(60, 270), door=(1246, 648), shrine=(1170, 680), dress=("graveyard", 34)),
    "dead_bridge": dict(
        # A long ruin: the riverbed, a broken bridge on two piers, and the
        # battlements above it. The gate is up on the far battlement.
        backdrop="dead_bridge", width=1600, height=540, weather="fireflies", fog=0.45, intro="voice_catacombs", music="dead_bridge",
        ground=[(0, 500, 1600, 40), (560, 440, 40, 60), (1000, 440, 40, 60)],
        platforms=[(0, 380, 560, 20), (640, 380, 320, 20), (1040, 380, 560, 20),
                   (80, 440, 80, 12), (760, 440, 90, 12), (1460, 440, 80, 12),
                   (180, 260, 220, 16), (540, 260, 200, 16), (880, 260, 260, 16), (1280, 260, 320, 16),
                   (60, 320, 80, 12), (430, 320, 80, 12), (800, 320, 70, 12), (1200, 320, 70, 12),
                   (330, 150, 90, 12), (700, 160, 120, 12), (1100, 140, 100, 12)],
        spawns=[("cultist", 300, 488), ("fallen_guard", 700, 488), ("elite_possessed", 1150, 488), ("blind_preacher", 1350, 488),
                ("zealot", 400, 368), ("fallen_champion", 800, 368), ("cultist", 1300, 368),
                ("zealot", 650, 248), ("cultist", 1000, 248),
                ("shade", 900, 200), ("wraith", 1450, 180), ("shade", 300, 140), ("raven", 1200, 100)],
        props=[("crate", 160, 500), ("barrel_iron", 300, 500), ("crate_large", 500, 500), ("pot", 760, 500),
               ("barrel", 1080, 500), ("chest_wooden", 1500, 500), ("rubble", 250, 380), ("pot", 1200, 380),
               ("barrel_apples", 600, 260), ("chest_cursed", 750, 160)],
        decor=[("tree_1", 60, 500, "back"), ("tree_5", 900, 500, "back"), ("monument_8", 400, 500, "back"),
               ("monument_5", 1150, 500, "back"), ("crypt_2", 700, 500, "back"), ("tree_3", 1400, 500, "back"),
               ("crypt_1", 1300, 500, "back"),
               ("fence_2", 300, 500, "mid"), ("tombstone_3", 640, 500, "mid"), ("tombstone_6", 1080, 500, "mid"),
               ("rocks", 230, 380, "front"), ("grass_1", 370, 380, "front"), ("bush", 690, 380, "front"),
               ("grass_2", 1290, 380, "front"), ("fence_1", 1500, 380, "mid"),
               ("rocks", 300, 260, "front"), ("grass_2", 950, 260, "front")],
        npcs=[],
        ambient="#8ea0a4", lights=[(1566, 201, "#ffb877", 60, 0.6, 0.3), (700, 240, "#7fe0b0", 80, 0.4, 0.12),
                                    (1020, 420, "#7fe0b0", 70, 0.35, 0.12)],
        player=(60, 480), door=(1566, 228), shrine=(1480, 260), dress=("ruin", 30)),
    "fallen_knight": dict(
        # Boss arena, one screen: a raised dais in the middle, ledges to escape to.
        backdrop="dead_bridge", width=1024, height=360, weather="rain", fog=0.5, intro="", music="boss_knight",
        intro_cutscene="knight_arrival",
        ground=[(0, 320, 1024, 40), (412, 272, 200, 48)],
        platforms=[(120, 230, 110, 12), (800, 230, 110, 12), (300, 180, 90, 12), (640, 180, 90, 12)],
        spawns=[("knight_of_ash", 720, 308)],
        props=[("barrel", 110, 320), ("box_goods", 960, 320)],
        decor=[("monument_8", 180, 320, "back"), ("monument_2", 512, 272, "back"), ("tree_5", 860, 320, "back"),
               ("tombstone_3", 300, 320, "mid"), ("fence_2", 690, 320, "mid")],
        barriers=[(36, 320), (1000, 320)],
        ambient="#8688a8", lights=[(990, 261, "#ffb877", 60, 0.6, 0.3), (512, 250, "#ff6a4a", 100, 0.5, 0.2)],
        player=(60, 300), door=(990, 288), shrine=(900, 320), dress=("arena", 9)),
    "practice_yard": dict(
        # The practice yard (docs/PRACTICE.md): a cloister at dusk, one screen,
        # entered from the bestiary or the main menu, never from the chapter.
        # Painted by tools/art/make_practice_yard.py. A flat floor for footwork,
        # a ledge each side and one over the middle for the moves in the air.
        backdrop="practice_yard", width=960, height=360, weather="none", fog=0.2, intro="", music="arena",
        ground=[(0, 320, 960, 40)],
        platforms=[(96, 244, 120, 12), (744, 244, 120, 12), (420, 196, 120, 12)],
        spawns=[],
        props=[],
        decor=[("practice/dummy", 150, 320, "mid"), ("practice/rack", 214, 320, "mid"),
               ("practice/dummy", 262, 320, "mid"), ("clutter/brazier_lit", 330, 320, "mid"),
               ("clutter/brazier_lit", 630, 320, "mid"), ("practice/rack", 760, 320, "mid"),
               ("practice/dummy", 830, 320, "mid"), ("grass_1", 60, 320, "front"), ("rocks", 900, 320, "front")],
        ambient="#b8a4a4",
        lights=[(330, 300, "#ffb060", 90, 1.0, 0.3), (630, 300, "#ffb060", 90, 1.0, 0.3),
                (480, 190, "#ffc890", 200, 0.5, 0.05)],
        player=(120, 300), door=(926, 288)),
    "church_ophanim": dict(
        # Boss arena, one screen: a symmetrical nave with a high altar in the middle.
        backdrop="village_night", width=960, height=360, weather="embers", fog=0.3, intro="ch1_ophanim", music="boss_ophanim",
        intro_cutscene="ophanim_arrival", outro_cutscene="ch1_finale",
        ground=[(0, 320, 960, 40)],
        platforms=[(90, 250, 120, 12), (750, 250, 120, 12), (240, 200, 100, 14), (620, 200, 100, 14), (430, 160, 100, 12)],
        spawns=[("ophanim", 480, 110)],
        npcs=[("matthew", 120, 320)],
        props=[("pot", 180, 320), ("barrel", 240, 320), ("barrel_apples", 340, 320), ("crate", 830, 320)],
        # The nave's dressing was rolled once from DRESSING["nave"] and is
        # kept as placed: the arena was tuned around it (ophanim_room_art_test).
        decor=[("tree_2", 110, 320, "back"), ("monument_5", 480, 320, "back"), ("monument_2", 800, 320, "back"),
               ("graveyard/angel_1", 167, 320, "back"), ("graveyard/angel_4", 394, 320, "back"),
               ("graveyard/cross_2", 653, 200, "back"), ("graveyard/angel_2", 770, 320, "back"),
               ("fence_1", 250, 320, "mid"), ("fence_3", 700, 320, "mid"),
               ("clutter/brazier_lit", 261, 200, "mid"), ("graveyard/yard_4", 307, 200, "mid"),
               ("clutter/brazier_lit", 329, 320, "mid"), ("clutter/brazier_lit", 515, 320, "mid"),
               ("graveyard/yard_1", 738, 320, "mid"), ("clutter/brazier_lit", 890, 320, "mid"),
               ("grass_1", 150, 250, "front"), ("rocks", 470, 160, "front"), ("grass_2", 800, 250, "front")],
        barriers=[(36, 320), (936, 320)],
        ambient="#a08c98", lights=[(926, 261, "#ffb877", 60, 0.6, 0.3), (480, 140, "#ffd27a", 120, 0.55, 0.15)],
        player=(60, 300), door=(926, 288), shrine=(860, 320)),
}

## Lights painted into the backdrops, in painting pixels (640x360): the lamp on
## the post, the candles at the shrine, the moon. They ride on the Parallax node
## so they stay on the painting. (x, y, colour, radius, energy, flicker)
BACKDROP_LIGHTS = {
    "village_night": [(215, 190, "#ffb060", 70, 0.9, 0.25), (80, 205, "#ff9a50", 50, 0.6, 0.2),
                      (12, 215, "#ff9a50", 40, 0.5, 0.2), (520, 100, "#ffd080", 60, 0.5, 0.05),
                      (485, 245, "#ff8040", 40, 0.5, 0.15)],
    "graveyard": [(400, 100, "#ffb070", 160, 0.55, 0.0), (565, 165, "#c0a060", 40, 0.35, 0.1)],
    "dead_bridge": [(75, 185, "#ffb060", 70, 0.9, 0.25), (565, 265, "#ff9040", 50, 0.7, 0.3),
                    (490, 45, "#d0d8ff", 140, 0.45, 0.0)],
}

WEATHER = {
    "embers": """[node name="Weather" type="CPUParticles2D" parent="."]
z_index = 2
position = Vector2({cx}, {cy})
amount = {amount_low}
lifetime = 6.0
preprocess = 6.0
texture = SubResource("dot")
emission_shape = 3
emission_rect_extents = Vector2({ex}, {ey})
direction = Vector2(0, -1)
spread = 25.0
gravity = Vector2(0, -12)
initial_velocity_min = 15.0
initial_velocity_max = 45.0
angular_velocity_min = -60.0
angular_velocity_max = 60.0
scale_amount_min = 0.5
scale_amount_max = 1.2
color = Color(1.4, 0.8, 0.3, 0.9)
color_ramp = SubResource("fade")
""",
    "rain": """[node name="Weather" type="CPUParticles2D" parent="."]
z_index = 2
position = Vector2({cx}, -20)
amount = {amount_high}
lifetime = {rain_life}
preprocess = {rain_life}
texture = SubResource("drop")
emission_shape = 3
emission_rect_extents = Vector2({ex}, 4)
direction = Vector2(-0.15, 1)
spread = 2.0
gravity = Vector2(0, 600)
initial_velocity_min = 260.0
initial_velocity_max = 340.0
scale_amount_min = 0.7
scale_amount_max = 1.0
color = Color(0.9, 0.95, 1.1, 0.5)

[node name="WeatherFar" type="CPUParticles2D" parent="."]
position = Vector2({cx}, -20)
amount = {amount_low}
lifetime = {rain_life}
preprocess = {rain_life}
texture = SubResource("drop")
emission_shape = 3
emission_rect_extents = Vector2({ex}, 4)
direction = Vector2(-0.15, 1)
spread = 2.0
gravity = Vector2(0, 500)
initial_velocity_min = 200.0
initial_velocity_max = 260.0
scale_amount_min = 0.4
scale_amount_max = 0.6
color = Color(0.7, 0.75, 0.9, 0.3)
""",
    "fireflies": """[node name="Weather" type="CPUParticles2D" parent="."]
z_index = 2
position = Vector2({cx}, {cy})
amount = {amount_low}
lifetime = 5.0
preprocess = 5.0
texture = SubResource("dot")
emission_shape = 3
emission_rect_extents = Vector2({ex}, {ey})
direction = Vector2(1, 0)
spread = 180.0
gravity = Vector2(0, 0)
initial_velocity_min = 6.0
initial_velocity_max = 18.0
scale_amount_min = 0.4
scale_amount_max = 0.9
color = Color(0.9, 1.4, 0.6, 1)
color_ramp = SubResource("fade")
""",
}

WEATHER["ash"] = """[node name="Weather" type="CPUParticles2D" parent="."]
z_index = 2
position = Vector2({cx}, -20)
amount = {amount_low}
lifetime = 9.0
preprocess = 9.0
texture = SubResource("dot")
emission_shape = 3
emission_rect_extents = Vector2({ex}, 4)
direction = Vector2(0.2, 1)
spread = 30.0
gravity = Vector2(0, 14)
initial_velocity_min = 8.0
initial_velocity_max = 22.0
angular_velocity_min = -40.0
angular_velocity_max = 40.0
scale_amount_min = 0.5
scale_amount_max = 1.1
color = Color(0.75, 0.75, 0.85, 0.7)
color_ramp = SubResource("fade")
"""

## Dust in the air of every room: slow, faint, in front of the characters so it
## reads as air between them and the camera.
MOTES = """[node name="Motes" type="CPUParticles2D" parent="."]
z_index = 1
position = Vector2({cx}, {cy})
amount = {amount}
lifetime = 9.0
preprocess = 9.0
texture = SubResource("dot")
emission_shape = 3
emission_rect_extents = Vector2({ex}, {ey})
direction = Vector2(1, 0)
spread = 180.0
gravity = Vector2(0, -3)
initial_velocity_min = 3.0
initial_velocity_max = 9.0
scale_amount_min = 0.3
scale_amount_max = 0.6
color = Color(1, 0.95, 0.85, 0.5)
color_ramp = SubResource("fade")

"""

HEAD = """[gd_scene load_steps={steps} format=3]

[ext_resource type="Script" path="res://scripts/rooms/room.gd" id="1_room"]
[ext_resource type="Texture2D" path="res://assets/backgrounds/{backdrop}.png" id="2_backdrop"]
[ext_resource type="Shader" path="res://assets/shaders/fog.gdshader" id="3_fog"]
[ext_resource type="Script" path="res://scripts/rooms/door.gd" id="4_door"]
[ext_resource type="Script" path="res://scripts/rooms/enemy_spawn.gd" id="5_spawn"]
[ext_resource type="PackedScene" path="res://scenes/props/prop.tscn" id="7_prop"]
[ext_resource type="Texture2D" path="res://assets/decor/door_gate.png" id="8_gate"]
[ext_resource type="Texture2D" path="res://assets/decor/shrine.png" id="9_shrine"]
[ext_resource type="Texture2D" path="res://assets/decor/barrier.png" id="11_barrier"]
[ext_resource type="Script" path="res://scripts/rooms/room_fixture.gd" id="10_fixture"]
[ext_resource type="PackedScene" path="res://scenes/npc/npc.tscn" id="11_npc"]
[ext_resource type="Script" path="res://scripts/fx/glow_light.gd" id="12_light"]
[ext_resource type="Script" path="res://scripts/fx/ambient_light.gd" id="13_ambient"]
[ext_resource type="Script" path="res://scripts/rooms/church_bell.gd" id="14_bell"]
[ext_resource type="Script" path="res://scripts/rooms/hazard.gd" id="15_hazard"]
{decor_ext}{piece_ext}
[sub_resource type="Gradient" id="fade"]
offsets = PackedFloat32Array(0, 0.15, 0.7, 1)
colors = PackedColorArray(1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0.8, 1, 1, 1, 0)

[sub_resource type="FastNoiseLite" id="noise"]
frequency = 0.012

[sub_resource type="NoiseTexture2D" id="noise_tex"]
seamless = true
noise = SubResource("noise")

[sub_resource type="ShaderMaterial" id="fog_mat"]
shader = ExtResource("3_fog")
shader_parameter/noise = SubResource("noise_tex")
shader_parameter/density = {fog}

[sub_resource type="Gradient" id="glow_grad"]
offsets = PackedFloat32Array(0, 1)
colors = PackedColorArray(1, 0.85, 0.5, 0.7, 1, 0.85, 0.5, 0)

[sub_resource type="GradientTexture2D" id="glow_tex"]
gradient = SubResource("glow_grad")
width = 96
height = 96
fill = 1
fill_from = Vector2(0.5, 0.5)
fill_to = Vector2(0.5, 0)

[sub_resource type="Gradient" id="dot_grad"]
offsets = PackedFloat32Array(0, 1)
colors = PackedColorArray(1, 1, 1, 1, 1, 1, 1, 0)

[sub_resource type="GradientTexture2D" id="dot"]
gradient = SubResource("dot_grad")
width = 4
height = 4
fill = 1
fill_from = Vector2(0.5, 0.5)
fill_to = Vector2(0.5, 0)

[sub_resource type="GradientTexture2D" id="drop"]
gradient = SubResource("dot_grad")
width = 2
height = 10
fill_from = Vector2(0.5, 1)
fill_to = Vector2(0.5, 0)

[sub_resource type="CanvasItemMaterial" id="add_mat"]
blend_mode = 1

[sub_resource type="RectangleShape2D" id="door_shape"]
size = Vector2(20, 56)

{shapes}[node name="Room" type="Node2D"]
script = ExtResource("1_room")
width = {width}
height = {height}
intro_dialogue = "{intro}"
intro_cutscene = "{intro_cutscene}"
outro_cutscene = "{outro_cutscene}"

[node name="Ambient" type="CanvasModulate" parent="."]
color = {ambient}
script = ExtResource("13_ambient")
music = "{music}"

[node name="Parallax" type="Parallax2D" parent="."]
scroll_scale = Vector2({bscroll_x}, {bscroll_y})

[node name="Backdrop" type="Sprite2D" parent="Parallax"]
texture_filter = 2
scale = Vector2({bscale}, {bscale})
texture = ExtResource("2_backdrop")
centered = false

{backdrop_lights}[node name="FogFar" type="Parallax2D" parent="."]
scroll_scale = Vector2(0.75, 0.75)

[node name="Fog" type="ColorRect" parent="FogFar"]
material = SubResource("fog_mat")
offset_right = {fogw}.0
offset_bottom = {fogh}.0
mouse_filter = 2

[node name="Geometry" type="StaticBody2D" parent="."]
collision_layer = 1
collision_mask = 0

"""

FILL_COLOR = "Color(0.11, 0.09, 0.1, 1)"
## How far the 640x360 backdrop paintings are blown up. See build().
BACKDROP_SCALE = 1.1
## Neighbouring pieces overlap this much so no seam shows.
OVERLAP = 3


def shapes(rects, prefix, names=None):
    return "".join(f'[sub_resource type="RectangleShape2D" id="{(names or {}).get(i + 1, prefix + str(i + 1))}_shape"]\n'
                   f'size = Vector2({w}, {h})\n\n' for i, (x, y, w, h) in enumerate(rects))


def collider(rects, prefix, parent, one_way=False, names=None):
    out = []
    for i, (x, y, w, h) in enumerate(rects, 1):
        name = (names or {}).get(i, f"{prefix}{i}")
        out.append(f'[node name="{name}Shape" type="CollisionShape2D" parent="{parent}"]\n'
                   f'position = Vector2({x + w / 2}, {y + h / 2})\nshape = SubResource("{name}_shape")\n'
                   + ("one_way_collision = true\n" if one_way else "") + "\n")
    return "".join(out)


def ramp_nodes(ramps, parent, authored_treads=None):
    """Trace stair treads, not a smooth slope that floats over painted steps.

    A riser is at most 8 px: the hero's 12 px step-up can walk uphill, while
    downhill movement follows the visible stair instead of skating through it.
    The strip stays thin so routes below an open staircase remain open.
    """
    out = []
    for i, (x0, y0, x1, y1) in enumerate(ramps, 1):
        if x1 < x0:
            x0, x1 = x1, x0
            y0, y1 = y1, y0
        if authored_treads and i in authored_treads:
            top = list(authored_treads[i])
        else:
            count = max(1, (abs(y1 - y0) + 7) // 8)
            top = [(float(x0), float(y0))]
            for step in range(count):
                right_x = x0 + (x1 - x0) * (step + 1) / count
                top.append((right_x, y0 + (y1 - y0) * step / count))
                if step + 1 < count:
                    top.append((right_x, y0 + (y1 - y0) * (step + 1) / count))
            top.append((float(x1), float(y1)))
        thick = 16.0
        polygon = top + [(x, y + thick) for x, y in reversed(top)]
        coords = ", ".join(f"{round(x, 2)}, {round(y, 2)}" for x, y in polygon)
        out.append(f'[node name="Ramp{i}" type="CollisionPolygon2D" parent="{parent}"]\n'
                   f'polygon = PackedVector2Array({coords})\n\n')
    return "".join(out)


def family(name):
    return [piece for piece in sorted(PIECES) if PIECES[piece]["family"] == name]


def lay(x0, x1, pieces, rng, left_cap=None, right_cap=None):
    """Pieces laid left to right over [x0, x1): (name, x, crop width, flip).

    Whole pieces overlap by OVERLAP; the last one is cropped to the edge unless
    that would leave a sliver, in which case it slides back over its
    neighbour instead. Caps are the broken-off ends of the ground at a pit.
    """
    out = []
    x = x0
    if left_cap:
        out.append((left_cap, x0, PIECES[left_cap]["w"], True))
        x += PIECES[left_cap]["w"] - OVERLAP
    stop = x1 - (PIECES[right_cap]["w"] - OVERLAP if right_cap else 0)
    previous = left_cap
    while x < stop:
        # never the same piece twice in a row: a pair of twins is the first
        # thing an eye finds in a laid floor
        name = rng.choice([p for p in pieces if p != previous] or pieces)
        previous = name
        w = PIECES[name]["w"]
        last = x + w >= stop
        if last and stop - x < w * 0.45 and out:
            x = max(x0, stop - w)  # slide back over the neighbour, no sliver
        w = min(w, stop - x)
        out.append((name, x, w, rng.random() < 0.5 and w == PIECES[name]["w"]))
        if last:
            break
        x += w - OVERLAP
    if right_cap:
        out.append((right_cap, x1 - PIECES[right_cap]["w"], PIECES[right_cap]["w"], False))
    return out


def _piece_shade(prefix, x):
    """A piece a few percent darker or lighter than its neighbours: the same
    six blocks laid along a floor read as stamped until each sits in its own
    light. Hashed from where it lies, so a regeneration is not a diff."""
    h = int(hashlib.md5(f"{prefix}:{x}".encode()).hexdigest()[:4], 16) / 0xFFFF
    v = round(0.9 + 0.1 * h, 3)
    return "" if v >= 0.995 else f"modulate = Color({v}, {v}, {round(v * 0.98 + 0.02, 3)}, 1)\n"


def piece_nodes(layout, top_y, prefix, used):
    """Sprites for a lay() result, each piece's walkable top on top_y."""
    out = []
    for i, (name, x, w, flip) in enumerate(layout, 1):
        used.add(name)
        info = PIECES[name]
        out.append(f'[node name="{prefix}_{i}" type="Sprite2D" parent="Terrain"]\n'
                   f'position = Vector2({x}, {top_y - info["top"]})\n'
                   f'texture = ExtResource("piece_{name}")\ncentered = false\n'
                   + ("flip_h = true\n" if flip else "")
                   + _piece_shade(prefix, x)
                   + (f'region_enabled = true\nregion_rect = Rect2(0, 0, {w}, {info["h"]})\n' if w < info["w"] else "")
                   + "\n")
    return "".join(out)


def interior_nodes(r, rng, used):
    """A room inside: stone wall pieces tiled over the whole back, dim, with
    pillars standing on the floor line and, above, whatever "arches" the room
    lists (window openings; a cool light behind each is the glass)."""
    width, height = r["width"], r.get("height", 360)
    # solid dark behind the stones: their mossy edges leave gaps
    out = [f'[node name="Backing" type="ColorRect" parent="Interior"]\noffset_right = {width}.0\n'
           f'offset_bottom = {height}.0\ncolor = Color(0.06, 0.05, 0.07, 1)\nmouse_filter = 2\n\n']
    pieces = family("wall")
    y = -12
    row = 0
    while y < height:
        x = -8 - (row % 2) * 12
        while x < width:
            name = rng.choice(pieces)
            used.add(name)
            # brighter than it looks right: the lights multiply into this
            out.append(f'[node name="Wall_{row}_{len(out)}" type="Sprite2D" parent="Interior"]\n'
                       f'position = Vector2({x}, {y})\ntexture = ExtResource("piece_{name}")\ncentered = false\n'
                       + ("flip_h = true\n" if rng.random() < 0.5 else "")
                       + 'modulate = Color(1.15, 1.1, 1.2, 1)\n\n')
            x += PIECES[name]["w"] - OVERLAP
        y += 46
        row += 1
    pillars = family("pillar")[:4]  # the standing columns, not the pedestals
    for i, (x, y) in enumerate(r.get("pillars", []), 1):
        name = pillars[i % len(pillars)]
        used.add(name)
        info = PIECES[name]
        out.append(f'[node name="Pillar{i}" type="Sprite2D" parent="Interior"]\n'
                   f'position = Vector2({x - info["w"] // 2}, {y - info["h"]})\ntexture = ExtResource("piece_{name}")\n'
                   'centered = false\nmodulate = Color(1.2, 1.15, 1.25, 1)\n\n')
    return "".join(out)


def terrain_nodes(r, rng, used, walls=True):
    """The ground and the ledges drawn out of sheet pieces (assets/decor/platforms).

    Solid ground: grass-topped earth blocks, broken-off caps at a pit, a dark
    fill under them where the block is taller than the art. Narrow tall
    blocks (bridge piers) are wall segments. Ledges (jump-through) are stone
    shelves with hanging moss, small mossy chunks when they are short.
    """
    width = r["width"]
    out = []
    for i, (x, y, w, h) in enumerate(r["ground"], 1):
        if w <= 48 and h >= 48:
            out.append(piece_nodes(lay(x, x + w, family("wall"), rng), y, f"Ground{i}", used))
            continue
        pieces = family(r.get("floor", "ground" if w >= 120 else "earth"))
        caps = family("cap")
        layout = lay(x, x + w, pieces, rng,
                     left_cap=rng.choice(caps) if x > 0 else None,
                     right_cap=rng.choice(caps) if x + w < width else None)
        art_bottom = y + min(PIECES[n]["h"] - PIECES[n]["top"] for n, _, _, _ in layout)
        if y + h > art_bottom + 2:
            out.append(f'[node name="Ground{i}Fill" type="ColorRect" parent="Terrain"]\n'
                       f'offset_left = {x}.0\noffset_top = {art_bottom - 4}.0\noffset_right = {x + w}.0\n'
                       f'offset_bottom = {y + h}.0\ncolor = {FILL_COLOR}\nmouse_filter = 2\n\n')
        out.append(piece_nodes(layout, y, f"Ground{i}", used))
    for i, (x, y, w, h) in enumerate(r["platforms"], 1):
        named = r.get("platform_names", {}).get(i)
        hanging = r.get("hanging_supports", {}).get(i)
        if hanging:
            out.append(f'[node name="{named or f"Platform{i}"}Hangers" type="Node2D" parent="Terrain"]\n'
                       f'position = Vector2({x}, {y})\nscript = ExtResource("hanging_support")\n'
                       f'walk_width = {float(w)}\nleft_length = {float(hanging[0])}\n'
                       f'right_length = {float(hanging[1])}\n'
                       + ('timber = true\n' if len(hanging) > 2 and hanging[2] == "timber" else '')
                       + '\n')
        if r.get("painted_cornices"):
            # Reuse this room's painted stone cap, rather than a foreign
            # grid-textured pier. Both cornices meet the existing arch wall.
            crop_x, crop_y = r.get("cornice_crop", (990, 385))
            script = (f'script = ExtResource("hell_cornice")\nwalk_width = {float(w)}\n'
                      f'wall_on_right = {str(x + w == width).lower()}\n'
                      if r.get("hell_cornice_art") else "")
            out.append(f'[node name="{named + "Cornice" if named else f"Platform{i}_1"}" type="Sprite2D" parent="Terrain"]\n'
                       f'{script}'
                       f'position = Vector2({x}, {y})\ntexture = ExtResource("2_backdrop")\n'
                       f'centered = false\nregion_enabled = true\nregion_rect = Rect2({crop_x}, {crop_y}, {w}, 12)\n\n')
            if r.get("cornice_post"):
                sx, sy, pw, ph = r["cornice_post"]
                out.append(f'[node name="{named or f"Platform{i}"}Post" type="Sprite2D" parent="Terrain"]\n'
                           f'position = Vector2({x + (w - pw) / 2}, {y + 12})\n'
                           f'texture = ExtResource("2_backdrop")\ncentered = false\nregion_enabled = true\n'
                           f'region_rect = Rect2({sx}, {sy}, {pw}, {ph})\n\n')
            support = r.get("cornice_supports", {}).get(i)
            if support:
                polygon = ", ".join(str(v) for point in support for v in point)
                ux, uy = r.get("cornice_support_shift", {}).get(i, (0, 0))
                uv = ", ".join(str(v) for px, py in support for v in (crop_x + ux + px, crop_y + uy + py))
                out.append(f'[node name="{named or f"Platform{i}"}Support" type="Polygon2D" parent="Terrain"]\n'
                           f'position = Vector2({x}, {y})\ntexture = ExtResource("2_backdrop")\n'
                           f'polygon = PackedVector2Array({polygon})\nuv = PackedVector2Array({uv})\n\n')
            continue
        pieces = family("ledge") if r.get("stone_steps") or w >= 80 else family("float")
        out.append(piece_nodes(lay(x, x + w, pieces, rng), y, f"Platform{i}", used))
    if not walls:
        return "".join(out)
    # the room's edges: a mossy wall on each side, behind everything
    walls = family("wall")
    for side, x in (("L", -4), ("R", width - 26)):
        y = r.get("height", 360)
        i = 0
        while y > -16:
            name = rng.choice(walls)
            used.add(name)
            i += 1
            y -= PIECES[name]["h"] - OVERLAP
            out.append(f'[node name="Wall{side}_{i}" type="Sprite2D" parent="Terrain"]\n'
                       f'position = Vector2({x}, {y})\ntexture = ExtResource("piece_{name}")\ncentered = false\n'
                       'modulate = Color(0.8, 0.8, 0.85, 1)\n\n')
    return "".join(out)


def color(hex_rgb):
    """'#rrggbb' -> 'Color(r, g, b, 1)'."""
    return "Color(%s, 1)" % ", ".join(str(round(int(hex_rgb[i:i + 2], 16) / 255.0, 3)) for i in (1, 3, 5))


def thin_lights(lights, max_count=26, spacing=48):
    """A painted room can carry a hundred candles; the renderer should not.
    Keep the big ones, then the rest from the left, none closer than spacing."""
    kept = []
    for light in sorted(lights, key=lambda l: (-l[3], l[0])):
        if len(kept) >= max_count:
            break
        if all(abs(light[0] - k[0]) >= spacing or abs(light[1] - k[1]) >= spacing for k in kept):
            kept.append(light)
    return sorted(kept)


def light_nodes(lights, parent, prefix, scale=1.0):
    out = []
    for i, (x, y, tint, radius, energy, flicker) in enumerate(lights, 1):
        out.append(f'[node name="{prefix}{i}" type="PointLight2D" parent="{parent}"]\n'
                   f'position = Vector2({round(x * scale)}, {round(y * scale)})\ncolor = {color(tint)}\n'
                   f'energy = {energy}\nscript = ExtResource("12_light")\nradius = {radius}.0\nflicker = {flicker}\n\n')
    return "".join(out)


def decor_nodes(decor, layer, parent, ambient):
    """Sprites anchored at their bottom centre. Back layer is darker and parallaxed."""
    out = []
    rgb = [int(ambient[i:i + 2], 16) / 255.0 for i in (1, 3, 5)]
    shade = 0.76 if layer == "back" else 1.04
    tint = "Color(%s, %s, %s, 1)" % tuple(round(min(1.0, channel * shade), 3) for channel in rgb)
    for i, (name, x, y, where) in enumerate(decor, 1):
        if where != layer:
            continue
        w, h = Image.open(os.path.join(DECOR_DIR, f"{name}.png")).size
        out.append(f'''[node name="{ident(name)}_{i}" type="Sprite2D" parent="{parent}"]
modulate = {tint}
position = Vector2({x}, {y - h / 2})
texture = ExtResource("decor_{ident(name)}")

''')
    return "".join(out)


def ident(name):
    """A decor name as a node name / resource id: sub-folders flattened."""
    return name.replace("/", "_")


# What each kind of place is dressed with (assets/decor/<folder>/<family>_N.png,
# cut by tools/art/slice_batch10.py). Families are weighted by how often they
# should turn up; a room asks for a kind and a count with dress=(kind, count).
DRESSING = {
    "graveyard": {"graveyard/tomb": 5, "graveyard/cross": 3, "graveyard/monument": 1, "graveyard/angel": 1,
                  "graveyard/railing": 1, "graveyard/coffin": 1, "graveyard/grave": 1, "graveyard/bones": 2,
                  "graveyard/deadwood": 1, "graveyard/crypt": 1, "wilds/stump": 1, "wilds/brush": 2,
                  "wilds/sapling": 1},
    "ruin": {"wilds/tree": 2, "wilds/sapling": 2, "wilds/fallen": 2, "wilds/stump": 2, "wilds/brush": 3,
             "graveyard/tomb": 1, "graveyard/cross": 1, "graveyard/bones": 1, "clutter/clutter": 2},
    "arena": {"graveyard/angel": 2, "graveyard/monument": 1, "graveyard/tomb": 2, "graveyard/bones": 2,
              "clutter/brazier_lit": 1, "wilds/brush": 1},
    "nave": {"clutter/altar_lit": 1, "clutter/brazier_lit": 2, "graveyard/angel": 2, "graveyard/coffin": 1,
             "graveyard/yard": 1, "graveyard/bones": 1, "graveyard/cross": 1},
}
# Anything this tall or more is scenery behind the fight, not clutter in it.
BACK_FROM = 50
# Anything this short or less sits in front of the bodies, like grass does.
FRONT_UPTO = 24


def dress(name, r):
    """Extra decor scattered over the room's own surfaces: [(name, x, floor, layer)].

    Seeded by the room name, so a regeneration puts the same piece in the same
    place. A piece only lands where it fits: on a surface wide enough for it,
    under enough headroom (the tier above is 65-70 px up; scenery behind the
    geometry may reach 20 px into it), and never on top of a prop, an enemy, an
    npc, the player's spawn, the door or the shrine, nor another piece.
    """
    if "dress" not in r:
        return []
    kind, count = r["dress"]
    pool = []
    for family, weight in DRESSING[kind].items():
        folder, stem = family.split("/")
        files = sorted(f for f in os.listdir(os.path.join(DECOR_DIR, folder))
                       if f.endswith(".png") and (f.startswith(stem + "_") or f == stem + ".png"))
        for f in files:
            w, h = Image.open(os.path.join(DECOR_DIR, folder, f)).size
            pool.append((f"{folder}/{f[:-4]}", w, h, weight / len(files)))
    surfaces = [(x, y, w) for x, y, w, _ in r["ground"] + r["platforms"] if w >= 60]
    taken = [(x, y) for _, x, y, _ in r.get("decor", [])]
    for key in ("props", "spawns", "npcs"):
        taken += [(x, y if key != "spawns" else y + 12) for _, x, y in r.get(key, [])]
    for key in ("player", "door", "shrine"):
        if key in r:
            x, y = r[key]
            taken.append((x, y + {"player": 20, "door": 32}.get(key, 0)))

    def headroom(x0, x1, y):
        above = [sy for sx, sy, sw in surfaces if sy < y - 8 and sx < x1 and sx + sw > x0]
        return y - max(above) if above else 999

    rng = random.Random("dress:" + name)
    out = []
    for _ in range(count * 12):  # a bounded number of tries: a crowded room just gets fewer
        if len(out) >= count:
            break
        piece, w, h, _ = rng.choices(pool, weights=[p[3] for p in pool])[0]
        sx, sy, sw = rng.choices(surfaces, weights=[s[2] for s in surfaces])[0]
        if sw < w + 16:
            continue
        x = round(rng.uniform(sx + 8 + w / 2, sx + sw - 8 - w / 2))
        layer = "back" if h >= BACK_FROM else ("front" if h <= FRONT_UPTO else "mid")
        room_above = headroom(x - w / 2, x + w / 2, sy)
        if h > room_above - 4 + (20 if layer == "back" else 0):
            continue
        near = max(24, w * 0.6)
        if any(abs(tx - x) < near and abs(ty - sy) < 6 for tx, ty in taken):
            continue
        taken.append((x, sy))
        out.append((piece, x, sy, layer))
    return out


def build(name, r):
    r = deepcopy(r)
    r["props"] = contextual_props(name, r.get("props", []))
    width, height = r["width"], r.get("height", 360)
    # Walls on both sides and a lid over the top: the player has a double jump
    # and the camera stops at y = 0.
    walls = [(-16, -16, 16, height + 16), (width, -16, 16, height + 16), (0, -16, width, 16)]
    painted = "painting" in r
    ledges = r.get("ledges", [])
    shape_text = (shapes(r["ground"], "Ground") + shapes(r["platforms"], "Platform", r.get("platform_names")) + shapes(ledges, "Ledge")
                  + shapes(walls, "Wall"))
    decor = r.get("decor", []) + dress(name, r)
    decor_names = sorted({d[0] for d in decor})
    decor_ext = "".join(f'[ext_resource type="Texture2D" path="res://assets/decor/{n}.png" id="decor_{ident(n)}"]\n'
                        for n in decor_names)
    # Same pieces in the same places every time the script runs: the layout is
    # part of the room, not a dice roll on every regeneration.
    rng = random.Random(name)
    used = set()
    # A painted room draws nothing over its ground and ledges: the panel already
    # has them. Only the extra "platforms" get piece art.
    terrain_room = dict(r, ground=[], ledges=[]) if painted else r
    if painted:
        # A hand-painted foothold has its own silhouette and support in the
        # panel. Drawing a generic terrain sprite over it creates doubled
        # masonry (or a green island over a wooden swamp pier).
        terrain_room["platforms"] = [p for p in r["platforms"] if p not in r.get("painted_platforms", [])]
    terrain = terrain_nodes(terrain_room, rng, used, walls=not painted)
    interior = interior_nodes(r, rng, used) if r.get("interior") else ""
    piece_ext = "".join(f'[ext_resource type="Texture2D" path="res://assets/decor/platforms/{n}.png" id="piece_{n}"]\n'
                        for n in sorted(used))
    ambient = color(r["ambient"])
    # The backdrops are painted at exactly one screen (640x360), so every pixel of
    # upscale costs detail and any non-uniform scale bends the painting. Keep the
    # scale uniform and barely above 1 and buy the parallax travel from the
    # scroll instead. A Parallax2D layer sits at camera * (1 - scroll_scale), so
    # over a room it slips scroll_scale * (width - 640) pixels against the
    # screen, and that slip has to fit in the 640 * (BACKDROP_SCALE - 1) pixels
    # the upscale gives us (36 vertically, for a room taller than one screen).
    bscroll_x = round(min(0.1, 640 * (BACKDROP_SCALE - 1.0) / (width - 640)), 2) if width > 640 else 0.0
    bscroll_y = round(min(0.1, 360 * (BACKDROP_SCALE - 1.0) / (height - 360)), 2) if height > 360 else 0.0
    area = width * height / (1280.0 * 360.0)
    weather = "" if r["weather"] == "none" else WEATHER[r["weather"]].format(
        cx=width / 2, cy=height / 2, ex=width / 2 + 60, ey=max(10, height / 2 - 30),
        amount_low=int(40 * area), amount_high=min(400, int(260 * area)),
        rain_life=round(1.2 * max(1.0, height / 480.0), 2))
    text = HEAD.format(intro_cutscene=r.get("intro_cutscene", ""), outro_cutscene=r.get("outro_cutscene", ""), steps=0, backdrop=r.get("backdrop", ""), fog=r["fog"], width=width, height=height, intro=r["intro"],
                       music=r.get("music", ""),
                       fogw=width + 200, fogh=height + 400, bscale=BACKDROP_SCALE,
                       bscroll_x=bscroll_x, bscroll_y=bscroll_y, shapes=shape_text, decor_ext=decor_ext,
                       piece_ext=piece_ext, ambient=ambient,
                       backdrop_lights=light_nodes(BACKDROP_LIGHTS.get(r.get("backdrop"), []), "Parallax", "Painted", BACKDROP_SCALE))
    if "void_kill_y" in r:
        text = text.replace(f'height = {height}\n', f'height = {height}\nvoid_kill_y = {r["void_kill_y"]}\n', 1)
    if r.get("interior"):
        # Inside: no painting, no fog; a stone wall behind everything.
        text = text.replace('[ext_resource type="Texture2D" path="res://assets/backgrounds/.png" id="2_backdrop"]\n', '')
        a = text.index('[node name="Parallax" type="Parallax2D" parent="."]')
        b = text.index('[node name="Geometry" type="StaticBody2D" parent="."]')
        text = text[:a] + '[node name="Interior" type="Node2D" parent="."]\n\n' + interior + text[b:]
    if painted:
        text = text.replace('outro_cutscene = "' + r.get("outro_cutscene", "") + '"\n',
                            'outro_cutscene = "' + r.get("outro_cutscene", "") + '"\n'
                            + f'painting_source = "res://assets/levels/{r["painting_wide"]}.png"\n', 1)
        # The wide panel contains inserted local scenery bands rather than a
        # non-uniformly stretched source, so stone and figures keep their scale.
        text = text.replace('[ext_resource type="Texture2D" path="res://assets/backgrounds/.png" id="2_backdrop"]',
                            f'[ext_resource type="Texture2D" path="res://assets/levels/{r["painting_wide"]}.png" id="2_backdrop"]')
        text = text.replace('[ext_resource type="Shader" path="res://assets/shaders/fog.gdshader" id="3_fog"]',
                            '[ext_resource type="Shader" path="res://assets/shaders/fog.gdshader" id="3_fog"]\n'
                            '[ext_resource type="Shader" path="res://assets/shaders/depth_window.gdshader" id="depth_shader"]\n'
                            f'[ext_resource type="Texture2D" path="res://assets/levels/depth/{r["painting"]}_backfill_wide.png" id="depth_plate"]')
        if name in SEAM_SILHOUETTES:
            art, _, _, _, _ = SEAM_SILHOUETTES[name]
            text = text.replace('[ext_resource type="Shader" path="res://assets/shaders/depth_window.gdshader" id="depth_shader"]',
                                '[ext_resource type="Shader" path="res://assets/shaders/depth_window.gdshader" id="depth_shader"]\n'
                                f'[ext_resource type="Texture2D" path="res://assets/decor/{art}.png" id="seam_silhouette"]')
        a = text.index('[node name="Parallax" type="Parallax2D" parent="."]')
        b = text.index('[node name="FogFar" type="Parallax2D" parent="."]')
        text = text[:a] + (f'[node name="Painting" type="Sprite2D" parent="."]\n'
                          'texture_filter = 2\ntexture = ExtResource("2_backdrop")\ncentered = false\n\n') + text[b:]
        depth_materials = (f'[sub_resource type="ShaderMaterial" id="depth_window_mat"]\n'
                           f'shader = ExtResource("depth_shader")\n'
                           f'shader_parameter/plate_width = {width}.0\n\n')
        text = text.replace('[sub_resource type="Gradient" id="glow_grad"]',
                            depth_materials + '[sub_resource type="Gradient" id="glow_grad"]', 1)
        strength, windows = DEPTH_WINDOWS[name]
        text = text.replace('painting_source = "res://assets/levels/' + r["painting_wide"] + '.png"\n',
                            'painting_source = "res://assets/levels/' + r["painting_wide"] + '.png"\n'
                            + f'depth_parallax = {strength}\n', 1)
        masks = '[node name="DepthWindows" type="Node2D" parent="."]\n\n'
        for i, points in enumerate(windows, 1):
            mapped = [(_map_x(x, r["_x_inserts"]), y) for x, y in points]
            center = (round(sum(x for x, _ in mapped) / len(mapped)),
                      round(sum(y for _, y in mapped) / len(mapped)))
            for edge in range(len(mapped)):
                triangle = [center, mapped[edge], mapped[(edge + 1) % len(mapped)]]
                vertices = ", ".join(str(v) for point in triangle for v in point)
                masks += (f'[node name="Window{i}Feather{edge + 1}" type="Polygon2D" parent="DepthWindows"]\n'
                          f'texture_filter = 2\ntexture = ExtResource("depth_plate")\n'
                          f'material = SubResource("depth_window_mat")\n'
                          f'polygon = PackedVector2Array({vertices})\n'
                          f'uv = PackedVector2Array({vertices})\n'
                          f'vertex_colors = PackedColorArray(1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0)\n'
                          f'antialiased = true\n\n')
        text = text.replace('[node name="FogFar" type="Parallax2D" parent="."]',
                            masks + '[node name="FogFar" type="Parallax2D" parent="."]', 1)
        if name in SEAM_SILHOUETTES:
            _, x, baseline, art_scale, tint = SEAM_SILHOUETTES[name]
            art_path = os.path.join(DECOR_DIR, SEAM_SILHOUETTES[name][0] + ".png")
            art_height = Image.open(art_path).height
            silhouette = (f'[node name="SeamSilhouette" type="Sprite2D" parent="."]\n'
                          f'position = Vector2({x}, {round(baseline - art_height * art_scale / 2, 2)})\n'
                          f'scale = Vector2({art_scale}, {art_scale})\n'
                          f'modulate = {tint}\ntexture_filter = 2\n'
                          'texture = ExtResource("seam_silhouette")\n\n')
            text = text.replace('[node name="FogFar" type="Parallax2D" parent="."]',
                                silhouette + '[node name="FogFar" type="Parallax2D" parent="."]', 1)
    # Outdoor silhouettes can drift for depth. Interior arches are part of the
    # same masonry as their platforms; parallax made the apparent supports
    # slide away from the collision geometry when the camera followed a jump.
    decor_back = ('[node name="DecorBack" type="Parallax2D" parent="."]\nscroll_scale = Vector2(1, 1)\n\n'
                  if r.get("interior") else
                  '[node name="DecorBack" type="Parallax2D" parent="."]\nscroll_scale = Vector2(0.88, 1)\n\n')
    text = text.replace('[node name="Geometry" type="StaticBody2D" parent="."]',
                        decor_back
                        + decor_nodes(decor, "back", "DecorBack", r["ambient"])
                        + '[node name="Geometry" type="StaticBody2D" parent="."]')
    text += collider(r["ground"], "Ground", "Geometry") + collider(walls, "Wall", "Geometry")
    text += ramp_nodes(r.get("ramps", []), "Geometry", r.get("ramp_treads", {}))
    # Ledges live on their own layer (5) so a body can choose to fall through them.
    text += '[node name="Ledges" type="StaticBody2D" parent="."]\ncollision_layer = 16\ncollision_mask = 0\n\n'
    text += collider(r["platforms"], "Platform", "Ledges", one_way=True, names=r.get("platform_names")) + collider(ledges, "Ledge", "Ledges", one_way=True)
    for i, (x, y, w, surface_kind) in enumerate(r.get("crumbling_platforms", []), 1):
        text += (f'[node name="CrumblingPlatform{i}" type="StaticBody2D" parent="."]\n'
                 f'position = Vector2({x}, {y})\n'
                 'script = ExtResource("crumbling_platform")\n'
                 f'walk_width = {float(w)}\n'
                 + (f'surface_kind = "{surface_kind}"\n' if surface_kind != "stone" else '')
                 + '\n')
    # Draw order from here: terrain, then what stands on the lanes behind the
    # characters, props, (the run adds enemies and players), low clutter in
    # front of their feet (z 1), weather over it all (z 2), lights.
    text += '[node name="Terrain" type="Node2D" parent="."]\n\n' + terrain
    text += '[node name="DecorMid" type="Node2D" parent="."]\n\n' + decor_nodes(decor, "mid", "DecorMid", r["ambient"])
    text += '[node name="DecorFront" type="Node2D" parent="."]\nz_index = 1\n\n' + decor_nodes(decor, "front", "DecorFront", r["ambient"])
    text += '[node name="Props" type="Node2D" parent="."]\n\n'
    for i, (pid, x, y) in enumerate(r.get("props", []), 1):
        text += f'[node name="Prop{i}" parent="Props" instance=ExtResource("7_prop")]\nposition = Vector2({x}, {y})\nprop_id = "{pid}"\n\n'
    for i, (nid, x, y) in enumerate(r.get("npcs", []), 1):
        text += f'[node name="Npc{i}" parent="Props" instance=ExtResource("11_npc")]\nposition = Vector2({x}, {y})\nnpc_id = "{nid}"\n'
        path = r.get("npc_paths", [])
        if path and path[i - 1]:
            points = ", ".join(f"Vector2({dx}, {dy})" for dx, dy in path[i - 1])
            text += f"path_override = [{points}]\n"
        text += "\n"
    for i, (bx, by) in enumerate(r.get("barriers", []), 1):
        text += (f'[node name="Barrier{i}" type="Sprite2D" parent="."]\nposition = Vector2({bx}, {by})\n'
                 'texture = ExtResource("11_barrier")\nhframes = 7\ncentered = false\noffset = Vector2(-32, -80)\n'
                 'modulate = Color(0.85, 0.9, 1, 0.85)\nz_index = 2\n'
                 'script = ExtResource("10_fixture")\nloop = true\nfalls = true\nfps = 10.0\n\n')
    if r.get("shrine"):
        sx, sy = r["shrine"]
        text += (f'[node name="Shrine" type="Sprite2D" parent="."]\nposition = Vector2({sx}, {sy})\n'
                 'texture = ExtResource("9_shrine")\nhframes = 7\ncentered = false\noffset = Vector2(-24, -64)\n'
                 'script = ExtResource("10_fixture")\nlights = true\n\n')
    for i, (hx, hy, hw, hh) in enumerate(r.get("hazards", []), 1):
        text += (f'[node name="Hazard{i}" type="Area2D" parent="."]\nposition = Vector2({hx}, {hy})\n'
                 f'script = ExtResource("15_hazard")\nsize = Vector2({hw}, {hh})\n\n')
    if r.get("bell"):
        bx, by = r["bell"]
        text += f'[node name="Bell" type="Node2D" parent="."]\nposition = Vector2({bx}, {by})\nscript = ExtResource("14_bell")\n\n'
    text += '[node name="Spawns" type="Node2D" parent="."]\n\n'
    for i, (eid, x, y) in enumerate(r["spawns"], 1):
        text += f'[node name="Spawn{i}" type="Marker2D" parent="Spawns"]\nposition = Vector2({x}, {y})\nscript = ExtResource("5_spawn")\nenemy_id = "{eid}"\n\n'
    px, py = r["player"]
    dx, dy = r["door"]
    motes = MOTES.format(cx=width / 2, cy=height / 2, ex=width / 2, ey=height / 2, amount=int(36 * area))
    room_lights = r.get("lights", [])
    if room_lights == "auto":  # the candles the tracer found on the panel
        with open(os.path.join(ROOT, "assets", "levels", r["painting"] + ".lights.json")) as f:
            room_lights = [tuple(light) for light in json.load(f)]
        inserts = r.get("_x_inserts", [])
        room_lights = [(_map_x(x, inserts), y, tint, radius, energy, flicker)
                       for x, y, tint, radius, energy, flicker in room_lights]
    lights = light_nodes(thin_lights(room_lights), "Lights", "Light")
    text += f'''[node name="PlayerSpawn" type="Marker2D" parent="."]
position = Vector2({px}, {py})

[node name="Door" type="Area2D" parent="."]
position = Vector2({dx}, {dy})
collision_layer = 0
collision_mask = 2
script = ExtResource("4_door")
{"painted_arch = true" if painted else ""}

[node name="Shape" type="CollisionShape2D" parent="Door"]
shape = SubResource("door_shape")

[node name="Gate" type="Sprite2D" parent="Door"]
texture = ExtResource("8_gate")
hframes = 5

[node name="Glow" type="Sprite2D" parent="Door"]
visible = false
material = SubResource("add_mat")
scale = Vector2(1.6, 1.6)
texture = SubResource("glow_tex")

{weather}
{motes}[node name="Lights" type="Node2D" parent="."]

{lights}'''
    if r.get("hell_cornice_art"):
        text = text.replace('[ext_resource type="Script" path="res://scripts/rooms/room.gd" id="1_room"]',
                            '[ext_resource type="Script" path="res://scripts/rooms/room.gd" id="1_room"]\n'
                            '[ext_resource type="Script" path="res://scripts/rooms/hell_cornice.gd" id="hell_cornice"]')
    if r.get("hanging_supports"):
        text = text.replace('[ext_resource type="Script" path="res://scripts/rooms/room.gd" id="1_room"]',
                            '[ext_resource type="Script" path="res://scripts/rooms/room.gd" id="1_room"]\n'
                            '[ext_resource type="Script" path="res://scripts/rooms/hanging_support.gd" id="hanging_support"]')
    if r.get("crumbling_platforms"):
        text = text.replace('[ext_resource type="Script" path="res://scripts/rooms/room.gd" id="1_room"]',
                            '[ext_resource type="Script" path="res://scripts/rooms/room.gd" id="1_room"]\n'
                            '[ext_resource type="Script" path="res://scripts/rooms/crumbling_platform.gd" id="crumbling_platform"]')
    text = text.replace("load_steps=0", "load_steps=%d" % (text.count("[ext_resource") + text.count("[sub_resource")))
    path = os.path.join(ROOT, "scenes", "rooms", f"{name}.tscn")
    with open(path, "w") as f:
        f.write(text.rstrip() + "\n")
    print("wrote", os.path.relpath(path, ROOT))


ROOMS.update({name: expand_painted_room(name, room) if name in ROOM_EXPANSION_CUTS else deepcopy(room)
              for name, room in PAINTED.items()})

# What the art studio adds (tools/studio, its robot regenerates on its pull
# requests): spawns of its enemies, in the finished room's own pixels (after
# the painted widening, like a "wide" entry), and which cutscene a room plays.
# The spawns go through check_reach like every other walker.
STUDIO_ROOMS = os.path.join(ROOT, "tools", "rooms", "studio_rooms.json")
if os.path.exists(STUDIO_ROOMS):
    with open(STUDIO_ROOMS) as _f:
        for _name, _extra in json.load(_f).items():
            if _name not in ROOMS:
                raise SystemExit(f"tools/rooms/studio_rooms.json names no room: {_name}")
            ROOMS[_name]["spawns"] = list(ROOMS[_name].get("spawns", [])) + [tuple(s) for s in _extra.get("spawns", [])]
            for _key in ("intro_cutscene", "outro_cutscene"):
                if _key in _extra:
                    ROOMS[_name][_key] = _extra[_key]

if __name__ == "__main__":
    selected = set(sys.argv[1:])
    unknown = selected - ROOMS.keys()
    if unknown:
        raise SystemExit("unknown rooms: " + ", ".join(sorted(unknown)))
    failed = []
    for name, room in ROOMS.items():
        if selected and name not in selected:
            continue
        if "painting" in room:
            _validate_depth_windows(name)
            if not check_reach(name, room):
                failed.append(name)
            _expand_panel(room["painting"], room["_x_inserts"], FOCAL_RANGES.get(name, ()), _painted_floors(room))
            _expand_panel("depth/" + room["painting"] + "_backfill", room["_x_inserts"], FOCAL_RANGES.get(name, ()))
        build(name, room)
    if failed:
        raise SystemExit("unreachable mandatory route in: " + ", ".join(failed))
