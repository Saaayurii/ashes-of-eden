#!/usr/bin/env python3
"""The game as a pack makes it, for tools that read files rather than run Godot.

The engine merges its data roots at run time (scripts/data/data_doc.gd): a
pack's collections overlay the engine's by id, its one-document files are
deep-merged, game.json is the pack's alone, "inherit" and "exclude" choose what
the engine lends. tools/studio/build_data.py reads data/ straight from disk, so
for a pack it reads a view instead: a folder whose data/ is that merge and whose
every other entry is a link back to the checkout (assets/, scenes/, content/, …).

    view = game_view(ROOT)   # None when content/ holds no game pack

A collection entry is overlaid by file name here, not key by key as Data does:
close enough for showing and editing a file, which is what the studio does.
"""
from __future__ import annotations

import json
import shutil
import tempfile
from pathlib import Path

# The folders Data reads as collections (scripts/autoload/data_loader.gd); every
# other .json under data/ is a one-document file.
COLLECTIONS = {
    "abilities", "enemies", "enemy_archetypes", "dialogues", "cutscenes", "chapters", "props", "npcs",
    "notes", "items", "rest_points", "skins", "techniques", "forks", "achievements", "resonances",
    "vials", "relics", "omens", "affixes", "weapons", "endings",
}


def pack_game(root: Path) -> dict | None:
    """content/data/game.json, when content/ is a game pack (Ashes' own overlay has none)."""
    path = root / "content" / "data" / "game.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None


def merge(base: dict, overlay: dict) -> dict:
    """DataDoc.merge: tables key by key, lists and values replaced, "id" kept."""
    for key, value in overlay.items():
        if key in ("id", "_source"):
            continue
        if isinstance(base.get(key), dict) and isinstance(value, dict):
            merge(base[key], value)
        else:
            base[key] = json.loads(json.dumps(value))
    return base


def merged_data(engine: Path, pack: Path, game: dict) -> dict[str, object]:
    """{relative path under data/: parsed JSON} — the game's data as the engine would see it."""
    inherit, exclude = game.get("inherit"), game.get("exclude", {})
    out: dict[str, object] = {}
    for f in sorted(engine.rglob("*.json")):
        rel = f.relative_to(engine)
        folder = rel.parts[0] if len(rel.parts) > 1 else ""
        if rel.as_posix() == "game.json":
            continue
        if folder in COLLECTIONS:
            if isinstance(inherit, list) and folder not in inherit:
                continue
            if f.stem in map(str, exclude.get(folder, [])):
                continue
        out[rel.as_posix()] = json.loads(f.read_text(encoding="utf-8"))
    for f in sorted(pack.rglob("*.json")):
        rel = f.relative_to(pack)
        folder = rel.parts[0] if len(rel.parts) > 1 else ""
        doc = json.loads(f.read_text(encoding="utf-8"))
        key = rel.as_posix()
        if folder in COLLECTIONS or key == "game.json" or not isinstance(doc, dict) or not isinstance(out.get(key), dict):
            out[key] = doc
        else:
            out[key] = merge(out[key], doc)
    return out


def game_view(root: Path, into: Path | None = None) -> Path | None:
    game = pack_game(root)
    if game is None:
        return None
    view = into or Path(tempfile.mkdtemp(prefix="game-view-"))
    if view.exists() and into is not None:
        shutil.rmtree(view)
    view.mkdir(parents=True, exist_ok=True)
    for entry in root.iterdir():
        if entry.name != "data":
            (view / entry.name).symlink_to(entry.resolve(), target_is_directory=entry.is_dir())
    for rel, doc in merged_data(root / "data", root / "content" / "data", game).items():
        path = view / "data" / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(doc, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
    return view
