#!/usr/bin/env python3
"""Turn the approved 4x2 Elian action sheets into stable 128x64 strips.

Keep one scale and one ground line across each action: changing either makes
the player appear to grow, shrink, or hover during the animation.
"""

from pathlib import Path
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/sprites/source"
OUTPUT = ROOT / "assets/sprites"
CELL = (128, 64)
GRID = (4, 2)
SCALE = 0.13


def build(name: str) -> None:
    image = Image.open(SOURCE / f"elian_{name}_v2_source.png").convert("RGBA")
    assert image.width % GRID[0] == 0 and image.height % GRID[1] == 0
    width, height = image.width // GRID[0], image.height // GRID[1]
    strip = Image.new("RGBA", (CELL[0] * 8, CELL[1]))

    for frame in range(8):
        x, y = frame % GRID[0], frame // GRID[0]
        tile = image.crop((x * width, y * height, (x + 1) * width, (y + 1) * height))
        opaque = tile.getchannel("A").point(lambda alpha: 255 if alpha > 30 else 0)
        bounds = opaque.getbbox()
        assert bounds is not None, f"{name} frame {frame} is empty"
        # Include soft edge pixels, but do not use transparent padding to size
        # the character or infer its foot position.
        left = max(0, bounds[0] - 8)
        top = max(0, bounds[1] - 8)
        right = min(width, bounds[2] + 8)
        bottom = min(height, bounds[3] + 8)
        cropped = tile.crop((left, top, right, bottom))
        scaled = cropped.resize(
            (round(cropped.width * SCALE), round(cropped.height * SCALE)),
            Image.Resampling.LANCZOS,
        )
        foot_offset = round((bottom - bounds[3]) * SCALE)
        x_at = frame * CELL[0] + (CELL[0] - scaled.width) // 2
        y_at = CELL[1] - foot_offset - scaled.height
        strip.alpha_composite(scaled, (x_at, y_at))

    strip.save(OUTPUT / f"elian_{name}_v2.png", optimize=True)


if __name__ == "__main__":
    build("heal")
    build("rise")
