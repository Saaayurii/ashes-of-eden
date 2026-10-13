#!/usr/bin/env python3
"""Start a new game on this engine (docs/GAME_PACKS.md).

    python3 tools/packs/new_game.py ../saints-of-rust --name "Saints of Rust"

Writes the template (tools/packs/template) into a new folder with the game's
id and name filled in, ready to be `git init`-ed and pushed as its own
repository. Nothing is created on GitHub: that, and the repository's Pages
and Actions settings, are yours to do.
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = Path(__file__).resolve().parent / "template"
TEXT = {".json", ".csv", ".md", ".yml", ".gitignore"}


def engine_repo() -> str:
    url = subprocess.run(["git", "remote", "get-url", "origin"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    found = re.search(r"github\.com[:/]([^/]+/[^/.]+)", url)
    return found[1] if found else "Saaayurii/ashes-of-eden"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--name", required=True, help="the game's title, as the window and the menu show it")
    parser.add_argument("--id", help="snake_case id (default: from the folder's name)")
    args = parser.parse_args()
    if args.folder.exists() and any(args.folder.iterdir()):
        raise SystemExit(f"{args.folder} is not empty")
    game_id = args.id or re.sub(r"[^a-z0-9]+", "_", args.folder.resolve().name.lower()).strip("_")
    engine = re.search(r"^const ENGINE := (\d+)", (ROOT / "scripts/data/data_doc.gd").read_text(), re.M)[1]
    fill = {"__ID__": game_id, "__KEY__": game_id.upper(), "__NAME__": args.name, "__ENGINE__": engine,
            "__ENGINE_REPO__": engine_repo()}
    shutil.copytree(TEMPLATE, args.folder, dirs_exist_ok=True)
    for path in args.folder.rglob("*"):
        if path.is_file() and (path.suffix in TEXT or path.name in TEXT):
            text = path.read_text(encoding="utf-8")
            for key, value in fill.items():
                text = text.replace(key, value)
            path.write_text(text, encoding="utf-8")
    print(f"{args.name} ({game_id}) written to {args.folder}.\n"
          f"Next: cd {args.folder} && git init && git add -A && git commit -m 'New game'\n"
          f"Play it: python3 tools/packs/apply_pack.py {args.folder} && make import && make room ROOM=0")


if __name__ == "__main__":
    main()
