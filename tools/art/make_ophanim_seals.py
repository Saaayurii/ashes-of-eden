#!/usr/bin/env python3
"""The seals the Ophanim hides behind (docs/BALANCE.md, the seal phase).

When the wheel of eyes closes them, three seals hang in the air of the arena;
it is only open again once all three are broken. A seal is the boss's own
metal in a small shape the eye already knows: a gold ring with spokes and one
eye at the hub, the same palette as the Ophanim's sheet (sampled from it), so
it reads as a piece of the angel, not a pickup.

    python3 tools/art/make_ophanim_seals.py

Writes assets/sprites/ophanim_seal_{idle,hurt,death}.png, 48x48 cells.
Deterministic: every frame is drawn from arithmetic, no dice.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter
from studio_overrides import patched  # the art studio's edits of what this writes (tools/studio/overrides)

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "assets", "sprites")
SOURCE = os.path.join(OUT, "ophanim_idle.png")
CELL = 48
SCALE = 4  # drawn large, reduced: clean curves without anti-aliasing noise


def palette():
    """Dark, body, light and glint gold, taken from the boss's own pixels."""
    image = Image.open(SOURCE).convert("RGBA")
    data = image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()
    pixels = [p[:3] for p in data if p[3] > 200 and p[0] > p[2] + 30]
    pixels.sort(key=lambda p: 0.3 * p[0] + 0.59 * p[1] + 0.11 * p[2])

    def at(fraction):
        chunk = pixels[int(len(pixels) * max(0.0, fraction - 0.03)):int(len(pixels) * min(1.0, fraction + 0.03)) + 1]
        return tuple(sum(c[i] for c in chunk) // len(chunk) for i in range(3))

    return {"dark": at(0.12), "body": at(0.5), "light": at(0.82), "glint": at(0.97)}


def seal(pal, turn, glow, crack=0.0, flash=0.0, spread=0.0, fade=1.0):
    """One frame. turn: spoke angle; glow: 0..1 halo; crack: 0..1 fracture;
    flash: 0..1 white; spread: 0..1 the pieces flying apart; fade: alpha."""
    size = CELL * SCALE
    c = size / 2
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    def mix(color, amount):
        return tuple(int(color[i] + (255 - color[i]) * amount) for i in range(3))

    outer, inner = 17 * SCALE, 12 * SCALE
    # the ring, broken into eight arcs so a crack can pull them apart
    for k in range(8):
        start = k * 45 + turn * 0.5
        # the arcs part, but stay inside the cell: the burst of shards is Fx's
        push = spread * (2 + (k * 37) % 3) * SCALE
        mid = math.radians(start + 22.5)
        dx, dy = math.cos(mid) * push, math.sin(mid) * push
        box = [c - outer + dx, c - outer + dy, c + outer + dx, c + outer + dy]
        gap = 3 + crack * 6 * ((k * 5) % 3)
        draw.arc(box, start + gap, start + 45 - gap, fill=mix(pal["body"], flash) + (255,), width=4 * SCALE)
        draw.arc([b + (1 if i < 2 else -1) * SCALE for i, b in enumerate(box)], start + gap, start + 45 - gap,
                 fill=mix(pal["light"], flash) + (255,), width=SCALE)
    # spokes
    if spread < 0.5:
        for k in range(6):
            a = math.radians(turn + k * 60)
            x0, y0 = c + math.cos(a) * 6 * SCALE, c + math.sin(a) * 6 * SCALE
            x1, y1 = c + math.cos(a) * inner, c + math.sin(a) * inner
            draw.line([x0, y0, x1, y1], fill=mix(pal["dark"], flash) + (255,), width=2 * SCALE)
        # the eye at the hub
        draw.ellipse([c - 7 * SCALE, c - 4 * SCALE, c + 7 * SCALE, c + 4 * SCALE],
                     fill=mix(pal["glint"], flash) + (255,), outline=mix(pal["dark"], flash) + (255,), width=SCALE)
        draw.ellipse([c - 2.5 * SCALE, c - 2.5 * SCALE, c + 2.5 * SCALE, c + 2.5 * SCALE],
                     fill=mix(pal["dark"], flash * 0.6) + (255,))
    # cracks: dark lines out from the hub
    if crack > 0.0:
        for k in range(3):
            a = math.radians(40 + k * 125)
            length = (8 + 10 * crack) * SCALE
            draw.line([c, c, c + math.cos(a) * length, c + math.sin(a) * length],
                      fill=(30, 18, 8, 255), width=SCALE)
    small = layer.resize((CELL, CELL), Image.Resampling.LANCZOS)
    # the halo: the frame's own light, blurred, behind it
    halo = small.filter(ImageFilter.GaussianBlur(3))
    glow_alpha = halo.getchannel("A").point(lambda v: int(v * 0.8 * glow))
    halo = Image.new("RGBA", small.size, pal["glint"] + (0,))
    halo.putalpha(glow_alpha)
    frame = Image.alpha_composite(halo, small)
    if fade < 1.0:
        frame.putalpha(frame.getchannel("A").point(lambda v: int(v * fade)))
    return frame


def strip(frames):
    out = Image.new("RGBA", (CELL * len(frames), CELL), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        out.paste(frame, (i * CELL, 0))
    return out


def main():
    pal = palette()
    idle = [seal(pal, turn=i * 10, glow=0.55 + 0.35 * math.sin(i / 6 * math.tau)) for i in range(6)]
    hurt = [seal(pal, turn=0, glow=1.0, crack=0.4, flash=0.7), seal(pal, turn=4, glow=0.8, crack=0.5, flash=0.25)]
    death = [seal(pal, turn=6 * i, glow=1.0 - i * 0.18, crack=0.6 + i * 0.1, flash=0.5 if i == 0 else 0.0,
                  spread=i / 4, fade=1.0 - i * 0.2) for i in range(5)]
    for name, frames in (("idle", idle), ("hurt", hurt), ("death", death)):
        path = os.path.join(OUT, "ophanim_seal_%s.png" % name)
        patched(path, strip(frames)).save(path, "PNG", optimize=False, compress_level=6)
        print(os.path.relpath(path, ROOT), "%d frames" % len(frames))


if __name__ == "__main__":
    main()
