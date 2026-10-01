# Elites

An elite is the chosen of the dead: a stronger kind of a common enemy (`"elite"` in `tags`
in `data/enemies`, never a boss). Four stand in chapter I — the elite possessed, the fallen
champion, the Zealot Brothers (`elite_cultist`) and the elder wraith — and the vials of wrath
and the omen of the Procession promote more of the commons into them (`Run._spawn_enemy`,
`docs/VIALS.md`).

## Read before it swings

- **The mark** (`Enemy._mark_elite`): a low ember light under it and a mote rising off it now
  and then. A tint alone was too quiet. `vials_test.gd`.
- **The affix** (`data/affixes`, `Enemy._apply_affix`): every elite rises with one, its name
  over the head in its colour (lifted back from the room's night so it reads):

  | Affix | Life | Blows | Between blows | Speed | Armour |
  |---|---|---|---|---|---|
  | Ironclad | — | — | — | ×0.85 | +0.2 |
  | Swift | ×0.85 | — | ×0.85 | ×1.35 | — |
  | Brutal | — | ×1.35 | ×1.15 | — | — |
  | Enduring | ×1.6 | ×0.9 | — | — | — |

  Never the wind-up: every blow stays readable. The host rolls the affix (`Run.roll_affix`)
  and carries it in the spawn data, so both players fight the same body. Commons, bosses and
  anything in the practice yard rise with none. The validator bounds the mods (multipliers
  0.5–2, armour 0–0.3). `affix_test.gd`.

## What it is worth

- **The cache** (`Enemy._leave_cache`, prop `elite_cache`): its fall leaves a chest on the
  floor under the body — a common item while any are left tonight, and 30 essence. Laid on
  every peer as it sees the death; never in the yard; a flyer over a pit leaves none.
  `elite_cache_test.gd`.
- **Trophy Hunter** (a rare will gift, stat `chosen_damage`): blows on elites and bosses
  +25 %, capped at +60 % in all. `gift_test.gd`.
- **Rest points** raise the common dead again; elites stay down.

## What it remembers

- The bestiary page of an elite lists the affixes it has been beaten in ("Beaten as",
  `Profile.record_affix`).
- The night's end names the affix of an elite that laid him low (`Game.slain_affix`).
- Deeds: **The Chosen Laid Low** (one of every elite) and **Hunter of the Chosen** (twenty-five
  elites, counter `elites`).
- The balance probe counts the caches real hands opened (`trade_rows`).
