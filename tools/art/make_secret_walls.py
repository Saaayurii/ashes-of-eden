#!/usr/bin/env python3
"""Bricked-up doorways for the secrets of chapter I (docs/CHAPTER1.md, Secrets).

Each wall is a prop strip (scripts/props/prop.gd): whole -> cracked -> bursting
-> leftovers. The stones are drawn here, but their colours are sampled from the
painted panel around the spot the wall stands on, so the doorway belongs to the
picture and only the cracks, the dust and a thread of light give it away.

    python3 tools/art/make_secret_walls.py

Writes assets/props/secret_wall_<place>.png. Deterministic (seeded per wall).
"""
import os
import random
import sys

from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "assets", "props")

# place: (panel, sample box in panel pixels, frame width, frame height, seed)
WALLS = {
    "catacombs": ("catacombs_2", (1058, 575, 1098, 688), 64, 100, 7),
    "village": ("graveyard_moon", (1085, 560, 1135, 640), 48, 72, 11),
    "swamp": ("swamp_crypt", (600, 330, 640, 420), 52, 76, 5),
}
GLOW = (255, 204, 120)


def palette(panel, box, stone_only=False):
    """Mortar, shadow, base, light and highlight from the panel's own stones."""
    img = Image.open(os.path.join(ROOT, "assets", "levels", panel + ".png")).convert("RGB")
    pixels = [img.getpixel((x, y)) for x in range(box[0], box[2]) for y in range(box[1], box[3])]
    if stone_only:
        # A crypt-wall sample includes black mortar and red roots. The secret
        # opening must borrow the visible grey masonry, not those shadows.
        stones = [p for p in pixels if 0.3 * p[0] + 0.59 * p[1] + 0.11 * p[2] > 38
                  and max(p) - min(p) < 45]
        if stones:
            pixels = stones
    pixels.sort(key=lambda p: 0.3 * p[0] + 0.59 * p[1] + 0.11 * p[2])

    def at(fraction, spread=0.04):
        lo = int(len(pixels) * max(0.0, fraction - spread))
        hi = max(lo + 1, int(len(pixels) * min(1.0, fraction + spread)))
        chunk = pixels[lo:hi]
        return tuple(sum(c[i] for c in chunk) // len(chunk) for i in range(3))

    return {"mortar": at(0.05), "shadow": at(0.25), "base": at(0.5), "light": at(0.78), "high": at(0.95)}


def shade(color, factor):
    return tuple(max(0, min(255, int(c * factor))) for c in color)


def arch_mask(w, h):
    """A doorway: straight jambs, a round head."""
    radius = w / 2.0
    inside = set()
    for y in range(h):
        for x in range(w):
            if y >= radius:
                inside.add((x, y))
            elif (x + 0.5 - radius) ** 2 + (y + 0.5 - radius) ** 2 <= radius * radius:
                inside.add((x, y))
    return inside


def stones(w, h, rng):
    """Rows of blocks, staggered: a list of (x0, y0, x1, y1) inclusive."""
    blocks = []
    y = 0
    row = 0
    while y < h:
        height = rng.choice((7, 8, 8, 9))
        x = -rng.randint(0, 6) if row % 2 else 0
        while x < w:
            width = rng.randint(9, 15)
            blocks.append((x, y, min(w - 1, x + width - 2), min(h - 1, y + height - 2)))
            x += width
        y += height
        row += 1
    return blocks


def draw_wall(w, h, pal, rng, missing=()):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    mask = arch_mask(w, h)
    blocks = stones(w, h, rng)
    for (x, y) in mask:
        px[x, y] = pal["mortar"] + (255,)
    for index, (x0, y0, x1, y1) in enumerate(blocks):
        if index in missing:
            for x in range(max(0, x0 - 1), min(w, x1 + 2)):
                for y in range(max(0, y0 - 1), min(h, y1 + 2)):
                    if (x, y) in mask:
                        px[x, y] = (0, 0, 0, 0)
            continue
        tone = rng.uniform(0.86, 1.1)
        for x in range(max(0, x0), x1 + 1):
            for y in range(y0, y1 + 1):
                if (x, y) not in mask:
                    continue
                if y == y0 or x == x0:
                    color = pal["light"]
                elif y == y1 or x == x1:
                    color = pal["shadow"]
                else:
                    color = pal["base"] if rng.random() > 0.18 else pal["shadow"]
                if y == y0 and x == x0 + 1:
                    color = pal["high"]
                # depth: the lower courses sit in shadow, the head catches light
                depth = 1.0 - 0.18 * (y / h)
                px[x, y] = shade(color, tone * depth) + (255,)
    # the frame: one pixel of the darkest mortar round the whole doorway
    for (x, y) in mask:
        edge = any((x + dx, y + dy) not in mask for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        if edge and px[x, y][3] > 0:
            px[x, y] = shade(pal["mortar"], 0.7) + (255,)
    return img, blocks, mask


def crack(img, mask, start, steps, rng, glow=0.0):
    """A random walk downhill: dark core, a lit lip, light seeping when glow > 0."""
    px = img.load()
    x, y = start
    for _ in range(steps):
        if (x, y) in mask and px[x, y][3] > 0:
            if glow > 0.0 and rng.random() < glow:
                px[x, y] = GLOW + (255,)
            else:
                px[x, y] = (18, 14, 14, 255)
            lip = (x + 1, y)
            if lip in mask and px[lip][3] > 0 and rng.random() < 0.8:
                r, g, b, a = px[lip]
                px[lip] = (min(255, r + 55), min(255, g + 48), min(255, b + 40), a)
        x += rng.choice((-1, 0, 0, 1))
        y += rng.choice((0, 1, 1))
        if y >= img.height:
            break


def rubble(w, h, pal, rng):
    """What is left on the floor: a low mound of broken blocks."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for _ in range(26):
        cx = rng.gauss(w / 2.0, w / 5.0)
        size_w = rng.randint(3, 7)
        size_h = rng.randint(2, 4)
        height = max(0.0, 1.0 - abs(cx - w / 2.0) / (w / 1.7)) * 12
        top = int(h - 1 - rng.uniform(0, height) - size_h)
        x0 = int(cx - size_w / 2)
        for x in range(x0, x0 + size_w):
            for y in range(top, min(h, top + size_h + 1)):
                if 0 <= x < w and 0 <= y < h:
                    color = pal["light"] if y == top else (pal["shadow"] if x == x0 + size_w - 1 else pal["base"])
                    px[x, y] = shade(color, rng.uniform(0.8, 1.05)) + (255,)
    return img


def build(place, spec):
    panel, box, w, h, seed = spec
    pal = palette(panel, box, stone_only=place == "swamp")
    frames = []
    # 0: whole, two hairline cracks — enough for a looking eye
    rng = random.Random(seed)
    whole, blocks, mask = draw_wall(w, h, pal, rng)
    starts = [(w // 2 + random.Random(seed + 1).randint(-6, 6), int(h * 0.3)), (w // 3, int(h * 0.55))]
    for index, start in enumerate(starts):
        crack(whole, mask, start, int(h * 0.4), random.Random(seed * 10 + index), glow=0.08)
    frames.append(whole)
    # 1: struck — the cracks run on, light seeps through
    cracked = whole.copy()
    for index, start in enumerate(starts + [(w * 2 // 3, int(h * 0.2)), (w // 2, int(h * 0.6))]):
        crack(cracked, mask, start, int(h * 0.7), random.Random(seed * 20 + index), glow=0.35)
    frames.append(cracked)
    # 2: bursting — half the blocks gone, the rest around the holes
    rng = random.Random(seed)
    gone = set(random.Random(seed + 3).sample(range(len(blocks)), len(blocks) // 2))
    bursting, _, _ = draw_wall(w, h, pal, rng, missing=gone)
    for index, start in enumerate(starts):
        crack(bursting, mask, start, int(h * 0.6), random.Random(seed * 30 + index), glow=0.5)
    frames.append(bursting)
    # 3: leftovers
    frames.append(rubble(w, h, pal, random.Random(seed + 5)))
    strip = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.paste(frame, (index * w, 0))
    path = os.path.join(OUT, "secret_wall_%s.png" % place)
    # Spelled out rather than left to Pillow's defaults. Without this the same
    # picture compresses differently between Pillow or zlib versions, so the
    # file changes on a machine that only regenerated it — which is how CI
    # caught this: identical pixels, different bytes, a diff nobody made.
    strip.save(path, "PNG", optimize=False, compress_level=6)
    print("%s  %dx%d x%d  palette %s" % (os.path.relpath(path, ROOT), w, h, len(frames), pal["base"]))


if __name__ == "__main__":
    selected = set(sys.argv[1:]) or set(WALLS)
    unknown = selected - set(WALLS)
    if unknown:
        raise SystemExit("unknown secret walls: " + ", ".join(sorted(unknown)))
    for place in WALLS:
        if place in selected:
            build(place, WALLS[place])
