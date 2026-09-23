# Asset credits

| File(s) | Author | Source | License / notes |
|---|---|---|---|
| `sprites/elian_*.png` (72×48: idle 4, walk 8, run 5, attack 5, attack2 4, roll 5, death 5), `sprites/slash.png` | Roman, AI-generated (full hero sheet), sliced with `tools/art/slice_batch4.py` | project | prototype art, see `LICENSE-ASSETS.md` |
| `sprites/possessed_*.png` (40×36: idle, walk, attack, hurt, death) | Roman, AI-generated (full "Possessed" sheet), `tools/art/slice_batch4.py` | project | prototype art |
| `sprites/shade.png` (4 frames, 24×28) | Roman, AI-generated, extracted from the concept atlas | project | prototype art — lossy extraction; to be redrawn |
| `sprites/cultist_*.png` (32×40), `sprites/smoke.png` (32×32) | Roman, AI-generated (hooded figure sheet with alpha) | project | prototype art |
| `sprites/zealot_*.png` (36×44) | Roman, AI-generated ("Radiant Mage" sheet), idle + walk rows only | project | prototype art |
| `sprites/ophanim_*.png` (112×112) | Roman, AI-generated (boss sheet), first boss | project | prototype art |
| `sprites/wraith_*.png` (72×56: idle, walk, attack, death) | Roman, AI-generated (green spectre sheet), `tools/art/slice_batch8.py` | project | prototype art, re-skin of the first 32×40 wraith |
| `sprites/guard_*.png` (36–44×44) | Roman, AI-generated ("Fallen Guard" sheet) | project | prototype art |
| `sprites/preacher_*.png` (56×64: idle, walk, attack, death) | Roman, AI-generated ("Blind Preacher" labelled sheet), `tools/art/slice_batch8.py` | project | prototype art, mid-boss |
| `sprites/champion_idle.png`, `sprites/champion_attack.png` (72×64) | Roman, AI-generated ("dark hooded warrior" frame pack), `tools/art/slice_batch6.py` | project | prototype art |
| `sprites/raven_fly.png` (48×28) | Roman, AI-generated ("black bird in flight" frame pack, side views only), `tools/art/slice_batch6.py` | project | prototype art |
| `sprites/ash_knight_*.png` (96×72: idle, walk, attack, death) | Roman, AI-generated (red knight sheet), `tools/art/slice_batch8.py` | project | prototype art, the Knight of Ash arena boss |
| `sprites/mara_idle.png`, `sprites/matthew_idle.png` (32×44) | Roman, AI-generated ("Мара" / "Матфей" NPC sheets), `tools/art/slice_batch8.py` | project | prototype art, story NPCs |
| `props/barrel*.png`, `crate*.png`, `crates_stacked.png`, `pot.png`, `sack.png` (48×40 ×4), `props/chest_*.png` (40×32 ×4) | Roman, AI-generated (destructibles and chest sheets), `tools/art/slice_batch7.py` | project | breakable props and loot chests (`data/props/`) |
| `icons/*.png` (24 px) | Roman, AI-generated (loot item sheet), `tools/art/slice_batch7.py` | project | what pops out of an opened chest |
| `decor/door_gate.png` (48×64 ×5), `decor/barrier.png` (64×80 ×7), `decor/shrine.png` (48×64 ×7) | Roman, AI-generated ("Doors & Gates", "Boss Arena Barrier", angel shrine sheets), `tools/art/slice_batch8.py` | project | the room exit, the arena walls and the shrine that lights up |
| `decor/tree_*.png`, `decor/tombstone_*.png`, `decor/monument_*.png`, `decor/fence_*.png`, `decor/crypt_*.png`, `decor/ground_tiles.png` | Roman, AI-generated ("Dead Trees", "Graveyard Props" sheets) | project | room decoration and ground tiles |
| `sprites/knight_idle.png`, `nun_idle.png`, `villager_idle.png`, `elian_wake.png`, `elian_talk.png`; `decor/ground_tiles.png`, `wall_tiles.png`, `pillar.png`, `arch.png`, `rocks.png`, `grass_*.png`, `bush.png`, `ruin_stumps.png`; `ui/icons/*.png` | Roman, AI-generated (NPC/tileset sheet, civilian Elian sheet, "Dark Realms" icon pack), `tools/art/slice_batch5.py` | project | prototype art |
| `decor/graveyard/*.png` (tomb, cross, monument, railing, crypt, coffin, grave, yard, deadwood, angel, bones, ground — 55 pieces), `decor/wilds/*.png` (tree, sapling, fallen, stump, brush, ground — 30), `decor/clutter/*.png` (clutter ×5, brazier and altar strips 32×40 ×4 plus `_lit` stills) | Roman, AI-generated ("Graveyard Props", "Dead Trees", chest/interactables sheets), `tools/art/slice_batch10.py` | project | prototype art; scattered into rooms by `dress=` in `tools/rooms/generate_rooms.py` |
| `icons/realm/*.png` (142 icons, 24 px: resources, potions, gear, status, markers, banners, documents, relics, trinkets, weather, trophies, loot, badges, runes) | Roman, AI-generated ("Dark Realms" icon pack), `tools/art/slice_batch10.py` | project | prototype art; gift cards (`icon` in `data/abilities/`) |
| `icons/quest/*.png` (94 icons, 24 px: keys, letters, relics, essence, remedies, gate keys, tools, materials, ritual things, keepsakes, emblems, flasks, trophies, curios) | Roman, AI-generated ("Quest Items" sheet), `tools/art/slice_batch10.py` | project | prototype art; what chests hold (`icon` pools in `data/props/`) |
| `props/chest_iron.png` (40×32 ×6), `props/barrel_apples.png`, `props/box_goods.png`, `props/rubble.png` (48×40 ×4) | Roman, AI-generated (chest/destructibles sheets), `tools/art/slice_batch10.py` | project | new chest and breakables (`data/props/`) |
| `backgrounds/*.png` (640×360) | Roman, AI-generated | project | prototype backdrops, parallax layers in rooms |
| `fonts/Forum-Regular.ttf` | Denis Masharov | https://github.com/google/fonts/tree/main/ofl/forum | SIL OFL 1.1, `fonts/OFL-Forum.txt` — display face (titles, buttons); Latin + Cyrillic, no CJK |
| `fonts/EBGaramond-Variable.ttf` | The EB Garamond Project Authors (Octavio Pardo, Georg Duffner) | https://github.com/google/fonts/tree/main/ofl/ebgaramond | SIL OFL 1.1, `fonts/OFL-EBGaramond.txt` — body face; Latin + Cyrillic, no CJK |
| `audio/sfx/*.ogg` (swings, impacts, footsteps, interface clicks, jingles) | Kenney Vleugels | https://kenney.nl/assets/impact-sounds · /ui-audio · /rpg-audio · /music-jingles | CC0 — copied untouched; level and pitch are set in `scripts/autoload/audio.gd` |
| `audio/music/menu.ogg` | qubodup | https://opengameart.org/content/dark-shrine-loop | CC0 |
| `audio/music/village_night.ogg`, `audio/music/dead_bridge.ogg` | Tsorthan Grove | https://opengameart.org/content/the-world-fell-silent | CC0 |
| `audio/music/graveyard.ogg` | Eponasoft | https://opengameart.org/content/cold-silence | CC0 |
| `audio/music/boss_knight.ogg` | Emma_MA | https://opengameart.org/content/determined-pursuit-epic-orchestra-loop | CC0 — encoded from the WAV source |
| `audio/music/boss_ophanim.ogg` | cynicmusic | https://opengameart.org/content/epic-endgame-cinematic | CC0 — encoded from the WAV source |
| `audio/music/arena.ogg` | cynicmusic | https://opengameart.org/content/dramatic-boss-encounter | CC0 — encoded from the WAV source |
| `audio/music/end.ogg` | beardalaxy | https://opengameart.org/content/dark-urban-church-theme-loop | CC0 |
| `audio/sfx/prop_break.wav`, `audio/music/ambient_night.wav` | Roman, synthesised by `tools/audio/generate_sfx.py` | project | placeholder, stands in until a real clip is chosen |

Not used on purpose: two generated sheets depicting a real footballer and a Marvel character (likeness and
trademark rights), and a modern cityscape with real-world political symbols (off-theme, and a liability in the
game's own target markets).

Prototype art is a placeholder for the real art pass (see `docs/ROADMAP.md`). Note that purely
AI-generated images may not be copyrightable in some jurisdictions, so they are not suitable as the
"official artwork" the monetization plan relies on; that artwork must be human-made.

When adding an asset, append a row. Third-party assets must be CC0 / CC BY / OFL.

Audio is not hand-placed: `tools/audio/build_audio.py` holds the source URL of every third-party clip
and rebuilds `assets/audio/` from them, so the set above can be re-fetched, re-tuned or swapped out
without guesswork. Sources that are already Ogg Vorbis are copied byte for byte.

### Music library (generated)

| File | Author — title | Source | License / notes |
|---|---|---|---|
<!-- music-manifest:start -->
| `audio/music/ossuary_6_air.mp3` | Kevin MacLeod — "Ossuary 6 - Air" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/long_note_one.mp3` | Kevin MacLeod — "Long Note One" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/virtutes_vocis.mp3` | Kevin MacLeod — "Virtutes Vocis" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/lost_frontier.mp3` | Kevin MacLeod — "Lost Frontier" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/heart_of_nowhere.mp3` | Kevin MacLeod — "Heart of Nowhere" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/sunset_at_glengorm.mp3` | Kevin MacLeod — "Sunset at Glengorm" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/ossuary_2_turn.mp3` | Kevin MacLeod — "Ossuary 2 - Turn" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/gathering_darkness.mp3` | Kevin MacLeod — "Gathering Darkness" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/dark_times.mp3` | Kevin MacLeod — "Dark Times" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/long_note_two.mp3` | Kevin MacLeod — "Long Note Two" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/ghost_story.mp3` | Kevin MacLeod — "Ghost Story" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/the_dread.mp3` | Kevin MacLeod — "The Dread" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/darkest_child.mp3` | Kevin MacLeod — "Darkest Child" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/ossuary_5_rest.mp3` | Kevin MacLeod — "Ossuary 5 - Rest" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/unseen_horrors.mp3` | Kevin MacLeod — "Unseen Horrors" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/ossuary_1_a_beginning.mp3` | Kevin MacLeod — "Ossuary 1 - A Beginning" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/deep_noise.mp3` | Kevin MacLeod — "Deep Noise" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/anguish.mp3` | Kevin MacLeod — "Anguish" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/shadowlands_5_antechamber.mp3` | Kevin MacLeod — "Shadowlands 5 - Antechamber" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/lightless_dawn.mp3` | Kevin MacLeod — "Lightless Dawn" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/penumbra.mp3` | Kevin MacLeod — "Penumbra" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/virtutes_instrumenti.mp3` | Kevin MacLeod — "Virtutes Instrumenti" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/ossuary_7_resolve.mp3` | Kevin MacLeod — "Ossuary 7 - Resolve" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/volatile_reaction.mp3` | Kevin MacLeod — "Volatile Reaction" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/killers.mp3` | Kevin MacLeod — "Killers" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/grim_league.mp3` | Kevin MacLeod — "Grim League" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/rites.mp3` | Kevin MacLeod — "Rites" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/exit_the_premises.mp3` | Kevin MacLeod — "Exit the Premises" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/five_armies.mp3` | Kevin MacLeod — "Five Armies" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/impact_prelude.mp3` | Kevin MacLeod — "Impact Prelude" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/wretched_destroyer.mp3` | Kevin MacLeod — "Wretched Destroyer" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/stormfront.mp3` | Kevin MacLeod — "Stormfront" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/achilles.mp3` | Kevin MacLeod — "Achilles" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/aftermath.mp3` | Kevin MacLeod — "Aftermath" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/immersed.mp3` | Kevin MacLeod — "Immersed" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/wounded.mp3` | Kevin MacLeod — "Wounded" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/lamentation.mp3` | Kevin MacLeod — "Lamentation" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/decline.mp3` | Kevin MacLeod — "Decline" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/evil_awaits.mp3` | bosslevelaudio — "Evil Awaits" | https://opengameart.org/content/evil-awaits | CC0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/clocktower.mp3` | symphony — "Clocktower" | https://opengameart.org/content/clocktower | CC0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/beyond_redemption.mp3` | ISAo — "Dark Solemn Choral with Organ" | https://opengameart.org/content/dark-solemn-choral-with-organ | OGA-BY 3.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/final_boss_appearance.mp3` | ISAo — "Final Boss Appearance Dark Fantasy" | https://opengameart.org/content/final-boss-appearance-dark-fantasy | OGA-BY 3.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/blood_stained_glass.mp3` | FoxSynergy — "(Blood) Stained Glass" | https://opengameart.org/content/blood-stained-glass | CC BY 3.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/long_note_three.mp3` | Kevin MacLeod — "Long Note Three" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/floating_cities.mp3` | Kevin MacLeod — "Floating Cities" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/satiate.mp3` | Kevin MacLeod — "Satiate" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/relent.mp3` | Kevin MacLeod — "Relent" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/moorland.mp3` | Kevin MacLeod — "Moorland" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/hidden_past.mp3` | Kevin MacLeod — "Hidden Past" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/dark_walk.mp3` | Kevin MacLeod — "Dark Walk" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/disquiet.mp3` | Kevin MacLeod — "Disquiet" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/dark_fog.mp3` | Kevin MacLeod — "Dark Fog" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/curse_of_the_scarab.mp3` | Kevin MacLeod — "Curse of the Scarab" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/mourning_song.mp3` | Kevin MacLeod — "Mourning Song" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/grave_matters.mp3` | Kevin MacLeod — "Grave Matters" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/shadowlands_1_horizon.mp3` | Kevin MacLeod — "Shadowlands 1 - Horizon" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/shadowlands_4_breath.mp3` | Kevin MacLeod — "Shadowlands 4 - Breath" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/the_descent.mp3` | Kevin MacLeod — "The Descent" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/crypto.mp3` | Kevin MacLeod — "Crypto" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/nightmare_machine.mp3` | Kevin MacLeod — "Nightmare Machine" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/controlled_chaos.mp3` | Kevin MacLeod — "Controlled Chaos" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/failing_defense.mp3` | Kevin MacLeod — "Failing Defense" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/malicious.mp3` | Kevin MacLeod — "Malicious" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/undaunted.mp3` | Kevin MacLeod — "Undaunted" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/echoes_of_time_v2.mp3` | Kevin MacLeod — "Echoes of Time v2" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/prelude_and_action.mp3` | Kevin MacLeod — "Prelude and Action" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/redletter.mp3` | Kevin MacLeod — "Redletter" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/thunderbird.mp3` | Kevin MacLeod — "Thunderbird" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/deadly_roulette.mp3` | Kevin MacLeod — "Deadly Roulette" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
| `audio/music/voxel_revolution.mp3` | Kevin MacLeod — "Voxel Revolution" | https://incompetech.com | CC BY 4.0 — trimmed to 150s, loudness-normalised, MP3 VBR q7 by `tools/audio/fetch_music.py` |
<!-- music-manifest:end -->
