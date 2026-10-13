"""Tests for the game-pack tools (tools/packs, docs/GAME_PACKS.md): the strings a
pack lays over the engine's, the game a pack makes as the studio reads it, a new
game from the template, and the studio's builder pointed at one.

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


if __name__ == "__main__":
    unittest.main()
