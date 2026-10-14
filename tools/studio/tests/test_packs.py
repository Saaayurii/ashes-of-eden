"""Tests for the game-pack tools (tools/packs, docs/GAME_PACKS.md): the strings a
pack lays over the engine's, the game a pack makes as the studio reads it, a new
game from the template, the studio's builder pointed at one, and the rooms a
pack makes from the engine's (generate_rooms.py --pack).

    python3 -m unittest discover -s tools/studio/tests
"""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "packs"))
sys.path.insert(0, str(ROOT / "tools" / "studio"))

import apply_pack  # noqa: E402
import build_data  # noqa: E402
import game_view  # noqa: E402

sys.path.insert(0, str(ROOT / "tools" / "rooms"))
_argv, sys.argv = sys.argv, [sys.argv[0]]
import generate_rooms  # noqa: E402
import painted_rooms  # noqa: E402
sys.argv = _argv


class Strings(unittest.TestCase):
    ENGINE = 'keys,en,ru\nGAME_TITLE,"Ashes of Eden","Пепел Эдема"\nOK,"OK","ОК"\n'

    def test_pack_key_wins_and_new_keys_follow(self):
        out = apply_pack.merge_strings(self.ENGINE, 'keys,en,ru\nGAME_TITLE,"Saints","Святые"\nNEW,"New",""\n')
        self.assertEqual(out, 'keys,en,ru\nGAME_TITLE,"Saints","Святые"\nOK,"OK","ОК"\nNEW,"New",""\n')

    def test_empty_cell_keeps_the_engine_text(self):
        out = apply_pack.merge_strings(self.ENGINE, 'keys,en\nGAME_TITLE,"Saints"\n')
        self.assertIn('GAME_TITLE,"Saints","Пепел Эдема"\n', out)

    def test_twice_is_once(self):
        pack = 'keys,en,ru\nGAME_TITLE,"Saints","Святые"\n'
        once = apply_pack.merge_strings(self.ENGINE, pack)
        self.assertEqual(apply_pack.merge_strings(self.ENGINE, pack), once)

    def test_unknown_locale_is_refused(self):
        with self.assertRaises(SystemExit):
            apply_pack.merge_strings(self.ENGINE, "keys,de\nX,\"x\"\n")

    def test_project_takes_the_pack_name(self):
        text = '[application]\nconfig/name="Ashes of Eden"\nconfig/version="0.9.0"\n'
        self.assertEqual(apply_pack.set_project(text, "Saints", "0.1.0"),
                         '[application]\nconfig/name="Saints"\nconfig/version="0.1.0"\n')


class View(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.engine, self.pack = self.tmp / "data", self.tmp / "content" / "data"
        for rel, doc in {
            "game.json": {"id": "ashes", "rooms": ["a"]},
            "gore.json": {"bodies": {"elian": {"limbs": 0}}, "materials": {"blood": {"drops": 4}}},
            "enemies/ghoul.json": {"id": "ghoul", "hp": 10},
            "enemies/imp.json": {"id": "imp", "hp": 5},
            "dialogues/crone.json": {"id": "crone"},
        }.items():
            (self.engine / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.engine / rel).write_text(json.dumps(doc))
        for rel, doc in {
            "game.json": {"id": "saints", "inherit": ["enemies"], "exclude": {"enemies": ["imp"]}},
            "gore.json": {"materials": {"blood": {"drops": 9}}},
            "enemies/ghoul.json": {"id": "ghoul", "hp": 30},
            "dialogues/nun.json": {"id": "nun"},
        }.items():
            (self.pack / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.pack / rel).write_text(json.dumps(doc))

    def test_the_game_a_pack_makes(self):
        game = json.loads((self.pack / "game.json").read_text())
        data = game_view.merged_data(self.engine, self.pack, game)
        self.assertEqual(data["game.json"], game, "game.json is the pack's alone")
        self.assertEqual(data["gore.json"], {"bodies": {"elian": {"limbs": 0}}, "materials": {"blood": {"drops": 9}}})
        self.assertEqual(data["enemies/ghoul.json"]["hp"], 30)
        self.assertNotIn("enemies/imp.json", data, "excluded")
        self.assertNotIn("dialogues/crone.json", data, "dialogues are not inherited")
        self.assertIn("dialogues/nun.json", data)

    def test_view_links_everything_but_data(self):
        (self.tmp / "assets").mkdir()
        view = game_view.game_view(self.tmp, self.tmp.parent / (self.tmp.name + "-view"))
        self.assertTrue((view / "assets").is_symlink())
        self.assertFalse((view / "data").is_symlink())
        self.assertEqual(json.loads((view / "data/game.json").read_text())["id"], "saints")
        self.assertIsNone(game_view.game_view(self.tmp / "content"), "no pack inside a pack")


class NewGame(unittest.TestCase):
    def test_template_fills_and_studio_reads_it(self):
        out = Path(tempfile.mkdtemp()) / "saints-of-rust"
        subprocess.run([sys.executable, str(ROOT / "tools/packs/new_game.py"), str(out), "--name", "Saints of Rust"],
                       check=True, capture_output=True)
        game = json.loads((out / "data/game.json").read_text(encoding="utf-8"))
        self.assertEqual((game["id"], game["name"]), ("saints_of_rust", "Saints of Rust"))
        self.assertEqual(game["engine"], apply_pack.engine_version())
        leftovers = [p for p in out.rglob("*") if p.is_file() and "__" in p.read_text(encoding="utf-8", errors="ignore").replace("__init__", "")
                     and any(k in p.read_text(encoding="utf-8", errors="ignore") for k in ("__ID__", "__KEY__", "__NAME__", "__ENGINE"))]
        self.assertEqual(leftovers, [])
        for res in game["rooms"] + [game["practice_room"]]:
            self.assertTrue(build_data.res_to_path(ROOT, res).exists(), res)


class PackRooms(unittest.TestCase):
    """A pack's rooms.json entry: an engine room's ground under its own story."""

    def test_takes_the_ground_and_leaves_the_story(self):
        base, room = generate_rooms.pack_room("shallows", {"base": "swamp_moon", "weather": "bubbles",
                                                           "spawns": [["shade", 700, 300]]})
        engine = generate_rooms.ROOMS["swamp_moon"]
        self.assertEqual(base, "swamp_moon")
        self.assertEqual((room["width"], room["height"], room["door"]), (engine["width"], engine["height"], engine["door"]))
        self.assertEqual(room["spawns"], [("shade", 700, 300)])
        self.assertEqual((room["weather"], room["props"], room["npcs"], room["intro_cutscene"]), ("bubbles", [], [], ""))
        self.assertTrue(painted_rooms.check_reach("swamp_moon", room))

    def test_spawns_left_out_are_the_base_rooms(self):
        _, room = generate_rooms.pack_room("again", {"base": "catacombs_2"})
        self.assertEqual(room["spawns"], generate_rooms.ROOMS["catacombs_2"]["spawns"])

    def test_refuses_what_it_cannot_build(self):
        for name, entry in [("x", {"base": "nowhere"}), ("swamp_red", {"base": "swamp_moon"}),
                            ("Bad Name", {"base": "swamp_moon"}), ("x", {"base": "swamp_moon", "weather": "snow"}),
                            ("x", {"base": "swamp_moon", "spawns": [["no_such_enemy", 1, 2]]})]:
            with self.assertRaises(SystemExit, msg=f"{name} {entry}"):
                generate_rooms.pack_room(name, entry)

    def test_the_studio_adds_beside_the_table(self):
        _, room = generate_rooms.pack_room("shallows", {"base": "swamp_moon", "spawns": [["shade", 700, 300]]})
        generate_rooms.studio_extra("shallows", room, {"spawns": [["raven", 900, 200]], "music": "graveyard"})
        self.assertEqual((room["spawns"], room["music"]), ([("shade", 700, 300), ("raven", 900, 200)], "graveyard"))
        with self.assertRaises(SystemExit):
            generate_rooms.studio_extra("shallows", room, {"spawns": [["nobody", 1, 2]]})

    def test_water_weather(self):
        for kind in ("drips", "bubbles"):
            self.assertIn('[node name="Weather"', generate_rooms.WEATHER[kind])

    def test_scene_names_its_base(self):
        path = Path(tempfile.mkdtemp()) / "room.tscn"
        path.write_text('[node name="Room" type="Node2D"]\nscript = ExtResource("1_room")\nwidth = 1600\n', encoding="utf-8")
        generate_rooms._mark_base(str(path), "swamp_moon")
        self.assertIn('script = ExtResource("1_room")\nbase_room = "swamp_moon"\n', path.read_text(encoding="utf-8"))

    def test_flyers_come_from_the_data(self):
        for file in (ROOT / "data/enemies").glob("*.json"):
            flies = json.loads(file.read_text(encoding="utf-8")).get("behaviour") == "flyer"
            self.assertEqual(file.stem in painted_rooms.FLYERS, flies or file.stem == "ophanim", file.stem)


if __name__ == "__main__":
    unittest.main()
