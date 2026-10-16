#!/usr/bin/env python3
"""Bolts drawn by the Codex CLI's image generation, cut into the game's
`*_flight_v3` strips (data/projectiles.json): four 96x128 frames, the bolt
flying right in the middle of each, like ash_flight_v3 and the rest.

The source is assets/sprites/projectiles/source/<id>_flight_v3_source.png: one
row of four frames on a transparent ground (drawn on flat magenta, keyed to
alpha before it is kept). Every frame is cut to its shape, all four scaled by
the one factor that fits the largest into FIT, and laid on the frame's middle
about the frames' common centre, so the bolt breathes and does not swim.

    python3 tools/art/build_flight_strips.py [id ...]

Deterministic. Writes through `patched()` (the art studio's edits).
"""
import os
import sys
from statistics import median

from PIL import Image
from studio_overrides import patched  # the art studio's edits of what this writes (tools/studio/overrides)

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
SOURCES = os.path.join(ROOT, "assets", "sprites", "projectiles", "source")
OUT = os.path.join(ROOT, "assets", "sprites", "projectiles")
FRAME = (96, 128)
COUNT = 4
# id -> the largest frame's box in the 96x128 frame (width, height): the game
# scales the style again (`scale`), this only keeps the drawing at 1:1 pixels
BOLTS = {
    "incense": (72, 72),     # a censer's puff (chapter VI)
    "host_arrow": (88, 40),  # the Host's archers (chapter III)
    "wormwood": (80, 64),    # a drop of bitter water (chapter III)
    "wormwood_ember": (80, 60),
}


def _frames(sheet: Image.Image) -> list[Image.Image]:
    w = sheet.width // COUNT
    frames = []
    for i in range(COUNT):
        frame = sheet.crop((i * w, 0, (i + 1) * w, sheet.height))
        frame.putalpha(frame.getchannel("A").point(lambda a: a if a > 24 else 0))
        frames.append(frame)
    return frames


def build(name: str, fit: tuple[int, int]) -> None:
    path = os.path.join(SOURCES, name + "_flight_v3_source.png")
    if not os.path.exists(path):
        print("no source for", name)
        return
    frames = _frames(Image.open(path).convert("RGBA"))
    boxes = [f.getbbox() or (0, 0, 1, 1) for f in frames]
    scale = min(fit[0] / max(b[2] - b[0] for b in boxes), fit[1] / max(b[3] - b[1] for b in boxes))
    cx = median((b[0] + b[2]) / 2 for b in boxes)
    cy = median((b[1] + b[3]) / 2 for b in boxes)
    strip = Image.new("RGBA", (FRAME[0] * COUNT, FRAME[1]), (0, 0, 0, 0))
    for i, (frame, box) in enumerate(zip(frames, boxes)):
        body = frame.crop(box)
        size = (max(1, round(body.width * scale)), max(1, round(body.height * scale)))
        body = body.resize(size, Image.Resampling.LANCZOS)
        x = round(FRAME[0] / 2 + (box[0] - cx) * scale)
        y = round(FRAME[1] / 2 + (box[1] - cy) * scale)
        cell = Image.new("RGBA", FRAME, (0, 0, 0, 0))
        cell.alpha_composite(body, (max(0, min(FRAME[0] - size[0], x)), max(0, min(FRAME[1] - size[1], y))))
        strip.alpha_composite(cell, (i * FRAME[0], 0))
    out = os.path.join(OUT, name + "_flight_v3.png")
    patched(out, strip).save(out, optimize=True)
    print("wrote", os.path.relpath(out, ROOT))


def main() -> None:
    only = set(sys.argv[1:])
    for name, fit in BOLTS.items():
        if not only or name in only:
            build(name, fit)


if __name__ == "__main__":
    main()
