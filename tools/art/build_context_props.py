#!/usr/bin/env python3
"""Turn the approved 4x4 context-prop concept sheet into game-ready strips.

The source stays in assets/props/source so the export can be reproduced.  Each
row is normalised to a fixed 64x56 cell and bottom-centred; this keeps hit,
break and idle frames from visibly sliding around.
"""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/props/source/context_props_v1.png"
OUTPUT = ROOT / "assets/props"
NAMES = ("funeral_offering", "swamp_bundle", "bone_reliquary", "village_supplies")
CELL_W, CELL_H = 48, 44
PAD = 2


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    grid_w = source.width / 4.0
    grid_h = source.height / 4.0
    for row, name in enumerate(NAMES):
        frames = []
        for col in range(4):
            left = round(col * grid_w)
            top = round(row * grid_h)
            right = round((col + 1) * grid_w)
            bottom = round((row + 1) * grid_h)
            cell = source.crop((left, top, right, bottom))
            alpha_box = cell.getchannel("A").getbbox()
            if alpha_box is None:
                raise RuntimeError(f"empty cell at row {row}, column {col}")
            art = cell.crop(alpha_box)
            scale = min((CELL_W - PAD * 2) / art.width, (CELL_H - PAD * 2) / art.height)
            target = (max(1, round(art.width * scale)), max(1, round(art.height * scale)))
            art = art.resize(target, Image.Resampling.LANCZOS)
            frame = Image.new("RGBA", (CELL_W, CELL_H))
            frame.alpha_composite(art, ((CELL_W - art.width) // 2, CELL_H - PAD - art.height))
            frames.append(frame)
        strip = Image.new("RGBA", (CELL_W * 4, CELL_H))
        for col, frame in enumerate(frames):
            strip.alpha_composite(frame, (col * CELL_W, 0))
        path = OUTPUT / f"{name}.png"
        strip.save(path, optimize=True)
        print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
