# Ashes of Eden

*Пепел Эдема · Попіл Едему · 伊甸余烬*

An open-source 2D pixel action roguelite about a human soul that neither Heaven nor the Abyss can claim.
Side-view, fast and forgiving in the spirit of Dead Cells on the surface; a serious, deliberately ambiguous
story underneath for those who want it.

> **Status: prototype (v0.1-dev).** Four hand-made areas, eight enemies including a mid-boss and a boss with two
> patterns, nine gifts, three dialogues, four languages, settings with key rebinding, a living layered main menu,
> online co-op and a 1v1 duel with crossplay. Placeholder art — see [docs/ROADMAP.md](docs/ROADMAP.md).

**Free. Open source. No pay-to-win. No loot boxes.** — [how the game funds itself](docs/MONETIZATION.md)

[Русская версия README](README.ru.md)

## The pitch

- **Angels are not good. Demons are not evil.** Heaven wants a world without suffering — and without choice. The Abyss wants freedom — with every consequence freedom brings. The player is the only being that can say *no* to both.
- **Gameplay is dumb on purpose.** Run, jump, roll, strike. Clear the area, walk through the door, pick a gift, repeat. You can play the whole game without reading a word.
- **The story is optional but it watches you.** Every gift and every choice quietly shifts three hidden counters — Grace, Temptation, Will. The world reacts. Nobody tells you the numbers.
- **Built to be forked.** Enemies, gifts, dialogues and translations are plain JSON/CSV. You can add content without opening the engine.
- **Bring a friend.** The whole story can be played by two, and there is a one-on-one duel. A laptop, a phone and a browser tab can share the same match — see [docs/MULTIPLAYER.md](docs/MULTIPLAYER.md).

Full design: [docs/GDD.md](docs/GDD.md) · the first five minutes, second by second: [docs/CORE_LOOP.md](docs/CORE_LOOP.md) (both Russian, English translations welcome).

## Controls

| Action | Keyboard | Gamepad | Touch |
|---|---|---|---|
| Move | A/D / arrows | left stick | virtual joystick (left half) |
| Jump / double jump | Space / W / Up | A | green button |
| Roll (i-frames) | Shift / K | B | blue button |
| Attack | J / left mouse | X | gold button |
| Block (hold) / parry (tap it just before a blow lands) | L / right mouse | RB | pale blue button |
| Pause / settings | Esc | Start | — |

Keys can be rebound in Settings.

## Playing together

Main menu → **Play together**. One of you picks *Story together* or *Duel* and presses
**Create game**; the screen shows the address to read out. The other types it in and presses
**Join**. Both press Ready, the host presses Start. Default port is `8910`.

It is crossplay in both directions: the transport is WebSocket, so a desktop host can serve a
browser and a phone at once. A browser cannot host (it cannot listen for connections), so if
both of you are in a browser, run the dedicated referee:

```bash
make server                                           # ws://localhost:8910
godot --headless -- --server --port=8910 --mode=pvp   # without Docker
```

Details, and what the host decides versus what your own game decides:
[docs/MULTIPLAYER.md](docs/MULTIPLAYER.md).

## Run it

**Native editor (recommended for development):** install [Godot 4.7](https://godotengine.org/download) and open `project.godot`.

```bash
brew install --cask godot        # macOS
make editor
```

**Docker (validation, tests and exports — same image as CI):**

```bash
make image      # build the image once (~1 GB of Godot + export templates)
make validate   # check data files and all 4 locales
make test       # headless end-to-end run of the game loop
make net-test   # two-process crossplay stand: co-op and duel, host and dedicated
make server     # dedicated host for two browsers, on ws://localhost:8910
make build      # export Windows / Linux / macOS / Web into ./build
make web        # export Web and serve it at http://localhost:8080
```

## Project layout

```
data/            game content as JSON — abilities, enemies, dialogues (no engine knowledge needed)
localization/    strings.csv with en / ru / uk / zh_CN columns
scenes/          Godot scenes (.tscn): player, enemies, rooms (hand-made areas), run, UI
assets/shaders/  fog and water shaders used by rooms and the menu
scripts/
  autoload/      global systems: EventBus, Data (loader), Game (run state), Settings, Net (session)
  combat/        AbilitySystem — applies data-driven gifts to the player
  pvp/           duel.gd — the 1v1 match, rounds and score
  tools/         validate_data.gd, smoke_test.gd and net_test.gd (run headless, used by CI)
assets/          sprites / audio / fonts / ui (empty for now, see LICENSE-ASSETS.md)
tools/docker/    entrypoint and nginx config for the build image
tools/net_test.sh  two-process crossplay stand (host + guest, or referee + two guests)
content/         (git-ignored) official assets overlay from the private content repo — optional
docs/            GDD, core loop, monetization, roadmap, data formats, localization guide
```

## Contributing

Translations, gifts, enemies and dialogue are the easiest places to start — see [CONTRIBUTING.md](CONTRIBUTING.md)
and [docs/DATA_FORMATS.md](docs/DATA_FORMATS.md). CI validates every pull request.

## License

Code: [MIT](LICENSE). Story text, translations and community assets: CC BY 4.0. Official art, music and the
name are reserved and live outside this repo — see [LICENSE-ASSETS.md](LICENSE-ASSETS.md). A build without
them is the fully playable community edition.
