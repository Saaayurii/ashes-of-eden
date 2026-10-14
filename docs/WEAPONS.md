# Weapons

A night used to differ only by its gifts: the hero had one weapon, the sword.
In a game of this kind a new weapon is what makes a night feel new, so the hero
now finds them — four in all, the sword among them — and every one is data.

No weapon has frames of its own yet. Each is a chain of the poses Elian already
has (`attack`, `attack2`, `attack3`, `thrust`, `rising`, `dash_strike`), its own
reach (the hitbox), the arc the `Slash` sprite draws over it (`white`, `gold`,
`red`, `heavy`, or `path` — the lean's colour) and a handful of numbers.

Their icons are their own: the sword keeps the realm pack's (`gear_1`), the
other three are cut from one generated sheet on a magenta key
(`tools/art/weapons/weapon_icons_raw.png`) by `tools/art/make_weapon_icons.py`
into `assets/icons/weapons/` — regenerate, don't hand-edit (it passes them
through `patched()`, so the studio's touch-ups survive).

## The four

| Weapon | Chain (poses) | Per blow (× `attack_damage`) | Recovery (× `attack_cooldown`) | Reach | Per second | What it is for |
|---|---|---|---|---|---|---|
| Elian's Sword (`sword`) | attack · attack2 · attack3 | 1.0 · 1.1 · 1.6 | 0.45 · 0.45 · 1.0 | 30 × 30 box, ~44 px | ~24 | the all-rounder, every night's first |
| Pilgrim's Spear (`spear`) | thrust · thrust · dash_strike | 1.0 · 1.1 · 1.6 | 0.6 · 0.6 · 1.1 | 54 × 16 box, ~68 px | ~20 | reach: hits from where a walker cannot answer, but a hand high — a flyer above it is missed |
| Headsman's Blade (`headsman`) | attack3 · attack2 | 1.9 · 2.6 | 1.15 · 1.5 | 40 × 40 box, ~52 px | ~21 | two slow blows that stop what they land on (stagger 0.35 / 0.55 s); poise 0.3 |
| Twin Knives (`daggers`) | attack · attack2 · thrust · attack | 0.55 · 0.55 · 0.6 · 0.75 | 0.28 · 0.28 · 0.28 · 0.55 | 24 × 26 box, ~36 px | ~22 | quick and short; backstab +1 (×3.5 on the hero's ×2.5); four hits for every on-hit gift |

"Per second" is the chain's damage over its recovery (`Weapons.chain_damage` /
`Weapons.chain_time`) at a fresh body; `weapon_test.gd` measures it against the
straw man and fails if it strays more than a fifth from the data, or if any
weapon strays more than a quarter from the sword. No weapon is simply better:
each pays for what it is good at.

## The format (`data/weapons/<id>.json`)

```json
{
  "id": "spear",
  "name": "WEAPON_SPEAR", "description": "WEAPON_SPEAR_DESC",
  "icon": "res://assets/icons/weapons/spear.png",
  "hitbox": [54, 16], "offset": [36, -6],
  "slash_scale": [1.35, 0.6],
  "pitch": 0.9, "auto_reach": 62, "combo_window": 1.1,
  "damage": 1.0, "backstab": 0.0, "poise": 0.0,
  "chain": [
    {"animation": "thrust", "multiplier": 1.0, "recovery": 0.6, "wind": 0.05,
     "knockback": 1.2, "heavy": false, "arc": "path", "animation_time": 0.3, "speed": 0.85}
  ],
  "techniques": {"lunge": {"hitbox": [84, 20], "offset": [44, -6]}},
  "notes": "for whoever tunes it; never shown"
}
```

Weapon-wide: `hitbox` / `offset` (the box every chain step uses unless the step
has its own), `slash_scale` (the drawn arc, x and y), `pitch` (the swing sound),
`auto_reach` (how far the auto-attack assist looks), `combo_window`, and three
numbers on every blow, techniques included: `damage` (×), `backstab` (added to
the hero's `backstab_multiplier`), `poise` (the share of a wound not taken while
a swing is out). Per step: `animation`, `multiplier`, `recovery`, `wind` (a
breath between the hit frame and the bite — it delays the blow, not the next
one), `knockback`, `heavy` (lands like a finisher: the hit-stop, the shake, the
wave of Ashen Wake), `stagger`, `arc`, `animation_time` and `speed` (the pose's
playback). `techniques` lays keys over a special move's own
(`player_actions.json` lunge / cleave / sweep). The validator (`_check_weapon`)
bounds every one of them and refuses a pose Elian does not have.

**The sword is the hero's own chain.** Its steps name only their animation, and
a key a step leaves out is the hero's own for that step: `combo_multipliers`,
`combo_recovery`, `combo_window` in `hero.json` and the `attack` / `attack2` /
`attack3` rows of `player_actions.json`, which the studio's «Боёвка» tunes. So
the sword plays exactly as it did before weapons existed and the studio still
edits it in the one place it always did. Any other weapon must give
`multiplier`, `recovery`, `knockback` and `heavy` on every step (the validator).

## In play

- `Player.weapon` (replicated through `NET_PROPERTIES`, so the other player's
  arc is drawn the weapon's size), `Player.equip(id)` returns the one laid down.
  `_attack` reads the step, `_land_hits` is unchanged but for `damage` and
  `backstab` — so every gift, item, resonance and technique applies to every
  weapon, and the knives' four hits feed lifesteal four times.
- **Found**: a chest prop with `"weapon": true` (the gold chest) lays one weapon
  a night beside itself (`Prop._lay_weapon`, `Game.weapon_found`), never the one
  in hand, the night of the day's from its seed. It lies on the floor as a
  `WeaponDrop`: standing at it shows its name, `interact` takes it, and the one
  in hand is laid where it lay — nothing is lost by trying one. Local to the
  peer who opened the chest, like an item.
- **The practice yard** has a rack: every weapon not in hand on the floor behind
  the gate. There `interact` takes a weapon when one is under his feet and
  changes the drill otherwise.
- **Kept**: `Saves.capture` writes `player.weapon` and `weapons_used`; an old
  save, or a weapon since removed, restores as the sword.
- **Told**: Pause → Gifts lists the weapon first, the codex keeps a page per
  weapon (`weapon:<id>`, named once held), the chronicle line keeps the weapon
  the night ended with, the end screen names it when it was not the sword, and
  `Playtest` logs `weapon` on `run_start`, `run_end`, `death` and a `weapon`
  event for each one taken.

## Adding one

1. `data/weapons/<id>.json` with a chain of poses Elian has, and an icon: a fourth
   shape on the sheet (and its id in `IDS`), then `make_weapon_icons.py`.
2. `WEAPON_<ID>` and `WEAPON_<ID>_DESC` in `localization/strings.csv`, all four
   columns; new Chinese characters → `python3 tools/art/make_cjk_font.py`.
3. `validate_data.gd`, then `weapon_test.gd`; keep it within a quarter of the
   sword's damage a second.
