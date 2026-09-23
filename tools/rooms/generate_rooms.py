#!/usr/bin/env python3
"""Generates scenes/rooms/*.tscn from the ROOMS table below.

Rooms are hand-made levels; this script is just a faster way to write the
first versions than clicking rectangles in the editor. Once a room is tuned by
hand in Godot, delete it from ROOMS so this script never overwrites it.

    python3 tools/rooms/generate_rooms.py
"""
import json
import os
import random
import filecmp
from copy import deepcopy

from PIL import Image, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DECOR_DIR = os.path.join(ROOT, "assets", "decor")
PLATFORM_DIR = os.path.join(DECOR_DIR, "platforms")
## Piece sizes and walkable tops, written by tools/art/slice_batch9.py.
with open(os.path.join(PLATFORM_DIR, "manifest.json")) as _f:
    PIECES = json.load(_f)

from painted_rooms import PAINTED, check_reach  # noqa: E402  (rooms drawn as one panel each)

# Each room gets two expansion seams in different places. Unlike global x
# scaling, seams add real traversal space without fattening characters,
# masonry, trees and props in the painted panel.
ROOM_EXPANSION_CUTS = {
    "village_night": (360, 880), "graveyard_cross": (390, 940),
    "graveyard_arches": (430, 900), "graveyard_tree": (380, 850),
    "swamp_moon": (350, 900), "swamp_red": (410, 930),
    "swamp_crypt": (360, 850), "catacombs_1": (430, 900),
    "catacombs_2": (370, 890), "catacombs_3": (420, 920),
    "crypt_skulls": (390, 870), "crypt_lava": (410, 900),
    "hell_gate": (380, 900), "church": (320, 640), "preacher_nave": (300, 660),
}

TRAVERSAL_PATCHES = {
    "village_night": [(430, 275, 80, 10)],
    "graveyard_cross": [(1320, 350, 80, 10)],
    "graveyard_arches": [(1450, 430, 72, 10)],
    "swamp_moon": [(425, 315, 90, 10)],
    "swamp_crypt": [(1440, 245, 80, 10)],
    "catacombs_3": [(480, 225, 80, 10)],
    "crypt_skulls": [(400, 285, 80, 10), (510, 270, 64, 10)],
    "hell_gate": [(1420, 310, 72, 10), (1450, 250, 72, 10)],
}


def _map_x(x, inserts):
    return round(x + sum(amount for cut, amount in inserts if x >= cut))


def _expand_panel(painting, inserts):
    """Insert seamless mirrored local bands; preserve every original pixel."""
    source_path = os.path.join(ROOT, "assets", "levels", painting + ".png")
    output_name = painting + "_wide"
    output_path = os.path.join(ROOT, "assets", "levels", output_name + ".png")
    source = Image.open(source_path).convert("RGBA")
    target = Image.new("RGBA", (source.width + sum(v for _, v in inserts), source.height))
    src_x = 0
    dst_x = 0
    for cut, amount in inserts:
        segment = source.crop((src_x, 0, cut, source.height))
        target.paste(segment, (dst_x, 0))
        dst_x += segment.width
        radius = min(max(16, amount // 2), source.width - cut)
        sample = source.crop((cut, 0, cut + radius, source.height))
        half = sample.resize((amount // 2, source.height), Image.Resampling.LANCZOS)
        loop = Image.new("RGBA", (amount, source.height))
        loop.paste(half, (0, 0))
        loop.paste(ImageOps.mirror(half), (amount - half.width, 0))
        target.paste(loop, (dst_x, 0))
        dst_x += amount
        src_x = cut
    target.paste(source.crop((src_x, 0, source.width, source.height)), (dst_x, 0))
    pending_path = output_path + ".pending.png"
    target.save(pending_path)
    # Do not invalidate Godot's imported texture when the painting has not
    # changed. Replacing identical PNGs could leave a stale valid=false remap
    # while a run was already loading the next room.
    if os.path.exists(output_path) and filecmp.cmp(pending_path, output_path, shallow=False):
        os.unlink(pending_path)
    else:
        os.replace(pending_path, output_path)
    return output_name


def expand_painted_room(name, room):
    """Return a wider copy, inserting space rather than stretching every gap."""
    out = deepcopy(room)
    amount = 120 if room.get("interior") else 160
    inserts = [(cut, amount) for cut in ROOM_EXPANSION_CUTS[name]]
    out["_x_inserts"] = inserts
    out["width"] = room["width"] + sum(value for _, value in inserts)
    if "painting" in room:
        out["painting_wide"] = room["painting"] + "_wide"
    for key in ("ground", "ledges", "platforms"):
        out[key] = [(_map_x(x, inserts), y, _map_x(x + w, inserts) - _map_x(x, inserts), h)
                    for x, y, w, h in room.get(key, [])]
    out["ramps"] = [(_map_x(x0, inserts), y0, _map_x(x1, inserts), y1)
                    for x0, y0, x1, y1 in room.get("ramps", [])]
    for key in ("spawns", "props", "npcs"):
        out[key] = [(item_id, _map_x(x, inserts), y) for item_id, x, y in room.get(key, [])]
    out["decor"] = [(item_id, _map_x(x, inserts), y, layer)
                    for item_id, x, y, layer in room.get("decor", [])]
    for key in ("player", "door", "shrine", "bell"):
        if key in room:
            x, y = room[key]
            out[key] = (_map_x(x, inserts), y)
    out["pillars"] = [(_map_x(x, inserts), y) for x, y in room.get("pillars", [])]
    if isinstance(room.get("lights"), list):
        out["lights"] = [(_map_x(x, inserts), y, tint, radius, energy, flicker)
                         for x, y, tint, radius, energy, flicker in room["lights"]]
    out["platforms"].extend(TRAVERSAL_PATCHES.get(name, []))
    _place_expansion_accents(name, out)
    return out


def _place_expansion_accents(name, room):
    """Anchor small story props on the actual new walkable seams."""
    if "swamp" in name:
        pool = ("swamp_bundle", "rubble", "pot")
    elif any(word in name for word in ("catacombs", "crypt", "hell")):
        pool = ("bone_reliquary", "pot", "rubble")
    elif name == "village_night":
        pool = ("village_supplies", "barrel", "rubble")
    elif name == "church":
        pool = ("funeral_offering", "pot")
    else:
        pool = ("funeral_offering", "rubble", "pot")
    for index, (cut, amount) in enumerate(room["_x_inserts"]):
        x = _map_x(cut, room["_x_inserts"]) - amount // 2
        surfaces = [(sy, sx, sw) for sx, sy, sw, _ in
                    room.get("ground", []) + room.get("ledges", []) + room.get("platforms", [])
                    if sx + 28 <= x <= sx + sw - 28
                    and sy <= room["height"] - (30 if room.get("interior") else 50)]
        if not surfaces:
            continue
        # Prefer a visible route or combat pocket over the invisible catch
        # floor. Keep a breathing gap around enemies, NPCs and other props.
        for y, _, _ in sorted(surfaces):
            occupied = any(abs(px - x) < 52 and abs(py - y) < 35
                           for _, px, py in room["props"] + room["npcs"])
            occupied |= any(abs(px - x) < 56 and abs(py + 12 - y) < 35
                            for _, px, py in room["spawns"])
            if not occupied:
                room["props"].append((pool[(index + len(name)) % len(pool)], x, y))
                break


def contextual_props(name, props):
    """Replace obvious copy-paste clutter with props belonging to this place.

    Chests and their rewards stay untouched. The replacement is deterministic,
    so generation produces authored layouts rather than runtime dice.
    """
    if "swamp" in name:
        replacements = {"barrel_apples": "swamp_bundle"}
    elif any(word in name for word in ("catacombs", "crypt", "hell")):
        replacements = {"barrel_apples": "bone_reliquary"}
    elif "village" in name:
        replacements = {"barrel_apples": "village_supplies", "box_goods": "village_supplies"}
    else:
        replacements = {"barrel_apples": "funeral_offering"}
    return [(replacements.get(prop_id, prop_id), x, y) for prop_id, x, y in props]

ROOMS = {
    # Every room but the boss arenas is two screens tall. Floors are jump-through
    # ledges (layer 5) 65-70 px apart with a small step ledge between two tiers,
    # so a tier is one double jump or two single ones; "ground" is solid.
    # Coordinates: enemies stand at floor-12, the player at floor-20, props,
    # decor and shrines at the floor, the door at floor-32.
    "graveyard": dict(
        # The hill at the top, the crypts at the bottom: a descent, with a pit
        # under the middle of the ground.
        backdrop="graveyard", width=1280, height=720, weather="rain", fog=0.55, intro="", music="graveyard",
        ground=[(0, 680, 540, 40), (600, 680, 680, 40), (540, 716, 60, 4)],
        platforms=[(0, 290, 380, 20), (470, 290, 200, 16), (760, 290, 520, 20),
                   (380, 355, 90, 12), (1180, 355, 100, 12),
                   (80, 420, 240, 16), (420, 420, 180, 16), (700, 420, 160, 16), (960, 420, 320, 16),
                   (330, 485, 80, 12), (880, 485, 70, 12),
                   (0, 550, 260, 16), (350, 550, 220, 16), (660, 550, 240, 16), (1000, 550, 280, 16),
                   (280, 615, 70, 12), (920, 615, 80, 12),
                   (560, 190, 120, 12), (1080, 200, 100, 12)],
        spawns=[("cultist", 900, 278), ("zealot", 1150, 408), ("possessed_villager", 200, 408),
                ("cultist", 480, 538), ("possessed_villager", 1100, 538),
                ("fallen_guard", 800, 668), ("cultist", 1100, 668),
                ("wraith", 300, 620), ("shade", 600, 380), ("raven", 900, 160), ("wraith", 1050, 260)],
        props=[("pot", 330, 290), ("barrel", 460, 680), ("crates_stacked", 700, 680), ("sack", 880, 680),
               ("chest_gold", 1050, 190), ("pot", 150, 420), ("barrel_apples", 1150, 550)],
        decor=[("tree_2", 90, 680, "back"), ("tree_4", 700, 680, "back"), ("crypt_1", 1010, 680, "back"),
               ("crypt_2", 470, 680, "back"), ("monument_1", 640, 680, "back"), ("monument_6", 820, 680, "back"),
               ("monument_9", 1230, 680, "back"), ("monument_8", 250, 290, "back"), ("tree_5", 1000, 290, "back"),
               ("tombstone_1", 150, 680, "mid"), ("tombstone_2", 210, 680, "mid"), ("tombstone_4", 350, 680, "mid"),
               ("tombstone_5", 620, 680, "mid"), ("tombstone_7", 760, 680, "mid"), ("tombstone_8", 960, 680, "mid"),
               ("fence_1", 880, 680, "mid"), ("fence_3", 1150, 680, "mid"), ("monument_3", 1090, 680, "mid"),
               ("grass_2", 210, 290, "front"), ("rocks", 620, 290, "front"), ("grass_1", 830, 290, "front"),
               ("bush", 1040, 420, "front"), ("tombstone_3", 120, 420, "mid"), ("tombstone_6", 560, 550, "mid"),
               ("fence_2", 1100, 550, "mid")],
        npcs=[("nun", 170, 290), ("mara", 1180, 260)],
        ambient="#a0a4b4", lights=[(1246, 621, "#ffb877", 60, 0.6, 0.3), (470, 250, "#8fd0ff", 70, 0.45, 0.1),
                                    (570, 630, "#7fd8b8", 60, 0.4, 0.1)],
        player=(60, 270), door=(1246, 648), shrine=(1170, 680), dress=("graveyard", 34)),
    "dead_bridge": dict(
        # A long ruin: the riverbed, a broken bridge on two piers, and the
        # battlements above it. The gate is up on the far battlement.
        backdrop="dead_bridge", width=1600, height=540, weather="fireflies", fog=0.45, intro="voice_catacombs", music="dead_bridge",
        ground=[(0, 500, 1600, 40), (560, 440, 40, 60), (1000, 440, 40, 60)],
        platforms=[(0, 380, 560, 20), (640, 380, 320, 20), (1040, 380, 560, 20),
                   (80, 440, 80, 12), (760, 440, 90, 12), (1460, 440, 80, 12),
                   (180, 260, 220, 16), (540, 260, 200, 16), (880, 260, 260, 16), (1280, 260, 320, 16),
                   (60, 320, 80, 12), (430, 320, 80, 12), (800, 320, 70, 12), (1200, 320, 70, 12),
                   (330, 150, 90, 12), (700, 160, 120, 12), (1100, 140, 100, 12)],
        spawns=[("cultist", 300, 488), ("fallen_guard", 700, 488), ("elite_possessed", 1150, 488), ("blind_preacher", 1350, 488),
                ("zealot", 400, 368), ("fallen_champion", 800, 368), ("cultist", 1300, 368),
                ("zealot", 650, 248), ("cultist", 1000, 248),
                ("shade", 900, 200), ("wraith", 1450, 180), ("shade", 300, 140), ("raven", 1200, 100)],
        props=[("crate", 160, 500), ("barrel_iron", 300, 500), ("crate_large", 500, 500), ("pot", 760, 500),
               ("barrel", 1080, 500), ("chest_wooden", 1500, 500), ("rubble", 250, 380), ("pot", 1200, 380),
               ("barrel_apples", 600, 260), ("chest_cursed", 750, 160)],
        decor=[("tree_1", 60, 500, "back"), ("tree_5", 900, 500, "back"), ("monument_8", 400, 500, "back"),
               ("monument_5", 1150, 500, "back"), ("crypt_2", 700, 500, "back"), ("tree_3", 1400, 500, "back"),
               ("crypt_1", 1300, 500, "back"),
               ("fence_2", 300, 500, "mid"), ("tombstone_3", 640, 500, "mid"), ("tombstone_6", 1080, 500, "mid"),
               ("rocks", 230, 380, "front"), ("grass_1", 370, 380, "front"), ("bush", 690, 380, "front"),
               ("grass_2", 1290, 380, "front"), ("fence_1", 1500, 380, "mid"),
               ("rocks", 300, 260, "front"), ("grass_2", 950, 260, "front")],
        npcs=[],
        ambient="#8ea0a4", lights=[(1566, 201, "#ffb877", 60, 0.6, 0.3), (700, 240, "#7fe0b0", 80, 0.4, 0.12),
                                    (1020, 420, "#7fe0b0", 70, 0.35, 0.12)],
        player=(60, 480), door=(1566, 228), shrine=(1480, 260), dress=("ruin", 30)),
    "fallen_knight": dict(
        # Boss arena, one screen: a raised dais in the middle, ledges to escape to.
        backdrop="dead_bridge", width=1024, height=360, weather="rain", fog=0.5, intro="", music="boss_knight",
        intro_cutscene="knight_arrival",
        ground=[(0, 320, 1024, 40), (412, 272, 200, 48)],
        platforms=[(120, 230, 110, 12), (800, 230, 110, 12), (300, 180, 90, 12), (640, 180, 90, 12)],
        spawns=[("knight_of_ash", 720, 308)],
        props=[("barrel", 110, 320), ("box_goods", 960, 320)],
        decor=[("monument_8", 180, 320, "back"), ("monument_2", 512, 272, "back"), ("tree_5", 860, 320, "back"),
               ("tombstone_3", 300, 320, "mid"), ("fence_2", 690, 320, "mid")],
        barriers=[(36, 320), (1000, 320)],
        ambient="#8688a8", lights=[(990, 261, "#ffb877", 60, 0.6, 0.3), (512, 250, "#ff6a4a", 100, 0.5, 0.2)],
        player=(60, 300), door=(990, 288), shrine=(900, 320), dress=("arena", 9)),
    "church_ophanim": dict(
        # Boss arena, one screen: a symmetrical nave with a high altar in the middle.
        backdrop="village_night", width=960, height=360, weather="embers", fog=0.3, intro="ch1_ophanim", music="boss_ophanim",
        intro_cutscene="ophanim_arrival", outro_cutscene="ch1_finale",
        ground=[(0, 320, 960, 40)],
        platforms=[(90, 250, 120, 12), (750, 250, 120, 12), (240, 200, 100, 14), (620, 200, 100, 14), (430, 160, 100, 12)],
        spawns=[("ophanim", 480, 110)],
        npcs=[("matthew", 120, 320)],
        props=[("pot", 120, 320), ("barrel", 240, 320), ("barrel_apples", 276, 320), ("crate", 830, 320)],
        decor=[("tree_2", 110, 320, "back"), ("monument_5", 480, 320, "back"), ("monument_2", 800, 320, "back"),
               ("fence_1", 250, 320, "mid"), ("fence_3", 700, 320, "mid"),
               ("grass_1", 150, 250, "front"), ("rocks", 470, 160, "front"), ("grass_2", 800, 250, "front")],
        barriers=[(36, 320), (936, 320)],
        ambient="#a08c98", lights=[(926, 261, "#ffb877", 60, 0.6, 0.3), (480, 140, "#ffd27a", 120, 0.55, 0.15)],
        player=(60, 300), door=(926, 288), shrine=(860, 320), dress=("nave", 10)),
}

## Lights painted into the backdrops, in painting pixels (640x360): the lamp on
## the post, the candles at the shrine, the moon. They ride on the Parallax node
## so they stay on the painting. (x, y, colour, radius, energy, flicker)
BACKDROP_LIGHTS = {
    "village_night": [(215, 190, "#ffb060", 70, 0.9, 0.25), (80, 205, "#ff9a50", 50, 0.6, 0.2),
                      (12, 215, "#ff9a50", 40, 0.5, 0.2), (520, 100, "#ffd080", 60, 0.5, 0.05),
                      (485, 245, "#ff8040", 40, 0.5, 0.15)],
    "graveyard": [(400, 100, "#ffb070", 160, 0.55, 0.0), (565, 165, "#c0a060", 40, 0.35, 0.1)],
    "dead_bridge": [(75, 185, "#ffb060", 70, 0.9, 0.25), (565, 265, "#ff9040", 50, 0.7, 0.3),
                    (490, 45, "#d0d8ff", 140, 0.45, 0.0)],
}

WEATHER = {
    "embers": """[node name="Weather" type="CPUParticles2D" parent="."]
z_index = 2
position = Vector2({cx}, {cy})
amount = {amount_low}
lifetime = 6.0
preprocess = 6.0
texture = SubResource("dot")
emission_shape = 3
emission_rect_extents = Vector2({ex}, {ey})
direction = Vector2(0, -1)
spread = 25.0
gravity = Vector2(0, -12)
initial_velocity_min = 15.0
initial_velocity_max = 45.0
angular_velocity_min = -60.0
angular_velocity_max = 60.0
scale_amount_min = 0.5
scale_amount_max = 1.2
color = Color(1.4, 0.8, 0.3, 0.9)
color_ramp = SubResource("fade")
""",
    "rain": """[node name="Weather" type="CPUParticles2D" parent="."]
z_index = 2
position = Vector2({cx}, -20)
amount = {amount_high}
lifetime = {rain_life}
preprocess = {rain_life}
texture = SubResource("drop")
emission_shape = 3
emission_rect_extents = Vector2({ex}, 4)
direction = Vector2(-0.15, 1)
spread = 2.0
gravity = Vector2(0, 600)
initial_velocity_min = 260.0
initial_velocity_max = 340.0
scale_amount_min = 0.7
scale_amount_max = 1.0
color = Color(0.9, 0.95, 1.1, 0.5)

[node name="WeatherFar" type="CPUParticles2D" parent="."]
position = Vector2({cx}, -20)
amount = {amount_low}
lifetime = {rain_life}
preprocess = {rain_life}
texture = SubResource("drop")
emission_shape = 3
emission_rect_extents = Vector2({ex}, 4)
direction = Vector2(-0.15, 1)
spread = 2.0
gravity = Vector2(0, 500)
initial_velocity_min = 200.0
initial_velocity_max = 260.0
scale_amount_min = 0.4
scale_amount_max = 0.6
color = Color(0.7, 0.75, 0.9, 0.3)
""",
    "fireflies": """[node name="Weather" type="CPUParticles2D" parent="."]
z_index = 2
position = Vector2({cx}, {cy})
amount = {amount_low}
lifetime = 5.0
preprocess = 5.0
texture = SubResource("dot")
emission_shape = 3
emission_rect_extents = Vector2({ex}, {ey})
direction = Vector2(1, 0)
spread = 180.0
gravity = Vector2(0, 0)
initial_velocity_min = 6.0
initial_velocity_max = 18.0
scale_amount_min = 0.4
scale_amount_max = 0.9
color = Color(0.9, 1.4, 0.6, 1)
color_ramp = SubResource("fade")
""",
}

WEATHER["ash"] = """[node name="Weather" type="CPUParticles2D" parent="."]
z_index = 2
position = Vector2({cx}, -20)
amount = {amount_low}
lifetime = 9.0
preprocess = 9.0
texture = SubResource("dot")
emission_shape = 3
emission_rect_extents = Vector2({ex}, 4)
direction = Vector2(0.2, 1)
spread = 30.0
gravity = Vector2(0, 14)
initial_velocity_min = 8.0
initial_velocity_max = 22.0
angular_velocity_min = -40.0
angular_velocity_max = 40.0
scale_amount_min = 0.5
scale_amount_max = 1.1
color = Color(0.75, 0.75, 0.85, 0.7)
color_ramp = SubResource("fade")
"""

## Dust in the air of every room: slow, faint, in front of the characters so it
## reads as air between them and the camera.
MOTES = """[node name="Motes" type="CPUParticles2D" parent="."]
z_index = 1
position = Vector2({cx}, {cy})
amount = {amount}
lifetime = 9.0
preprocess = 9.0
texture = SubResource("dot")
emission_shape = 3
emission_rect_extents = Vector2({ex}, {ey})
direction = Vector2(1, 0)
spread = 180.0
gravity = Vector2(0, -3)
initial_velocity_min = 3.0
initial_velocity_max = 9.0
scale_amount_min = 0.3
scale_amount_max = 0.6
color = Color(1, 0.95, 0.85, 0.5)
color_ramp = SubResource("fade")

"""

HEAD = """[gd_scene load_steps={steps} format=3]

[ext_resource type="Script" path="res://scripts/rooms/room.gd" id="1_room"]
[ext_resource type="Texture2D" path="res://assets/backgrounds/{backdrop}.png" id="2_backdrop"]
[ext_resource type="Shader" path="res://assets/shaders/fog.gdshader" id="3_fog"]
[ext_resource type="Script" path="res://scripts/rooms/door.gd" id="4_door"]
[ext_resource type="Script" path="res://scripts/rooms/enemy_spawn.gd" id="5_spawn"]
[ext_resource type="PackedScene" path="res://scenes/props/prop.tscn" id="7_prop"]
[ext_resource type="Texture2D" path="res://assets/decor/door_gate.png" id="8_gate"]
[ext_resource type="Texture2D" path="res://assets/decor/shrine.png" id="9_shrine"]
[ext_resource type="Texture2D" path="res://assets/decor/barrier.png" id="11_barrier"]
[ext_resource type="Script" path="res://scripts/rooms/room_fixture.gd" id="10_fixture"]
[ext_resource type="PackedScene" path="res://scenes/npc/npc.tscn" id="11_npc"]
[ext_resource type="Script" path="res://scripts/fx/glow_light.gd" id="12_light"]
[ext_resource type="Script" path="res://scripts/fx/ambient_light.gd" id="13_ambient"]
[ext_resource type="Script" path="res://scripts/rooms/church_bell.gd" id="14_bell"]
[ext_resource type="Script" path="res://scripts/rooms/hazard.gd" id="15_hazard"]
{decor_ext}{piece_ext}
[sub_resource type="Gradient" id="fade"]
offsets = PackedFloat32Array(0, 0.15, 0.7, 1)
colors = PackedColorArray(1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0.8, 1, 1, 1, 0)

[sub_resource type="FastNoiseLite" id="noise"]
frequency = 0.012

[sub_resource type="NoiseTexture2D" id="noise_tex"]
seamless = true
noise = SubResource("noise")

[sub_resource type="ShaderMaterial" id="fog_mat"]
shader = ExtResource("3_fog")
shader_parameter/noise = SubResource("noise_tex")
shader_parameter/density = {fog}

[sub_resource type="Gradient" id="glow_grad"]
offsets = PackedFloat32Array(0, 1)
colors = PackedColorArray(1, 0.85, 0.5, 0.7, 1, 0.85, 0.5, 0)

[sub_resource type="GradientTexture2D" id="glow_tex"]
gradient = SubResource("glow_grad")
width = 96
height = 96
fill = 1
fill_from = Vector2(0.5, 0.5)
fill_to = Vector2(0.5, 0)

[sub_resource type="Gradient" id="dot_grad"]
offsets = PackedFloat32Array(0, 1)
colors = PackedColorArray(1, 1, 1, 1, 1, 1, 1, 0)

[sub_resource type="GradientTexture2D" id="dot"]
gradient = SubResource("dot_grad")
width = 4
height = 4
fill = 1
fill_from = Vector2(0.5, 0.5)
fill_to = Vector2(0.5, 0)

[sub_resource type="GradientTexture2D" id="drop"]
gradient = SubResource("dot_grad")
width = 2
height = 10
fill_from = Vector2(0.5, 1)
fill_to = Vector2(0.5, 0)

[sub_resource type="CanvasItemMaterial" id="add_mat"]
blend_mode = 1

[sub_resource type="RectangleShape2D" id="door_shape"]
size = Vector2(20, 56)

{shapes}[node name="Room" type="Node2D"]
script = ExtResource("1_room")
width = {width}
height = {height}
intro_dialogue = "{intro}"
intro_cutscene = "{intro_cutscene}"
outro_cutscene = "{outro_cutscene}"

[node name="Ambient" type="CanvasModulate" parent="."]
color = {ambient}
script = ExtResource("13_ambient")
music = "{music}"

[node name="Parallax" type="Parallax2D" parent="."]
scroll_scale = Vector2({bscroll_x}, {bscroll_y})

[node name="Backdrop" type="Sprite2D" parent="Parallax"]
texture_filter = 2
scale = Vector2({bscale}, {bscale})
texture = ExtResource("2_backdrop")
centered = false

{backdrop_lights}[node name="FogFar" type="Parallax2D" parent="."]
scroll_scale = Vector2(0.75, 0.75)

[node name="Fog" type="ColorRect" parent="FogFar"]
material = SubResource("fog_mat")
offset_right = {fogw}.0
offset_bottom = {fogh}.0
mouse_filter = 2

[node name="Geometry" type="StaticBody2D" parent="."]
collision_layer = 1
collision_mask = 0

"""

FILL_COLOR = "Color(0.11, 0.09, 0.1, 1)"
## How far the 640x360 backdrop paintings are blown up. See build().
BACKDROP_SCALE = 1.1
## Neighbouring pieces overlap this much so no seam shows.
OVERLAP = 3


def shapes(rects, prefix):
    return "".join(f'[sub_resource type="RectangleShape2D" id="{prefix}{i + 1}_shape"]\nsize = Vector2({w}, {h})\n\n'
                   for i, (x, y, w, h) in enumerate(rects))


def collider(rects, prefix, parent, one_way=False):
    out = []
    for i, (x, y, w, h) in enumerate(rects, 1):
        out.append(f'[node name="{prefix}{i}Shape" type="CollisionShape2D" parent="{parent}"]\n'
                   f'position = Vector2({x + w / 2}, {y + h / 2})\nshape = SubResource("{prefix}{i}_shape")\n'
                   + ("one_way_collision = true\n" if one_way else "") + "\n")
    return "".join(out)


def ramp_nodes(ramps, parent):
    """Solid slopes under painted stairs: a strip from (x0, y0) to (x1, y1)."""
    out = []
    for i, (x0, y0, x1, y1) in enumerate(ramps, 1):
        thick = 16
        out.append(f'[node name="Ramp{i}" type="CollisionPolygon2D" parent="{parent}"]\n'
                   f'polygon = PackedVector2Array({x0}, {y0}, {x1}, {y1}, {x1}, {y1 + thick}, {x0}, {y0 + thick})\n\n')
    return "".join(out)


def family(name):
    return [piece for piece in sorted(PIECES) if PIECES[piece]["family"] == name]


def lay(x0, x1, pieces, rng, left_cap=None, right_cap=None):
    """Pieces laid left to right over [x0, x1): (name, x, crop width, flip).

    Whole pieces overlap by OVERLAP; the last one is cropped to the edge unless
    that would leave a sliver, in which case it slides back over its
    neighbour instead. Caps are the broken-off ends of the ground at a pit.
    """
    out = []
    x = x0
    if left_cap:
        out.append((left_cap, x0, PIECES[left_cap]["w"], True))
        x += PIECES[left_cap]["w"] - OVERLAP
    stop = x1 - (PIECES[right_cap]["w"] - OVERLAP if right_cap else 0)
    while x < stop:
        name = rng.choice(pieces)
        w = PIECES[name]["w"]
        last = x + w >= stop
        if last and stop - x < w * 0.45 and out:
            x = max(x0, stop - w)  # slide back over the neighbour, no sliver
        w = min(w, stop - x)
        out.append((name, x, w, rng.random() < 0.5 and w == PIECES[name]["w"]))
        if last:
            break
        x += w - OVERLAP
    if right_cap:
        out.append((right_cap, x1 - PIECES[right_cap]["w"], PIECES[right_cap]["w"], False))
    return out


def piece_nodes(layout, top_y, prefix, used):
    """Sprites for a lay() result, each piece's walkable top on top_y."""
    out = []
    for i, (name, x, w, flip) in enumerate(layout, 1):
        used.add(name)
        info = PIECES[name]
        out.append(f'[node name="{prefix}_{i}" type="Sprite2D" parent="Terrain"]\n'
                   f'position = Vector2({x}, {top_y - info["top"]})\n'
                   f'texture = ExtResource("piece_{name}")\ncentered = false\n'
                   + ("flip_h = true\n" if flip else "")
                   + (f'region_enabled = true\nregion_rect = Rect2(0, 0, {w}, {info["h"]})\n' if w < info["w"] else "")
                   + "\n")
    return "".join(out)


def interior_nodes(r, rng, used):
    """A room inside: stone wall pieces tiled over the whole back, dim, with
    pillars standing on the floor line and, above, whatever "arches" the room
    lists (window openings; a cool light behind each is the glass)."""
    width, height = r["width"], r.get("height", 360)
    # solid dark behind the stones: their mossy edges leave gaps
    out = [f'[node name="Backing" type="ColorRect" parent="Interior"]\noffset_right = {width}.0\n'
           f'offset_bottom = {height}.0\ncolor = Color(0.06, 0.05, 0.07, 1)\nmouse_filter = 2\n\n']
    pieces = family("wall")
    y = -12
    row = 0
    while y < height:
        x = -8 - (row % 2) * 12
        while x < width:
            name = rng.choice(pieces)
            used.add(name)
            # brighter than it looks right: the lights multiply into this
            out.append(f'[node name="Wall_{row}_{len(out)}" type="Sprite2D" parent="Interior"]\n'
                       f'position = Vector2({x}, {y})\ntexture = ExtResource("piece_{name}")\ncentered = false\n'
                       + ("flip_h = true\n" if rng.random() < 0.5 else "")
                       + 'modulate = Color(1.15, 1.1, 1.2, 1)\n\n')
            x += PIECES[name]["w"] - OVERLAP
        y += 46
        row += 1
    pillars = family("pillar")[:4]  # the standing columns, not the pedestals
    for i, (x, y) in enumerate(r.get("pillars", []), 1):
        name = pillars[i % len(pillars)]
        used.add(name)
        info = PIECES[name]
        out.append(f'[node name="Pillar{i}" type="Sprite2D" parent="Interior"]\n'
                   f'position = Vector2({x - info["w"] // 2}, {y - info["h"]})\ntexture = ExtResource("piece_{name}")\n'
                   'centered = false\nmodulate = Color(1.2, 1.15, 1.25, 1)\n\n')
    return "".join(out)


def terrain_nodes(r, rng, used, walls=True):
    """The ground and the ledges drawn out of sheet pieces (assets/decor/platforms).

    Solid ground: grass-topped earth blocks, broken-off caps at a pit, a dark
    fill under them where the block is taller than the art. Narrow tall
    blocks (bridge piers) are wall segments. Ledges (jump-through) are stone
    shelves with hanging moss, small mossy chunks when they are short.
    """
    width = r["width"]
    out = []
    for i, (x, y, w, h) in enumerate(r["ground"], 1):
        if w <= 48 and h >= 48:
            out.append(piece_nodes(lay(x, x + w, family("wall"), rng), y, f"Ground{i}", used))
            continue
        pieces = family(r.get("floor", "ground" if w >= 120 else "earth"))
        caps = family("cap")
        layout = lay(x, x + w, pieces, rng,
                     left_cap=rng.choice(caps) if x > 0 else None,
                     right_cap=rng.choice(caps) if x + w < width else None)
        art_bottom = y + min(PIECES[n]["h"] - PIECES[n]["top"] for n, _, _, _ in layout)
        if y + h > art_bottom + 2:
            out.append(f'[node name="Ground{i}Fill" type="ColorRect" parent="Terrain"]\n'
                       f'offset_left = {x}.0\noffset_top = {art_bottom - 4}.0\noffset_right = {x + w}.0\n'
                       f'offset_bottom = {y + h}.0\ncolor = {FILL_COLOR}\nmouse_filter = 2\n\n')
        out.append(piece_nodes(layout, y, f"Ground{i}", used))
    for i, (x, y, w, h) in enumerate(r["platforms"], 1):
        pieces = family("float") if w < 80 else family("ledge")
        out.append(piece_nodes(lay(x, x + w, pieces, rng), y, f"Platform{i}", used))
    if not walls:
        return "".join(out)
    # the room's edges: a mossy wall on each side, behind everything
    walls = family("wall")
    for side, x in (("L", -4), ("R", width - 26)):
        y = r.get("height", 360)
        i = 0
        while y > -16:
            name = rng.choice(walls)
            used.add(name)
            i += 1
            y -= PIECES[name]["h"] - OVERLAP
            out.append(f'[node name="Wall{side}_{i}" type="Sprite2D" parent="Terrain"]\n'
                       f'position = Vector2({x}, {y})\ntexture = ExtResource("piece_{name}")\ncentered = false\n'
                       'modulate = Color(0.8, 0.8, 0.85, 1)\n\n')
    return "".join(out)


def color(hex_rgb):
    """'#rrggbb' -> 'Color(r, g, b, 1)'."""
    return "Color(%s, 1)" % ", ".join(str(round(int(hex_rgb[i:i + 2], 16) / 255.0, 3)) for i in (1, 3, 5))


def thin_lights(lights, max_count=26, spacing=48):
    """A painted room can carry a hundred candles; the renderer should not.
    Keep the big ones, then the rest from the left, none closer than spacing."""
    kept = []
    for light in sorted(lights, key=lambda l: (-l[3], l[0])):
        if len(kept) >= max_count:
            break
        if all(abs(light[0] - k[0]) >= spacing or abs(light[1] - k[1]) >= spacing for k in kept):
            kept.append(light)
    return sorted(kept)


def light_nodes(lights, parent, prefix, scale=1.0):
    out = []
    for i, (x, y, tint, radius, energy, flicker) in enumerate(lights, 1):
        out.append(f'[node name="{prefix}{i}" type="PointLight2D" parent="{parent}"]\n'
                   f'position = Vector2({round(x * scale)}, {round(y * scale)})\ncolor = {color(tint)}\n'
                   f'energy = {energy}\nscript = ExtResource("12_light")\nradius = {radius}.0\nflicker = {flicker}\n\n')
    return "".join(out)


def decor_nodes(decor, layer, parent):
    """Sprites anchored at their bottom centre. Back layer is darker and parallaxed."""
    out = []
    for i, (name, x, y, where) in enumerate(decor, 1):
        if where != layer:
            continue
        w, h = Image.open(os.path.join(DECOR_DIR, f"{name}.png")).size
        tint = "Color(0.55, 0.5, 0.55, 1)" if layer == "back" else "Color(0.85, 0.8, 0.85, 1)"
        out.append(f'''[node name="{ident(name)}_{i}" type="Sprite2D" parent="{parent}"]
modulate = {tint}
position = Vector2({x}, {y - h / 2})
texture = ExtResource("decor_{ident(name)}")

''')
    return "".join(out)


def ident(name):
    """A decor name as a node name / resource id: sub-folders flattened."""
    return name.replace("/", "_")


# What each kind of place is dressed with (assets/decor/<folder>/<family>_N.png,
# cut by tools/art/slice_batch10.py). Families are weighted by how often they
# should turn up; a room asks for a kind and a count with dress=(kind, count).
DRESSING = {
    "graveyard": {"graveyard/tomb": 5, "graveyard/cross": 3, "graveyard/monument": 1, "graveyard/angel": 1,
                  "graveyard/railing": 1, "graveyard/coffin": 1, "graveyard/grave": 1, "graveyard/bones": 2,
                  "graveyard/deadwood": 1, "graveyard/crypt": 1, "wilds/stump": 1, "wilds/brush": 2,
                  "wilds/sapling": 1},
    "ruin": {"wilds/tree": 2, "wilds/sapling": 2, "wilds/fallen": 2, "wilds/stump": 2, "wilds/brush": 3,
             "graveyard/tomb": 1, "graveyard/cross": 1, "graveyard/bones": 1, "clutter/clutter": 2},
    "arena": {"graveyard/angel": 2, "graveyard/monument": 1, "graveyard/tomb": 2, "graveyard/bones": 2,
              "clutter/brazier_lit": 1, "wilds/brush": 1},
    "nave": {"clutter/altar_lit": 1, "clutter/brazier_lit": 2, "graveyard/angel": 2, "graveyard/coffin": 1,
             "graveyard/yard": 1, "graveyard/bones": 1, "graveyard/cross": 1},
}
# Anything this tall or more is scenery behind the fight, not clutter in it.
BACK_FROM = 50
# Anything this short or less sits in front of the bodies, like grass does.
FRONT_UPTO = 24


def dress(name, r):
    """Extra decor scattered over the room's own surfaces: [(name, x, floor, layer)].

    Seeded by the room name, so a regeneration puts the same piece in the same
    place. A piece only lands where it fits: on a surface wide enough for it,
    under enough headroom (the tier above is 65-70 px up; scenery behind the
    geometry may reach 20 px into it), and never on top of a prop, an enemy, an
    npc, the player's spawn, the door or the shrine, nor another piece.
    """
    if "dress" not in r:
        return []
    kind, count = r["dress"]
    pool = []
    for family, weight in DRESSING[kind].items():
        folder, stem = family.split("/")
        files = sorted(f for f in os.listdir(os.path.join(DECOR_DIR, folder))
                       if f.endswith(".png") and (f.startswith(stem + "_") or f == stem + ".png"))
        for f in files:
            w, h = Image.open(os.path.join(DECOR_DIR, folder, f)).size
            pool.append((f"{folder}/{f[:-4]}", w, h, weight / len(files)))
    surfaces = [(x, y, w) for x, y, w, _ in r["ground"] + r["platforms"] if w >= 60]
    taken = [(x, y) for _, x, y, _ in r.get("decor", [])]
    for key in ("props", "spawns", "npcs"):
        taken += [(x, y if key != "spawns" else y + 12) for _, x, y in r.get(key, [])]
    for key in ("player", "door", "shrine"):
        if key in r:
            x, y = r[key]
            taken.append((x, y + {"player": 20, "door": 32}.get(key, 0)))

    def headroom(x0, x1, y):
        above = [sy for sx, sy, sw in surfaces if sy < y - 8 and sx < x1 and sx + sw > x0]
        return y - max(above) if above else 999

    rng = random.Random("dress:" + name)
    out = []
    for _ in range(count * 12):  # a bounded number of tries: a crowded room just gets fewer
        if len(out) >= count:
            break
        piece, w, h, _ = rng.choices(pool, weights=[p[3] for p in pool])[0]
        sx, sy, sw = rng.choices(surfaces, weights=[s[2] for s in surfaces])[0]
        if sw < w + 16:
            continue
        x = round(rng.uniform(sx + 8 + w / 2, sx + sw - 8 - w / 2))
        layer = "back" if h >= BACK_FROM else ("front" if h <= FRONT_UPTO else "mid")
        room_above = headroom(x - w / 2, x + w / 2, sy)
        if h > room_above - 4 + (20 if layer == "back" else 0):
            continue
        near = max(24, w * 0.6)
        if any(abs(tx - x) < near and abs(ty - sy) < 6 for tx, ty in taken):
            continue
        taken.append((x, sy))
        out.append((piece, x, sy, layer))
    return out


def build(name, r):
    r = deepcopy(r)
    r["props"] = contextual_props(name, r.get("props", []))
    width, height = r["width"], r.get("height", 360)
    # Walls on both sides and a lid over the top: the player has a double jump
    # and the camera stops at y = 0.
    walls = [(-16, -16, 16, height + 16), (width, -16, 16, height + 16), (0, -16, width, 16)]
    painted = "painting" in r
    ledges = r.get("ledges", [])
    shape_text = (shapes(r["ground"], "Ground") + shapes(r["platforms"], "Platform") + shapes(ledges, "Ledge")
                  + shapes(walls, "Wall"))
    decor = r.get("decor", []) + dress(name, r)
    decor_names = sorted({d[0] for d in decor})
    decor_ext = "".join(f'[ext_resource type="Texture2D" path="res://assets/decor/{n}.png" id="decor_{ident(n)}"]\n'
                        for n in decor_names)
    # Same pieces in the same places every time the script runs: the layout is
    # part of the room, not a dice roll on every regeneration.
    rng = random.Random(name)
    used = set()
    # A painted room draws nothing over its ground and ledges: the panel already
    # has them. Only the extra "platforms" get piece art.
    terrain = terrain_nodes(dict(r, ground=[], ledges=[]) if painted else r, rng, used, walls=not painted)
    interior = interior_nodes(r, rng, used) if r.get("interior") else ""
    piece_ext = "".join(f'[ext_resource type="Texture2D" path="res://assets/decor/platforms/{n}.png" id="piece_{n}"]\n'
                        for n in sorted(used))
    ambient = color(r["ambient"])
    # The backdrops are painted at exactly one screen (640x360), so every pixel of
    # upscale costs detail and any non-uniform scale bends the painting. Keep the
    # scale uniform and barely above 1 and buy the parallax travel from the
    # scroll instead. A Parallax2D layer sits at camera * (1 - scroll_scale), so
    # over a room it slips scroll_scale * (width - 640) pixels against the
    # screen, and that slip has to fit in the 640 * (BACKDROP_SCALE - 1) pixels
    # the upscale gives us (36 vertically, for a room taller than one screen).
    bscroll_x = round(min(0.1, 640 * (BACKDROP_SCALE - 1.0) / (width - 640)), 2) if width > 640 else 0.0
    bscroll_y = round(min(0.1, 360 * (BACKDROP_SCALE - 1.0) / (height - 360)), 2) if height > 360 else 0.0
    area = width * height / (1280.0 * 360.0)
    weather = "" if r["weather"] == "none" else WEATHER[r["weather"]].format(
        cx=width / 2, cy=height / 2, ex=width / 2 + 60, ey=max(10, height / 2 - 30),
        amount_low=int(40 * area), amount_high=min(400, int(260 * area)),
        rain_life=round(1.2 * max(1.0, height / 480.0), 2))
    text = HEAD.format(intro_cutscene=r.get("intro_cutscene", ""), outro_cutscene=r.get("outro_cutscene", ""), steps=0, backdrop=r.get("backdrop", ""), fog=r["fog"], width=width, height=height, intro=r["intro"],
                       music=r.get("music", ""),
                       fogw=width + 200, fogh=height + 400, bscale=BACKDROP_SCALE,
                       bscroll_x=bscroll_x, bscroll_y=bscroll_y, shapes=shape_text, decor_ext=decor_ext,
                       piece_ext=piece_ext, ambient=ambient,
                       backdrop_lights=light_nodes(BACKDROP_LIGHTS.get(r.get("backdrop"), []), "Parallax", "Painted", BACKDROP_SCALE))
    if r.get("interior"):
        # Inside: no painting, no fog; a stone wall behind everything.
        text = text.replace('[ext_resource type="Texture2D" path="res://assets/backgrounds/.png" id="2_backdrop"]\n', '')
        a = text.index('[node name="Parallax" type="Parallax2D" parent="."]')
        b = text.index('[node name="Geometry" type="StaticBody2D" parent="."]')
        text = text[:a] + '[node name="Interior" type="Node2D" parent="."]\n\n' + interior + text[b:]
    if painted:
        text = text.replace('outro_cutscene = "' + r.get("outro_cutscene", "") + '"\n',
                            'outro_cutscene = "' + r.get("outro_cutscene", "") + '"\n'
                            + f'painting_source = "res://assets/levels/{r["painting_wide"]}.png"\n', 1)
        # The wide panel contains inserted local scenery bands rather than a
        # non-uniformly stretched source, so stone and figures keep their scale.
        text = text.replace('[ext_resource type="Texture2D" path="res://assets/backgrounds/.png" id="2_backdrop"]',
                            f'[ext_resource type="Texture2D" path="res://assets/levels/{r["painting_wide"]}.png" id="2_backdrop"]')
        a = text.index('[node name="Parallax" type="Parallax2D" parent="."]')
        b = text.index('[node name="FogFar" type="Parallax2D" parent="."]')
        text = text[:a] + (f'[node name="Painting" type="Sprite2D" parent="."]\n'
                          'texture_filter = 2\ntexture = ExtResource("2_backdrop")\ncentered = false\n\n') + text[b:]
    # decor behind the geometry: slightly parallaxed for depth
    text = text.replace('[node name="Geometry" type="StaticBody2D" parent="."]',
                        '[node name="DecorBack" type="Parallax2D" parent="."]\nscroll_scale = Vector2(0.88, 1)\n\n'
                        + decor_nodes(decor, "back", "DecorBack")
                        + '[node name="Geometry" type="StaticBody2D" parent="."]')
    text += collider(r["ground"], "Ground", "Geometry") + collider(walls, "Wall", "Geometry")
    text += ramp_nodes(r.get("ramps", []), "Geometry")
    # Ledges live on their own layer (5) so a body can choose to fall through them.
    text += '[node name="Ledges" type="StaticBody2D" parent="."]\ncollision_layer = 16\ncollision_mask = 0\n\n'
    text += collider(r["platforms"], "Platform", "Ledges", one_way=True) + collider(ledges, "Ledge", "Ledges", one_way=True)
    # Draw order from here: terrain, then what stands on the lanes behind the
    # characters, props, (the run adds enemies and players), low clutter in
    # front of their feet (z 1), weather over it all (z 2), lights.
    text += '[node name="Terrain" type="Node2D" parent="."]\n\n' + terrain
    text += '[node name="DecorMid" type="Node2D" parent="."]\n\n' + decor_nodes(decor, "mid", "DecorMid")
    text += '[node name="DecorFront" type="Node2D" parent="."]\nz_index = 1\n\n' + decor_nodes(decor, "front", "DecorFront")
    text += '[node name="Props" type="Node2D" parent="."]\n\n'
    for i, (pid, x, y) in enumerate(r.get("props", []), 1):
        text += f'[node name="Prop{i}" parent="Props" instance=ExtResource("7_prop")]\nposition = Vector2({x}, {y})\nprop_id = "{pid}"\n\n'
    for i, (nid, x, y) in enumerate(r.get("npcs", []), 1):
        text += f'[node name="Npc{i}" parent="Props" instance=ExtResource("11_npc")]\nposition = Vector2({x}, {y})\nnpc_id = "{nid}"\n\n'
    for i, (bx, by) in enumerate(r.get("barriers", []), 1):
        text += (f'[node name="Barrier{i}" type="Sprite2D" parent="."]\nposition = Vector2({bx}, {by})\n'
                 'texture = ExtResource("11_barrier")\nhframes = 7\ncentered = false\noffset = Vector2(-32, -80)\n'
                 'modulate = Color(0.85, 0.9, 1, 0.85)\nz_index = 2\n'
                 'script = ExtResource("10_fixture")\nloop = true\nfalls = true\nfps = 10.0\n\n')
    if r.get("shrine"):
        sx, sy = r["shrine"]
        text += (f'[node name="Shrine" type="Sprite2D" parent="."]\nposition = Vector2({sx}, {sy})\n'
                 'texture = ExtResource("9_shrine")\nhframes = 7\ncentered = false\noffset = Vector2(-24, -64)\n'
                 'script = ExtResource("10_fixture")\nlights = true\n\n')
    for i, (hx, hy, hw, hh) in enumerate(r.get("hazards", []), 1):
        text += (f'[node name="Hazard{i}" type="Area2D" parent="."]\nposition = Vector2({hx}, {hy})\n'
                 f'script = ExtResource("15_hazard")\nsize = Vector2({hw}, {hh})\n\n')
    if r.get("bell"):
        bx, by = r["bell"]
        text += f'[node name="Bell" type="Node2D" parent="."]\nposition = Vector2({bx}, {by})\nscript = ExtResource("14_bell")\n\n'
    text += '[node name="Spawns" type="Node2D" parent="."]\n\n'
    for i, (eid, x, y) in enumerate(r["spawns"], 1):
        text += f'[node name="Spawn{i}" type="Marker2D" parent="Spawns"]\nposition = Vector2({x}, {y})\nscript = ExtResource("5_spawn")\nenemy_id = "{eid}"\n\n'
    px, py = r["player"]
    dx, dy = r["door"]
    motes = MOTES.format(cx=width / 2, cy=height / 2, ex=width / 2, ey=height / 2, amount=int(36 * area))
    room_lights = r.get("lights", [])
    if room_lights == "auto":  # the candles the tracer found on the panel
        with open(os.path.join(ROOT, "assets", "levels", r["painting"] + ".lights.json")) as f:
            room_lights = [tuple(light) for light in json.load(f)]
        inserts = r.get("_x_inserts", [])
        room_lights = [(_map_x(x, inserts), y, tint, radius, energy, flicker)
                       for x, y, tint, radius, energy, flicker in room_lights]
    lights = light_nodes(thin_lights(room_lights), "Lights", "Light")
    text += f'''[node name="PlayerSpawn" type="Marker2D" parent="."]
position = Vector2({px}, {py})

[node name="Door" type="Area2D" parent="."]
position = Vector2({dx}, {dy})
collision_layer = 0
collision_mask = 2
script = ExtResource("4_door")

[node name="Shape" type="CollisionShape2D" parent="Door"]
shape = SubResource("door_shape")

[node name="Gate" type="Sprite2D" parent="Door"]
texture = ExtResource("8_gate")
hframes = 5

[node name="Glow" type="Sprite2D" parent="Door"]
visible = false
material = SubResource("add_mat")
scale = Vector2(1.6, 1.6)
texture = SubResource("glow_tex")

{weather}
{motes}[node name="Lights" type="Node2D" parent="."]

{lights}'''
    text = text.replace("load_steps=0", "load_steps=%d" % (text.count("[ext_resource") + text.count("[sub_resource")))
    path = os.path.join(ROOT, "scenes", "rooms", f"{name}.tscn")
    with open(path, "w") as f:
        f.write(text)
    print("wrote", os.path.relpath(path, ROOT))


ROOMS.update({name: expand_painted_room(name, room) if name in ROOM_EXPANSION_CUTS else deepcopy(room)
              for name, room in PAINTED.items()})

if __name__ == "__main__":
    for name, room in ROOMS.items():
        if "painting" in room:
            if not check_reach(name, room):
                raise SystemExit(f"room {name} has an unreachable mandatory route")
            _expand_panel(room["painting"], room["_x_inserts"])
        build(name, room)
