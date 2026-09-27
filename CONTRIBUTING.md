# Contributing

Thanks for being here. Three rules keep this project healthy:

1. **Content is data.** Enemies, gifts, dialogues and strings live in `data/` and `localization/`, not in scripts. If you need a new effect type, add it to `AbilitySystem` *and* to `scripts/tools/validate_data.gd`.
2. **Every player-facing string is a localization key** in all four locales (`en`, `ru`, `uk`, `zh_CN`). Don't know a language? Put the English text in the column and open the PR anyway — a translator will follow up.
3. **Story is optional.** Nothing may block the player from skipping a dialogue.

## Before you open a PR

```bash
make validate   # data + localization checks
make test       # end-to-end smoke test
```

Both run in Docker, so you don't need Godot installed to contribute content. CI runs the same commands.

`make validate` fails on a dialogue node nothing can reach, a `next` pointing at a node that is not
there, a localization key used but not written, and an empty cell in any of the four locales. It
*warns* — without failing — when a Russian or Ukrainian line reads exactly like the English one,
which usually means the column was filled in to get the check to pass.

`make test` plays the whole chapter headless at four times speed — about two minutes, not the
hour it took at 1x. Pass a slower scale if your machine struggles:
`docker compose run --rm godot godot --headless -s scripts/tools/smoke_test.gd -- 2`.

## A word on the repository's size

It is big — about 610 MB of history, most of it the painted panels, sprite sheets and audio in
`assets/`. A first clone takes a while. `git clone --depth 1` gets you everything you need to build
and play, and is the right call unless you need the history.

**We deliberately do not use Git LFS**, even though the size invites it. GitHub's free tier gives
1 GiB of LFS bandwidth a month, and *every* clone re-downloads the LFS objects no matter how shallow
it is — including CI. Three workflows check this repository out on each push, so at 415 MB of tracked
assets a single push would spend more than the whole monthly allowance, and LFS would cut out for
everyone until someone paid. Plain Git has no such cap. If the assets ever outgrow what GitHub will
host, the answer is an asset CDN or a separate content repository (`docs/MONETIZATION.md` already
describes one), not LFS.

## What's easy to pick up

| I want to… | Touch |
|---|---|
| add / fix a translation | `localization/strings.csv` — see `docs/LOCALIZATION.md` |
| add a gift (ability) | `data/abilities/*.json` + 2 strings |
| add an enemy | `data/enemies/*.json` + 1 string |
| write a dialogue | `data/dialogues/*.json` + strings, then wire it in a level script |
| replace placeholder art | `assets/`, list it in `assets/CREDITS.md`, respect `LICENSE-ASSETS.md` |

By contributing text, translations or assets to this repo you license them CC BY 4.0 (code: MIT).
Official art and paid content live in a separate private repo and are overlaid at build time — the
open repo is always a complete, playable game on its own.

Formats: [docs/DATA_FORMATS.md](docs/DATA_FORMATS.md).

## Code style

- GDScript, tabs, static typing where it doesn't fight you. `snake_case` files, `PascalCase` node names.
- Systems talk through `EventBus` signals, not direct references.
- Physics layers: 1 world · 2 player · 3 enemies · 4 player hitbox.
- Keep the core loop dumb. Depth goes into gifts, enemies and story, not into more buttons.

## Story contributions

The tone matters more than the plot. Read `docs/GDD.md` first. In short: nobody in this world is simply right;
angels are sincere, demons can tell the truth, and the game never awards "+10 good". Show consequences instead.
