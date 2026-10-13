"""tools/rooms/compose.py: rooms put together from several paintings (the studio's «Конструктор»)."""
import sys
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/rooms"))
import compose  # noqa: E402

PANEL = "graveyard_cross"  # any painted panel the game has


def entry(**over):
    e = {"live": False, "cells": [{"painting": PANEL, "col": 0, "row": 0}, {"painting": PANEL, "col": 1, "row": 0}],
         "ground": [[0, 600, 2560, 120]], "player": [40, 590], "door": [2500, 590],
         "spawns": [["cultist", 1200, 588]], "props": [["barrel", 900, 600]]}
    e.update(over)
    return e


class Stitch(unittest.TestCase):
    def test_a_seam_keeps_both_pictures_whole_away_from_it(self):
        rng = np.random.default_rng(3)
        left = rng.uniform(0, 255, (60, 300, 4)).astype(np.float32)
        right = rng.uniform(0, 255, (60, 300, 4)).astype(np.float32)
        joined = compose._join(left, right, seam=32)
        self.assertEqual(joined.shape, (60, 600, 4))
        np.testing.assert_array_equal(joined[:, :300 - 32], left[:, :300 - 32])
        np.testing.assert_array_equal(joined[:, 300 + 32:], right[:, 32:])

    def test_the_band_meets_its_neighbours_exactly(self):
        # the stitch bends each side's light toward the other, but not at its own edge
        rng = np.random.default_rng(5)
        a = rng.uniform(0, 255, (40, 64, 4)).astype(np.float32)
        b = a + 60.0
        band = compose._stitch(a, b, 16, 48)
        np.testing.assert_allclose(band[:, 0], a[:, 0], atol=1e-3)
        np.testing.assert_allclose(band[:, -1], b[:, -1], atol=1e-3)

    def test_rows_stack_like_columns(self):
        top = np.zeros((100, 50, 4), np.float32)
        bottom = np.full((100, 50, 4), 200, np.float32)
        out = compose._join_below(top, bottom, seam=16)
        self.assertEqual(out.shape, (200, 50, 4))
        np.testing.assert_array_equal(out[:84], top[:84])
        np.testing.assert_array_equal(out[116:], bottom[16:])


class Validate(unittest.TestCase):
    def refused(self, e, words):
        with self.assertRaises(SystemExit) as caught:
            compose.validate("test", e)
        self.assertIn(words, str(caught.exception))

    def test_a_good_room_passes(self):
        compose.validate("test", entry())

    def test_what_is_refused(self):
        self.refused(entry(cells=[]), "no cells")
        self.refused(entry(cells=[{"painting": PANEL, "col": 0, "row": 0}] * 2), "two cells")
        self.refused(entry(cells=[{"painting": PANEL, "col": 9, "row": 0}]), "outside")
        self.refused(entry(cells=[{"painting": "../secret", "col": 0, "row": 0}]), "no painting")
        self.refused(entry(cells=[{"painting": "nope_not_here", "col": 0, "row": 0}]), "no painting")
        self.refused(entry(ledges=[[2500, 10, 200, 14]]), "not inside")
        self.refused(entry(ramps=[[0, 0, 3000, 10]]), "leaves the room")
        self.refused(entry(door=None), "no door")
        self.refused(entry(spawns=[["no_such_enemy", 10, 10]]), "data/enemies/no_such_enemy")

    def test_the_room_table_is_the_grid(self):
        base = {"ambient": "x", "music": "graveyard", "spawns": [("old", 1, 1)], "painting": PANEL}
        room = compose.room_table("graveyard_cross", entry(cells=entry()["cells"] + [{"painting": PANEL, "col": 0, "row": 1}]), base)
        self.assertEqual((room["width"], room["height"]), (2560, 1440))
        self.assertEqual(room["painting_wide"], "composed/graveyard_cross")
        self.assertEqual(room["music"], "graveyard")       # the room's own atmosphere
        self.assertEqual(room["spawns"], [("cultist", 1200, 588)])  # and none of its old things
        self.assertNotIn("painting", room)
        self.assertEqual(room["void_kill_y"], 1440 - 30)


if __name__ == "__main__":
    unittest.main()
