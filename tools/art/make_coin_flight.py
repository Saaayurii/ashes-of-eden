#!/usr/bin/env python3
"""The coin of Tyre in flight (data/projectiles.json "coin", docs/CHAPTER4_ART.md §2):
what the Prince and the treasurer throw. Four 96x128 frames like every other
`*_flight_v3` sheet, the figure in the middle: a gold coin turning — face on,
three-quarter, edge, three-quarter — with a thin warm halo; the game spins,
lights and trails it (`Projectile.style`). Drawn pixel by pixel, so it stands
at 1:1 like the rest of the game's small art.

    python3 tools/art/make_coin_flight.py

Writes assets/sprites/projectiles/coin_flight_v3.png. Deterministic.
"""
import os

from PIL import Image
from studio_overrides import patched  # the art studio's edits of what this writes (tools/studio/overrides)

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "assets", "sprites", "projectiles", "coin_flight_v3.png")

W, H = 96, 128
RADIUS = 30
WIDTHS = (1.0, 0.6, 0.14, 0.6)  # the coin's face as it turns
RIM = (122, 78, 26, 255)
GOLD_DARK = (176, 120, 40, 255)
GOLD = (232, 176, 72, 255)
GOLD_LIGHT = (255, 224, 140, 255)
SHINE = (255, 248, 214, 255)
HALO = (255, 214, 112)


def coin(img, ox, share):
    cx, cy = ox + W // 2, H // 2
    rx = max(2.0, RADIUS * share)
    for y in range(cy - RADIUS - 8, cy + RADIUS + 9):
        for x in range(ox, ox + W):
            dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / RADIUS
            d = dx * dx + dy * dy
            # the halo: a faint ring of warm light a few pixels out
            hx, hy = (x + 0.5 - cx) / (rx + 7), (y + 0.5 - cy) / (RADIUS + 7)
            h = hx * hx + hy * hy
            if d > 1.0:
                if h <= 1.0:
                    img.putpixel((x, y), HALO + (int(70 * (1.0 - h)),))
                continue
            if d > 0.78:
                colour = RIM
            elif d > 0.6:
                colour = GOLD_DARK
            else:
                # light from the upper left, a stamped ring and a crude lighthouse
                colour = GOLD_LIGHT if dx + dy < -0.5 else GOLD
                if 0.34 < d < 0.42:
                    colour = GOLD_DARK
                if abs(dx) < 0.12 and -0.5 < dy < 0.35 and share > 0.3:
                    colour = RIM
                if abs(dy + 0.5) < 0.08 and abs(dx) < 0.22 and share > 0.3:
                    colour = SHINE
            img.putpixel((x, y), colour)
    if share > 0.3:  # a glint on the face
        for x, y in ((cx - int(rx * 0.45), cy - 14), (cx - int(rx * 0.45) + 1, cy - 14), (cx - int(rx * 0.45), cy - 13)):
            img.putpixel((x, y), SHINE)


def build():
    img = Image.new("RGBA", (W * len(WIDTHS), H), (0, 0, 0, 0))
    for frame, share in enumerate(WIDTHS):
        coin(img, frame * W, share)
    return img


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    patched(OUT, build()).save(OUT)
    print("wrote", os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()
