"""The art studio's edits of generated pictures (tools/art/studio_overrides.py):
a generator lays her edit over its own picture and keeps doing so, says when
the picture under it changed, refuses one that no longer fits, and `settle`
brings in line a picture no generator writes. One round trip per kind of
generator: a prop, a room's painting, the bestiary's strips.

    python3 -m unittest discover -s tools/studio/tests
"""
import json
import os
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "art"))

try:
    from PIL import Image
except ImportError:  # the studio's Node half runs without Pillow
    Image = None

import studio_overrides as so  # noqa: E402

OVR = ROOT / "tools" / "studio" / "overrides"


def git(*a):
    return subprocess.run(["git", *a], cwd=ROOT, capture_output=True, text=True)


@unittest.skipIf(Image is None, "needs Pillow")
class Overrides(unittest.TestCase):
    """Every test writes an override, runs the real generator, and puts back
    exactly what it touched: the generator's outputs and the overrides folder."""

    def setUp(self):
        self.had_dir = OVR.exists()
        self.saved = {p.relative_to(OVR): p.read_bytes() for p in OVR.rglob("*") if p.is_file()} if self.had_dir else {}
        self.touched = []

    def tearDown(self):
        if OVR.exists():
            shutil.rmtree(OVR)
        for rel, data in self.saved.items():
            (OVR / rel).parent.mkdir(parents=True, exist_ok=True)
            (OVR / rel).write_bytes(data)
        if self.touched:
            git("checkout", "--", *self.touched)
        so._cache = None

    # an edit: the picture as the game has it, a block of loud red at (x, y)
    def override(self, rel, x=2, y=2, w=4, h=4, base=None, size=None):
        pic = Image.open(ROOT / rel).convert("RGBA")
        if size:
            pic = pic.resize(size)
        mask = Image.new("L", pic.size, 0)
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                pic.putpixel((xx, yy), (230, 20, 30, 255))
                mask.putpixel((xx, yy), 255)
        edit_path, mask_path = so.files_of(rel)
        os.makedirs(os.path.dirname(edit_path), exist_ok=True)
        pic.save(edit_path)
        mask.save(mask_path)
        data = json.loads((OVR / "overrides.json").read_text()) if (OVR / "overrides.json").exists() else {}
        data[rel] = {"size": list(pic.size), "base": base, "by": "test", "at": "2026-10-07"}
        so.save_manifest(data)
        so._cache = None

    def run_gen(self, script, *args, record=True):
        env = dict(os.environ, STUDIO_OVERRIDES_RECORD="1" if record else "")
        return subprocess.run([sys.executable, script, *args], cwd=ROOT, env=env, capture_output=True, text=True)

    def red_at(self, rel, x, y):
        return Image.open(ROOT / rel).convert("RGBA").getpixel((x, y)) == (230, 20, 30, 255)

    def manifest(self):
        return json.loads((OVR / "overrides.json").read_text())

    def test_a_prop_keeps_her_edit_through_regeneration(self):
        rel = "assets/props/altar_book.png"
        self.touched.append(rel)
        before = Image.open(ROOT / rel).convert("RGBA")
        self.override(rel)
        r = self.run_gen("tools/art/make_altar_book.py")
        self.assertEqual(r.returncode, 0, r.stderr)
        after = Image.open(ROOT / rel).convert("RGBA")
        self.assertTrue(self.red_at(rel, 3, 3), "her pixels are in the output")
        self.assertEqual(after.getpixel((20, 20)), before.getpixel((20, 20)), "the rest is the generator's")
        base = self.manifest()[rel]["base"]
        self.assertTrue(base, "the robot's run records the picture she drew on")
        first = so.pixel_hash(after)
        self.assertEqual(self.run_gen("tools/art/make_altar_book.py", record=False).returncode, 0)
        self.assertEqual(so.pixel_hash(Image.open(ROOT / rel)), first, "regenerating is not a diff (what check_generators asks)")
        self.assertEqual(self.manifest()[rel]["base"], base, "and a plain run writes nothing into the manifest")

    def test_a_changed_base_is_said_and_marked(self):
        rel = "assets/props/blood_altar.png"
        self.touched.append(rel)
        self.override(rel, base="0123456789abcdef")
        r = self.run_gen("tools/art/make_blood_altar.py")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("changed since it was drawn", r.stderr)
        self.assertTrue(self.manifest()[rel].get("stale"))
        self.assertTrue(self.red_at(rel, 3, 3), "it still applies: the size is the same")

    def test_an_edit_that_no_longer_fits_fails_naming_it(self):
        rel = "assets/props/altar_book.png"
        self.touched.append(rel)
        with Image.open(ROOT / rel) as im:
            w, h = im.size
        self.override(rel, size=(w + 8, h))
        r = self.run_gen("tools/art/make_altar_book.py")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("studio override assets/props/altar_book.png", r.stderr + r.stdout)
        self.assertIn("redo the edit", r.stderr + r.stdout)

    def test_settle_brings_in_a_picture_no_generator_writes(self):
        rel = "assets/sprites/elian_idle.png"   # in the bestiary's folder, written by nobody
        self.touched.append(rel)
        self.override(rel, x=60, y=30, w=2, h=2)
        self.assertEqual(so.settle(), [rel])
        self.assertTrue(self.red_at(rel, 60, 30))
        so._cache = None
        self.assertEqual(so.settle(), [], "settled once, nothing more to do")

    def test_a_rooms_painting_keeps_her_repaint(self):
        rel = "assets/levels/graveyard_cross_wide.png"
        self.touched += ["assets/levels", "scenes/rooms"]
        self.override(rel, x=100, y=100, w=6, h=3)
        r = self.run_gen("tools/rooms/generate_rooms.py", "graveyard_cross")
        self.assertEqual(r.returncode, 0, r.stderr[-2000:])
        self.assertTrue(self.red_at(rel, 103, 101))

    def test_the_bestiary_keeps_her_touch_up(self):
        rel = "assets/sprites/cultist_v2_idle.png"
        self.touched += ["assets/sprites", "assets/portraits", "data/enemy_archetypes/tree.json"]
        self.override(rel, x=30, y=40, w=3, h=3)
        r = self.run_gen("tools/art/build_bestiary_assets.py")
        self.assertEqual(r.returncode, 0, r.stderr[-2000:])
        self.assertTrue(self.red_at(rel, 31, 41))

    def test_every_generator_that_writes_pictures_honours_edits(self):
        # the generators of tools/check_generators.py that write PNGs, minus those that write none
        for name, (script, _paths) in so.owners().items():
            if name in so.OVERRIDABLE:
                self.assertIn("patched(", (ROOT / script).read_text(), "%s (%s) must pass its pictures through patched()" % (name, script))


if __name__ == "__main__":
    unittest.main()
