#!/usr/bin/env python3
"""Normalise the approved eight-frame Elian run sheet for the game rig."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/sprites/source/elian_run_v2_source.png"
OUTPUT = ROOT / "assets/sprites/elian_run_v2.png"
CELL = (128, 64)
FRAMES = 8
BODY_HEIGHT = 43
FEET_Y = 63
SOLID_ALPHA = 16


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    step = source.width / FRAMES
    strip = Image.new("RGBA", (CELL[0] * FRAMES, CELL[1]))
    for index in range(FRAMES):
        cell = source.crop((round(index * step), 0, round((index + 1) * step), source.height))
        # Image generation leaves almost invisible stray pixels hundreds of
        # pixels from the figure. Cropping by alpha > 0 changed the scale of
        # every frame independently and made Elian visibly pulse in game.
        solid = cell.getchannel("A").point(lambda value: 255 if value >= SOLID_ALPHA else 0)
        box = solid.getbbox()
        if box is None:
            raise RuntimeError(f"empty run frame {index}")
        body = cell.crop(box)
        # All eight poses use one scale derived from the median figure height.
        # One source pose was painted about 9% smaller; correct that outlier so
        # the player does not briefly shrink halfway through the cycle.
        scale = BODY_HEIGHT / 190.0
        if body.height < 180:
            scale = BODY_HEIGHT / body.height
        width = round(body.width * scale)
        body = body.resize((width, round(body.height * scale)), Image.Resampling.LANCZOS)
        frame = Image.new("RGBA", CELL)
        frame.alpha_composite(body, ((CELL[0] - body.width) // 2, FEET_Y - body.height))
        strip.alpha_composite(frame, (index * CELL[0], 0))
    strip.save(OUTPUT, optimize=True)
    print(OUTPUT.relative_to(ROOT), strip.size)


if __name__ == "__main__":
    main()
