#!/usr/bin/env python3
"""The living liquids' pixels (data/liquids.json, scripts/rooms/hazard.gd).

Four body textures, 64x64 and seamless on both axes, that the engine scrolls
and tints under a pool's surface — water's caustic bands, lava's crust plates
split by glowing cracks, the bog's murk with weed and flecks, blood's clots
and streaks — and the strips that play on and around a pool: splashes, a
ripple, bubbles and pops, steam, a drip, a glint. Drawn here pixel by pixel:
1:1, hard alpha, no anti-aliasing, every colour from a small ramp of the
kind's own colours in data/liquids.json. The white strips are white and grey
on purpose: the engine modulates them by the kind's tint. Lava's own strips
(lava_splash, lava_pop) and the bog's gas_pop carry their colours.

    python3 tools/art/make_liquids.py

Writes assets/fx/liquids/*.png, assets/fx/liquids/manifest.json and a contact
sheet (x4, labelled) at tools/art/contact/liquids.png. Deterministic: every
random choice comes from a Random seeded by the picture's name.
"""
import json, math, os, random, zlib

from PIL import Image, ImageDraw
from studio_overrides import patched  # the art studio's edits of what this writes (tools/studio/overrides)

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "fx", "liquids")
CONTACT = os.path.join(ROOT, "tools", "art", "contact", "liquids.png")
LIQUIDS = os.path.join(ROOT, "data", "liquids.json")

CLEAR = (0, 0, 0, 0)


def rng(name):
    return random.Random(zlib.crc32(name.encode()))


def hexc(s, a=255):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3)) + (255,)


def colours():
    with open(LIQUIDS, encoding="utf-8") as f:
        kinds = json.load(f)["kinds"]
    return {k: {n: hexc(c) for n, c in v["colors"].items()} for k, v in kinds.items()}


# ---------------------------------------------------------------- periodic noise

class Lattice:
    """Value noise on a lattice that wraps every `period` pixels of a 64 tile."""

    def __init__(self, r, cells):
        self.n = cells
        self.v = [[r.random() for _ in range(cells)] for _ in range(cells)]

    def at(self, x, y, size=64):
        fx, fy = x / size * self.n, y / size * self.n
        x0, y0 = int(math.floor(fx)), int(math.floor(fy))
        tx, ty = fx - x0, fy - y0
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        n = self.n
        a = self.v[y0 % n][x0 % n]
        b = self.v[y0 % n][(x0 + 1) % n]
        c = self.v[(y0 + 1) % n][x0 % n]
        d = self.v[(y0 + 1) % n][(x0 + 1) % n]
        return (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * ty


def fbm(r, octaves):
    lats = [Lattice(r, c) for c in octaves]

    def f(x, y):
        s, w, tot = 0.0, 1.0, 0.0
        for lat in lats:
            s += lat.at(x, y) * w
            tot += w
            w *= 0.55
        return s / tot
    return f


def wrapd(a, b, size=64):
    d = abs(a - b) % size
    return min(d, size - d)


def ramp(stops, steps):
    """`steps` colours spread across the gradient through `stops`."""
    out = []
    for i in range(steps):
        t = i / (steps - 1) * (len(stops) - 1)
        j = min(int(t), len(stops) - 2)
        out.append(mix(stops[j], stops[j + 1], t - j))
    return out


def pick(pal, v):
    return pal[max(0, min(len(pal) - 1, int(v * len(pal))))]


# ---------------------------------------------------------------- bodies (64x64, tile both ways)

S = 64


def body_water(c):
    r = rng("body_water")
    n1, n2, warp = fbm(r, (4, 8)), fbm(r, (4, 8)), fbm(r, (2, 4))
    pal = ramp([c["deep"], c["body"], mix(c["body"], c["glow"], 0.45), c["glow"]], 5)
    img = Image.new("RGBA", (S, S))
    for y in range(S):
        for x in range(S):
            w = warp(x, y)
            # two sheets of noise; where they cross the light gathers (caustics)
            a = n1(x + w * 9, y) - n2(x, y + w * 9)
            caustic = max(0.0, 1.0 - abs(a) * 15.0)
            # long soft bands that run with the flow
            band = 0.5 + 0.5 * math.sin((y / S) * 2 * math.pi * 3 + w * 4.0)
            v = 0.34 + band * 0.12 + caustic * 0.36
            img.putpixel((x, y), pick(pal, v))
    return img


def voronoi_points(r, n):
    return [(r.random() * S, r.random() * S) for _ in range(n)]


def body_lava(c):
    r = rng("body_lava")
    pts = voronoi_points(r, 11)
    shade = [r.random() for _ in pts]
    grain = fbm(r, (8, 16))
    wob = fbm(r, (4, 8))
    crust = ramp([(26, 4, 2, 255), c["deep"], mix(c["deep"], c["body"], 0.35)], 4)
    hot = [c["foam"], c["surface"], c["glow"], c["body"]]
    img = Image.new("RGBA", (S, S))
    for y in range(S):
        for x in range(S):
            wx, wy = x + (wob(x, y) - 0.5) * 8, y + (wob(y, x) - 0.5) * 8
            ds = sorted((math.hypot(wrapd(wx, px), wrapd(wy, py)), i) for i, (px, py) in enumerate(pts))
            edge = ds[1][0] - ds[0][0]
            if edge < 0.55:
                col = hot[0] if grain(x, y) > 0.55 else hot[1]
            elif edge < 1.25:
                col = hot[1] if grain(x, y) > 0.6 else hot[2]
            elif edge < 2.1:
                col = hot[3]
            else:
                # the plate: darker toward its middle, each plate its own shade, a little grain
                inner = min(1.0, (edge - 2.1) / 9.0)
                v = 0.85 - inner * 0.55 + (shade[ds[0][1]] - 0.5) * 0.25 + (grain(x, y) - 0.5) * 0.3
                col = pick(crust, v)
            img.putpixel((x, y), col)
    return img


def wrap_put(img, x, y, col):
    img.putpixel((x % S, y % S), col)


def body_bog(c):
    r = rng("body_bog")
    murk, fine = fbm(r, (2, 4, 8)), fbm(r, (16,))
    pal = ramp([c["deep"], c["body"], mix(c["body"], c["surface"], 0.55)], 5)
    img = Image.new("RGBA", (S, S))
    for y in range(S):
        for x in range(S):
            v = murk(x, y) * 0.9 + (fine(x, y) - 0.5) * 0.25
            img.putpixel((x, y), pick(pal, v - 0.08))
    weed = mix(c["body"], c["foam"], 0.3)
    weed_dark = mix(c["deep"], c["body"], 0.6)
    for _ in range(7):  # strands of weed hanging in the murk
        x, y = r.randrange(S), r.randrange(S)
        length = r.randint(6, 12)
        for i in range(length):
            wrap_put(img, x + int(round(math.sin(i * 0.7 + x) * 1.2)), y + i, weed if i % 3 else weed_dark)
    fleck = mix(c["surface"], c["foam"], 0.4)
    for _ in range(26):  # flecks of leaf and silt
        wrap_put(img, r.randrange(S), r.randrange(S), fleck if r.random() < 0.5 else pal[0])
    ring = c["foam"]
    for _ in range(5):  # tiny bubbles caught in the mud
        x, y = r.randrange(S), r.randrange(S)
        for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
            wrap_put(img, x + dx, y + dy, ring)
        wrap_put(img, x, y, pal[1])
        wrap_put(img, x - 1, y - 1, (255, 255, 230, 255))
    return img


def body_blood(c):
    r = rng("body_blood")
    base, clot = fbm(r, (2, 4, 8)), fbm(r, (4, 8))
    streak = Lattice(r, 4), Lattice(r, 16)
    pal = ramp([c["deep"], c["body"], mix(c["body"], c["glow"], 0.55)], 5)
    img = Image.new("RGBA", (S, S))
    for y in range(S):
        for x in range(S):
            v = base(x, y) * 0.8 + 0.1
            # streaks: noise stretched along x, a few lighter runs
            s = streak[0].at(x, y * 4 % S) * 0.6 + streak[1].at(x, y) * 0.4
            if s > 0.68:
                v += 0.28
            cl = clot(x, y)
            if cl > 0.66:
                v = 0.05 if cl > 0.72 else min(v, 0.2)
            img.putpixel((x, y), pick(pal, v))
    gl = mix(c["glow"], c["foam"], 0.4)
    for _ in range(10):  # a glint where a clot's skin catches the light
        x, y = r.randrange(S), r.randrange(S)
        wrap_put(img, x, y, gl)
    return img


# ---------------------------------------------------------------- drawing helpers

def disc(img, cx, cy, rad, col, ox=0):
    """A crisp filled circle (no edge blending) inside the frame at ox."""
    r2 = rad * rad + rad * 0.6
    w, h = FRAME
    for y in range(int(cy - rad - 1), int(cy + rad + 2)):
        for x in range(int(cx - rad - 1), int(cx + rad + 2)):
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r2 and 0 <= x < w and 0 <= y < h:
                img.putpixel((ox + x, y), col)


def put(img, x, y, col, ox=0):
    w, h = FRAME
    x, y = int(round(x)), int(round(y))
    if 0 <= x < w and 0 <= y < h:
        img.putpixel((ox + x, y), col)


def strip(w, h, frames):
    global FRAME
    FRAME = (w, h)
    return Image.new("RGBA", (w * frames, h), CLEAR)


FRAME = (0, 0)
WHITE = (255, 255, 255, 255)
LIGHT = (222, 228, 232, 255)
GREY = (176, 184, 192, 255)
DIM = (128, 136, 146, 255)


def droplets(r, n, speed, spread, size):
    out = []
    for _ in range(n):
        ang = math.radians(90 + r.uniform(-spread, spread))
        v = speed * r.uniform(0.55, 1.0)
        out.append((math.cos(ang) * v * r.choice((-1, 1)) * r.uniform(0.6, 1.2), math.sin(ang) * v,
                    r.uniform(0.6, 1.0) * size, r.uniform(-1.5, 1.5)))
    return out


def splash_strip(name, w, h, col_h, crown_w, n_drops, lava=False, c=None):
    """A crown and column rising from the bottom centre, droplets breaking off."""
    frames = 8
    img = strip(w, h, frames)
    r = rng(name)
    cx, base = w / 2, h - 1
    drops = droplets(r, n_drops, h * 0.11, 55, 1.6 if w > 32 else 1.1)
    g = h * 0.0056
    if lava:
        temps = [c["foam"], c["surface"], c["glow"], c["body"], c["deep"], (34, 6, 3, 255)]
    for f in range(frames):
        ox = f * w
        t = f / (frames - 1)
        rise = math.sin(min(1.0, t * 1.35) * math.pi)       # 0 → 1 → 0, peaks early
        # the column: a narrow tongue up the middle
        ch = col_h * rise * (1.0 if f < 5 else 0.6)
        cw = max(1.0, (w * 0.07) * (1.0 - t * 0.5))
        for y in range(int(base - ch), base + 1):
            k = (base - y) / max(1.0, ch)
            half = cw * (1.0 - k * 0.6)
            for x in range(int(cx - half), int(cx + half) + 1):
                if lava:
                    col = temps[0] if k > 0.55 else temps[1] if x < cx else temps[2]
                else:
                    col = WHITE if x < cx else LIGHT
                put(img, x, y, col, ox)
        if ch > 2:
            disc(img, cx - 0.5, base - ch, cw * 0.8 + 0.6, temps[0] if lava else WHITE, ox)
        # the crown: two walls leaning out from a widening rim, lower as it spreads
        rim = 3 + crown_w * min(1.0, t * 1.6)
        wall = (h * 0.28) * math.sin(min(1.0, t * 1.5) * math.pi) * (1.0 if f < 6 else 0.4)
        for side in (-1, 1):
            for i in range(int(wall) + 1):
                k = i / max(1.0, wall)
                x = cx + side * (rim - 2 + k * 3.0)
                y = base - i
                if lava:
                    col = temps[2 if k < 0.5 else 1] if f < 5 else temps[3 + (f > 6)]
                else:
                    col = LIGHT if k < 0.7 else WHITE
                put(img, x, y, col, ox)
                put(img, x - side, y, GREY if not lava else temps[3], ox)
            if wall > 3 and f < 6:  # the crown's points come off as beads
                put(img, cx + side * (rim + 1.5), base - wall - 1.5, WHITE if not lava else temps[1], ox)
        # the foam rim along the bottom
        for x in range(int(cx - rim), int(cx + rim) + 1):
            if (x + f) % 5 != 0 or f < 6:
                put(img, x, base, (GREY if not lava else temps[4]) if f > 5 else (LIGHT if not lava else temps[2]), ox)
        # droplets on their arcs, from the second frame
        if f >= 1:
            tt = (f - 0.5) * 1.6
            for i, (vx, vy, size, jit) in enumerate(drops):
                x = cx + vx * tt + jit
                y = base - 2 - vy * tt + g * tt * tt * 1.6
                if y > base:
                    continue
                if lava:
                    col = temps[min(len(temps) - 1, 1 + f // 2 + (i % 2))]
                else:
                    col = WHITE if (i + f) % 3 else GREY
                if size >= 1.3 and f < 6:
                    disc(img, x, y, size * (1.0 - t * 0.35), col, ox)
                else:
                    put(img, x, y, col, ox)
                    if lava and f < 5:  # a hot blob trails a darker skin behind it
                        put(img, x - math.copysign(1, vx), y + 1, temps[min(5, 3 + f // 3)], ox)
    return img


def ripple():
    w, h, frames = 32, 8, 6
    img = strip(w, h, frames)
    tones = [WHITE, WHITE, LIGHT, GREY, GREY, DIM]
    for f in range(frames):
        ox = f * w
        rx = 3 + f * 2.5
        ry = max(1.2, min(3.4, rx / 4.2))
        cx, cy = w / 2 - 0.5, h / 2 - 0.5
        steps = int(rx * 8)
        for i in range(steps):
            a = i / steps * 2 * math.pi
            # it breaks up as it fades: whole, then every other run of pixels missing
            if f >= 3 and int(a * (3 + f)) % (6 - f + 2) == 0:
                continue
            x, y = cx + math.cos(a) * rx, cy + math.sin(a) * ry
            put(img, x, y, tones[f] if math.sin(a) > -0.2 else (GREY if f < 4 else DIM), ox)
    return img


def bubble():
    w, h, frames = 8, 8, 5
    img = strip(w, h, frames)
    for f, (cy, rad) in enumerate([(6.0, 1.0), (5.0, 1.5), (3.6, 2.2), (3.0, 2.6), (3.0, 3.2)]):
        ox, cx = f * w, 3.5
        if f < 2:
            disc(img, cx, cy, rad, LIGHT, ox)
            put(img, cx - 0.5, cy - 0.5, WHITE, ox)
            continue
        steps = 20
        for i in range(steps):
            a = i / steps * 2 * math.pi
            if f == 3 and i % 4 == 0:      # the skin thinning
                continue
            if f == 4 and i % 3:           # popped: what is left flies out
                continue
            put(img, cx + math.cos(a) * rad, cy + math.sin(a) * rad, WHITE if f < 4 else LIGHT, ox)
        if f == 2:
            put(img, cx - 1, cy - 1, WHITE, ox)
    return img


def pop(name, c, gas=False):
    w, h, frames = 16, 16, 6
    img = strip(w, h, frames)
    r = rng(name)
    cx, base = 7.5, 15
    if gas:
        skin, hi, dark = c["surface"], c["foam"], c["deep"]
        puff = [c["foam"], c["glow"], c["surface"], mix(c["surface"], c["body"], 0.5)]
    else:
        skin, hi, dark = c["glow"], c["foam"], (34, 6, 3, 255)
        puff = [c["foam"], c["surface"], c["glow"], c["body"]]
    sparks = [(r.uniform(-1, 1) * 3.2, r.uniform(2.0, 3.6)) for _ in range(7)]
    for f in range(frames):
        ox = f * w
        if f < 3:  # the dome swells out of the surface
            rad = 2.5 + f * 1.6
            for y in range(int(base - rad), base + 1):
                for x in range(int(cx - rad - 1), int(cx + rad + 2)):
                    if (x + 0.5 - cx) ** 2 + ((y + 0.5 - base) * 1.15) ** 2 <= rad * rad:
                        edge = (x + 0.5 - cx) ** 2 + ((y + 0.5 - base) * 1.15) ** 2 > (rad - 1.2) ** 2
                        put(img, x, y, (dark if not gas else c["body"]) if edge and y < base - 1 else skin, ox)
            put(img, cx - rad * 0.4, base - rad * 0.7, hi, ox)
            put(img, cx - rad * 0.4 + 1, base - rad * 0.7, hi, ox)
            if not gas and f == 2:
                for x in range(int(cx - 1), int(cx + 2)):
                    put(img, x, base - rad + 1, c["surface"], ox)  # the skin stretched thin and hot
            continue
        k = f - 3
        # a crater ring where it was
        for x in range(int(cx - 5 - k), int(cx + 6 + k)):
            if abs(x - cx) > 2 + k:
                put(img, x, base - (1 if abs(x - cx) < 4 + k else 0), dark if k else skin, ox)
        if gas:
            # a little greenish puff, growing and breaking up
            pr = rng(name + str(f))
            for i in range(6 + k * 2):
                px = cx + pr.uniform(-2.5, 2.5) * (1 + k * 0.5)
                py = base - 5 - k * 2.5 + pr.uniform(-2.0, 2.0) * (1 + k * 0.3)
                if k == 2 and i % 2:
                    continue
                disc(img, px, py, 1.8 - k * 0.4, puff[min(3, (i + k) % 4 if k else i % 2)], ox)
        else:
            # sparks thrown up and falling back, cooling
            for i, (vx, vy) in enumerate(sparks):
                tt = 1.2 + k * 1.3
                x = cx + vx * tt
                y = base - 3 - vy * tt + 0.55 * tt * tt
                col = puff[min(3, k + (i % 2))]
                put(img, x, y, col, ox)
                if k == 0:
                    put(img, x, y + 1, puff[2], ox)
            if k == 0:
                disc(img, cx, base - 2, 2.2, puff[1], ox)
    return img


def steam():
    w, h, frames = 24, 24, 8
    img = strip(w, h, frames)
    r = rng("steam")
    blobs = [(r.uniform(-2, 2), r.uniform(0, 3), r.uniform(2.0, 3.4), r.uniform(0, 6.28)) for _ in range(6)]
    for f in range(frames):
        ox = f * w
        t = f / (frames - 1)
        for i, (bx, by, br, ph) in enumerate(blobs):
            rise = 3 + t * 15 + by
            x = 12 + bx + math.sin(ph + t * 4.0 + i) * (1.0 + t * 3.0)  # the curl
            y = 22 - rise
            rad = br * (0.6 + t * 0.9)
            col = WHITE if t < 0.35 else LIGHT if t < 0.7 else GREY
            # thinning: as it rises the puff is drawn on fewer and fewer pixels
            keep = 1.0 - max(0.0, t - 0.3) * 1.2
            r2 = rad * rad + rad * 0.6
            for yy in range(int(y - rad - 1), int(y + rad + 2)):
                for xx in range(int(x - rad - 1), int(x + rad + 2)):
                    if (xx + 0.5 - x) ** 2 + (yy + 0.5 - y) ** 2 > r2:
                        continue
                    if (zlib.crc32(b"%d,%d,%d" % (xx, yy, f)) % 997) / 997.0 >= keep:
                        continue
                    shade = col if (yy + 0.5 - y) < rad * 0.2 else GREY if col != GREY else DIM
                    put(img, xx, yy, shade, ox)
    return img


def drip():
    w, h, frames = 4, 8, 4
    img = strip(w, h, frames)
    shapes = [
        [(1, 0), (2, 0), (1, 1), (2, 1)],
        [(1, 0), (1, 1), (2, 1), (1, 2), (2, 2), (1, 3)],
        [(1, 1), (1, 2), (1, 3), (2, 3), (1, 4), (2, 4), (1, 5)],
        [(1, 2), (1, 3), (1, 4), (1, 5), (2, 5), (1, 6), (2, 6), (1, 7)],
    ]
    for f, px in enumerate(shapes):
        for i, (x, y) in enumerate(px):
            put(img, x, y, WHITE if x == 1 else LIGHT, f * w)
        put(img, px[-1][0], px[-1][1], GREY, f * w)
    return img


def glint():
    w, h, frames = 8, 3, 4
    img = strip(w, h, frames)
    shapes = [
        {(3, 1): WHITE},
        {(2, 1): LIGHT, (3, 1): WHITE, (4, 1): LIGHT},
        {(0, 1): GREY, (1, 1): LIGHT, (2, 1): WHITE, (3, 1): WHITE, (4, 1): WHITE, (5, 1): LIGHT, (6, 1): GREY,
         (3, 0): LIGHT, (3, 2): LIGHT},
        {(4, 1): LIGHT, (5, 1): GREY},
    ]
    for f, px in enumerate(shapes):
        for (x, y), col in px.items():
            put(img, x, y, col, f * w)
    return img


# ---------------------------------------------------------------- what is written

def build():
    c = colours()
    out = {}  # name -> (image, cell, frames, fps, tint)
    for kind, fn in (("water", body_water), ("lava", body_lava), ("bog", body_bog), ("blood", body_blood)):
        out["body_" + kind] = (fn(c[kind]), (64, 64), 1, 0, False)
    out["splash"] = (splash_strip("splash", 32, 32, 13, 9, 11), (32, 32), 8, 16, True)
    out["splash_big"] = (splash_strip("splash_big", 48, 48, 26, 14, 18), (48, 48), 8, 14, True)
    out["lava_splash"] = (splash_strip("lava_splash", 48, 48, 20, 12, 14, lava=True, c=c["lava"]), (48, 48), 8, 12, False)
    out["ripple"] = (ripple(), (32, 8), 6, 10, True)
    out["bubble"] = (bubble(), (8, 8), 5, 10, True)
    out["lava_pop"] = (pop("lava_pop", c["lava"]), (16, 16), 6, 10, False)
    out["gas_pop"] = (pop("gas_pop", c["bog"], gas=True), (16, 16), 6, 9, False)
    out["steam"] = (steam(), (24, 24), 8, 9, True)
    out["drip"] = (drip(), (4, 8), 4, 12, True)
    out["surface_glint"] = (glint(), (8, 3), 4, 12, True)
    return out


def hard(img):
    """Alpha is 0 or 255, and a clear pixel holds no colour."""
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            p = px[x, y]
            px[x, y] = (p[0], p[1], p[2], 255) if p[3] >= 128 else CLEAR
    return img


def contact(made):
    scale, pad, label = 4, 8, 12
    rows = []
    for name, (img, cell, frames, _fps, tint) in made.items():
        if name.startswith("body_"):
            tile = Image.new("RGBA", (128, 128))
            for y in (0, 64):
                for x in (0, 64):
                    tile.paste(img, (x, y))  # 2x2, so a seam would show
            show = tile
        else:
            show = img
        rows.append((name + ("  (tinted in game)" if tint else "") + "  %dx%d x%d" % (cell[0], cell[1], frames), show))
    width = max(s.width * scale for _, s in rows) + pad * 2
    height = sum(s.height * scale + label + pad for _, s in rows) + pad
    sheet = Image.new("RGBA", (width, height), (24, 22, 28, 255))
    d = ImageDraw.Draw(sheet)
    y = pad
    for text, show in rows:
        d.text((pad, y), text, fill=(220, 210, 190, 255))
        y += label
        big = show.resize((show.width * scale, show.height * scale), Image.NEAREST)
        sheet.alpha_composite(big, (pad, y))
        y += big.height + pad
    return sheet


def main():
    os.makedirs(OUT, exist_ok=True)
    made = build()
    manifest = {}
    for name, (img, cell, frames, fps, tint) in made.items():
        img = hard(img)
        made[name] = (img, cell, frames, fps, tint)
        path = os.path.join(OUT, name + ".png")
        patched(path, img).save(path)
        manifest[name] = {"cell": list(cell), "frames": frames, "fps": fps, "tint": tint}
    with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as f:
        f.write(json.dumps(manifest, indent=2) + "\n")
    os.makedirs(os.path.dirname(CONTACT), exist_ok=True)
    contact(made).save(CONTACT)
    print("wrote %d pictures to %s" % (len(made), os.path.relpath(OUT, ROOT)))


if __name__ == "__main__":
    main()
