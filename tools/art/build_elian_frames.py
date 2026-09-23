#!/usr/bin/env python3
"""Writes assets/sprites/elian_frames.tres (the hero) and slash_frames.tres
(his sword's effects) from the strips slice_hero.py cuts.

    python3 tools/art/build_elian_frames.py

The hero's SpriteFrames is the one resource that has to know about every strip,
so it is generated rather than clicked together: add a row to ANIMATIONS, run
this, and the player has the animation. Frame counts come from the png widths
(one 128x64 cell per frame; the effects use 80x48).
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SPRITES = os.path.join(ROOT, "assets", "sprites")
CELL = (128, 64)
FX_CELL = (80, 48)

# name -> strip, loops, frames per second
ANIMATIONS = [
    ("idle", "elian_idle", True, 5.0),           # sword out
    ("rest", "elian_rest", True, 5.0),           # sword sheathed: nobody has seen us yet
    ("draw", "elian_draw", False, 14.0),         # rest -> idle
    ("walk", "elian_walk", True, 12.0),
    ("run", "elian_run_v2", True, 16.0),
    ("jump", "elian_jump", False, 12.0),
    ("fall", "elian_fall", True, 9.0),
    ("land", "elian_land", False, 16.0),
    ("climb", "elian_climb", True, 14.0),        # pulling up through a ledge
    ("attack", "elian_slash", False, 24.0),      # the chain: slash, overhead, slam
    ("attack2", "elian_overhead", False, 22.0),
    ("attack3", "elian_slam", False, 16.0),
    ("thrust", "elian_thrust", False, 20.0),     # the backstab
    ("rising", "elian_rising", False, 20.0),     # swinging in the air
    ("dash_strike", "elian_dash_strike", False, 20.0),  # swinging out of the roll
    ("hurt", "elian_hurt", False, 16.0),
    ("knockback", "elian_knockback", False, 16.0),
    ("roll", "elian_roll", False, 18.0),
    ("death", "elian_death", False, 8.0),
    ("wake", "elian_wake", False, 7.0),
    ("talk", "elian_talk", True, 6.0),
    ("talk2", "elian_talk2", True, 6.0),
]
## Animations that borrow single frames from another strip instead of their own.
## The guard is the braced stance and the blade up across the body, two frames
## of the short base swing, held on the second.
BORROWED = [("guard", "elian_attack", [0, 4], False, 16.0)]

## The sword's effects (scenes/player/player.tscn, Hitbox/Slash): one arc per
## colour, the finisher's heavy arc, and what a hit throws off a body.
FX = [
    ("white", "slash_white", False, 22.0),
    ("heavy", "slash_heavy", False, 20.0),
    ("gold", "slash_gold", False, 22.0),
    ("red", "slash_red", False, 22.0),
    ("spark", "hit_spark", False, 20.0),
    ("blood", "hit_blood", False, 18.0),
]


def frame_count(strip, cell):
    with Image.open(os.path.join(SPRITES, f"{strip}.png")) as image:
        return image.width // cell[0]


def build():
    write("elian_frames.tres", ANIMATIONS, BORROWED, CELL)
    write("slash_frames.tres", FX, [], FX_CELL)


def write(file_name, animations, borrowed, cell):
    strips = sorted({strip for _, strip, _, _ in animations} | {strip for _, strip, _, _, _ in borrowed},
                    key=lambda s: [a[1] for a in animations].index(s) if any(a[1] == s for a in animations) else 99)
    counts = {strip: frame_count(strip, cell) for strip in strips}

    ext = "".join(f'[ext_resource type="Texture2D" path="res://assets/sprites/{s}.png" id="tex_{s}"]\n' for s in strips)
    subs = []
    for strip in strips:
        for i in range(counts[strip]):
            subs.append(f'[sub_resource type="AtlasTexture" id="{strip}_{i}"]\n'
                        f'atlas = ExtResource("tex_{strip}")\n'
                        f'region = Rect2({i * cell[0]}, 0, {cell[0]}, {cell[1]})\n')

    blocks = []
    for name, strip, loop, speed in animations:
        blocks.append((name, [f"{strip}_{i}" for i in range(counts[strip])], loop, speed))
    for name, strip, indices, loop, speed in borrowed:
        blocks.append((name, [f"{strip}_{i}" for i in indices], loop, speed))

    animations = []
    for name, frames, loop, speed in blocks:
        body = ", ".join('{\n"duration": 1.0,\n"texture": SubResource("%s")\n}' % f for f in frames)
        animations.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %s\n}'
                          % (body, "true" if loop else "false", name, speed))

    text = (f'[gd_resource type="SpriteFrames" load_steps={len(strips) + len(subs) + 1} format=3]\n\n'
            f"{ext}\n" + "\n".join(subs) + "\n[resource]\nanimations = [" + ", ".join(animations) + "]\n")
    path = os.path.join(SPRITES, file_name)
    with open(path, "w") as handle:
        handle.write(text)
    print("wrote", os.path.relpath(path, ROOT), f"({len(blocks)} animations, {len(subs)} frames)")


if __name__ == "__main__":
    build()
