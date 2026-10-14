"""The studio's «Текстуры» as the room generator lays them: tools/rooms/studio_textures.py.

    python3 -m unittest discover -s tools/studio/tests
"""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/rooms"))

import studio_textures as st  # noqa: E402

SCENE = """[gd_scene format=3 uid="uid://x"]

[ext_resource type="Script" path="res://scripts/rooms/room.gd" id="1_room"]
[ext_resource type="Texture2D" path="res://assets/decor/tombstone_3.png" id="2_tomb"]

[sub_resource type="RectangleShape2D" id="shape_1"]
size = Vector2(10, 10)

[node name="Room" type="Node2D"]
script = ExtResource("1_room")

[node name="DecorMid" type="Node2D" parent="."]

[node name="tomb_1" type="Sprite2D" parent="DecorMid"]
position = Vector2(100, 200)
texture = ExtResource("2_tomb")

[node name="Geometry" type="StaticBody2D" parent="."]

[node name="Floor" type="CollisionShape2D" parent="Geometry"]
shape = SubResource("shape_1")

[node name="Props" type="Node2D" parent="."]
"""
TOMB = "decor/tombstone_3.png"


def refused(entry):
    try:
        st.validate("room", entry)
    except SystemExit as err:
        return str(err)
    return ""


class Validate(unittest.TestCase):
    def test_a_full_entry_passes(self):
        self.assertEqual(refused({"textures": [{
            "tex": TOMB, "at": [10, 20], "scale": [1.5, 0.5], "rot": -12, "flip_h": True, "flip_v": False,
            "layer": "top", "z": 2, "tint": "#c8b8ff", "alpha": 0.5, "blend": "add",
            "region": [0, 0, 300, 40], "repeat": "tile", "filter": "pixel", "name": "angel"}],
            "retouch": {"DecorMid/tomb_1": {"was": TOMB, "at": [1, 2], "hidden": True}}}), "")

    def test_what_is_refused(self):
        cases = [
            ({"textures": [{"at": [0, 0]}]}, "tex is missing"),
            ({"textures": [{"tex": TOMB}]}, "at is missing"),
            ({"textures": [{"tex": "../secret.png", "at": [0, 0]}]}, "must be a .png"),
            ({"textures": [{"tex": "scripts/x.png", "at": [0, 0]}]}, "must be a .png"),
            ({"textures": [{"tex": "decor/nothing_here.png", "at": [0, 0]}]}, "no picture at"),
            ({"textures": [{"tex": TOMB, "at": [0, 0], "scale": [0, 1]}]}, "scale is"),
            ({"textures": [{"tex": TOMB, "at": [0, 0], "rot": 400}]}, "rot is"),
            ({"textures": [{"tex": TOMB, "at": [0, 0], "layer": "sky"}]}, "layer is"),
            ({"textures": [{"tex": TOMB, "at": [0, 0], "tint": "red"}]}, "tint is"),
            ({"textures": [{"tex": TOMB, "at": [0, 0], "alpha": 2}]}, "alpha is"),
            ({"textures": [{"tex": TOMB, "at": [0, 0], "blend": "screen"}]}, "blend is"),
            ({"textures": [{"tex": TOMB, "at": [0, 0], "region": [0, 0, 0, 5]}]}, "region is"),
            ({"textures": [{"tex": TOMB, "at": [0, 0], "z": 1.5}]}, "z is"),
            ({"textures": [{"tex": TOMB, "at": [0, 0], "wobble": 1}]}, "unknown key"),
            ({"retouch": {"DecorMid/tomb_1": {"layer": "top"}}}, "unknown key"),
            ({"retouch": {"../x": {}}}, "not a node path"),
            ({"textures": [{"tex": TOMB, "at": [0, 0]}] * (st.MAX_TEXTURES + 1)}, "at most"),
        ]
        for entry, why in cases:
            self.assertIn(why, refused(entry), entry)


class Apply(unittest.TestCase):
    def test_nothing_to_do_leaves_the_scene_alone(self):
        self.assertEqual(st.apply(SCENE, None), (SCENE, []))
        self.assertEqual(st.apply(SCENE, {"textures": [], "retouch": {}}), (SCENE, []))

    def test_textures_land_in_their_layers_with_what_they_need(self):
        text, warnings = st.apply(SCENE, {"textures": [
            {"tex": TOMB, "at": [5, 6], "layer": "back"},
            {"tex": "decor/studio/new.png", "at": [7, 8], "rot": 90, "blend": "add", "repeat": "tile",
             "region": [0, 0, 64, 8]},
            {"tex": TOMB, "at": [1, 1], "layer": "top", "blend": "mul"}]})
        self.assertEqual(warnings, [])
        # one new picture, after the scene's own; the old one reused
        self.assertEqual(text.count("[ext_resource"), 3)
        self.assertLess(text.index('id="2_tomb"'), text.index('id="studio_tex_1"'))
        self.assertLess(text.index('id="studio_tex_1"'), text.index("[sub_resource"))
        # blend materials among the sub-resources, before the first node
        self.assertLess(text.index('id="studio_blend_add"'), text.index("[node "))
        self.assertIn("blend_mode = 1", text)
        self.assertIn("blend_mode = 3", text)
        # back behind the terrain, mid before the props, top last
        self.assertLess(text.index('name="StudioBack"'), text.index('name="Geometry"'))
        self.assertLess(text.index('name="StudioMid"'), text.index('name="Props"'))
        self.assertGreater(text.index('name="StudioTop"'), text.index('name="Props"'))
        self.assertIn('z_index = 3', text)
        mid = text[text.index('[node name="Tex2"'):]
        self.assertIn('texture = ExtResource("studio_tex_1")', mid)
        self.assertIn("rotation = 1.570796", mid)
        self.assertIn('material = SubResource("studio_blend_add")', mid)
        self.assertIn("texture_repeat = 2", mid)
        self.assertIn("region_rect = Rect2(0, 0, 64, 8)", mid)
        self.assertIn('texture = ExtResource("2_tomb")', text[text.index('[node name="Tex1"'):])

    def test_a_retouch_rewrites_the_node(self):
        text, warnings = st.apply(SCENE, {"retouch": {"DecorMid/tomb_1": {
            "was": TOMB, "at": [150, 210], "scale": [1, 1.4], "hidden": True}}})
        self.assertEqual(warnings, [])
        block = text[text.index('[node name="tomb_1"'):text.index('[node name="Geometry"')]
        self.assertIn("position = Vector2(150, 210)", block)
        self.assertNotIn("Vector2(100, 200)", block)
        self.assertIn("scale = Vector2(1, 1.4)", block)
        self.assertIn("visible = false", block)
        self.assertIn('texture = ExtResource("2_tomb")', block)

    def test_a_retouch_puts_defaults_back_too(self):
        text, _ = st.apply(SCENE, {"retouch": {"DecorMid/tomb_1": {"rot": 0, "scale": [1, 1], "hidden": False}}})
        block = text[text.index('[node name="tomb_1"'):]
        self.assertIn("rotation = 0.0", block)
        self.assertIn("scale = Vector2(1, 1)", block)
        self.assertIn("visible = true", block)

    def test_a_retouch_that_no_longer_fits_is_left_off(self):
        for retouch, why in (({"DecorMid/gone": {"at": [0, 0]}}, "no such node"),
                             ({"Geometry/Floor": {"at": [0, 0]}}, "not a picture"),
                             ({"DecorMid/tomb_1": {"was": "decor/other.png", "at": [0, 0]}}, "the generator lays")):
            text, warnings = st.apply(SCENE, {"retouch": retouch})
            self.assertEqual(text, SCENE)
            self.assertEqual(len(warnings), 1)
            self.assertIn(why, warnings[0])


if __name__ == "__main__":
    unittest.main()
