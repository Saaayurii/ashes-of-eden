#!/usr/bin/env python3
"""Elian's special moves (docs/TECHNIQUES.md), drawn from his own frames.

Every strip here is made from poses the hero already has, so the moves look
like him, not like somebody else's sheet:

- lunge   the thrust, with two fading after-images and speed lines behind it
          (back, forward + attack);
- charge  the slam's raised blade held, a gold edge breathing along the body
          (attack held after a swing);
- cleave  the slam released, its arc turned to hot gold and the body lit
          on the frames that hit;
- sweep   down to the ground, the low cut out of the roll, and up again
          (down + attack on the ground).

Deterministic; 128x64 cells like every other hero strip, feet where they are.
Run tools/art/build_elian_frames.py afterwards (check_generators runs both).

    python3 tools/art/make_elian_moves.py
"""
import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SPRITES = os.path.join(ROOT, "assets", "sprites")
CELL = (128, 64)
GOLD = (255, 214, 120)


def frames(name):
    strip = Image.open(os.path.join(SPRITES, name + ".png")).convert("RGBA")
    return [strip.crop((i * CELL[0], 0, (i + 1) * CELL[0], CELL[1])) for i in range(strip.width // CELL[0])]


def save(name, sequence):
    out = Image.new("RGBA", (CELL[0] * len(sequence), CELL[1]), (0, 0, 0, 0))
    for i, frame in enumerate(sequence):
        out.alpha_composite(frame, (i * CELL[0], 0))
    path = os.path.join(SPRITES, name + ".png")
    out.save(path, optimize=True)
    print(os.path.relpath(path, ROOT), "%d frames" % len(sequence))


def shifted(frame, dx):
    out = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    out.alpha_composite(frame, (dx, 0)) if dx >= 0 else out.alpha_composite(frame.crop((-dx, 0, frame.width, frame.height)), (0, 0))
    return out


def ghost(frame, alpha, tint=(170, 200, 255)):
    """The frame as a flat, see-through after-image in one cool colour."""
    a = np.asarray(frame).astype(float)
    out = np.zeros_like(a)
    out[..., 0], out[..., 1], out[..., 2] = tint
    out[..., 3] = a[..., 3] * alpha
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def edge_glow(frame, strength, color=GOLD):
    """A one-pixel rim of light round the silhouette, and a soft halo past it."""
    alpha = frame.getchannel("A").point(lambda v: 255 if v > 40 else 0)
    grown = alpha.filter(ImageFilter.MaxFilter(3))
    rim = np.asarray(grown).astype(float) - np.asarray(alpha).astype(float)
    halo = np.asarray(alpha.filter(ImageFilter.GaussianBlur(3))).astype(float)
    glow = np.zeros((frame.height, frame.width, 4))
    glow[..., 0], glow[..., 1], glow[..., 2] = color
    glow[..., 3] = np.clip(rim * strength + halo * 0.45 * strength, 0, 255)
    out = Image.fromarray(glow.astype(np.uint8), "RGBA")
    out.alpha_composite(frame)
    return out


def hot_arc(frame, heat):
    """The white arc drawn into a swing, turned toward gold: bright, near-grey
    pixels only, so the cloak and the skin keep their colours."""
    a = np.asarray(frame).astype(float)
    rgb = a[..., :3]
    light = rgb.mean(axis=2)
    grey = (rgb.max(axis=2) - rgb.min(axis=2)) < 40
    mask = (light > 170) & grey & (a[..., 3] > 0)
    target = np.array([255, 196, 96], float)
    rgb[mask] = rgb[mask] * (1 - heat) + target * heat
    a[..., :3] = rgb
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def speed_lines(frame, count, length):
    out = frame.copy()
    a = np.asarray(frame)
    ys = np.nonzero(a[..., 3].max(axis=1) > 0)[0]
    if ys.size == 0:
        return out
    top, bottom = ys[0], ys[-1]
    xs = np.nonzero(a[..., 3].max(axis=0) > 0)[0]
    back = int(xs[0])
    px = out.load()
    for k in range(count):
        y = int(top + (bottom - top) * (k + 1) / (count + 1))
        for i in range(length):
            x = back - 3 - i
            if 0 <= x < CELL[0]:
                px[x, y] = (230, 236, 255, int(170 * (1 - i / length)))
    return out


def main():
    thrust = frames("elian_thrust")
    lunge = []
    for index, trail in ((0, 0), (1, 1), (2, 2), (2, 2), (3, 1), (4, 0)):
        frame = thrust[index]
        canvas = Image.new("RGBA", CELL, (0, 0, 0, 0))
        for step in range(trail, 0, -1):
            canvas.alpha_composite(ghost(shifted(frame, -9 * step), 0.34 / step))
        canvas.alpha_composite(frame)
        if trail:
            canvas = speed_lines(canvas, 3, 10 + 6 * trail)
        lunge.append(canvas)
    save("elian_lunge", lunge)

    slam = frames("elian_slam")
    save("elian_charge", [edge_glow(slam[0], s) for s in (0.35, 0.65, 1.0, 0.65)])
    save("elian_cleave", [edge_glow(slam[0], 1.0), edge_glow(hot_arc(slam[1], 0.6), 0.6),
                          hot_arc(slam[2], 0.85), hot_arc(slam[3], 0.7), slam[4]])

    land, dash = frames("elian_land"), frames("elian_dash_strike")
    save("elian_sweep", [land[1], dash[1], dash[2], dash[3], land[2], land[3]])


if __name__ == "__main__":
    main()
