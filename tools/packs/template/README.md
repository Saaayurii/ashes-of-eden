# __NAME__

A game on the [Ashes of Eden](https://github.com/__ENGINE_REPO__) engine: its combat, its
code and its tools, with this repository's own story, places and pictures laid over them.

- `data/game.json` — what makes the game this game: rooms in play order, the menu, the
  three paths' colours, which of the engine's collections it takes (`inherit`).
- `data/` — the game's own entries; one with the same id as the engine's replaces it.
  A one-document file (`hero.json`, `projectiles.json`, …) changes only the keys it names.
- `localization/strings.csv` — keys the game adds or retells (`GAME_TITLE`, …).
- `assets/`, `scenes/` — the game's pictures and rooms, named `res://content/...`.

Play it locally from an engine checkout:

    python3 tools/packs/apply_pack.py ../__ID__
    make import && make room ROOM=0

Open it in the art studio: the studio's «Открыть игру» → `owner/__ID__`.
