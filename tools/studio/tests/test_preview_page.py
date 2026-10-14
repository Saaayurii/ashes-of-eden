"""The studio's sandbox and preview pages (tools/studio/make_preview_page.py)
keep the engine and the pack in Cache Storage under the hash of their bytes:
the page names each file with the hash it has now, so a changed file is a new
name and an unchanged one is never fetched twice.

    python3 -m unittest discover -s tools/studio/tests
"""
import hashlib
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "studio"))

import make_preview_page as mp  # noqa: E402

PAGE = ('<!DOCTYPE html><html><head><title>t</title></head><body><script>'
        'const canFull = true; const engine = new Engine({"executable": "index", '
        '"fileSizes": {"index.pck": 3, "index.wasm": 4}});</script></body></html>')


def kept(page):
    return json.loads(re.search(r"const KEEP = (\{.*?\}), plain", page)[1])


class KeepTest(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        (self.dir / "index.html").write_text(PAGE, encoding="utf-8")
        (self.dir / "index.wasm").write_bytes(b"wasm")
        (self.dir / "index.pck").write_bytes(b"pck")
        (self.dir / "preview").mkdir()
        (self.dir / "preview" / "7.pck").write_bytes(b"pr pack")

    def run_tool(self, *args):
        return subprocess.run([sys.executable, str(ROOT / "tools/studio/make_preview_page.py"), *args],
                              check=True, capture_output=True, text=True).stdout

    def test_live_page_keeps_the_engine_and_the_pack_by_their_hash(self):
        page = self.run_tool("--live", str(self.dir / "index.html"))
        self.assertEqual(kept(page), {"index.wasm": hashlib.sha256(b"wasm").hexdigest()[:16],
                                      "index.pck": hashlib.sha256(b"pck").hexdigest()[:16]})
        self.assertLess(page.index("const KEEP"), page.index("new Engine"), "in place before the engine asks for them")
        self.assertIn('"--studio-live"', page)

    def test_a_changed_pack_is_a_new_name(self):
        before = kept(self.run_tool("--live", str(self.dir / "index.html")))
        (self.dir / "index.pck").write_bytes(b"pck, changed")
        after = kept(self.run_tool("--live", str(self.dir / "index.html")))
        self.assertEqual(before["index.wasm"], after["index.wasm"])
        self.assertNotEqual(before["index.pck"], after["index.pck"])

    def test_a_preview_keeps_the_shared_engine_and_its_own_pack(self):
        page = self.run_tool(str(self.dir / "index.html"), "7", str(self.dir / "preview" / "7.pck"))
        self.assertEqual(set(kept(page)), {"index.wasm", "preview/7.pck"})
        self.assertIn('"mainPack": "preview/7.pck"', page)

    def test_without_files_nothing_is_kept(self):
        self.assertNotIn("const KEEP", mp.live_page(PAGE))


if __name__ == "__main__":
    unittest.main()
