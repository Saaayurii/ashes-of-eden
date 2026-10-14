#!/usr/bin/env python3
"""Elian holding each weapon (docs/WEAPONS.md), drawn from his own frames.

The sword in Elian's strips is a thin grey line two pixels wide. For every
frame that shows it, this finds the line (its grip, where it leaves the hand,
and its tip), lifts it off the body, and rasterises the weapon in its place
along the same line, one pixel to a pixel:

- spear     a long ash shaft through the hands, a leaf-shaped steel head
            ahead and an iron heel behind;
- headsman  the executioner's sword: a broad, square-ended blade a little
            longer than the sword's, a long two-hand grip and a bar guard;
- daggers   two knives: a short blade forward along the old one, and a
            second held point-down in the other hand on the grip.

The white arc a swing has drawn in is cut out with the blade and laid back
scaled about the grip to the weapon's reach (wider for the headsman, a short
hook for the knives). The body itself is never redrawn, so it cannot double.
Strips that show no sword (idle, walking, the jump) are the hero's own.

A detected line can be put right by hand in LINES (strip, frame) -> (grip, tip)
in cell pixels, or None for a frame whose sword is out of sight. --debug writes
tools/art/contact/weapon_lines.png with every line found; --contact writes
tools/art/contact/weapons.png, every weapon's strips beside the sword's.

Deterministic; 128x64 cells, feet where they are. Run
tools/art/build_elian_frames.py afterwards (check_generators runs both).

    python3 tools/art/make_weapon_frames.py [--debug] [--contact]
"""
import math
import os
import sys

import numpy as np
from PIL import Image
from studio_overrides import patched  # the art studio's edits of what this writes (tools/studio/overrides)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SPRITES = os.path.join(ROOT, "assets", "sprites")
CONTACT = os.path.join(ROOT, "tools", "art", "contact")
CELL = (128, 64)

## The hero's strips that show the sword: the chain, the thrust, the swing in
## the air and out of the roll, drawing it, the guard's frames, and the falls
## that keep it in hand. The special moves are drawn from these by
## make_elian_moves.py, once per weapon.
STRIPS = ["elian_slash", "elian_overhead", "elian_slam", "elian_thrust", "elian_rising",
          "elian_dash_strike", "elian_draw", "elian_attack", "elian_hurt", "elian_knockback", "elian_land"]
WEAPONS = ["spear", "headsman", "daggers"]

## Corrections to the detector, in cell pixels: (strip, frame) -> ((grip x, y),
## (tip x, y)), or None where no blade is drawn.
LINES = {
    ("elian_slash", 2): ((79, 39), (96, 36)),
    ("elian_slash", 3): ((77, 40), (90, 37)),
    ("elian_slash", 4): ((82, 43), (94, 41)),
    ("elian_slash", 5): ((75, 41), (86, 38)),
    ("elian_overhead", 2): ((78, 32), (88, 21)),
    ("elian_overhead", 3): ((73, 30), (63, 14)),
    ("elian_overhead", 4): ((73, 30), (64, 16)),
    ("elian_overhead", 5): ((71, 32), (79, 9)),
    ("elian_slam", 1): ((70, 24), (90, 34)),
    ("elian_slam", 2): None,        # a smear: the blade is the arc
    ("elian_slam", 3): ((71, 45), (79, 57)),
    ("elian_thrust", 0): None,      # drawn back behind the shoulders
    ("elian_thrust", 3): None,
    ("elian_rising", 2): ((87, 50), (100, 51)),
    ("elian_dash_strike", 0): None,  # out of sight under the roll
    ("elian_dash_strike", 1): None,
    ("elian_dash_strike", 2): ((70, 51), (82, 51)),
    ("elian_dash_strike", 3): None,
    ("elian_dash_strike", 4): None,
    ("elian_draw", 0): None,        # still in the scabbard
    ("elian_draw", 1): None,
    ("elian_draw", 2): None,
    ("elian_draw", 5): ((70, 39), (86, 26)),
    ("elian_attack", 3): ((83, 45), (96, 41)),
}
## Further steel to lift off a frame that is not the blade in hand: the far
## half of a sword held across the head, a second blade a frame drew twice.
ERASE = {
    ("elian_slam", 1): [((68, 23), (56, 19))],
    ("elian_attack", 4): [((75, 30), (94, 34))],
}


def frames(name):
    strip = Image.open(os.path.join(SPRITES, name + ".png")).convert("RGBA")
    return [strip.crop((i * CELL[0], 0, (i + 1) * CELL[0], CELL[1])) for i in range(strip.width // CELL[0])]


def save(name, sequence):
    out = Image.new("RGBA", (CELL[0] * len(sequence), CELL[1]), (0, 0, 0, 0))
    for i, frame in enumerate(sequence):
        out.alpha_composite(frame, (i * CELL[0], 0))
    path = os.path.join(SPRITES, name + ".png")
    patched(path, out).save(path, optimize=True)
    print(os.path.relpath(path, ROOT), "%d frames" % len(sequence))


# --- finding the sword -------------------------------------------------------

def shifted(m, dy, dx):
    """m moved by (dy, dx), zeros brought in at the edges."""
    out = np.zeros_like(m)
    h, w = m.shape
    out[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = m[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
    return out


def erode(m, offsets):
    """Set where every offset of the pixel is set (outside the cell is not)."""
    out = np.ones_like(m, bool)
    for dy, dx in offsets:
        out &= shifted(m, -dy, -dx).astype(bool)
    return out


def dilate(m, offsets):
    out = np.zeros_like(m, bool)
    for dy, dx in offsets:
        out |= shifted(m, dy, dx).astype(bool)
    return out


def neighbours(m, kernel):
    """How many of the kernel's cells around each pixel are set (a 3×3 kernel)."""
    out = np.zeros(m.shape, int)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if kernel[dy + 1][dx + 1]:
                out += shifted(m.astype(int), -dy, -dx)
    return out


SQUARE = [(dy, dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1)]
PAIR = [(dy, dx) for dy in (-1, 0) for dx in (-1, 0)]
CROSS = [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)]


def label(m):
    """Eight-connected patches of m, numbered from 1 (0 is background)."""
    labels = np.zeros(m.shape, int)
    h, w = m.shape
    count = 0
    for y, x in zip(*np.nonzero(m)):
        if labels[y, x]:
            continue
        count += 1
        labels[y, x] = count
        todo = [(y, x)]
        while todo:
            cy, cx = todo.pop()
            for dy, dx in SQUARE:
                ny, nx = cy + dy, cx + dx
                if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and not labels[ny, nx]:
                    labels[ny, nx] = count
                    todo.append((ny, nx))
    return labels


def steel(a):
    """Pale, colourless pixels: the blade, the arc, a highlight on the armour."""
    rgb = a[..., :3].astype(int)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    return (a[..., 3] > 0) & (sat < 38) & (rgb.mean(axis=2) > 92)


def arc_mask(a):
    """The drawn-in swing: every patch of steel joined to a core thick enough
    to survive an erosion (a blade is two pixels wide and never does)."""
    s = steel(a)
    core = erode(s & (a[..., :3].mean(axis=2) > 150), SQUARE)
    core = dilate(erode(core, PAIR), PAIR)
    if not core.any():
        return np.zeros_like(s)
    labels = label(s)
    ids = np.unique(labels[core & (labels > 0)])
    arc = np.isin(labels, ids)
    # its soft grey rim, a pixel out
    rgb = a[..., :3].astype(int)
    rim = (a[..., 3] > 0) & ((rgb.max(axis=2) - rgb.min(axis=2)) < 50) & (rgb.mean(axis=2) > 70)
    return arc | (dilate(arc, CROSS) & rim)


def find_line(a):
    """The longest straight run of steel, two pixels wide at most, with one end
    on the body: ((grip x, y), (tip x, y)) or None."""
    cand = steel(a) & ~arc_mask(a)
    ys, xs = np.nonzero(cand)
    if xs.size < 8:
        return None
    pts = np.stack([xs, ys], axis=1).astype(float)
    body = (a[..., 3] > 0) & ~steel(a)
    rng = np.random.default_rng(7)
    best, best_score = None, 0
    n = len(pts)
    pairs = [(i, j) for i in range(n) for j in range(i + 1, n)] if n < 90 else \
        [tuple(rng.choice(n, 2, replace=False)) for _ in range(4000)]
    for i, j in pairs:
        p, q = pts[i], pts[j]
        d = q - p
        length = math.hypot(*d)
        if length < 6:
            continue
        d /= length
        nrm = np.array([-d[1], d[0]])
        rel = pts - p
        u = rel @ d
        v = rel @ nrm
        on = np.abs(v) <= 1.1
        us = np.sort(u[on])
        if us.size < 6:
            continue
        # the longest run along the line with gaps of at most two pixels
        runs, start = [], 0
        for k in range(1, us.size + 1):
            if k == us.size or us[k] - us[k - 1] > 2.5:
                runs.append((us[start], us[k - 1], k - start))
                start = k
        lo, hi, count = max(runs, key=lambda r: r[2])
        span = hi - lo
        if span < 9 or count < span * 0.9:
            continue
        score = count
        if score > best_score:
            best_score, best = score, (p + d * lo, p + d * hi)
    if best is None:
        return None
    e0, e1 = best

    def touching(e):
        x, y = int(round(e[0])), int(round(e[1]))
        return body[max(0, y - 2):y + 3, max(0, x - 2):x + 3].sum()
    grip, tip = (e0, e1) if touching(e0) >= touching(e1) else (e1, e0)
    return (tuple(np.round(grip, 1)), tuple(np.round(tip, 1)))


def line_of(strip, index, a):
    if (strip, index) in LINES:
        return LINES[(strip, index)]
    return find_line(a)


# --- lifting it off ----------------------------------------------------------

def along(g, t):
    """Every pixel's (u along, v across) the segment g -> t, and its length."""
    g, t = np.array(g, float), np.array(t, float)
    d = t - g
    length = max(math.hypot(*d), 1e-6)
    d /= length
    yy, xx = np.mgrid[0:CELL[1], 0:CELL[0]]
    rel = np.stack([xx - g[0], yy - g[1]], axis=-1)
    return rel @ d, rel @ np.array([-d[1], d[0]]), length


def lift(a, line, extra=()):
    """The frame without the blade on [param line] (and the steel on each of
    [param extra]) and without the arc; the arc is returned on its own layer.
    Holes where the blade crossed the body are filled from their neighbours."""
    a = a.copy()
    arc = arc_mask(a)
    arc_layer = np.zeros_like(a)
    arc_layer[arc] = a[arc]
    a[arc] = 0
    if line is not None:
        u, v, length = along(*line)
        arc_layer[(np.abs(v) <= 1.6) & (u >= -1) & (u <= length + 1)] = 0
    rgb = a[..., :3].astype(int)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    grey = (sat < 44) & (rgb.mean(axis=2) > 62) & (a[..., 3] > 0)
    for g, t in extra:
        u, v, length = along(g, t)
        a[grey & (np.abs(v) <= 1.6) & (u >= -1) & (u <= length + 1)] = 0
    if line is not None:
        u, v, length = along(*line)
        near = (np.abs(v) <= 1.6) & (u >= -1) & (u <= length + 1.5)
        a[near & grey & (u > 1.5)] = 0
        # strays left along the line: a pixel with almost no neighbours
        alpha = a[..., 3] > 0
        neigh = neighbours(alpha, np.ones((3, 3))) - alpha
        strays = alpha & (neigh <= 1) & (np.abs(v) <= 2.6) & (u > 1.5) & (u <= length + 2.5)
        a[strays] = 0
    # fill pin-holes inside the body (the blade crossed it)
    for _ in range(2):
        alpha = a[..., 3] > 0
        cross = np.array([[0, 1, 0], [1, 0, 1], [0, 1, 0]])
        count = neighbours(alpha, cross)
        holes = ~alpha & (count >= 3)
        if not holes.any():
            break
        acc = np.zeros(a.shape, float)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            shifted = np.roll(np.roll(a, dy, axis=0), dx, axis=1).astype(float)
            acc += shifted * (np.roll(np.roll(alpha, dy, axis=0), dx, axis=1)[..., None])
        fill = (acc / np.maximum(count, 1)[..., None]).astype(np.uint8)
        fill[..., 3] = 255
        a[holes] = fill[holes]
    return a, arc_layer


# --- the weapons -------------------------------------------------------------

WOOD = (92, 62, 38)
WOOD_LIGHT = (138, 98, 60)
WOOD_DARK = (58, 38, 24)
STEEL = (196, 202, 210)
STEEL_LIGHT = (236, 240, 244)
STEEL_DARK = (104, 110, 122)
IRON = (70, 72, 80)
IRON_LIGHT = (122, 124, 132)
LEATHER = (74, 46, 32)
BRASS = (168, 128, 64)


def spear(u, v, s):
    """Shaft from the heel behind the hands to the socket, then the head."""
    head0, head1 = s["reach"] - 9, s["reach"]
    if -s["back"] <= u < -s["back"] + 2 and abs(v) <= 1.0:
        return IRON_LIGHT if v < 0 else IRON
    if -s["back"] + 2 <= u < head0 - 1.5:
        if -0.75 <= v < 0.25:
            return WOOD_LIGHT
        if 0.25 <= v < 1.1:
            return WOOD_DARK
        return None
    if head0 - 1.5 <= u < head0 + 0.5 and abs(v) <= 1.1:
        return IRON
    if head0 + 0.5 <= u <= head1:
        t = (u - head0) / (head1 - head0)
        half = 2.2 * math.sin(math.pi * min(1.0, t * 1.35) ** 0.8) if t < 0.74 else 2.2 * (1 - t) / 0.26 * 0.62
        half = max(half, 0.45)
        if abs(v) <= half:
            if v < -half + 0.9:
                return STEEL_LIGHT
            if v > half - 0.9:
                return STEEL_DARK
            return STEEL
    return None


def headsman(u, v, s):
    """A long grip with a round pommel, a bar guard, a broad square blade."""
    reach = s["reach"]
    if -7.5 <= u < -6 and abs(v) <= 1.3:
        return BRASS
    if -6 <= u < 1.5 and abs(v) <= 0.8:
        return LEATHER if int(u) % 3 else WOOD_DARK
    if 1.5 <= u < 3 and abs(v) <= 4.2:
        return IRON_LIGHT if u < 2.25 else IRON
    if 3 <= u <= reach:
        # broad and straight, the end cut square with its corners eased
        top, bottom = -2.4, 2.4
        if u > reach - 1.5:
            top, bottom = -1.6, 1.6
        if top <= v <= bottom:
            if v < top + 1.0:
                return STEEL_LIGHT      # the edge
            if v > bottom - 1.0:
                return STEEL_DARK       # the spine
            if 5 <= u <= reach - 5 and abs(v - 0.2) < 0.45:
                return STEEL_DARK       # the fuller
            return STEEL
    return None


def knife(u, v, s):
    reach = s["reach"]
    if -3 <= u < 0.5 and abs(v) <= 0.7:
        return LEATHER
    if 0.5 <= u < 1.8 and abs(v) <= 2.0:
        return IRON_LIGHT
    if 1.8 <= u <= reach:
        half = 1.15 * min(1.0, (reach - u) / 3.5) + 0.2
        if abs(v) <= half:
            return STEEL_LIGHT if v < 0 else STEEL
    return None


SHAPES = {"spear": spear, "headsman": headsman, "daggers": knife}
## How far the weapon reaches past the grip, as a share of the sword's blade,
## and how much the drawn-in swing grows (about the grip) to match it.
REACH = {"spear": 1.75, "headsman": 1.2, "daggers": 0.48}
ARC_SCALE = {"spear": 1.15, "headsman": 1.22, "daggers": 0.6}


def raster(layer, shape, grip, d, spec, under=None):
    """Draws [param shape] into [param layer] (H×W×4) at [param grip] facing
    [param d]: each pixel's centre in the weapon's own (u along, v across)
    decides its colour, so every angle is clean 1:1 pixels. Pixels with u <
    [param under] go only where the body is not (the grip stays in the hand)."""
    nrm = np.array([-d[1], d[0]])
    if nrm[1] > 0:
        nrm = -nrm  # v < 0 is the side toward the sky: the lit edge
    span = spec.get("reach", 20) + spec.get("back", 8) + 6
    x0, x1 = int(grip[0] - span), int(grip[0] + span) + 1
    y0, y1 = int(grip[1] - span), int(grip[1] + span) + 1
    for y in range(max(0, y0), min(CELL[1], y1)):
        for x in range(max(0, x0), min(CELL[0], x1)):
            rel = np.array([x + 0.5 - grip[0], y + 0.5 - grip[1]])
            u, v = float(rel @ d), float(rel @ nrm)
            colour = shape(u, v, spec)
            if colour is None:
                continue
            if under is not None and u < under and layer[y, x, 3] > 0:
                continue
            layer[y, x, :3] = colour
            layer[y, x, 3] = 255


def scaled_arc(arc_layer, grip, k):
    """The swing's drawn arc, scaled about the grip by [param k] (nearest)."""
    out = np.zeros_like(arc_layer)
    if not arc_layer[..., 3].any():
        return out
    yy, xx = np.mgrid[0:CELL[1], 0:CELL[0]]
    sx = np.round(grip[0] + (xx + 0.5 - grip[0]) / k - 0.5).astype(int)
    sy = np.round(grip[1] + (yy + 0.5 - grip[1]) / k - 0.5).astype(int)
    ok = (sx >= 0) & (sx < CELL[0]) & (sy >= 0) & (sy < CELL[1])
    out[ok] = arc_layer[sy[ok], sx[ok]]
    return out


def armed(frame, line, weapon, extra=()):
    a = np.asarray(frame).copy()
    if line is None:
        return frame
    body, arc = lift(a, line, extra)
    (gx, gy), (tx, ty) = line
    grip = np.array([gx, gy], float)
    d = np.array([tx, ty], float) - grip
    blade = math.hypot(*d)
    d /= blade
    reach = blade * REACH[weapon]
    out = body.copy()
    if weapon == "spear":
        # room ahead inside the cell: the head stops a pixel short of the edge
        room = min([(CELL[0] - 2 - gx) / d[0] if d[0] > 1e-3 else 1e9,
                    (gx - 1) / -d[0] if d[0] < -1e-3 else 1e9,
                    (CELL[1] - 2 - gy) / d[1] if d[1] > 1e-3 else 1e9,
                    (gy - 1) / -d[1] if d[1] < -1e-3 else 1e9])
        reach = max(min(reach, room), blade * 1.1)
        raster(out, spear, grip, d, {"reach": reach, "back": 15}, under=2.5)
    elif weapon == "headsman":
        raster(out, headsman, grip, d, {"reach": reach}, under=1.5)
    else:
        raster(out, knife, grip, d, {"reach": max(reach, 9)}, under=0.5)
        # the other hand on the grip, its knife held point down and back
        back = -d
        turn = math.radians(-40 if d[0] >= 0 else 40)
        d2 = np.array([back[0] * math.cos(turn) - back[1] * math.sin(turn),
                       back[0] * math.sin(turn) + back[1] * math.cos(turn)])
        if d2[1] < 0:
            d2 = np.array([d2[0], -d2[1]])  # point toward the ground, never the sky
        raster(out, knife, grip - d * 3, d2, {"reach": 8}, under=0.5)
    sweep = scaled_arc(arc, grip, ARC_SCALE[weapon])
    img = Image.fromarray(out, "RGBA")
    img.alpha_composite(Image.fromarray(sweep, "RGBA"))
    return img


def lines_of(strip):
    result = []
    for i, frame in enumerate(frames(strip)):
        result.append(line_of(strip, i, np.asarray(frame)))
    return result


def debug():
    rows = []
    for strip in STRIPS:
        fr = frames(strip)
        row = Image.new("RGBA", (CELL[0] * 8, CELL[1]), (52, 54, 64, 255))
        for i, frame in enumerate(fr):
            a = np.asarray(frame)
            line = line_of(strip, i, a)
            img = frame.copy()
            px = img.load()
            if line is not None:
                (gx, gy), (tx, ty) = line
                for k in range(41):
                    t = k / 40
                    x, y = int(gx + (tx - gx) * t), int(gy + (ty - gy) * t)
                    if 0 <= x < CELL[0] and 0 <= y < CELL[1]:
                        px[x, y] = (0, 255, 0, 255)
                px[int(gx), int(gy)] = (255, 0, 255, 255)
            arc = arc_mask(a)
            for y, x in zip(*np.nonzero(arc)):
                px[int(x), int(y)] = (0, 160, 255, 255)
            row.alpha_composite(img, (i * CELL[0], 0))
            print(strip, i, line)
        rows.append(row)
    sheet(rows, "weapon_lines.png", 3)


def sheet(rows, name, zoom):
    out = Image.new("RGBA", (max(r.width for r in rows), CELL[1] * len(rows)), (52, 54, 64, 255))
    for i, row in enumerate(rows):
        out.alpha_composite(row, (0, i * CELL[1]))
    os.makedirs(CONTACT, exist_ok=True)
    out.resize((out.width * zoom, out.height * zoom), Image.NEAREST).save(os.path.join(CONTACT, name))
    print("wrote", os.path.relpath(os.path.join(CONTACT, name), ROOT))


def strip_name(weapon, strip):
    return "elian_%s_%s" % (weapon, strip[len("elian_"):])


def main():
    found = {strip: lines_of(strip) for strip in STRIPS}
    for weapon in WEAPONS:
        for strip in STRIPS:
            save(strip_name(weapon, strip), [armed(f, found[strip][i], weapon, ERASE.get((strip, i), ()))
                                             for i, f in enumerate(frames(strip))])


def contact():
    rows = []
    for strip in STRIPS:
        for weapon in [None] + WEAPONS:
            name = strip if weapon is None else strip_name(weapon, strip)
            row = Image.new("RGBA", (CELL[0] * 8, CELL[1]), (52, 54, 64, 255))
            for i, f in enumerate(frames(name)):
                row.alpha_composite(f, (i * CELL[0], 0))
            rows.append(row)
    sheet(rows, "weapons.png", 2)


if __name__ == "__main__":
    if "--debug" in sys.argv:
        debug()
    else:
        main()
        if "--contact" in sys.argv:
            contact()
