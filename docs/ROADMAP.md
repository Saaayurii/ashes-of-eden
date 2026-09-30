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
- [x] Ground slam (down in the air: a fast drop that knocks down what he lands beside) and wall grab (hold into a wall to slide, jump to push off) — `traversal_moves_test.gd`
- [x] One new discovery per night: gifts carry `unlock_nights` and stay out of the pool until the profile reaches it; the night one arrives, the run says so (`gift_test.gd`)
- [x] Skins as data (`data/skins`): five free cloaks, earned by play (nights, a boss put down, the dead put to rest), picked in Settings, seen by the other player online (`skins_test.gd`) — the store and `sku` skins come only with a real storefront (v0.6)
- [x] 3 more enemy behaviours as data: ranged (zealot, wraith), charger (lunge: raven, Knight of Ash), summoner (Cult caller: `caster` behaviour + `summon` attack)
- [x] Elite enemies (elite possessed with a death blast, fallen champion)
- [x] Active ability slot (U / LB): three skill gifts, one per path — Radiance (nova + heal), Blood Lash (drain), Ash Spear (bolt)
- [x] Android export in Docker (SDK + debug keystore in the image), built by `.github/workflows/mobile.yml` — [ ] Play Console internal test

## v0.3 — Chapter 1: "The First Trumpet"
- [x] First location: 15 rooms (13 painted panels + church + preacher nave), one route, lava, reach-tested by a bot (`reach_test.gd`)
- [x] Ophanim boss ("DO NOT BE AFRAID") with its seal phase (eyes closed → three seals → damage window, `seal_phase_test.gd`), Knight of Ash, Blind Preacher
- [x] Elian's opening monologue over black, in full the first night and two lines every night after
- [x] Story scenes spoken in all four languages (Piper, clean-licensed voices only; pitch through the WORLD vocoder so formants stay put, and a switch in Settings to turn it off — `docs/VOICE.md`)
- [x] NPC dialogues with real consequences; flags read back by later dialogues (Father Matthew reads Mara and the Voice)
- [x] Alignment shows on the hero: an aura of the leading path and a tint on his light
- [x] Alignment on the body and in the score: a music layer per path under the room's track, and a shader on the sprite — light along his edge for grace, veins for temptation, ash for will (`alignment_test.gd`). It works off the sprite's alpha, so it needs no painted mask; glowing *eyes* still would, and wait on art.
- [x] Saves: autosave + 3 slots, continue / load, export / import (file or text code)

## v0.4 — Community
- [x] Mod loading from `user://mods` (extra data folders)
- [x] Dialogue validator reports unreachable nodes (error) and translations identical to the English (warning), per locale
- [x] Art direction doc for contributors (`docs/ART_DIRECTION.md`): the look, the screen, how panels, atlases, the hero and effects are made and by which tool — [ ] the contributor art pass itself, which needs contributors

## v0.5 — Chinese market
- [x] A CJK font that ships with the build and matches the Latin one: Noto **Serif** SC at weight 400, subsetted (`tools/art/make_cjk_font.py`). The line used to ask for a *pixel* face, from when the art was placeholder rectangles; the game is now set in EB Garamond and Forum, so Song is the face that belongs beside them — [ ] full zh_CN review by a native speaker
- [x] Web build with fonts embedded — the Chinese reads in a browser, where there are no system fonts to fall back on
- [x] The browser build opens on its own page rather than Godot's: the chapter-one graveyard panel with Elian's idle sprite standing in it, generated from the game's own art by `tools/art/make_web_gate.py`. It also fixes the two things the default shell got wrong — audio, which a browser will not start without a click, and the touch pad, which appeared on every desktop browser because a Web export has no `pc` feature

## v0.6 — Desktop stores
- [ ] Steam page, achievements, cloud saves
- [x] itch.io publishing wired (`.github/workflows/itch.yml`): the web build on every push to main, the desktop zips when a release is published, and a cover composed from the game's own art by `tools/art/make_store_art.py` — [ ] the page itself, which needs an account and a `BUTLER_API_KEY` (`docs/ITCH.md`). The only store here with no entry fee.
- [ ] Supporter Pack + OST on itch/Steam; entitlement check against store receipts
- [ ] Opt-in server-side telemetry: the four numbers in `CORE_LOOP.md`
- [x] macOS notarization and Windows signing written and wired into `release.yml`, Android upload-key signing into `mobile.yml` — [ ] the certificates themselves, which have to be bought: `docs/RELEASE.md` says what each costs, what it fixes and in what order it is worth paying

## v1.0 — Campaign
- [ ] Seven regions, four endings
- [ ] iOS — the preset and the macOS job exist (`.github/workflows/mobile.yml`), but Godot will not export for iOS without an App Store Team ID, so nothing can be built until there is a paid Apple Developer account. The job skips itself and says so.
