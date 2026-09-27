# Roadmap

Small releases, each one playable. The rule: one room that is fun beats a world that is half-built.

## v0.1 — Core loop *(now)*
- [x] Godot 4.7 project, GL Compatibility renderer, pixel-perfect 640×360
- [x] Player: move / attack / dash with i-frames
- [x] Data-driven enemies, gifts (abilities), dialogues
- [x] Hidden alignment counters (grace / temptation / will) + story flags
- [x] Wave arena, gift picker, run end
- [x] Localization pipeline: en / ru / uk / zh_CN
- [x] Touch controls (virtual joystick + buttons)
- [x] Docker image for validation / tests / exports, CI on every PR
- [x] First five minutes as specified in `CORE_LOOP.md`: captions over the fight, trickle spawns, hit-stop, shake, run summary, one-tap retry
- [x] Persistent profile (nights, best wave, kills) with schema versioning
- [x] Content overlay roots (`./content`, `user://mods`) for official DLC and mods
- [x] Pause menu (Escape / Start) with settings
- [x] Settings: language, master / music / SFX buses, fullscreen, screen shake, key rebinding (saved to `user://settings.cfg`)
- [x] Death / victory page: a line from the path you leaned to, night stats, best area, gifts taken
- [x] Boss with two readable patterns (lunge, cross beam), mid-boss (Blind Preacher: censer + crosses)
- [x] Room decor layers and tiled ground; 8 enemies, 4 rooms, 8 backdrops
- [x] Hero animation set: idle / walk / run / two alternating swings with a slash sprite / roll / death
- [x] Baseline balance fixed in `docs/BALANCE.md` and in data: 3-hit combo, crit, armor, healing charges, essence levels, soft caps, difficulty modes, time scaling, elites, boss phases
- [x] NPCs (knight, nun, old woman) with one caption line each; Elian wakes up face-down in the intro
- [x] HUD icons (heart / essence / potions) and path icons on gift cards
- [x] Music library: 43 free tracks (CC0 / CC BY / OGA-BY) in 11 mood playlists, random per room, fetched by `tools/audio/fetch_music.py`
- [x] Ornate HUD bars (`OrnateBar`, nine-patch from the UI pack) for HP / essence / cooldowns / boss
- [x] Room ambience layer: ravens, leaves, wisps, motes, embers, low fog, lightning + thunder (`data/ambience.json`)
- [x] A voice per creature (alert / attack / hurt / death), synthesised placeholders
- [x] Enemies stand on the ground (sprite sole = collision sole); rolls pass through enemies
- [x] Music for mobile / Web: a light subset (one fetched track per mood + the repository's own, ~16 MB) written into the Android and Web presets by `tools/export/music_filters.py`; playlists skip what a build does not carry
- [x] Web build exported in Docker and checked in a browser (boots, intro plays, no console errors); `index.pck` is ~99 MB, mostly the wide paintings and sprites — WebP/lossy import is the next saving
- [x] Sound: placeholder SFX, one ambient loop, CC0 hits and a voice per creature
- [x] First prototype art: hero (8 frames), two enemies, five painted backdrops (`assets/CREDITS.md`)
- [x] Side-view platformer body (Dead Cells-style: double jump, coyote, roll i-frames) instead of top-down
- [x] Three hand-made rooms with parallax backdrop, fog shader, weather particles, locked door
- [x] Living main menu from layers: painting, fog, rain, lantern/beam flicker, water shimmer, hero idle
- [x] Web build on GitHub Pages, rebuilt from main (`.github/workflows/pages.yml`) — https://saaayurii.github.io/ashes-of-eden/

## v0.2 — Feel
- [x] Damage numbers, attack swing arc, roll / landing / step dust
- [x] Enemy attack telegraphs (wind-up glow → strike), stagger on hit, melee / ranged / lunge attack types
- [x] Two new enemies (hooded cultist, radiant zealot with projectiles), first boss (Ophanim, summons at 50 %)
- [x] Damage numbers, smoke puffs on death / roll / projectile burst, boss bar
- [x] Drop through platforms (down + jump), ledge mantle
- [ ] Ground slam, wall grab (the rest of the Dead Cells set)
- [ ] One new discovery per night (gift / line / enemy unlocked by profile.nights)
- [ ] Skins as data (`data/skins`) — free skins first; the store comes only with a real storefront (v0.6)
- [x] 3 more enemy behaviours as data: ranged (zealot, wraith), charger (lunge: raven, Knight of Ash), summoner (Cult caller: `caster` behaviour + `summon` attack)
- [x] Elite enemies (elite possessed with a death blast, fallen champion)
- [x] Active ability slot (U / LB): three skill gifts, one per path — Radiance (nova + heal), Blood Lash (drain), Ash Spear (bolt)
- [x] Android export in Docker (SDK + debug keystore in the image), built by `.github/workflows/mobile.yml` — [ ] Play Console internal test

## v0.3 — Chapter 1: "The First Trumpet"
- [x] First location: 15 rooms (13 painted panels + church + preacher nave), one route, lava, reach-tested by a bot (`reach_test.gd`)
- [x] Ophanim boss ("DO NOT BE AFRAID"), Knight of Ash, Blind Preacher
- [x] Elian's opening monologue over black, in full the first night and two lines every night after
- [x] Story scenes spoken in all four languages (placeholder TTS, `docs/VOICE.md`)
- [x] NPC dialogues with real consequences; flags read back by later dialogues (Father Matthew reads Mara and the Voice)
- [x] Alignment shows on the hero: an aura of the leading path and a tint on his light
- [ ] Alignment: eyes / veins on the sprite, a music layer
- [x] Saves: autosave + 3 slots, continue / load, export / import (file or text code)

## v0.4 — Community
- [x] Mod loading from `user://mods` (extra data folders)
- [x] Dialogue validator reports unreachable nodes (error) and translations identical to the English (warning), per locale
- [ ] Contributor art pass, art direction doc

## v0.5 — Chinese market
- [ ] CJK pixel font, full zh_CN review by a native speaker
- [ ] Web build with fonts embedded

## v0.6 — Desktop stores
- [ ] Steam page, achievements, cloud saves
- [ ] Supporter Pack + OST on itch/Steam; entitlement check against store receipts
- [ ] Opt-in server-side telemetry: the four numbers in `CORE_LOOP.md`
- [ ] macOS notarization, Windows signing

## v1.0 — Campaign
- [ ] Seven regions, four endings
- [ ] iOS — the preset and the macOS job exist (`.github/workflows/mobile.yml`), but Godot will not export for iOS without an App Store Team ID, so nothing can be built until there is a paid Apple Developer account. The job skips itself and says so.
