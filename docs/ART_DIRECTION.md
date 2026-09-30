# Art direction

What the game looks like, why, and how to add to it without breaking it. For
contributors: read this before drawing anything, then read the tool named in
the section you are working in — almost every picture in the game is either
painted once and cut by a script, or drawn by a script outright, and the
script is where the exact numbers live.

Licences first: `LICENSE-ASSETS.md`. Nothing with a non-commercial or
no-derivatives clause enters the repository; every third-party file gets a row
in `assets/CREDITS.md`.

## The look in one paragraph

Dark gothic pixel art, painted rather than tiled: a night lit by candles,
moon and embers, worn blue-grey masonry, moss, ash in the air. Readable before
beautiful — a body, a blade and a wind-up must read against any wall at 640×360.
Warm light means life (candles, gold, grace); cold light means the
otherworldly (spirits, the moon, glass); red is blood and temptation, and
nothing else uses it loudly. The text is set in EB Garamond and Forum, the
Chinese in Noto Serif SC: a manuscript, not an arcade.

## The screen

- The game renders at **640×360**, integer-scaled, nearest filtering
  (`project.godot`). One art pixel is one screen pixel at 1×: never draw at a
  scale the camera will stretch, and never blow a small texture up in code.
- Draw order in a room (CLAUDE.md): terrain and `DecorMid` behind characters,
  `DecorFront` (z 1) only for low clutter over the feet, weather z 2, effects
  z 4–6, numbers z 10. Anything a body can walk *behind* is `DecorMid`.
- The lowest fifth of any background stays dark and quiet: that is where the
  bodies are.

## Rooms

**Painted panels** (`assets/levels/<name>.png`, 1280×720) are the first
location. The picture *is* the level: colliders trace its ledges
(`tools/rooms/trace_panel.py`), the generator widens it to 1600 by quilting
two seams (`tools/rooms/generate_rooms.py`, `_quilt_band`), and props stand on
what the painting shows. A new panel:

- straight-on side elevation, no perspective floor, entrance left and exit
  right, a real doorway at the exit (the game's door overlays it);
- ledges a hero can stand on drawn as ledges — flat tops, readable edges; no
  floating platforms the painting does not support;
- landmarks (the moon, a tower, an old tree) away from where the seams go, or
  listed in `FOCAL_RANGES` so the quilt leaves them whole;
- the sky openings that should slide with the camera listed in
  `RoomLayers.FAR_WINDOWS`, their plates in `assets/levels/depth/`;
- its lights (candles, windows, lava) in `<name>.lights.json`, so the game's
  `GlowLight`s sit on the painted flames.

The prompts that made the current interiors are kept beside them
(`docs/CHURCH_ART_V1.md`, `PREACHER_NAVE_ART_V1.md`, `OPHANIM_SANCTUM_ART_V1.md`,
`HELL_CORNICE_ART_V1.md`) — start from those for a matching style.

**Built rooms** (arenas, the church, the practice yard) are a 640×360 backdrop
in `assets/backgrounds/` behind floor and ledges laid from the sheet pieces in
`assets/decor/platforms/`. A backdrop is far scenery only: sky, hills,
architecture across the middle, nothing a body could seem to stand on.
`tools/art/make_practice_yard.py` is an example drawn entirely in code, in the
same limited palette (≈56 colours, Floyd–Steinberg dithered).

Lighting is never baked: rooms get an `Ambient` tint from their table and
every light is a `GlowLight` (`Fx.light`), so the "Lighting" setting can turn
them all off.

## Characters

**The hero** (`assets/sprites/elian_*.png`, 128×64 cells): feet on the bottom
row at x = 68, body 43 px tall — a hair under the village knight. Every strip
is cut by `tools/art/slice_hero.py` from generated sheets and listed in
`tools/art/build_elian_frames.py`; the special moves are drawn *from his own
frames* by `tools/art/make_elian_moves.py` (after-images, a glowing rim, a
hot arc) so they cannot drift off-model. The swings have their white arc drawn
in; path colour (gold, red) and the finisher's heavy arc are the `Slash`
sprite's (80×48).

**Enemies** come from one generated atlas each
(`assets/sprites/enemy_atlases/<id>.png`): a 7×7 grid, rows idle, walk,
attack, attack_alt, special, hurt, death. `tools/art/build_bestiary_assets.py`
cuts it into strips *as whole shapes* — a swing that crosses the grid line
stays in its frame, the next frame's blade stays out — scales every frame of a
creature by one factor taken from its idle row, keeps walkers' soles on the
bottom row, and grows the cell to fit the widest swing (written into
`data/enemy_archetypes/tree.json`). Rules for a new atlas:

- one creature, the same scale in every cell, room around it — a big spell
  may overflow its cell, a neighbour must not reach into it;
- idle row first and clean: it sets the scale and the anchor for everything;
- the attack rows carry their own arcs and magic; bolts in flight are the
  game's (`assets/sprites/projectiles/*_flight_v3.png`, four 96×128 frames),
  not the atlas's;
- every enemy attack has a readable wind-up (CLAUDE.md): draw one.

Portraits for the bestiary are 192×192 (`assets/portraits/`). Enemy `material`
(flesh, cloth, mail, plate, bone, feather, spirit, gold) chooses both the hit
sounds and what a death leaves behind — pick it by what the thing is made of.

## Effects

- Particles are 1:1 pixel shapes (`Fx.PIXELS`: a glint, a flake, a drop, a
  scrap, a shard, a feather, a wisp, a star, an ember), coloured by the
  emitter and never scaled up. A soft blob blown up into a square is the one
  thing that makes this game look cheap.
- A blast shows its reach (`Fx.ring`); a light shows as a `GlowLight`; smoke
  (`Fx.puff`) stays small.
- One-shot effects go through `Fx`, never an ad-hoc emitter; CPUParticles
  only (GL Compatibility and the Web build have no GPU particles).
- The hero's lean is shown on the body by a shader
  (`assets/shaders/alignment_marks.gdshader`), from the sprite's alpha: no
  painted mask needed, none should be added.

## UI

Nine-patch frames from the UI pack (`OrnateBar` and friends), gold for what
matters (`#f2d98c` family), dim lilac-grey for what does not. Text sizes 8–11
at 640×360. Every string is a key in `localization/strings.csv` with all four
columns; Chinese needs its characters in the font subset
(`tools/art/make_cjk_font.py`).

## Before you open a pull request with art

1. Run the tool that owns the file, not an image editor on its output — then
   `python3 tools/check_generators.py`: a generator that no longer writes what
   is committed fails CI.
2. `make import` (Godot keeps serving the old texture otherwise), then
   `validate_data.gd`: it checks every strip against its cell.
3. Look at it in the game: `scripts/tools/combat_fx_shot.gd` (a death and a
   bolt per enemy), `room_overview_shot.gd`, `layer_motion_shot.gd`,
   `practice_shot.gd`, `bestiary_screenshot.gd`.
4. Credit it in `assets/CREDITS.md`.
