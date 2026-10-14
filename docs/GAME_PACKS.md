# Game packs: more games on this engine

Ashes of Eden is one game on an engine that can carry several. The fight —
the hero's moves, the gifts, the enemies' AI, blood, bolts, the studio — is the
engine's; a story, its places, pictures and words are a **game pack**: its own
repository, laid over an engine checkout as `content/`.

```
engine (this repository)           game pack (its own repository)
├── data/            ← Ashes        ├── data/game.json   what the game is
├── scripts/, tools/                ├── data/…           its entries and overrides
├── assets/, scenes/                ├── assets/, scenes/ res://content/…
└── content/  ──── a checkout of ──▶└── localization/strings.csv
```

## How the data is put together

`scripts/data/data_doc.gd` reads three roots, later winning: `res://data` (the
engine's, which is Ashes'), `res://content/data` (the pack), `user://mods/*/data`.

- **Collections** (`data/enemies`, `data/abilities`, `data/dialogues`, …) overlay
  by id: a pack's `enemies/ghoul.json` with the engine's id replaces its keys.
- **One-document files** (`hero.json`, `projectiles.json`, `gore.json`,
  `action_fx.json`, `backdrops.json`, `ambience.json`, `dialogue_looks.json`,
  `player_actions.json`, `foliage.json`, `music/playlists.json`) are deep-merged: a pack names
  only the keys it changes; a list is replaced whole.
- **`game.json`** is the last root's, whole (`DataDoc.top`): a key a pack leaves
  out must not quietly be Ashes'.

### game.json

| key | what |
| --- | --- |
| `id`, `name`, `version` | the game; `apply_pack.py` writes `name`/`version` into project.godot |
| `engine` | the engine version it was made for (`DataDoc.ENGINE`); a newer one is refused |
| `rooms` | room scenes in play order (`Data.rooms`, `Run.ROOMS`) — borrowed `res://scenes/rooms/…` or its own `res://content/scenes/rooms/…` |
| `practice_room` | the practice yard |
| `menu` | `background` picture and `music` mood |
| `paths` | grace / temptation / will: `color`, `aura`, `drift`, `icon` |
| `inherit` | the engine collections the pack takes (`abilities`, `enemies`, …); every other collection is the pack's alone. Without `inherit` everything is inherited — that is Ashes itself |
| `exclude` | `{collection: [id, …]}` — inherited entries to leave out (props that carry Ashes' story) |
| `opening` | ids of the `prologue`, `prologue_short`, `intro` and `last_fall` scenes/dialogues; any may be absent; `"wake": false` starts the hero on his feet instead of rising out of the grave |
| `nights` | later nights, each `{id, rooms, opening, after_dawns}`: its own rooms (none shared with another night), its own opening, offered on Play («Which chapter?») once the profile has seen `after_dawns` dawns. `rooms` / `opening` above are the first night (`Data.nights`, `Game.night`) |
| `flags_read` | story flags only code reads, for the validator's both-ways check |

The validator (`validate_data.gd`) checks the merged game: every id a room
places (`enemy_id`, `npc_id`, `prop_id`, the intro/outro scenes) must exist in
it, so a borrowed room that still points at Ashes' story fails here, not in play.

### Strings

Godot imports one `localization/strings.csv`. `apply_pack.py` lays the pack's
over the engine's by key (an empty cell keeps the engine's text, new keys go to
the end); `--restore` puts the tracked file back. Every Chinese character must be
in the CJK subset (`tools/art/make_cjk_font.py`) — a pack that adds new ones has
to rebuild it in the engine for now.

## Tools

```bash
make new-game DIR=../saints-of-rust NAME="Saints of Rust"   # from tools/packs/template
make game GAME=../saints-of-rust                            # link it in as content/, re-import
make game-test                                              # validator + game_smoke_test (Docker)
make ashes                                                  # back to Ashes
python3 tools/studio/serve.py --game ../saints-of-rust      # the studio, writing into the pack
```

`content/` is the same slot Ashes' own private overlay uses: one pack per
checkout. Docker cannot follow a link out of the project, so CI copies
(`apply_pack.py --copy`). Most tests under `scripts/tools/` are Ashes' (they
name its rooms and story); for a pack, `validate_data.gd` and
`game_smoke_test.gd` (every room of the game opens, its creatures are its own,
the door is there) are the ones that hold.

## CI: `.github/workflows/game.yml`

The template's `build.yml` calls the engine's reusable workflow. It checks out
the engine at `engine_ref` and the pack beside it, lays the pack over, runs
`game-test`, exports the Web build to the pack's Pages with the studio beside it,
and publishes the studio's data (`tools/studio/build_data.py`, which reads the
merged game through `tools/packs/game_view.py`) to the pack's `studio-data`
branch. The pack's repository needs Pages on (Source: GitHub Actions).

## The studio

The hosted studio opens another game with **▣ → Открыть игру** (`?game=owner/name`):
everything it reads from `import/` comes from that repository's `studio-data`
branch, the engine's pictures from the engine's commit, the pack's own
(`content/…`) from the pack's. Sends go to the pack's repository as pull
requests (`packFiles` in `lib.js`): `data/…` and `localization/…` keep their
paths — the pack's copy overrides the engine's, starting from the engine's file
the first time — and a new picture becomes the pack's, its `res://` path turned
into `res://content/…` in the same send. Locally, `serve.py --game DIR` does the
same into the pack's folder and checks the result with the validator.

Not yet: rooms made in the studio (`tools/rooms/studio_rooms.json` and the room
generator are the engine's), per-game generator overrides, and the studio's
browser drafts are shared between games on one site.

## Engine versions

Raise `DataDoc.ENGINE` when a data format changes in a way an older pack would
not survive, and say here what changed.

- **1** — hero.json, game.json (`inherit`, `exclude`, `opening`, `flags_read`), data roots.
- **2** — game.json `nights`: a game told in more than one night. Older packs (no `nights`) play as before; a pack that has them needs this engine.
