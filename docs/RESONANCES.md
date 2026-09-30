# Resonances

What gifts do together that none does alone (docs/DEAD_CELLS_GAP_ANALYSIS.md: "improve the synergies of the gifts
we have before adding a second build system"). No new currency, no mutation slots: the gifts a night already
offers, read in pairs and in sets.

## Kinds

| Kind | Needs | Wakes |
|---|---|---|
| A path's chord | 3 or 5 gifts of one path | the path's own mechanic, a second one at 5 |
| A pair | two named gifts **of different paths** | a mechanic that ties them together |

| Id | Needs | Does |
|---|---|---|
| `chorus` | 3 × grace | a parry stops everyone near for 0.5 s (`parry_stun`) |
| `radiant_host` | 5 × grace | the flask scorches around you (`heal_burst` 25), a clean room refills one (`clean_clear_charge`) |
| `bloodied` | 3 × temptation | after a wound the next swing is worth +60 % (`wrath_after_hit`) |
| `devourer` | 5 × temptation | a crit under a third of the bar heals 6, +0.3 `execute` |
| `cutting_stride` | 3 × will | the roll cuts for 10 (`dash_damage`) |
| `unbroken_line` | 5 × will | the finisher's arc (`wave_damage` +0.4), roll cooldown ×0.85 |
| `thorned_oath` | Briar Mantle + Blood Pact | +0.15 `thorns`, +0.3 `wrath_after_hit` |
| `last_rites` | Executioner + Severing Arc | +0.3 `execute` |
| `shadow_step` | Knife in the Dark + Cutting Roll | a backstab gives the roll back (`backstab_refresh`) |
| `bulwark` | Iron Vigil + Ward of the Nameless | one more blow absorbed per room (`guard`) |

## Rules

- A resonance is a mechanic from `Player.BASE_STATS`, under `AbilitySystem.CAPS` like any gift — never "+20 % damage".
- It wakes once, on the gift that completes it (`AbilitySystem.apply`), and stays for the night.
- The card that would complete one says so (`◆ Chorus`): the reason to take a lesser gift is on the card.
- The HUD and the end screen list the ones awake; the toast names one as it wakes; the playtest log records it.
- A save keeps the body's stats, which already hold the resonances; `Saves.restore` reads the list off the gifts.
- A pair within one path is refused by the validator: the count already covers it.

`data/resonances`, `scripts/combat/resonances.gd`, `resonance_test.gd`.
