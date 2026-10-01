# Data formats

All content lives in `data/<collection>/*.json`. A file is either one object or an array of objects.
Every object needs a unique `id`. Any field starting with `_` is reserved.
Strings the player sees are **localization keys**, resolved from `localization/strings.csv`.

Run `make validate` to check everything below.

## Abilities (gifts) — `data/abilities/`

```json
{
  "id": "blood_pact",
  "name": "ABILITY_BLOOD_PACT_NAME",
  "description": "ABILITY_BLOOD_PACT_DESC",
  "path": "temptation",
  "icon": "res://assets/icons/realm/status_2.png",
  "rarity": "rare",
  "alignment": {"temptation": 1},
  "effects": [
    {"type": "stat", "stat": "attack_damage", "op": "mul", "value": 1.35},
    {"type": "stat", "stat": "max_hp", "op": "add", "value": -15}
  ]
}
```

- `path`: `grace` | `temptation` | `will`. After each wave the player is offered one gift per path.
- `rarity`: `common` | `rare` | `epic` | `legendary` (default `common`). Weights 55 / 30 / 12 / 3 decide how
  often a card is offered inside its path's pool (`RARITY_WEIGHT` in `run.gd`), never how strong it is. The card
  shows it (`RARITY_<NAME>` keys) and is tinted by it.
- `icon`: optional, shown on the card. Without it the card shows its path's icon. The 142 icons in
  `assets/icons/realm/` (weapons, armour, potions, status marks, relics, runes…) are there to pick from.
- `alignment`: hidden counters to shift when the gift is taken.
- `effects[].type`:
  - `stat` — `stat` is any key of `Player.BASE_STATS` (`max_hp`, `speed`, `attack_damage`, `attack_cooldown`, `attack_scale`, `crit_chance`, `crit_multiplier`, `backstab_multiplier`, `dash_speed`, `dash_time`, `dash_cooldown`, `armor`, `lifesteal`, `extra_lives`, `heal_charges`, …), `op` is `add` or `mul`. The validator rejects unknown stats.
    Mechanic stats — all 0 by default, so a body without the gift is unchanged:

    | stat | what it does | cap |
    |---|---|---|
    | `guard` | blows absorbed outright; refilled at the start of every room | 3 |
    | `thorns` | fraction of a blow taken dealt back to the attacker | 0.6 |
    | `kill_heal` | health returned by every kill | 10 |
    | `clear_heal` | health returned when a room is cleared | 40 |
    | `execute` | extra damage (`1 + execute`) to an enemy at or under 30 % health (`Enemy.EXECUTE_BELOW`) | 1.2 |
    | `essence_bonus` | extra essence from every kill (mirrored to `Game.essence_bonus`) | 0.6 |
    | `dash_damage` | damage the roll deals to each enemy it passes through, once per roll | 45 |
    | `wave_damage` | the third hit of a chain throws an arc worth `attack_damage × wave_damage` | 1.2 |
  - `lifesteal` — `value` fraction of damage dealt returned as health.
  - `extra_life` — `value` extra deaths survived (revive at 50% hp).
  - `heal` — `value` amount or `"full"`.

Effect `skill` gives the active skill (one at a time, key `skill`):
`{"type": "skill", "skill": {"kind": "nova" | "bolt" | "drain", "cooldown": 8, "damage": 22, "color": "#ffe9a8", ...}}` —
`nova`: `radius`, `heal` (hurts everything around, mends the hero); `bolt`: `speed` (a heavy thrown spear);
`drain`: `range`, `drain` (the nearest enemy in front, heals that fraction of the damage). Damage scales with `attack_damage`.

## Enemies — `data/enemies/`

Large visual/moveset expansions may live in `data/enemy_archetypes/`. Entries
use an existing enemy `id` and are recursively merged after inheritance is
resolved. This layer owns bestiary `family`, `tier`, `parent`, `avatar`, the
expanded `attacks` list and `abilities`, allowing each family to grow as a tree
without duplicating the base health and movement record.

```json
{
  "id": "shade",
  "name": "ENEMY_SHADE",
  "hp": 12, "speed": 95, "damage": 5, "attack_interval": 0.6,
  "size": 10, "color": "#3a2a55",
  "tags": ["spirit"]
}
```

- `behaviour`: `walker` (gravity, walks at the player within `aggro_range`), `flyer` (drifts at the player, bobbing)
  or `boss_ophanim` (hovers beside the player, lunges), or `seal` (hangs where it is put and only breaks: the
  Ophanim's seals). `damage` is contact damage per `attack_interval` (0 = none).
- `seal_phase` (a boss): `{"at_hp": 0.5, "seal": "ophanim_seal", "points": {"<room>": [[x, y], ...]}, "exposed": 6,
  "exposed_bonus": 0.5, "sealed_cooldown": 1.6}`. At `at_hp` of its health — a floor no blow can skip — the boss
  closes its eyes: nothing hurts it, a `seal` enemy appears at each of the room's points (room pixels; hang them
  ~22 px over a floor the hero stands on, `seal_phase_test.gd` checks), and it hovers out of reach using only
  attacks marked `"sealed": true` (`"sealed_only": true` keeps one for this phase alone), `sealed_cooldown` times
  slower. The last seal broken opens it: for `exposed` seconds it sinks low, does not attack and takes
  `exposed_bonus` more from every blow. Once per fight.
- `attacks` (optional list; a single `attack` object works too) — telegraphed attacks. Every type has a `windup`
  the enemy spends glowing and standing still; that is the window to roll through. Hitting an enemy during its
  wind-up may stagger it (`stagger_chance`). When several attacks are in range one is picked by `weight`.
  - `{"type": "melee", "range": 34, "reach": 40, "windup": 0.42, "damage": 16, "cooldown": 1.1, "recover": 0.3}`
  - `{"type": "ranged", "range": 260, "windup": 0.75, "damage": 10, "cooldown": 2.2, "projectile_speed": 160, "projectile_style": "zealot", "color": "#ffd27a"}` —
    `projectile_style` is one of the animated flights (`wraith` · `zealot` · `acolyte` · `preacher` · `cult` · `ash` · `ophanim`,
    `scripts/fx/projectile.gd`); the validator refuses a ranged enemy attack without one. `projectile_motion` separately
    chooses its path: `straight` (default), `wave` (sideways sway), `accelerate`, `arc` (falls), `surge` (pauses then rushes),
    or `return` (reverses after a miss). Non-straight paths require a positive `motion_amount`: pixels of sway,
    acceleration factor, downward bend, delay in seconds, or turnaround time in seconds respectively. A returned
    projectile must turn before its four-second lifetime ends.
  - `{"type": "lunge", "range": 420, "windup": 0.8, "damage": 20, "cooldown": 2.6, "lunge_speed": 430, "lunge_time": 0.45}`
  - `{"type": "beam", "range": 460, "windup": 1.1, "damage": 24, "cooldown": 3.4, "length": 440, "thickness": 26, "duration": 0.5, "color": "#ffd66a"}` —
    a cross of light through the enemy; only chosen when the player is near one of its axes. Thin lines during
    the wind-up show exactly where it will fire.
- Nobody starts hostile. An enemy patrols around its spawn until it notices a player: `sight: {"range": 210, "height": 70, "behind": 22}`
  is the cone in front of its face (cut by walls and floors) and the radius behind its back it can still feel you in;
  `patrol: {"radius": 110, "speed": 0.45, "pause": [0.8, 2.4]}` is how far it wanders, at what fraction of `speed`, and how
  long it stands at each end. Defaults are per behaviour (flyers see further and higher). `aware: true` skips all that.
  A hit on an enemy that has not noticed anyone is a backstab (docs/BALANCE.md).
- `behaviour: "caster"` is a walker that backs away from a player closer than `keep_away` (px, default 90), never off a ledge.
- How walkers and flyers keep their distance, queue up and give ground is docs/ENEMY_AI.md. `hit_retreat`
  (optional, default 0.35) is the chance a walker backs off after a hit instead of coming straight on.
- Attack type `summon`: `{"type": "summon", "id": "shade", "count": 2, "max_alive": 3, "range": 320, "windup": 1.1, "damage": 1, "cooldown": 6}` —
  after the wind-up calls `count` of `id` out of the ground beside it, never more than `max_alive` about (the Cult caller).
- `light` (optional): `{"color": "#5fe0b0", "radius": 56, "energy": 0.8, "flicker": 0.1}` — a `GlowLight`
  carried by the body (spirits, relics, bosses). `color` defaults to the enemy's `color`.
- `parry_opening` (optional, seconds, default 0.9): how long a parried swing leaves the enemy open to a
  riposte (halved for a boss).
- `material` is what the sword lands on: `flesh` · `cloth` · `mail` · `plate` · `bone` · `feather` · `spirit` · `gold`.
  It picks the impact sound — `<id>_impact_1..3` when `tools/audio/generate_voices.py` has made clips for that
  creature, `hit_<material>` for anything else. An entry with `extends` inherits its base's material.
- `boss: true` shows the boss bar, disables knockback, starts the enemy aware and lets the body linger dimmed after
  death (a cutscene may still want to look at it; `"lingers": false` makes it fade like the others); `summons: {"id": "shade", "count": 2, "at_hp": 0.5}` spawns reinforcements once.
- `tags` are free-form and reserved for story/ability interactions. The bestiary shows them, so every tag
  needs a `TAG_<NAME>` localization key (`"spirit"` → `TAG_SPIRIT`).
- `lore` (optional): localization key of a sentence or two for the bestiary page (`ENEMY_SHADE_LORE`).
- `tip`: localization key of one line of advice (`TIP_SHADE`), given on the night's end when this enemy
  laid the player low and on its bestiary page. Required for anything that can kill (not a `seal` or a `dummy`).
  The bestiary (`scenes/ui/bestiary.tscn`) lists every enemy id in the data; a kind is "seen" once it
  spawns in the player's room and "known" once one has died — only then are stats and lore shown.
  Progress lives in `Profile.data.bestiary`, across runs.

Optional `sprite`. Without it the enemy is drawn as a `color` rectangle. Either one strip:

```json
"sprite": {"path": "res://assets/sprites/possessed.png", "frame_w": 24, "frame_h": 28, "frames": 4, "fps": 6}
```

or one strip per animation (`idle` required; `walk`, `attack`, `hurt`, `death` optional — `attack` frame 0 is held
during the wind-up, `death` plays instead of the ash squash):

```json
"sprite": {"cell": [32, 40], "fps": 9, "animations": {
  "idle": "res://assets/sprites/cultist_idle.png", "walk": "...", "attack": "...", "death": "..."}}
```

Every strip is a whole number of `cell`s wide and exactly one cell tall (the validator checks it on the merged
data). The bestiary's strips are cut by `tools/art/build_bestiary_assets.py`, which also writes their `cell` (and,
for a flyer whose strip it had to pad above and below, `pad_y`, which keeps the body over its hitbox) into
`data/enemy_archetypes/tree.json`: regenerate, never edit those by hand. `"like": "cultist"` borrows another
creature's strips and cell; `"tint": "#c8b4ff"` colours the drawing (the Cult caller is a cultist in another robe).

Optional `unlock_nights`: the night this gift starts appearing on. `"unlock_nights": 3` keeps it out
of the pool entirely until the profile has finished three runs, so a later night can hold a card an
earlier one could not. A gift without the field has always been available. Locks are ignored in a
duel, where both players must be offered the same cards. The night a gift unlocks on, the run says
so once in a caption (`UNLOCKED_TONIGHT`).

## Dialogues — `data/dialogues/`

```json
{
  "id": "ch1_stranger",
  "start": "stranger_1",
  "nodes": {
    "stranger_1": {"speaker": "SPEAKER_STRANGER", "text": "DLG_CH1_STRANGER_1", "next": "stranger_2"},
    "stranger_2": {
      "speaker": "SPEAKER_STRANGER",
      "text": "DLG_CH1_STRANGER_2",
      "choices": [
        {"id": "kill",   "text": "DLG_CH1_STRANGER_KILL",   "effect": {"grace": 1, "set_flags": ["stranger_killed"]}, "next": "after_kill"},
        {"id": "listen", "text": "DLG_CH1_STRANGER_LISTEN", "effect": {"temptation": 1}, "next": "after_listen"}
      ]
    },
    "after_kill": {"speaker": "SPEAKER_ELIAN", "text": "DLG_CH1_STRANGER_AFTER_KILL"}
  }
}
```

- `"blocking": false` turns the dialogue into captions at the top of the screen: no pause, auto-advance,
  no choices allowed. Use it whenever the player should keep playing (the intro). Captions yield
  automatically if a blocking dialogue starts.
- A **router** node has `branches` instead of text: `{"branches": [{"flag": "stranger_killed", "next": "m_killed"}], "next": "m_default"}`.
  The first branch whose flag is in `Game.flags` wins; `next` is the fallback. This is how NPCs react to
  choices made rooms earlier (see `docs/CHAPTER1.md` §3).
- A node without `next` and without `choices` ends the dialogue.
- `effect` accepts `grace` / `temptation` / `will` (integers) and `set_flags` (list of story flags stored in `Game.flags`).
- Dialogues are started from code: `await $UI/DialogueBox.play("ch1_stranger")`. They pause the game and are always skippable.

## Cutscenes — `data/cutscenes/`

```json
{"id": "ophanim_arrival", "steps": [
  {"do": "hold"},
  {"do": "letterbox", "on": true, "time": 0.4},
  {"do": "move", "who": "boss", "by": [0, -140], "time": 0.0},
  {"do": "camera", "to": "boss", "zoom": 1.25, "time": 1.1},
  {"do": "move", "who": "boss", "by": [0, 140], "time": 2.2, "ease": "out"},
  {"do": "dialogue", "id": "ch1_ophanim_arrival"},
  {"do": "anim", "who": "player", "anim": "draw"},
  {"do": "letterbox", "on": false, "time": 0.3},
  {"do": "release"}
]}
```

A scene is a list of steps played in order by `scripts/ui/cutscene.gd`; a room names one in `intro_cutscene`
(as it starts) and `outro_cutscene` (when it is cleared). Any button skips: the remaining steps are applied
instantly, so the world after a skipped scene equals the world after a watched one. Actors: `player` (our own
body), `boss`, `door`, `npc:<id>`; a point is `[x, y]` in room pixels.

| step | fields | what happens |
|---|---|---|
| `hold` / `release` | — | hands off the controls, every enemy freezes / hands back. A scene that holds must release. |
| `letterbox` | `on`, `time` | black bars slide in or out |
| `wait` | `time` | |
| `camera` | `to`, `zoom`, `time` | a camera of its own glides to the actor or point (room limits kept); `to: "player"` is home |
| `move` / `walk` | `who`, `to` or `by`, `time`, `ease` | slide the body (walk also plays its walk strip and turns it) |
| `anim` | `who`, `anim`, `hold` | play a strip on the body (`hold`: freeze on the first frame, enemies only) |
| `face` | `who`, `dir` | turn the body (−1 / 1) |
| `dialogue` | `id`, `wait` | a dialogue from `data/dialogues` (captions run under the scene; `wait: false` lets the scene go on) |
| `shake`, `sound`, `music`, `fade` | `strength` / `name`, `volume` / `name` / `to`, `time`, `color` | theatre |
| `appear` / `vanish` | `who`, `time`, `ash` | a figure fades in / out; `ash: true` leaves a burst of ash (struck down, not leaving). A vanished NPC is gone for good |

**Conditions.** Any step may carry `"if": "flag"` (or a list — all of them), `"unless": [...]` (none of them), or
`"path": "grace" | "temptation" | "will"` (the way the run leans). They are read when the step is reached, so a choice
made earlier in the same scene counts:

```json
{"do": "dialogue", "id": "ch1_stranger"},
{"do": "vanish", "who": "npc:stranger", "ash": true, "time": 0.35, "if": "stranger_killed"},
{"do": "vanish", "who": "npc:stranger", "time": 0.8, "unless": ["stranger_killed", "stranger_heard", "stranger_refused"]}
```

A dialogue with choices inside a scene is shown as the bottom panel; skipping it means no choice was made.
An NPC entry with `"scripted": true` is somebody who exists only for a scene: hidden until an `appear` step, never
talked to on E (the Stranger, `data/npcs/stranger.json`).

Online, every peer plays the scene itself (rooms load on every peer); a body is only moved by the peer that
simulates it and arrives elsewhere through the synchronizer.

## Forks — `data/forks/`

Where the chapter's way splits and joins again (scripts/run/route.gd, docs/CHAPTER1.md).

```json
{
  "id": "swamp_fork",
  "after": "res://scenes/rooms/swamp_moon.tscn",
  "dialogue": "fork_swamp",
  "options": {"red": "res://scenes/rooms/swamp_red.tscn", "crypt": "res://scenes/rooms/swamp_crypt.tscn"},
  "then": "res://scenes/rooms/catacombs_1.tscn"
}
```

- Leaving `after`, the Run plays `dialogue`; the id of the answer picked is a key of `options`, and that
  room comes next (skipped or unanswered: the first). Out of any option the next room is `then`.
- The options stand next to each other in `ROOMS`; every room stays in `ROOMS`, a fork only decides
  which ones a night walks. `Route.step` numbers the rooms along the way walked, with no gap.
- An option must carry no story — no `intro_cutscene`/`outro_cutscene`/`intro_dialogue`, no NPC, no
  rest point — or the night that took the other way would lose it; the validator refuses one.

## Chapters — `data/chapters/`

The places a run walks through, and what the curtain between two rooms says. One entry covers a stretch
of rooms; the card is shown when the player walks into a stretch they were not in a moment ago, so a
chapter with four rooms announces itself once.

```json
{
  "id": "graveyard",
  "chapter": "CHAPTER_I",
  "title": "AREA_GRAVEYARD",
  "subtitle": "AREA_GRAVEYARD_SUB",
  "color": "#b9c6d8",
  "sound": "bell",
  "rooms": ["res://scenes/rooms/graveyard_cross.tscn", "res://scenes/rooms/graveyard_arches.tscn"]
}
```

- `chapter` / `title` / `subtitle` are localization keys: the overline, the name of the place, and one
  line under it. `subtitle` is optional, the other two are not.
- `color` tints the title and the rule; `sound` is an `Audio` name played as the card opens (optional).
- `rooms` are scene paths, and no room may be claimed by two chapters (`validate_data` refuses it).
  A room no chapter claims still gets the curtain, without a card.

`scripts/autoload/curtain.gd` plays it: the old room burns away along a noise front
(`assets/shaders/ash_curtain.gdshader`), the swap happens behind the black, the card comes up over
drifting embers, and the new room burns back in. Any button cuts the card short; the curtain itself is
never skipped, since it is what hides the seam. Rooms inside one chapter get the curtain plus the
place's name at the bottom, and nothing else — "clear, door, next" should not stop dead every time.
A room with an `intro_cutscene` gets a brisk card: it names the place and hands over to the scene.

The same curtain carries every other seam, because it is an autoload and outlives the scene under it:
the menu into a night, a death into the verdict, the verdict back out. `Settings.transitions`
(`full` / `short` / `off`) is the player's say in how much of it they sit through. Where a night ended
and where a creature was first met are named by their chapter too — the end screen, the save slots
and the bestiary all read `Data.chapter_for()`.

## Content roots and mods

`Data` loads every collection from several roots; a later root overrides an earlier one by `id`:

1. `res://data` — this repository.
2. `res://content/data` — official overlay (private repo checked out into `./content`, optional).
3. `user://mods/<mod-name>/data` — player mods, same folder layout.

So a mod that ships `data/abilities/my_pack.json` adds gifts, and one that reuses an existing `id` replaces it.

## Rooms — `scenes/rooms/*.tscn`

## Music — `data/music/playlists.json` and `tools/audio/music_manifest.json`

A room's `music` (and the menu's / end screen's) is a *mood name*, looked up in `playlists.json` first:
`"graveyard": ["graveyard", "ghost_story", "the_dread", ...]` → one is picked at random, never the same
twice in a row, and kept across rooms that ask for the same mood. A name with no playlist is a file in
`assets/audio/music/`. The library itself is described in `music_manifest.json` (source URL, author,
license, moods) and built by `tools/audio/fetch_music.py`: download → trim to 150 s with fades →
−18 LUFS → MP3. Adding a track is one manifest entry; the credits block in `assets/CREDITS.md` is
generated from it.

## Ambience — `data/ambience.json`

Living details a room gets, matched by a substring of its scene name: `ravens`, `bats`, `leaves`,
`petals`, `wisps`, `motes`, `embers`, `low_fog`, `lightning` (flash, light and a delayed `thunder`).
Built by `scripts/rooms/ambience.gd` from CPUParticles2D and sprites; never touches gameplay.

## Creature voices — `<voice>_alert / _attack / _hurt / _death`

Every enemy calls `_voice(kind, fallback)` at its alert, wind-up, hurt and death; it plays
`assets/audio/sfx/<id>_<kind>` when the clip exists (the `voice` field in enemy data renames the set)
and the generic cue otherwise. `tools/audio/generate_voices.py` synthesises a distinct placeholder set
for every id — a growl, a whisper, a chime, a bell — to be replaced by real clips of the same name.


## NPCs — `data/npcs/`

```json
{"id": "nun", "name": "NPC_NUN", "dialogue": "npc_nun", "face": "left",
 "sprite": {"path": "res://assets/sprites/nun_idle.png", "cell": [32, 44], "fps": 3}}
```

A person who is not hostile. Placed in a room through the generator's `npcs=[("nun", x, y)]`. When the
player walks up they speak their `dialogue` once (a caption dialogue, never blocking). Their body is on
no physics layer: you walk through people. They turn to whoever walks up; `wander` (px) lets them stroll
about their spot, or `path: [[dx, dy], ...]` gives them a round of stops (relative to their spot, each
must be on a ledge — the generator checks) with `pace` seconds at each; `travel: "fade"` makes them
vanish and reappear at the next stop instead of walking. `light` is carried like an enemy's, `motes` is
a colour of dust hanging about them, `lines` are keys muttered now and then after the talk. The bestiary
page (people get pages after the enemies: "???" → silhouette once you shared a room → page once you
talked) shows `role`, `location`, the first of `lines` and `lore`. `menu: false` keeps a data entry off
the main menu's character carousel (used when two entries share one strip).
`guard: {"range", "reach", "damage", "cooldown", "speed", "leash"}` makes them fight: they walk at an
enemy that comes within `range` on their ledge (never further than `leash` from their spot — a person
has no gravity) and swing at it. `sprite.animations: {"idle", "walk", "attack"}` works like the enemies';
without drawn `walk`/`attack` strips the idle strip bobs along and the swing is a lunge behind the slash. The world should
never be only enemies — see `docs/GDD.md` §10.

Areas are hand-made scenes, not data (level layout is where a human eye matters). A room is a `Node2D`
with `room.gd` and these children, in draw order: `Ambient` (CanvasModulate, the room's night; obeys the
"Lighting" setting through `ambient_light.gd`), `Parallax/Backdrop` (painting, `scroll_scale` 0.1, plus
`PointLight2D`s on the lamps painted into it), `FogFar/Fog` (fog shader), `DecorBack` (Parallax2D 0.88
with `assets/decor` sprites), `Geometry` (StaticBody2D, layer 1: ground, side walls — colliders only),
`Ledges` (layer 5, one-way colliders), `Terrain` (the art for both: pieces of
`assets/decor/platforms/` laid side by side by the generator — grass-topped earth for the ground, stone
shelves with hanging moss for ledges, wall segments at the room's edges), `DecorMid` (what stands on the
lanes behind the characters: tombstones, fences), `DecorFront` (z 1, low clutter over their feet: grass,
rocks), `Props` (breakable barrels and chests, see below), `Spawns` (markers with `enemy_spawn.gd` and an
`enemy_id`), `PlayerSpawn`, `Door` (opens when everything spawned is dead), `Weather` (z 2, CPUParticles2D:
embers / rain / fireflies), `Motes` (dust in the air), `Lights` (the room's own `GlowLight`s from the
generator's `lights=[(x, y, colour, radius, energy, flicker)]`; `ambient="#rrggbb"` is the tint).

**Painted rooms** (`tools/rooms/painted_rooms.py`, the first location): the room is one painted source panel
(`assets/levels/<name>.png`, normally 1280x720, made by `tools/rooms/trace_panel.py` from the generated
picture) and the colliders trace what is drawn on it. `generate_rooms.py` inserts two scenery bands into
each panel and shifts the colliders, lights, props and spawns with them; the figures and masonry keep their
original size. A conservative reachability check fails generation if a mandatory path breaks. Instead of
`backdrop`, the room has `painting`;
`ground` (solid) and `ledges` (jump-through) are painted and get no art; `ramps=[(x0, y0, x1, y1)]` are
painted stairs as slopes; `platforms` are extra broken steps drawn with sheet pieces, used only where the
painting leaves a gap no double jump can cross; `lights="auto"` places `GlowLight`s on the candles the
tracer found (`<name>.lights.json`). Every room has its entrance on the left (`player`) and its exit on
the right (`door`); the generator's `check_reach` proves the exit, every walker and every prop can be
reached from the entrance (single jump 46 px, double 93 px, ~165 px across) and prints what cannot.

**Interior rooms** (`interior=True`, the church): no painting and no fog; the generator tiles wall pieces
over the whole back (`Interior`), stands `pillars=[(x, floor_y)]` on the floor, and `floor="ledge"` picks
the stone-shelf pieces for the ground. Indoors the lights multiply into dark stone, so they are bigger and
brighter than outside. `bell=(x, y)` adds `church_bell.gd`: three strokes with a flash and a tremor when
the player rings it in Father Matthew's dialogue (choice `bell`). A room with no `spawns` is quiet: its
door is open from the start.
Optional fixtures carry `room_fixture.gd` and react when the last enemy dies: `Shrine` lights up,
`Barrier1..n` (the arena walls) fade out. `intro_dialogue` on the room plays a caption dialogue when it
starts (the boss talking). Copy an existing room, move the rectangles, change the ids,
add the path to `ROOMS` in `scripts/run/run.gd`.

## Props — `data/props/`

```json
{"id": "barrel", "kind": "destructible", "hp": 1, "essence": 4, "hitbox": [20, 26],
 "sprite": {"path": "res://assets/props/barrel.png", "frame_w": 48, "frame_h": 40, "frames": 4}}

{"id": "chest_cursed", "kind": "chest", "essence": 120, "glow": "#ff6a6a", "icon": "res://assets/icons/crystal_blue.png",
 "effect": {"temptation": 1}, "item": "rare", "curse": 10, "hitbox": [24, 20], "sprite": {"...": "40x32, four frames"}}
```

Scenery you can interact with, placed through the generator's `props=[("barrel", x, y)]`. The strip runs
whole → cracked → bursting → leftovers for a `destructible`, closed → open for a `chest`. A
`destructible` is hit by the sword (`scripts/props/prop.gd` answers `take_damage` like an enemy does, and
the player's swing looks at areas as well as bodies); a `chest` opens when the player walks into it and
pays out `essence`, an optional `heal`, an optional alignment `effect` and a floating `icon` — one path,
or a list of paths the chest picks from each time it opens (`chest_iron` draws from twenty-odd quest
items in `assets/icons/quest/`). A chest with `curse` (1–30) does not open on touch: standing at it shows
its price, `interact` opens it, and the opener's wounds land twice as hard until that many enemies have
fallen (`Player.take_curse`, saved with the body, paid off by a death; `curse_test.gd`). Props are
never enemies: nothing blocks movement and the room's door does not wait for them.

For a living four-frame prop use `"idle_frames": 2, "hit_frame": 2`: frames 0–1 loop while intact,
frame 2 is the hit/break reaction, and the last frame is the remains. `ambient` may be `candle`, `spores`,
`soul`, `bottles` or `dust` (grit trickling from a secret wall); it adds a restrained light or particle accent.

Items: a chest with `"item": "common"` or `"rare"` also holds one item from `data/items/` —
`{"id", "name", "description", "rarity": "common" | "rare", "icon", "effects": [{"type": "stat", "stat", "op", "value"}]}`,
where the stat is one of the item mechanics (`heal_burst`, `parry_stun`, `chest_heal`, `backstab_refresh`,
`clean_clear_charge`, `wrath_after_hit`, `desperate_crit_heal`; the validator refuses anything else). The item goes
onto the body of whoever opened the chest, each item once a night; a rare chest falls back to a common item.

Skins: `data/skins/*.json`, `{"id", "name", "description", "cloak": {"hue": 0..1, "saturation": ×, "value": ×},
"armor": "#rrggbb", "unlock": {"nights": n, "total_kills": n, "kills": {"<enemy>": n}}, "sku": ""}` — the hero's
cloak and a tint on the rest of him (docs/MONETIZATION.md: cosmetics are data). `unlock` is read from the Profile;
an entry with a `sku` is a store's and stays locked until there is one.

Rest points: `data/rest_points/*.json`, `{"id": "<room scene name>", "at": [x, y]}` — a spot on the room's floor, at
something the painting already shows (an altar, a statue with candles). See `scripts/rooms/rest_point.gd`.

Secrets: a destructible with `"reveals": "<prop id>"` leaves that prop where it broke (a bricked-up
doorway and the cache behind it); `"still": true` turns off the variation and sway for masonry. A secret
wall must read as a bricked-up doorway: either the painting already has the arch it stands in (listed in
`NICHE_PAINTED` in the validator), or `"niche": "<png>"` draws one behind it — a stone ring and the dark
behind the bricks, made with the wall by `tools/art/make_secret_walls.py` — which stays when the wall
comes down, so the cache is found standing in a doorway. A chest
with `"note": "<id>"` files a record from `data/notes/` (`{"id", "name", "dialogue", "place", "avatar"}`)
in the bestiary and plays its `dialogue` as a caption; its `"ash"` is paid only the first time that
record is found, so a cache with Ash must carry a note. Every prop also has stable scale/phase
variation and reacts to nearby land, jump, dash, attack and parry impulses. The room generator replaces
obviously misplaced generic clutter through `contextual_props()` while preserving all reward chests.

## Alignment

`Game.alignment` holds three hidden integers. `Game.dominant_path()` returns the leaning path (ties → `will`).
The player never sees the numbers. Use them to gate dialogue nodes, change visuals, pick endings.
