"""split_pack.py: the parts put back together are the pack, and the page says where they are.

    python3 -m unittest discover -s tools/web
"""
import json
import os
import re
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import split_pack  # noqa: E402

PAGE = '<script>\n\t\tconst GAME = new Engine({"executable":"index"});\n\t\tconst PACK_PARTS = null;\n</script>'


def manifest(page):
    return json.loads(re.search(r"const PACK_PARTS = (\{.*\});", page)[1])


class SplitPack(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.page = os.path.join(self.dir.name, "index.html")
        with open(self.page, "w") as out:
            out.write(PAGE)

    def tearDown(self):
        self.dir.cleanup()

    def pack(self, rel, size):
        path = os.path.join(self.dir.name, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.data = bytes((i * 7) % 251 for i in range(size))
        with open(path, "wb") as out:
            out.write(self.data)
        return path

    def test_parts_rebuild_the_pack(self):
        pack = self.pack("index.pck", 2500)
        parts = split_pack.split(self.page, pack, part_bytes=1000)
        self.assertEqual([s for _, s in parts], [1000, 1000, 500])
        self.assertFalse(os.path.exists(pack))
        joined = b"".join(open(os.path.join(self.dir.name, name), "rb").read() for name, _ in parts)
        self.assertEqual(joined, self.data)
        written = manifest(open(self.page).read())
        self.assertEqual(written["pack"], "index.pck")
        self.assertEqual(written["parts"][0], ["index.pck.0", 1000])

    def test_small_pack_left_whole(self):
        pack = self.pack("index.pck", 900)
        self.assertEqual(split_pack.split(self.page, pack, part_bytes=1000), [])
        self.assertTrue(os.path.exists(pack))
        self.assertIn("const PACK_PARTS = null;", open(self.page).read())

    def test_pack_named_from_the_page(self):
        pack = self.pack("preview/12.pck", 1500)
        split_pack.split(self.page, pack, part_bytes=1000)
        written = manifest(open(self.page).read())
        self.assertEqual(written["pack"], "preview/12.pck")
        self.assertEqual(written["parts"][1], ["preview/12.pck.1", 500])

    def test_refuses_a_page_without_the_line(self):
        with open(self.page, "w") as out:
            out.write("<script></script>")
        with self.assertRaises(SystemExit):
            split_pack.split(self.page, self.pack("index.pck", 2000), part_bytes=1000)


if __name__ == "__main__":
    unittest.main()
