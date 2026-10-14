# __NAME__

A game on the [Ashes of Eden](https://github.com/__ENGINE_REPO__) engine: its combat, its
code and its tools, with this repository's own story, places and pictures laid over them.

- `data/game.json` — what makes the game this game: rooms in play order, the menu, the
  three paths' colours, which of the engine's collections it takes (`inherit`).
- `data/` — the game's own entries; one with the same id as the engine's replaces it.
  A one-document file (`hero.json`, `projectiles.json`, …) changes only the keys it names.
- `data/hero.json` — the fight, only what differs from the engine's: the hero's `stats` and
  `feel`, which special `moves` he has, and how enemies keep their distance (`enemy_ai`).
- `rooms/rooms.json` — rooms made from the engine's (`base`) with the game's own enemies,
  weather and light; `rooms/composed_rooms.json` — rooms stitched from several paintings;
  `rooms/studio_rooms.json` — what the studio adds. The scenes in `scenes/rooms/` are
  written from them (`tools/rooms/generate_rooms.py --pack`, and by CI on a push): edit
  the tables, not the scenes.
- `assets/fonts/NotoSerifSC-Subset.ttf` — the Chinese the game's words use
  (`tools/art/make_cjk_font.py --pack`, cut from the engine's strings and the game's together),
  when it has words of its own; laying the game over the engine puts it in the engine's place.
- `localization/strings.csv` — keys the game adds or retells (`GAME_TITLE`, …).
- `assets/`, `scenes/` — the game's pictures and rooms, named `res://content/...`.

Play it locally from an engine checkout:

    python3 tools/packs/apply_pack.py ../__ID__
    make import && make room ROOM=0

Open it in the art studio: the studio's «Открыть игру» → `owner/__ID__`.
