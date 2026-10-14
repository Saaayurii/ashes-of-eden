#!/usr/bin/env python3
"""Lay a game pack over this engine checkout (docs/GAME_PACKS.md).

    python3 tools/packs/apply_pack.py ../my-game          # link it in as ./content
    python3 tools/packs/apply_pack.py ../my-game --copy   # copy it (CI, Docker)
    python3 tools/packs/apply_pack.py --restore           # back to Ashes of Eden

A game pack is a repository with the game's own data/, assets/, scenes/ and
localization/strings.csv. The engine reads res://content/data over res://data
by itself (scripts/data/data_doc.gd); what it cannot do at run time is done
here, in the working tree:

  * ./content becomes the pack (a symlink, or a copy with --copy);
  * the pack's strings are laid over localization/strings.csv by key — a key it
    names is its own in every column it fills, a new key is added — because
    Godot imports one CSV of strings, and the engine's code asks for keys like
    GAME_TITLE whatever the game;
  * project.godot takes the pack's name (game.json "name") and version;
  * the pack's CJK subset (tools/art/make_cjk_font.py --pack, cut from the
    merged strings) takes the place of the engine's, because the theme names
    the font by path — and changing the theme's fallbacks at run time crashes
    Godot on exit under Linux.

All three are tracked in the engine's repository, so --restore puts them back
with git and drops ./content. A pack made for a newer engine than this one
(game.json "engine" > DataDoc.ENGINE) is refused before anything changes.
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTENT = ROOT / "content"
STRINGS = ROOT / "localization" / "strings.csv"
PROJECT = ROOT / "project.godot"
CJK_FONT = ROOT / "assets" / "fonts" / "NotoSerifSC-Subset.ttf"
TOUCHED = [STRINGS, PROJECT, CJK_FONT]


def engine_version(root: Path = ROOT) -> int:
    text = (root / "scripts/data/data_doc.gd").read_text(encoding="utf-8")
    return int(re.search(r"^const ENGINE := (\d+)", text, re.M)[1])


def read_strings(path: Path) -> tuple[list[str], dict[str, dict[str, str]]]:
    rows = list(csv.reader(io.StringIO(path.read_text(encoding="utf-8"))))
    header, out = rows[0], {}
    for row in rows[1:]:
        if row and row[0]:
            out[row[0]] = dict(zip(header[1:], row[1:]))
    return header, out


def _row(cells: list[str]) -> str:
    """One line the way strings.csv writes them: the key bare, every text quoted."""
    return ",".join([cells[0]] + ['"' + c.replace('"', '""') + '"' for c in cells[1:]])


def merge_strings(engine_csv: str, pack_csv: str) -> str:
    """The engine's CSV with the pack's keys laid over it: the engine's lines
    untouched but the ones the pack names, the pack's new keys at the end. A
    pack's empty cell keeps the engine's text (a pack may translate only some
    locales). strings.csv holds one key a line (no text spans lines)."""
    lines = engine_csv.splitlines(keepends=True)
    header = next(csv.reader([lines[0]]))
    pack_rows = list(csv.reader(io.StringIO(pack_csv)))
    if not pack_rows:
        return engine_csv
    pack_header = pack_rows[0]
    unknown = [c for c in pack_header[1:] if c not in header]
    if unknown:
        raise SystemExit(f"pack strings.csv has locales the engine lacks: {unknown}")
    pack = {r[0]: dict(zip(pack_header[1:], r[1:])) for r in pack_rows[1:] if r and r[0]}
    out, seen = [lines[0]], set()
    for line in lines[1:]:
        row = next(csv.reader([line]), [])
        if row and row[0] in pack:
            seen.add(row[0])
            line = _row([row[0]] + [pack[row[0]].get(col) or (row[i + 1] if i + 1 < len(row) else "")
                                    for i, col in enumerate(header[1:])]) + "\n"
        out.append(line)
    if out and not out[-1].endswith("\n"):
        out[-1] += "\n"
    out += [_row([key] + [cells.get(col, "") for col in header[1:]]) + "\n" for key, cells in pack.items() if key not in seen]
    return "".join(out)


def set_project(text: str, name: str | None, version: str | None) -> str:
    if name:
        text = re.sub(r'^config/name=".*"$', f'config/name="{name}"', text, count=1, flags=re.M)
    if version:
        text = re.sub(r'^config/version=".*"$', f'config/version="{version}"', text, count=1, flags=re.M)
    return text


def restore() -> None:
    if CONTENT.is_symlink() or CONTENT.is_file():
        CONTENT.unlink()
    elif CONTENT.is_dir() and (CONTENT / "data" / "game.json").exists():
        shutil.rmtree(CONTENT)
    subprocess.run(["git", "checkout", "--"] + [str(p.relative_to(ROOT)) for p in TOUCHED], cwd=ROOT, check=True)
    print("engine back to its own game (content/ removed, strings, project and CJK font restored)")


def apply(pack: Path, copy: bool, force: bool) -> None:
    pack = pack.resolve()
    game_file = pack / "data" / "game.json"
    if not game_file.exists():
        raise SystemExit(f"{pack} is not a game pack: no data/game.json")
    game = json.loads(game_file.read_text(encoding="utf-8"))
    made_for, have = int(game.get("engine", 0)), engine_version()
    if made_for > have:
        raise SystemExit(f"{game.get('id', pack.name)} is made for engine {made_for}; this checkout is engine {have}")
    if CONTENT.exists() or CONTENT.is_symlink():
        same = CONTENT.is_symlink() and CONTENT.resolve() == pack
        if not same and not force:
            raise SystemExit("content/ is already there (another pack, or Ashes' own overlay): --restore first, or --force")
        if CONTENT.is_symlink() or CONTENT.is_file():
            CONTENT.unlink()
        else:
            shutil.rmtree(CONTENT)
    if copy:
        shutil.copytree(pack, CONTENT, ignore=shutil.ignore_patterns(".git", ".godot", "build"))
    else:
        CONTENT.symlink_to(pack, target_is_directory=True)
    # strings are merged from the engine's own (tracked) file, so applying twice is the same as once
    engine_csv = subprocess.run(["git", "show", "HEAD:localization/strings.csv"], cwd=ROOT, capture_output=True,
                                text=True, check=True).stdout
    pack_csv = pack / "localization" / "strings.csv"
    STRINGS.write_text(merge_strings(engine_csv, pack_csv.read_text(encoding="utf-8")) if pack_csv.exists() else engine_csv,
                       encoding="utf-8")
    engine_project = subprocess.run(["git", "show", "HEAD:project.godot"], cwd=ROOT, capture_output=True,
                                    text=True, check=True).stdout
    PROJECT.write_text(set_project(engine_project, game.get("name"), game.get("version")), encoding="utf-8")
    pack_font = pack / CJK_FONT.relative_to(ROOT)
    if pack_font.exists():
        shutil.copyfile(pack_font, CJK_FONT)
    else:
        subprocess.run(["git", "checkout", "--", str(CJK_FONT.relative_to(ROOT))], cwd=ROOT, check=True)
    print(f"{game.get('name', game.get('id'))}: pack {pack} laid over engine {have} "
          f"({'copied' if copy else 'linked'} as content/). Re-import before running: make import")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("pack", nargs="?", type=Path, help="the game pack's folder (a checkout of its repository)")
    parser.add_argument("--copy", action="store_true", help="copy instead of linking (Docker cannot follow a link out of the project)")
    parser.add_argument("--force", action="store_true", help="replace whatever is in content/")
    parser.add_argument("--restore", action="store_true", help="drop the pack and put the engine's own files back")
    args = parser.parse_args()
    if args.restore:
        restore()
    elif args.pack:
        apply(args.pack, args.copy, args.force)
    else:
        parser.error("name a pack folder, or --restore")


if __name__ == "__main__":
    sys.exit(main())
