# Omens

From the fourth night on, most nights (`Omens.CHANCE`, 60 %) are drawn under an omen: one rule that helps and
one that hurts, said once over the opening, shown in the pause menu, on the night's end and in the chronicle.
The vials of wrath are a ladder the player climbs on purpose; an omen is the weather — it makes two nights
of the same chapter play differently without asking anything of the player.

## Data

`data/omens/*.json`:

```json
{"id": "blood_moon", "name": "OMEN_BLOOD_MOON", "description": "OMEN_BLOOD_MOON_DESC",
 "rules": {"enemy_damage": 1.15, "essence": 1.3}}
```

`rules` are the vials' rules (`docs/VIALS.md`) and stack the same way on top of the vial's
(`Vials.rules()` adds tonight's omen; `Vials.rules(tier)` asked about one vial leaves it out), plus:

| Rule | Read in | Effect |
|---|---|---|
| `essence` | `Game.add_essence` | essence from every source, multiplied |
| `ash` | `Vials.ash_multiplier` | the night's Ash, multiplied with the vial's |

The validator refuses an omen that is not a trade (something that helps and something that hurts),
an unknown rule, and `promote_chance` without its `promote` map.

## Rules

- The first `Omens.FROM_NIGHT` (3) finished nights are plain: a new player meets the chapter as it is.
- Settings → Omens (`Settings.omens`, shown once they have begun) turns them off for the player's own nights.
- Solo only, none in the practice yard. The night of the day draws the day's own from its seed, the same for
  everyone, whatever the profile or the switch.
- The bestiary has a page per omen (`omen:<id>`, between the deeds and the chronicle), named once a night has
  been drawn under it: what it trades, its nights and its dawns (`Profile.record_run` keeps them).
- `Game.omen` goes into `Saves.capture` / `restore`; an omen since removed loads as a plain night.
- A tool script (`godot -s`) draws none on its own — a test that starts a run measures blows and flasks —
  unless it asks (`Omens.for_new_night(true)`).
- `omen_test.gd`.
