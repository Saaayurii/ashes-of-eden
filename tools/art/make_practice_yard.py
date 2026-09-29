#!/usr/bin/env python3
"""The practice yard: a monastery cloister at dusk, where the dead are fought
again for practice (scripts/practice/practice.gd, docs/PRACTICE.md).

Painted in code, in the palette of the other 640x360 backdrops: a dusk sky
with lit cloud edges and a low sun, far hills with a monastery on them, the
cloister's arcade across the middle with the sky through its arches, a bell
gable, the packed earth of the yard. Plus the two things a practice yard has
in it: a straw dummy and a rack of wooden weapons.

Deterministic (fixed seeds, no randomness from the clock):

    python3 tools/art/make_practice_yard.py

writes assets/backgrounds/practice_yard.png and
assets/decor/practice/{dummy,rack}.png.
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
W, H = 640, 360
SUN = (438.0, 176.0)


def value_noise(shape, scale, seed):
    """Smooth noise in [0, 1]: a random lattice, bicubic-ish interpolated."""
    rng = np.random.default_rng(seed)
    gh, gw = int(shape[0] / scale[1]) + 3, int(shape[1] / scale[0]) + 3
    grid = rng.random((gh, gw))
    ys = np.arange(shape[0]) / scale[1]
    xs = np.arange(shape[1]) / scale[0]
    y0, x0 = ys.astype(int), xs.astype(int)
    fy, fx = ys - y0, xs - x0
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
    a = grid[y0][:, x0]
    b = grid[y0][:, x0 + 1]
    c = grid[y0 + 1][:, x0]
    d = grid[y0 + 1][:, x0 + 1]
    top = a + (b - a) * fx[None, :]
    bottom = c + (d - c) * fx[None, :]
    return top + (bottom - top) * fy[:, None]


def fbm(shape, scale, seed, octaves=5):
    total, amp, norm = np.zeros(shape), 1.0, 0.0
    for i in range(octaves):
        total += amp * value_noise(shape, (scale[0] / 2 ** i, scale[1] / 2 ** i), seed + i * 17)
        norm += amp
        amp *= 0.5
    return total / norm


def mix(a, b, t):
    t = np.clip(t, 0.0, 1.0)[..., None]
    return a * (1 - t) + b * t


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def col(*rgb):
    return np.array(rgb, float)


def sky():
    y = np.arange(H)[:, None].repeat(W, 1).astype(float)
    x = np.arange(W)[None, :].repeat(H, 0).astype(float)
    t = y / 230.0
    img = mix(mix(np.broadcast_to(col(22, 24, 36), (H, W, 3)), np.broadcast_to(col(64, 56, 70), (H, W, 3)), smooth(0.0, 0.6, t)),
              np.broadcast_to(col(186, 128, 90), (H, W, 3)), smooth(0.55, 1.0, t))
    d = np.hypot(x - SUN[0], (y - SUN[1]) * 1.4)
    img += col(120, 70, 30) * np.exp(-d / 70.0)[..., None]
    img += col(255, 220, 160) * np.exp(-d / 9.0)[..., None]
    # clouds: long bands, dark bodies with edges lit from the sun below them
    n = fbm((H, W), (220.0, 48.0), 11)
    band = smooth(0.0, 0.25, y / 230.0) * (1.0 - smooth(0.78, 1.0, y / 230.0))
    dens = smooth(0.5, 0.68, n) * band
    lit = np.clip(dens - np.roll(dens, -3, axis=0) * 0.9, 0.0, 1.0) * np.exp(-np.abs(x - SUN[0]) / 240.0)
    img = mix(img, np.broadcast_to(col(48, 42, 54), (H, W, 3)), dens * 0.85)
    img = mix(img, np.broadcast_to(col(236, 166, 112), (H, W, 3)), lit * 1.6)
    # rays: a faint fan up and out of the sun
    ang = np.arctan2(y - SUN[1], x - SUN[0])
    rays = value_noise((1, 720), (6.0, 1.0), 5)[0][((ang + np.pi) / (2 * np.pi) * 700).astype(int)]
    img += col(90, 60, 30) * (smooth(0.55, 0.95, rays) * np.exp(-d / 170.0) * smooth(0.0, 40.0, SUN[1] - y))[..., None] * 0.22
    return img


def hills(img):
    x = np.arange(W)
    ridge_far = 224 + 16 * (fbm((1, W), (160.0, 1.0), 23, 4)[0] - 0.5) * 2
    ridge_near = 246 + 14 * (fbm((1, W), (110.0, 1.0), 29, 4)[0] - 0.5) * 2
    y = np.arange(H)[:, None]
    far = y >= ridge_far[None, :]
    near = y >= ridge_near[None, :]
    img[far] = img[far] * 0.35 + col(96, 82, 96) * 0.65
    img[near] = img[near] * 0.2 + col(62, 54, 66) * 0.8
    # the monastery on the far hill, through the third arch: one bell tower
    # and a roofline, hazy, with a window or two still lit
    haze_ink = col(84, 72, 86)
    base = int(ridge_far[222]) + 3
    for yy in range(base - 24, base):
        img[yy, 219:225] = haze_ink
    for k in range(10):
        half = max(0, (10 - k) * 3 // 10)
        img[base - 24 - k, 222 - half:222 + half + 1] = haze_ink
    for xx in range(205, 244):
        roof = base - 8 - max(0, 5 - abs(xx - 212) // 2) if xx < 219 else base - 7 - max(0, 4 - abs(xx - 234) // 2)
        img[roof:base, xx] = haze_ink
    for wx, wy in [(221, -18), (210, -4), (231, -3)]:
        img[base + wy, wx] = col(255, 196, 120)
    # haze where the land meets the light
    haze = np.exp(-np.abs(y - 240.0) / 14.0)
    img += (col(120, 84, 60) * 0.35) * haze[..., None]
    return img


def cloister(img):
    """The arcade across the middle, open to the sky through its arches."""
    y = np.arange(H)[:, None].repeat(W, 1)
    x = np.arange(W)[None, :].repeat(H, 0)
    top = 172 + (fbm((1, W), (40.0, 1.0), 41, 3)[0] * 10).astype(int)  # broken coping
    # one bay has lost its upper courses
    fall = np.exp(-((np.arange(W) - 330.0) / 26.0) ** 2)
    jag = (value_noise((1, W), (4.0, 1.0), 67)[0] - 0.5) * 12
    top = top + (fall * (22 + jag)).astype(int)
    wall = y >= top[None, :]
    # arches: round-headed openings on a steady rhythm
    opening = np.zeros((H, W), bool)
    for cx in range(40, W + 60, 92):
        half = 30
        spring = 236
        in_x = np.abs(x - cx) <= half
        rect = in_x & (y >= spring) & (y <= 300)
        head = ((x - cx) ** 2 + ((y - spring) * 1.0) ** 2 <= half ** 2) & (y < spring)
        opening |= rect | head
    stone = wall & ~opening & (y < 312)
    # masonry: courses of 9 px, joints staggered, each block its own shade
    course = (y - 172) // 9
    block = (x + (course % 2) * 11) // 22
    rng = np.random.default_rng(7)
    shades = rng.random((80, 60))
    shade = shades[np.clip(course, 0, 79), np.clip(block, 0, 59)]
    joint = ((y - 172) % 9 == 0) | (((x + (course % 2) * 11) % 22) == 0)
    base = col(78, 68, 70)
    weather = fbm((H, W), (70.0, 40.0), 43)
    tone = 0.78 + 0.28 * shade[..., None] - 0.35 * smooth(0.55, 0.8, weather)[..., None]
    lightside = 1.0 + 0.25 * np.exp(-np.abs(x - SUN[0]) / 260.0)[..., None]
    paint = base * tone * lightside
    paint[joint] *= 0.62
    # darker toward the ground, where the damp is
    paint *= (1.05 - 0.35 * smooth(200.0, 312.0, y))[..., None]
    # pilasters between the arches, a string course at the springing line
    for cx in range(40 + 46, W + 60, 92):
        pil = (np.abs(x - cx) <= 5) & (y > 214)
        paint[pil] = paint[pil] * 1.12 + 6
        paint[(np.abs(x - cx) == 5) & (y > 214)] *= 0.7
        cap = (np.abs(x - cx) <= 7) & (y >= 230) & (y <= 233)
        paint[cap] = col(150, 124, 108) * (1.0 + 0.1 * np.exp(-np.abs(x[cap] - SUN[0]) / 200.0))[..., None]
    string = (y >= 208) & (y <= 210)
    paint[string] = paint[string] * 0.5 + col(146, 120, 102) * 0.5
    paint[y == 211] *= 0.55
    # warm rim on the arch edges facing the sun, shadow on the far side
    edge = opening & ~np.roll(opening, 1, axis=1) & stone.any()
    img[stone] = paint[stone]
    rim = stone & (np.roll(opening, -1, axis=1) | np.roll(opening, 1, axis=0))
    img[rim] = img[rim] * 0.6 + col(214, 150, 104) * 0.4
    shadow = stone & np.roll(opening, 2, axis=1) & ~opening
    img[shadow] *= 0.7
    # moss creeping down from the coping and up from the ground
    moss = stone & ((y - top[None, :] < 6) | (y > 296)) & (fbm((H, W), (18.0, 8.0), 47) > 0.55)
    img[moss] = img[moss] * 0.5 + col(58, 74, 50) * 0.5
    # ivy hanging from the coping in a few places
    ivy = stone & (fbm((H, W), (10.0, 26.0), 59) > 0.6) & (y - top[None, :] < 40) \
        & (np.sin(x / 57.0) > 0.35)
    img[ivy] = img[ivy] * 0.3 + col(40, 58, 40) * 0.7
    leaf = ivy & (fbm((H, W), (3.0, 3.0), 61) > 0.62)
    img[leaf] = col(72, 96, 62)
    # rubble fallen from the broken bay
    for k in range(28):
        rx = int(300 + (k * 37) % 64)
        ry = int(300 + (k * 13) % 8)
        img[ry:ry + 2 + k % 2, rx:rx + 2 + k % 3] = col(92, 80, 80) * (0.8 + 0.1 * (k % 3))
    # coping line
    cope = wall & (y - top[None, :] < 2)
    img[cope] = img[cope] * 0.5 + col(140, 116, 100) * 0.5
    # through the arches: the far side of the cloister, deeper in shadow
    beyond = opening & (y > 262)
    img[beyond] = img[beyond] * 0.45 + col(52, 44, 54) * 0.55
    # and the far arcade itself, small and dark, across the yard
    far_open = np.zeros((H, W), bool)
    for fx in range(10, W, 30):
        far_open |= (np.abs(x - fx) <= 9) & (y > 276) & (y < 300)
        far_open |= ((x - fx) ** 2 + (y - 276) ** 2 <= 81) & (y <= 276)
    far_wall = opening & (y > 262) & (y < 300) & ~far_open
    img[far_wall] = img[far_wall] * 0.7 + col(70, 60, 66) * 0.3
    img[opening & far_open & (y > 266)] *= 0.7
    return img


def belfry(img):
    """A bell gable over the arcade, with the bell hanging in its opening."""
    x0, x1, top = 468, 532, 104
    cx = (x0 + x1) // 2
    for yy in range(top, 184):
        for xx in range(x0, x1):
            roof = yy < top + 26 and abs(xx - cx) > (yy - top) * 1.25
            if roof:
                continue
            joint = (yy - top) % 9 == 0 or (xx + ((yy - top) // 9 % 2) * 6) % 13 == 0
            tone = 0.62 if joint else 0.92 + 0.1 * (((xx * 7 + yy * 3) // 13) % 3) / 2
            roof_edge = yy < top + 30 and abs(xx - cx) > (yy - top) * 1.25 - 2
            img[yy, xx] = (col(62, 48, 50) if roof_edge else col(80, 70, 72) * tone) * (1.12 if xx < cx else 0.88)
    # the opening and the bell
    for yy in range(top + 30, top + 66):
        for xx in range(cx - 12, cx + 13):
            if yy < top + 42 and (xx - cx) ** 2 + (yy - (top + 42)) ** 2 > 144:
                continue
            img[yy, xx] = col(186, 128, 92) * 0.9
    for yy in range(top + 40, top + 60):
        half = 3 + (yy - (top + 40)) * 6 // 20
        img[yy, cx - half:cx + half + 1] = col(64, 50, 38)
        img[yy, cx - half] = col(150, 110, 70)
    img[top + 38:top + 41, cx] = col(40, 32, 28)
    # the cross on the gable
    img[top - 14:top + 1, cx] = col(58, 50, 54)
    img[top - 10, cx - 4:cx + 5] = col(58, 50, 54)
    return img


def yard(img):
    y = np.arange(H)[:, None].repeat(W, 1)
    ground = y >= 306
    n = fbm((H, W), (26.0, 6.0), 53)
    earth = col(64, 52, 46) * (0.75 + 0.4 * n[..., None])
    fade = smooth(306, 360, y)[..., None]
    earth = earth * (1.0 - 0.55 * fade)
    img[ground] = earth[ground]
    lip = (y >= 306) & (y < 309)
    img[lip] = img[lip] * 0.6 + col(120, 96, 80) * 0.4
    # low mist along the foot of the wall
    mist = np.exp(-np.abs(y - 300.0) / 9.0)[..., None]
    img += col(110, 90, 84) * 0.28 * mist
    # a vignette: the eye to the middle, the corners into the dusk
    yy, xx = np.mgrid[0:H, 0:W]
    v = ((xx - W / 2) / (W * 0.62)) ** 2 + ((yy - H * 0.45) / (H * 0.8)) ** 2
    img *= (1.0 - 0.45 * smooth(0.35, 1.0, v))[..., None]
    return img


def backdrop():
    img = sky()
    img = hills(img)
    img = cloister(img)
    img = belfry(img)
    img = yard(img)
    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")
    # the other backdrops are painted in a limited palette: so is this one
    out = out.quantize(colors=56, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG).convert("RGB")
    return out


def sprite(rows, palette):
    height, width = len(rows), max(len(r) for r in rows)
    im = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    for yy, row in enumerate(rows):
        for xx, ch in enumerate(row):
            if ch in palette:
                im.putpixel((xx, yy), palette[ch])
    return im


DUMMY = [
    "........kkkkk........",
    ".......kSSSSSk.......",
    "......kSSxSxSSk......",
    "......kSSSxSSSk......",
    "......kSSxSxSSk......",
    ".......kSSSSSk.......",
    "........kSSSk........",
    ".........kwk.........",
    "..kkkkkkkkwkkkkkkkk..",
    ".kwwwwwwwwwwwwwwwwwk.",
    "..kkkkkkkBBBkkkkkkk..",
    ".......kBBBBBk.......",
    "......kBBsBBBBk......",
    "......kBBBBsBBk......",
    "......kBtBBBBBk......",
    "......kBBBBBtBk......",
    "......kBBsBBBBk......",
    "......kBBBBBBBk......",
    "......krrrrrrrk......",
    "......kBBBBBBBk......",
    "......kBBtBBsBk......",
    "......kBBBBBBBk......",
    ".......kBBBBBk.......",
    "........ttkt.........",
    ".........kwk.........",
    ".........kwk.........",
    ".........kwk.........",
    ".........kwk.........",
    ".........kwk.........",
    ".........kwk.........",
    ".........kwk.........",
    ".........kwk.........",
    ".........kwk.........",
    "......kkkkwkkkk......",
    ".....kwwwwwwwwwk.....",
    "....kkkkkkkkkkkkk....",
]
DUMMY_PALETTE = {
    "k": (34, 26, 22, 255), "w": (112, 80, 52, 255), "S": (176, 150, 104, 255),
    "x": (96, 30, 26, 255), "B": (160, 132, 88, 255), "s": (120, 96, 60, 255),
    "t": (214, 190, 120, 255), "r": (120, 40, 34, 255),
}
RACK = [
    "..k.......k.......k.......k..",
    ".kHk.....kHk.....kPk.....kHk.",
    ".kbk.....kbk.....kPk.....kbk.",
    ".kbk.....kbk.....kPk.....kbk.",
    ".kbk.....kbk.....kPk.....kbk.",
    ".kbk.....kbk.....kPk.....kbk.",
    "kgggk...kgggk....kPk....kgggk",
    ".khk.....khk.....kPk.....khk.",
    ".khk.....khk.....kPk.....khk.",
    "kkkkkkkkkkkkkkkkkkkkkkkkkkkkk",
    "kwwwwwwwwwwwwwwwwwwwwwwwwwwwk",
    "kkkkkkkkkkkkkkkkkkkkkkkkkkkkk",
    ".kw.......................wk.",
    ".kw.......................wk.",
    ".kw.......................wk.",
    ".kw.......................wk.",
    ".kw.......................wk.",
    ".kw.......................wk.",
    "kkkkkkkkkkkkkkkkkkkkkkkkkkkkk",
    "kwwwwwwwwwwwwwwwwwwwwwwwwwwwk",
    "kkkkkkkkkkkkkkkkkkkkkkkkkkkkk",
]
RACK_PALETTE = {
    "k": (34, 26, 22, 255), "w": (112, 80, 52, 255), "b": (170, 136, 92, 255),
    "H": (196, 164, 112, 255), "g": (90, 62, 40, 255), "h": (76, 52, 36, 255),
    "P": (138, 104, 66, 255),
}


def main():
    path = os.path.join(ROOT, "assets", "backgrounds", "practice_yard.png")
    backdrop().save(path, optimize=True)
    print(os.path.relpath(path, ROOT))
    folder = os.path.join(ROOT, "assets", "decor", "practice")
    os.makedirs(folder, exist_ok=True)
    for name, rows, palette in (("dummy", DUMMY, DUMMY_PALETTE), ("rack", RACK, RACK_PALETTE)):
        out = os.path.join(folder, name + ".png")
        sprite(rows, palette).save(out, optimize=True)
        print(os.path.relpath(out, ROOT))
    # the dummy as something to hit (data/enemies/training_dummy.json): a
    # 32x40 cell, its foot on the bottom row, rocking on its post when struck
    body = sprite(DUMMY, DUMMY_PALETTE)
    for name, angles in (("idle", [0, 0, 1, 0, 0, -1]), ("hurt", [-12, 8, -5, 3, -1, 0])):
        strip = Image.new("RGBA", (32 * len(angles), 40), (0, 0, 0, 0))
        for i, angle in enumerate(angles):
            # it pivots about its foot, as a post in the ground does
            pad = Image.new("RGBA", (64, 80), (0, 0, 0, 0))
            pad.alpha_composite(body, (32 - body.width // 2, 80 - body.height))
            turned = pad.rotate(angle, resample=Image.Resampling.NEAREST, center=(32, 79))
            strip.alpha_composite(turned.crop((16, 40, 48, 80)), (32 * i, 0))
        out = os.path.join(ROOT, "assets", "sprites", "training_dummy_%s.png" % name)
        strip.save(out, optimize=True)
        print(os.path.relpath(out, ROOT))


if __name__ == "__main__":
    main()
