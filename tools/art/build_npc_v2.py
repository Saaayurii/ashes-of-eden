#!/usr/bin/env python3
"""Slice approved 4x3 NPC animation atlases into Godot's 48x48 strips.

The source atlas is retained so animation frames can be rebuilt without
resampling an already small strip. Each character has its own source art.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "assets/sprites/npc_sources"
OUTPUT = ROOT / "assets/sprites"
CELL = 48


def build(name: str) -> None:
    image = Image.open(SOURCES / f"{name}_v2_atlas.png").convert("RGBA")
    source_w, source_h = image.width // 4, image.height // 3
    for row, action in enumerate(("idle", "walk", "attack")):
        strip = Image.new("RGBA", (CELL * 4, CELL))
        for column in range(4):
            # All approved atlases have a strict 4x3 composition. Keep the
            # same cell centre and foot baseline through every action.
            cell = image.crop((column * source_w, row * source_h,
                               (column + 1) * source_w, (row + 1) * source_h))
            cell = cell.resize((CELL, CELL), Image.Resampling.LANCZOS)
            strip.paste(cell, (column * CELL, 0))
        strip.save(OUTPUT / f"{name}_v2_{action}.png", optimize=True)


if __name__ == "__main__":
    for npc in ("knight", "mara", "matthew", "nun", "villager", "severin"):
        build(npc)
