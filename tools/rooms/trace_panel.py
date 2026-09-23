#!/usr/bin/env python3
"""Turns a painted level panel (a ChatGPT png in ~/Downloads) into a room's
raw material for tools/rooms/generate_rooms.py:

    python3 tools/rooms/trace_panel.py <time stamp> <room name> [overlay.png]

- writes assets/levels/<room name>.png, the panel at exactly 1280x720
- prints candidate ledges: horizontal runs where a lit stone top sits over
  darker stone (x, y, w) — a human picks the real ones by index
- prints candidate lights: candle flames (small warm blobs), lava (large warm
  blobs), the moon (a large pale blob) as (x, y, colour, radius, energy, flicker)
- draws everything, numbered, on the overlay for that review

The tracing is deliberately dumb; the eye does the rest (docs/DATA_FORMATS.md,
Rooms: a painted room's colliders are hand-picked).
"""
import glob
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "levels")
SIZE = (1280, 720)


def load(stamp):
    hits = glob.glob(os.path.expanduser(f"~/Downloads/*{stamp}.png"))
    if not hits:
        sys.exit(f"no *{stamp}.png in ~/Downloads")
    image = Image.open(hits[0]).convert("RGB").resize(SIZE, Image.LANCZOS)
    return image.filter(ImageFilter.UnsharpMask(radius=1, percent=50, threshold=2))


def ledges(image, min_len=44, gap=6):
    """Runs of pixels whose row is clearly lighter than the 3..10 rows below it."""
    lum = np.asarray(image.convert("L"), dtype=np.float32)
    h, w = lum.shape
    below = np.zeros_like(lum)
    for dy in range(3, 11):
        below[: h - dy] += lum[dy:]
    below /= 8.0
    above = np.zeros_like(lum)
    for dy in range(2, 6):
        above[dy:] += lum[: h - dy]
    above /= 4.0
    # a top edge: bright line, darker stone under it, and not just the bottom
    # of a bright sky (the rows above must not be much brighter either)
    edge = (lum - below > 34) & (lum > 70) & (lum - above > -12)
    runs = []
    for y in range(h):
        row = edge[y]
        x = 0
        while x < w:
            if not row[x]:
                x += 1
                continue
            start = x
            last = x
            while x < w and (row[x] or x - last <= gap):
                if row[x]:
                    last = x
                x += 1
            if last - start + 1 >= min_len:
                runs.append([start, y, last - start + 1])
    # merge runs stacked within 3 rows that overlap in x (the highlight is 2-3 px tall)
    runs.sort(key=lambda r: (r[1], r[0]))
    merged = []
    for run in runs:
        for m in merged:
            if abs(m[1] - run[1]) <= 3 and run[0] < m[0] + m[2] and m[0] < run[0] + run[2]:
                x0 = min(m[0], run[0])
                x1 = max(m[0] + m[2], run[0] + run[2])
                m[0], m[2] = x0, x1 - x0
                m[1] = min(m[1], run[1])
                break
        else:
            merged.append(run)
    merged.sort(key=lambda r: (r[1], r[0]))
    return [tuple(m) for m in merged]


def blobs(mask, min_px=2, max_px=100000):
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    out = []
    ys, xs = np.nonzero(mask)
    for sy, sx in zip(ys, xs):
        if seen[sy, sx]:
            continue
        stack = [(sy, sx)]
        seen[sy, sx] = True
        pts = []
        while stack:
            y, x = stack.pop()
            pts.append((y, x))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        if min_px <= len(pts) <= max_px:
            cy = sum(p[0] for p in pts) / len(pts)
            cx = sum(p[1] for p in pts) / len(pts)
            out.append((int(cx), int(cy), len(pts)))
    return out


def lights(image):
    rgb = np.asarray(image, dtype=np.int16)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    warm = (r > 215) & (g > 130) & (b < 140) & (r - b > 90)
    pale = (r > 225) & (g > 225) & (b > 225)
    out = []
    for x, y, n in blobs(warm, 3):
        if n < 60:
            out.append((x, y, "#ffb060", 36, 0.5, 0.3))          # a candle
        else:
            out.append((x, y, "#ff7030", min(160, 40 + n // 20), 0.6, 0.15))  # lava, a brazier
    for x, y, n in blobs(pale, 400):
        out.append((x, y, "#c8d4ff", 220, 0.5, 0.0))              # the moon
    # candles come in clusters: one light per 24 px cell is enough
    thinned = []
    for light in out:
        if all(abs(light[0] - o[0]) > 24 or abs(light[1] - o[1]) > 24 for o in thinned):
            thinned.append(light)
    return thinned


def main():
    stamp, name = sys.argv[1], sys.argv[2]
    overlay_path = sys.argv[3] if len(sys.argv) > 3 else None
    image = load(stamp)
    os.makedirs(OUT, exist_ok=True)
    image.save(os.path.join(OUT, name + ".png"))
    found = ledges(image)
    lit = lights(image)
    # the generator reads these when a room says lights="auto"
    with open(os.path.join(OUT, name + ".lights.json"), "w") as f:
        json.dump(lit, f)
    print(f"# {name}: {len(found)} ledge candidates, {len(lit)} lights")
    print("LEDGES = [")
    for i, (x, y, w) in enumerate(found):
        print(f"    ({x}, {y}, {w}),  # {i}")
    print("]")
    print("LIGHTS = [")
    for light in lit:
        print(f"    {light},")
    print("]")
    if overlay_path:
        over = image.copy()
        draw = ImageDraw.Draw(over)
        for i, (x, y, w) in enumerate(found):
            draw.line([(x, y), (x + w, y)], fill=(255, 40, 40), width=2)
            draw.text((x + 2, y - 11), str(i), fill=(255, 255, 0))
        for x, y, *_ in lit:
            draw.ellipse([x - 4, y - 4, x + 4, y + 4], outline=(0, 255, 255))
        for x in range(0, 1280, 100):
            draw.line([(x, 0), (x, 720)], fill=(60, 60, 120))
            draw.text((x + 2, 2), str(x), fill=(120, 120, 255))
        for y in range(0, 720, 100):
            draw.line([(0, y), (1280, y)], fill=(60, 60, 120))
            draw.text((2, y + 2), str(y), fill=(120, 120, 255))
        over.save(overlay_path)


if __name__ == "__main__":
    main()
