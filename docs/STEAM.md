# Steam

The game keeps its own deeds (`docs/ACHIEVEMENTS.md`) and its own saves; Steam only
hears about them. Nothing here is needed to build or play — every build today has no
Steam in it and runs exactly the same.

## Achievements

`scripts/meta/store_bridge.gd` (`StoreBridge`) reaches Steam through the
[GodotSteam](https://godotsteam.com) GDExtension, **by name**
(`Engine.get_singleton("Steam")`), so the project compiles without the extension
and a Web, Android or tool-script run simply has no store.

- `Profile._ready` calls `StoreBridge.start()`: if the singleton exists and
  `steamInitEx()` reports status 0, the bridge keeps it, pumps `run_callbacks`
  every frame (`Profile._process`), and mirrors every deed the profile has already
  done — a profile older than the store page, or deeds done offline, catch up on
  the next launch.
- `Profile.check_achievements` hands each fresh deed to `StoreBridge.mirror`:
  `setAchievement(id)` for the ones Steam does not have yet, one `storeStats()` for
  the lot (Steam draws its own toast; the game's `DeedToast` still shows too).
- A deed the store already has is never set again.

The **API name** of each Steam achievement is the deed's `id` in
`data/achievements/*.json` — that is why an id is never renamed. On the Steamworks
partner site, create one achievement per id with the same API name; the display
name and description come from `DEED_<ID>` / `DEED_<ID>_DESC` in
`localization/strings.csv` (all four languages are there).

`store_test.gd` runs the bridge against a stand-in singleton (no store, a store that
will not start, the catch-up on start, a deed done live, one already on the store).

## Supporter skins

A skin with `"sku": "steam:<dlc app id>"` in `data/skins` is unlocked only while
`StoreBridge.owns` says Steam reports that DLC installed (`isDLCInstalled`), asked
each time the cloak list is read — never a flag in `user://`, which a player can
edit. Steam answers from its own licence cache when offline. A build without
Steam (Web, Android, itch) does not own any sku; the validator refuses a sku in
any other form until another store is wired here. `store_test.gd`.

## Putting GodotSteam in a build

1. Download the GodotSteam **GDExtension** build matching the Godot version and drop
   its `addons/godotsteam/` into the project (not committed: it carries the
   Steamworks redistributables, which have their own licence).
2. Put `steam_appid.txt` (the app id) next to the executable for local testing; a
   build launched by Steam does not need it.
3. Export the desktop presets as usual. The Web and Android presets must exclude
   `addons/godotsteam/`.

## Cloud saves

Steam Auto-Cloud needs no code. Under the app's Cloud settings, sync these from the
Godot user folder (`Ashes of Eden`, under `%APPDATA%/Godot/app_userdata/` on
Windows, `~/Library/Application Support/Godot/app_userdata/` on macOS,
`~/.local/share/godot/app_userdata/` on Linux):

| Path | What |
|---|---|
| `profile.json` | nights, Ash, relics, deeds, bestiary, chronicle |
| `saves/*.json` | autosave and the three slots (`Saves`) |
| `settings.cfg` | locale, volumes, key overrides, accessibility |

Leave out `playtest/` (local logs), `saves_tools/` (test runs) and `mods/`.
A save is the checkpoint on entering a room, never mid-room, so two machines can only disagree about whole rooms, and Steam's own
conflict dialog is enough.
