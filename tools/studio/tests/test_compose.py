"""tools/rooms/compose.py: rooms put together from several paintings (the studio's «Конструктор»)."""
import sys
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/rooms"))
import compose  # noqa: E402
import front  # noqa: E402

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
        tone = min(compose.TONE, 150)   # how far each side's light is evened out
        np.testing.assert_array_equal(joined[:, :300 - tone], left[:, :300 - tone])
        np.testing.assert_array_equal(joined[:, 300 + tone:], right[:, tone:])

    def test_two_lights_meet_halfway_and_keep_their_own_away_from_the_seam(self):
        # a torch-lit vault beside a cold crypt: no line where they meet
        left = np.full((60, 800, 4), 60.0, np.float32)
        right = np.full((60, 800, 4), 120.0, np.float32)
        left[..., 3] = right[..., 3] = 255.0
        joined = compose._join(left, right, seam=32)
        meet = np.sqrt(68.0 * 128.0) - 8.0
        self.assertLess(abs(joined[30, 800 - 8, 0] - meet), 3.0)
        self.assertLess(abs(joined[30, 800 + 8, 0] - meet), 3.0)
        np.testing.assert_array_equal(joined[:, :800 - compose.TONE], left[:, :800 - compose.TONE])
        np.testing.assert_array_equal(joined[:, 800 + compose.TONE:], right[:, compose.TONE:])
        self.assertTrue((joined[..., 3] == 255.0).all())   # the light, never the alpha

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
        np.testing.assert_array_equal(out[:50], top[:50])
        np.testing.assert_array_equal(out[150:], bottom[50:])   # past the light evened out (TONE, ≤ half)


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
        self.assertNotIn("void_kill_y", room)   # the edge of the map: a floor may run down to it


class Crumbling(unittest.TestCase):
    """`crumbling_platforms`: written as a painted room's are, never counted on by the route."""

    def test_they_are_checked(self):
        compose.validate("t", entry(crumbling_platforms=[[300, 400, 80], [900, 300, 60, "timber"]]))
        for piece, words in (([2500, 400, 200], "not inside"), ([10, 720 * 1, 40], "not inside"),
                             ([10, 10, 0], "not inside"), ([10, 10, 40, "glass"], "not one of"),
                             ([10, 10], "not [x, y, w]"), (["a", 10, 40], "not [x, y, w]")):
            with self.assertRaises(SystemExit) as caught:
                compose.validate("t", entry(crumbling_platforms=[piece]))
            self.assertIn(words, str(caught.exception))

    def test_the_room_table_carries_them_as_generate_rooms_writes_them(self):
        room = compose.room_table(PANEL, entry(crumbling_platforms=[[300, 400, 80], [900, 300, 60, "timber"]]), {"painting": PANEL})
        self.assertEqual(room["crumbling_platforms"], [(300, 400, 80, "stone"), (900, 300, 60, "timber")])
        self.assertEqual(compose.room_table(PANEL, entry(), {"painting": PANEL})["crumbling_platforms"], [])

    def test_the_route_never_counts_on_them(self):
        import painted_rooms
        # two floors a gap apart, bridged only by a crumbling platform: the door is not reached
        gap = entry(ground=[[0, 600, 1000, 120], [1600, 600, 960, 120]], spawns=[], props=[],
                    crumbling_platforms=[[1000, 600, 600]])
        room = compose.room_table(PANEL, gap, {"painting": PANEL})
        self.assertNotIn((1000, 600, 600), painted_rooms._surfaces(room)[0])
        self.assertFalse(painted_rooms.check_reach("t", room))
        bridged = compose.room_table(PANEL, dict(gap, platforms=[[1000, 600, 600, 10]]), {"painting": PANEL})
        self.assertTrue(painted_rooms.check_reach("t", bridged))


class Hole(unittest.TestCase):
    def test_night_is_the_darkest_tenth(self):
        tile = np.zeros((10, 10, 4), np.float32)
        tile[..., :3] = np.arange(100, dtype=np.float32).reshape(10, 10)[..., None]
        tile[..., 3] = 255
        dark = compose.night([tile])
        self.assertLess(dark[0], 10)          # only the darkest few pixels
        self.assertEqual(dark[3], 255)

    def test_a_hole_runs_its_neighbour_on_into_the_dark(self):
        w, h = compose.CELL
        left = np.full((h, w, 4), 200, np.float32)
        dark = np.array([5, 5, 5, 255], np.float32)
        filled = compose.hole({(0, 0): left}, 1, 0, dark)
        np.testing.assert_allclose(filled[:, 0], left[:, -1], atol=1e-3)   # meets its neighbour
        np.testing.assert_allclose(filled[:, compose.HOLE_FADE + 10], np.broadcast_to(dark, (h, 4)), atol=1e-3)
        lone = compose.hole({}, 3, 3, dark)                                   # nobody beside it: night
        np.testing.assert_allclose(lone[0, 0], dark)


class Windows(unittest.TestCase):
    def test_far_windows_are_read_from_room_layers(self):
        far = compose.far_windows()
        self.assertIn(PANEL, far)
        self.assertTrue(all(isinstance(i, int) for i in far[PANEL]))

    def test_the_sky_is_farthest(self):
        self.assertLess(compose.window_depth(1), compose.window_depth(2))
        self.assertEqual(compose.window_depth(9), 1.16)

    def test_a_cell_brings_its_rooms_openings_moved_into_it(self):
        owned = {PANEL: (0.03, [(1, [(10, 10), (100, 10), (100, 60)])])}
        got = compose.windows(entry(), owned)
        self.assertEqual(len(got), 2)
        self.assertEqual(got[1]["points"][0], [1290, 10])     # the second cell, 1280 to the right
        self.assertTrue(got[0]["sky"])
        self.assertEqual(compose.depth_parallax(entry(), owned), 0.03)
        own = [{"points": [[0, 0], [50, 0], [50, 50]], "depth": 0.9, "sky": False}]
        self.assertEqual(compose.windows(entry(windows=own), owned)[0]["depth"], 0.9)  # hers win

    def test_windows_and_lights_are_checked(self):
        with self.assertRaises(SystemExit):
            compose.validate("t", entry(windows=[{"points": [[0, 0], [10, 0]], "depth": 0.8}]))
        with self.assertRaises(SystemExit):
            compose.validate("t", entry(windows=[{"points": [[0, 0], [10, 0], [9000, 5]], "depth": 0.8}]))
        with self.assertRaises(SystemExit):
            compose.validate("t", entry(lights=[[99999, 5, "#ffffff", 30, 0.5, 0.3]]))
        compose.validate("t", entry(windows=[{"points": [[0, 0], [10, 0], [10, 10]], "depth": 0.8, "sky": True}],
                                    lights=[[50, 50, "#ffb060", 36, 0.5, 0.3]]))


class Front(unittest.TestCase):
    PIECE = {"from": PANEL, "crop": [100, 100, 80, 60], "at": [200, 300], "depth": 1.5, "dark": 0.8, "cut": 70}

    def test_a_piece_is_its_crop_times_its_depth(self):
        image = front.bake(self.PIECE)
        pad = int(front.blur_of(self.PIECE) * 3 + 1)
        self.assertEqual(image.size, (120 + 2 * pad, 90 + 2 * pad))
        self.assertEqual(front.placed(self.PIECE), (260.0, 345.0))

    def test_its_edges_fade_so_no_box_shows(self):
        fade = front.edge_fade(40, 20, 0.2)
        self.assertLess(fade[0, 20], 0.1)
        self.assertLess(fade[10, 0], 0.1)
        self.assertEqual(fade[10, 20], 1.0)
        a = np.asarray(front.bake(dict(self.PIECE, cut=255, blur=0)))[..., 3]
        self.assertLess(a[0].max(), 40)            # the crop's top row is nearly gone
        self.assertGreater(a[a.shape[0] // 2].max(), 200)

    def test_darkness_and_the_key(self):
        a = np.asarray(front.bake(dict(self.PIECE, dark=1.0, cut=255, blur=0)))
        self.assertEqual(a[..., :3][a[..., 3] > 0].max(), 0)    # a silhouette
        none = np.asarray(front.bake(dict(self.PIECE, cut=-100, blur=0)))
        self.assertEqual(none[..., 3].max(), 0)                  # nothing is darker than that

    def test_what_is_refused(self):
        def refused(piece, words):
            with self.assertRaises(SystemExit) as caught:
                front.validate("t", [dict(self.PIECE, **piece)], 1280, 720)
            self.assertIn(words, str(caught.exception))
        front.validate("t", [self.PIECE], 1280, 720)
        refused({"from": "../x"}, "no picture")
        refused({"crop": [1200, 0, 200, 10]}, "not inside")
        refused({"depth": 3}, "depth")
        refused({"at": [5000, 0]}, "outside")
        refused({"key": "chroma"}, "key")
        refused({"feather": 0.9}, "feather")
        with self.assertRaises(SystemExit):
            front.validate("t", [self.PIECE] * (front.MAX_PIECES + 1), 1280, 720)

    def test_a_composed_room_carries_its_layers(self):
        room = compose.room_table(PANEL, entry(front=[self.PIECE]), {"painting": PANEL}, {PANEL: (0.03, [(1, [(0, 0), (9, 0), (9, 9)])])})
        self.assertEqual(room["front"], [self.PIECE])
        self.assertEqual(len(room["windows"]), 2)
        self.assertEqual(room["depth_parallax"], 0.03)


if __name__ == "__main__":
    unittest.main()
