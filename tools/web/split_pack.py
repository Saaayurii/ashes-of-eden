#!/usr/bin/env python3
"""Serve a Web build's pack in parts, for GitHub Pages.

Pages refuses any single file over 100 MB, and the Web pack (index.pck) grows
by every chapter's rooms. This cuts the pack into parts of at most PART_MB,
deletes the whole one, and writes the parts' names and sizes into the page's
`const PACK_PARTS = null;` (tools/web/shell.template.html), which then fetches
them into one buffer and hands it to the engine as its main pack. The game
inside is the same pack, byte for byte: every room of every night stays in it.

A pack no bigger than one part is left whole and the page untouched, so a local
`make web` and itch.io (which takes the export as it is) keep the plain path.

    python3 tools/web/split_pack.py build/web/index.html build/web/index.pck
    python3 tools/web/split_pack.py build/web/preview-12.html build/web/preview/12.pck

The pack's name in the page is relative to the page, as the engine's mainPack is.
"""
import json
import os
import re
import sys

PART_MB = 64
SENTINEL = re.compile(r"^(\s*)const PACK_PARTS = null;$", re.M)


def split(page_path: str, pack_path: str, part_bytes: int = PART_MB * 1024 * 1024) -> list:
    page = open(page_path, encoding="utf-8").read()
    if not SENTINEL.search(page):
        raise SystemExit(f"{page_path}: no `const PACK_PARTS = null;` — the page cannot load a pack in parts")
    size = os.path.getsize(pack_path)
    if size <= part_bytes:
        return []
    pack = os.path.relpath(pack_path, os.path.dirname(os.path.abspath(page_path))).replace(os.sep, "/")
    parts = []
    with open(pack_path, "rb") as whole:
        i = 0
        while True:
            chunk = whole.read(part_bytes)
            if not chunk:
                break
            name = f"{pack_path}.{i}"
            with open(name, "wb") as out:
                out.write(chunk)
            parts.append([f"{pack}.{i}", len(chunk)])
            i += 1
    os.remove(pack_path)
    manifest = json.dumps({"pack": pack, "parts": parts}, separators=(",", ":"))
    page = SENTINEL.sub(lambda m: f"{m[1]}const PACK_PARTS = {manifest};", page, count=1)
    with open(page_path, "w", encoding="utf-8") as out:
        out.write(page)
    return parts


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    made = split(sys.argv[1], sys.argv[2])
    if made:
        print(f"{sys.argv[2]}: {len(made)} parts, " + ", ".join(f"{n} ({s / 1e6:.1f} MB)" for n, s in made))
    else:
        print(f"{sys.argv[2]}: one part, left whole")
