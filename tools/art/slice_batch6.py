#!/usr/bin/env python3
"""Batch 6: the two frame packs that arrive as zips (one png per frame).

    python3 tools/art/slice_batch6.py ~/Downloads

- dark-hooded-warrior-*-frames.zip (8 x 128x128, one overhead melee swing)
    -> assets/sprites/champion_idle.png    72x64 x 8  (two stances, held 4 frames each)
    -> assets/sprites/champion_attack.png  72x64 x 5  (frame 0 is the held wind-up)
  Frames are pasted on a common anchor, never cropped per frame, so the body
  stays put while the blade sweeps out of the body's own box.
- black-bird-in-flight-8-directions-*-frames.zip (8 x 154x154, yaw views)
    -> assets/sprites/raven_fly.png        48x28 x 4
  The pack is 8 camera angles, not a wing beat: only the three side-ish views
  are used, mirrored to face right (the engine flips for facing < 0) and
  cycled so the bird banks instead of spinning.

Requires Pillow and numpy.
"""
import glob, io, os, sys, zipfile

import numpy as np
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Downloads")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SPRITES = os.path.join(ROOT, "assets", "sprites")

CHAMPION_CELL = (72, 64)
CHAMPION_BODY_X = 58  # where the warrior stands inside the 128 px source frame
CHAMPION_FEET_Y = 122
RAVEN_CELL = (48, 28)
RAVEN_SCALE = 0.38
RAVEN_LIFT = 1.2  # the pack is almost pure black; a touch of light keeps the bird readable in a dark room


def pack(pattern):
    """The frames of a zip, in file order: {1: Image, ...}."""
    hits = sorted(glob.glob(os.path.join(SRC, pattern)))
    if not hits:
        sys.exit(f"missing {pattern} in {SRC}")
    out = {}
    with zipfile.ZipFile(hits[-1]) as zf:
        for name in zf.namelist():
            base = os.path.basename(name)
            if not base.startswith("frame-") or not base.endswith(".png"):
                continue
            out[int(base[len("frame-"):-len(".png")])] = Image.open(io.BytesIO(zf.read(name))).convert("RGBA")
    return out


def downscale(img, size, threshold=110):
    """Resize in premultiplied alpha (no dark fringe), then harden the edge."""
    a = np.array(img).astype(np.float32)
    alpha = a[:, :, 3:4]
    premultiplied = Image.fromarray(np.dstack([a[:, :, :3] * alpha / 255.0, alpha]).astype(np.uint8))
    b = np.array(premultiplied.resize(size, Image.LANCZOS)).astype(np.float32)
    alpha = b[:, :, 3:4]
    rgb = np.clip(np.where(alpha > 0, b[:, :, :3] * 255.0 / np.maximum(alpha, 1.0), 0), 0, 255)
    return Image.fromarray(np.dstack([rgb, np.where(alpha > threshold, 255, 0)]).astype(np.uint8))


def strip(cells, name):
    cw, ch = cells[0].size
    out = Image.new("RGBA", (cw * len(cells), ch), (0, 0, 0, 0))
    for i, cell in enumerate(cells):
        out.alpha_composite(cell, (i * cw, 0))
    out.save(os.path.join(SPRITES, f"{name}.png"))
    print(f"{name}.png", out.size, len(cells), "frames")


def champion():
    frames = pack("dark-hooded-warrior*-frames.zip")
    cw, ch = CHAMPION_CELL
    offset = (cw - CHAMPION_BODY_X, (ch * 2 - 2) - CHAMPION_FEET_Y)  # feet one row above the cell bottom

    def cell(index):
        canvas = Image.new("RGBA", (cw * 2, ch * 2), (0, 0, 0, 0))
        canvas.alpha_composite(frames[index], offset)
        return downscale(canvas, CHAMPION_CELL)

    # 8 is the resting stance, 1-2 the raised blade, 3-5 the strike, 6-7 the follow-through.
    # One fps per enemy (see _setup_sprite), so the two idle stances are held by repeating them.
    strip([cell(i) for i in (8, 8, 8, 8, 7, 7, 7, 7)], "champion_idle")
    strip([cell(i) for i in (1, 3, 4, 5, 6)], "champion_attack")


def raven():
    frames = pack("black-bird-in-flight*-frames.zip")
    cw, ch = RAVEN_CELL
    canvas_size = (round(cw / RAVEN_SCALE), round(ch / RAVEN_SCALE))

    def cell(index):
        frame = frames[index].transpose(Image.FLIP_LEFT_RIGHT)  # the pack flies left, the engine wants right
        lit = np.array(frame).astype(np.float32)
        lit[:, :, :3] = np.clip(lit[:, :, :3] * RAVEN_LIFT, 0, 255)
        frame = Image.fromarray(lit.astype(np.uint8))
        mask = np.array(frame)[:, :, 3] > 16
        ys, xs = np.where(mask)
        canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
        canvas.alpha_composite(frame, (canvas_size[0] // 2 - round(xs.mean()), canvas_size[1] // 2 - round(ys.mean())))
        return downscale(canvas, RAVEN_CELL, 90)

    # 7 is the pure side view, 8 and 6 the two neighbouring yaws: side, near, side, far.
    strip([cell(i) for i in (7, 8, 7, 6)], "raven_fly")


if __name__ == "__main__":
    champion()
    raven()
