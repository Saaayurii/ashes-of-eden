# Liquids — water, lava, bog, blood

A pool is a `Hazard` (`scripts/rooms/hazard.gd`, an `Area2D` in the group `liquids`) of one **kind** from `data/liquids.json`. The kind decides how it looks, how it moves, what it does to the hero and to enemies, what it throws off and how it sounds. Pools are data: a new kind is a new entry in the file, not new code.

## Where pools come from

- **A painted room's `hazards=[(x, y, w, h)]`** in `tools/rooms/painted_rooms.py`: the lava that is already in the picture. The generator writes it as `kind = "lava"`, `painted = true`. A painted pool draws its body at `painted_opacity` (the picture already shows the lava) and keeps the living rim, the particles, the light and the sound.
- **The studio** (room editor → «Жидкости»): a pool is drawn on the room and saved into `tools/rooms/studio_rooms.json` as `"liquids": [[kind, x, y, w, h, {"painted": true}?]]` in finished-room pixels. Here `y` is the surface and `h` the depth. `generate_rooms.py` merges it into the room's table and writes `Liquid<i>` nodes. The validator refuses an unknown kind or a pool smaller than 16×8.

Never place a pool in the editor alone: the tables are the rooms (`check_generators.py`).

## A kind (`data/liquids.json` → `kinds.<id>`)

| key | what it does |
|---|---|
| `colors` | `surface`, `body`, `deep`, `foam` (the 1-px rim) and `glow`, given to `assets/shaders/liquid.gdshader` |
| `opacity`, `painted_opacity` | how much of the body is drawn (a painted pool: the picture shows through) |
| `texture` | a 64×64 seamless body from `tools/art/make_liquids.py` (`assets/fx/liquids/body_<kind>.png`); missing = a plain gradient |
| `flow`, `shimmer` | the body texture's drift and the glints near the top; lava's cracks also glow and breathe (`molten`, set from `burns`) |
| `waves` | the living surface (`scripts/rooms/liquid_surface.gd`): a resting swell (`amplitude`, `speed`, `length`) and a spring per 4 px column (`spring`, `damping`, `spread`, and `splash`, how hard a push lands) |
| `body` | what it is to stand in: `drag` (run and dash), `buoyancy` (gravity is cut by it), `sink_speed` (how fast a body falls in it), `swim` (the stroke `jump` gives in deep liquid, 0 = none), `swim_cooldown`, `jump` (a jump off its floor is × this) |
| `damage`, `burns` | per hit through `Player.burn`, which hurts through a roll and puts him back on his last safe floor |
| `kills_walkers` | a walker that steps in falls (lava) |
| `enemy` | `drag` for walkers, `heal_per_second` (blood mends them), `harms` per `material` in dps (water burns a `spirit`) |
| `douses` | a bolt that meets it is put out in steam |
| `heal` | `{path, per_second}`: it mends the hero only while he leans that path (`Game.lead() >= 2`), never online for anyone but our own body |
| `particles` | `ambient` (glints / bubbles / embers / gas / clots) every `ambient_every` s, what a `splash` flings (drops / magma / mud / blood), the `trail` a body carries out (drips / smoke / mud) for `trail_time` s, and its `tint` |
| `light` | `{color, radius, energy, every, flicker}`: a `GlowLight` every `every` px along the surface (lava) |
| `sounds` | `enter`, `big`, `exit`, `wade`, `bubble` cues and an `ambient` loop (played through `Audio.looping`, on the SFX bus) |

`_check_liquids` in the validator bounds every number, checks the colours, the texture, the materials, the path and that the sounds have clips.

## What happens

- **Falling in** splashes by how fast you hit it: a small splash, a big one, or a slam (×2.2). You get the drawn strip (`LiquidFx.splash`), a ripple, flung drops, the sound, and a `world_impulse` the backdrop answers. The surface sinks where you landed and the wave runs to both ends.
- **Wading** leaves a ripple and a wade sound every `WADE_EVERY` and keeps pushing the springs.
- **Deep liquid** (`LIQUID_SWIM_DEPTH`) turns `jump` into a swim stroke. Gravity is cut by `buoyancy` and the fall is capped at `sink_speed`. A slam in it is slowed (`LIQUID_SLAM`).
- **Leaving** throws a rising splash, and the body carries its `trail` for a while.
- **A blade swung over it** throws spray. **A flyer skimming it** leaves a wake. **A bolt** is put out (`douses`) or burns away (lava).
- **Enemies** wade at `enemy.drag`. The host alone decides harm, healing and lava's fall (`_touch_enemy`).
- **Lava** burns, lights its surroundings, throws embers and haze and pops. Bog is slow, thick and gassy. Blood mends what crawls in it.

Everything you see is cosmetic and local on every peer, because each peer sees the same bodies move through the pool. What it does to a body follows the multiplayer rule: our own body on our side, enemies on the host.

`Settings.backdrop_motion` off stills the swell and the shader's drift, and the springs still answer a body. `Settings.flash_scale()` scales the glow.

## Art and sound

- `tools/art/make_liquids.py` → `assets/fx/liquids/` (bodies, `splash`, `splash_big`, `lava_splash`, `ripple`, `bubble`, `lava_pop`, `gas_pop`, `steam`, `drip`, `surface_glint`, `manifest.json` with cells and fps), contact sheet `tools/art/contact/liquids.png`. It reads its colours from `data/liquids.json`, is deterministic, goes through `patched()` and is in `check_generators.py`. `LiquidFx` (`scripts/fx/liquid_fx.gd`) plays the strips. A missing strip leaves only the particles.
- Sounds: `splash`, `splash_big`, `splash_out`, `wade`, `sizzle`, `lava_splash`, `lava_bubble`, `water_bubble`, `bog_squelch`, `bog_bubble` (takes) and `water_loop`, `lava_loop`, `bog_loop`, `blood_loop`. They are placeholders from `tools/audio/generate_sfx.py liquids` plus CC0 takes in `sfx_manifest.json`. `MIX` rows are in `audio.gd`.

## The studio

The «Жидкости» tab edits `data/liquids.json` with a live preview that ports `liquid_surface.gd`'s springs and `liquid.gdshader`: change one, change the other.

## Tests

`liquid_test.gd` checks that:

- every kind builds a surface;
- water slows the run, catches a fall and is stirred by it;
- jump is a stroke in deep water;
- lava burns, puts him back on safe ground and takes a walker;
- a walker wades slowly;
- blood mends an enemy, and the hero only on its path;
- water puts out a bolt;
- the generator writes pools.

`lava_room_test.gd`, `crypt_lava_exit_test.gd` and `hurt_grace_test.gd` keep the painted lava honest.
