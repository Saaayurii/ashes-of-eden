"""Tests for the studio's Python half: the data it reads about the game, and
the guard on what the local server may write.

    python3 -m unittest discover -s tools/studio/tests
"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

STUDIO = Path(__file__).resolve().parents[1]
ROOT = STUDIO.parents[1]
sys.path.insert(0, str(STUDIO))

import build_data  # noqa: E402
import serve  # noqa: E402


class LivingBackdrops(unittest.TestCase):
    def test_every_rule_has_its_picture_and_the_kinds_their_defaults(self):
        life = build_data.life(ROOT)
        rules = json.loads((ROOT / "data/backdrops.json").read_text(encoding="utf-8"))["rooms"]
        pictures = {p["key"]: p for p in life["pictures"]}
        for key in rules:
            self.assertIn(key, pictures, f"the studio cannot show the picture of rule {key}")
            self.assertTrue(pictures[key]["has_rule"])
        for key in ("church", "preacher_nave"):   # painted in code, not in the scene
            self.assertIn("interior", pictures[key]["res"])
        self.assertEqual(pictures["graveyard_cross"]["res"], "res://assets/levels/graveyard_cross_wide.png")
        self.assertEqual(set(life["kinds"]), {"falls", "water", "sway", "glow", "lava", "haze", "stars", "pulse"})
        self.assertEqual(life["kinds"]["glow"], {"index": 3, "strength": 0.12, "speed": 0.8})
        self.assertEqual(life["max_zones"], 24)

    def test_platform_pieces_know_where_they_lie(self):
        tiles = build_data.tiles(ROOT)
        pieces = {p["name"]: p for p in tiles["pieces"]}
        self.assertEqual(tiles["overlap"], 3)
        self.assertIn("practice_yard", tiles["played"])
        self.assertIn("practice_yard", pieces["ground_2"]["uses"])
        for p in pieces.values():
            self.assertTrue((ROOT / p["url"]).exists(), p["name"])



class SpriteFrames(unittest.TestCase):
    def test_hero_frames_parse_with_cells_and_durations(self):
        text = (ROOT / "assets/sprites/elian_frames.tres").read_text(encoding="utf-8")
        anims = {name: (fps, loop, frames) for name, fps, loop, frames in build_data.parse_sprite_frames(text)}
        for needed in ("idle", "run", "attack", "death"):  # player.gd relies on them
            self.assertIn(needed, anims)
        fps, loop, frames = anims["idle"]
        self.assertTrue(loop)
        self.assertTrue(all(f[1][2:] == (128, 64) for f in frames))
        self.assertTrue(all(f[2] > 0 for f in frames))

    def test_hero_project_knows_its_generator(self):
        hero = build_data.hero(ROOT)
        self.assertEqual(hero["origin"]["generator"], build_data.HERO_GENERATOR)
        self.assertEqual(hero["settings"]["cellW"], 128)
        self.assertTrue(all(a["file"].startswith("res://assets/sprites/") for a in hero["animations"]))


class Rooms(unittest.TestCase):
    def test_graveyard_layers(self):
        room = build_data.room_project(ROOT, ROOT / "scenes/rooms/graveyard.tscn")
        by_name = {l["name"]: l for l in room["layers"]}
        self.assertEqual(by_name["Parallax"]["scroll"], [0.1, 0.1])
        self.assertIn("DecorFront", by_name)
        self.assertEqual(room["origin"]["generator"], build_data.ROOM_GENERATOR)
        for res in room["images"]:
            self.assertTrue((ROOT / res.removeprefix("res://")).exists(), res)

    def test_take_base(self):
        self.assertEqual(build_data.take_base("hit_2"), "hit")
        self.assertEqual(build_data.take_base("hit_crit"), "hit_crit")
        self.assertEqual(build_data.take_base("block_11"), "block")


class Build(unittest.TestCase):
    def test_everything_is_written_and_consistent(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            counts = build_data.build(ROOT, out, "https://example/")
            meta = json.loads((out / "meta.json").read_text(encoding="utf-8"))
            self.assertEqual(meta["assetBase"], "https://example/")
            self.assertIn("assets/sprites/elian_frames.tres", meta["generated"])
            self.assertIn("assets/audio/sfx/bell.wav", meta["generated"])
            self.assertEqual(counts["cutscenes"], len(list((ROOT / "data/cutscenes").glob("*.json"))))
            for listing in ("list.json", "rooms_list.json"):
                for rel in json.loads((out / listing).read_text(encoding="utf-8")):
                    self.assertTrue((out / rel).exists(), rel)
            story = json.loads((out / "cutscenes.json").read_text(encoding="utf-8"))
            self.assertIn("knight_arrival", story["played_in"])
            self.assertIn("village_night", story["room_order"])
            audio = json.loads((out / "audio.json").read_text(encoding="utf-8"))
            self.assertTrue(all(not t["url"].startswith(("http", "/")) for e in audio for t in e["takes"]))


class Enemies(unittest.TestCase):
    def test_wizard_bases(self):
        listed = {e["id"]: e for e in build_data.enemies(ROOT, build_data.load_strings(ROOT))}
        self.assertEqual(listed["cultist"]["behaviour"], "walker")
        self.assertIn("melee", listed["cultist"]["attacks"])
        self.assertTrue(listed["cultist"]["name"]["ru"])
        self.assertEqual(listed["elite_possessed"]["extends"], "possessed_villager")


class PreviewPage(unittest.TestCase):
    def test_own_pack_no_saves_and_arguments(self):
        import make_preview_page
        html = '<body><script>const GAME = new Engine({"args":[],"executable":"index","fileSizes":{"index.pck":10,"index.wasm":20}});</script></body>'
        page = make_preview_page.preview_page(html, 7, 99)
        self.assertIn('"mainPack": "preview/7.pck"', page)
        self.assertIn('"persistentPaths": []', page)
        self.assertIn('"preview/7.pck": 99', page)
        self.assertNotIn('"index.pck"', page)
        self.assertIn("'--studio-preview'", page)
        self.assertIn("'practice'", page)
        self.assertIn("Превью отправки #7", page)

    def test_live_page_is_the_main_pack_in_studio_live(self):
        import make_preview_page
        html = ('<body><script>const canFull = !!(root.requestFullscreen || root.webkitRequestFullscreen);'
                'const GAME = new Engine({"args":[],"executable":"index","fileSizes":{"index.pck":10}});</script></body>')
        page = make_preview_page.live_page(html)
        self.assertIn("const canFull = false;", page)
        self.assertIn('"args": ["--", "--studio-live"]', page)
        self.assertIn('"persistentPaths": []', page)
        self.assertIn('"index.pck": 10', page)
        self.assertNotIn("mainPack", page)


class ServeGuard(unittest.TestCase):
    def test_allowed(self):
        for ok in ("assets/sprites/archer_idle.png", "data/cutscenes/x.json", "data/enemies/archer.json", "localization/strings.csv",
                   "tools/studio/projects/chars/archer.json"):
            self.assertEqual(serve.safe_path(ok), (ROOT / ok).resolve())

    def test_refused(self):
        for bad in ("scripts/player/player.gd", "../outside.txt", "assets/../scripts/x.gd",
                    "project.godot", "tools/studio/serve.py", "/etc/passwd"):
            with self.assertRaises(ValueError, msg=bad):
                serve.safe_path(bad)


if __name__ == "__main__":
    unittest.main()
