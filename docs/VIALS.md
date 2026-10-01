# The vials of wrath

The ladder above a dawn (Dead Cells' Boss Cells, docs/DEAD_CELLS_GAP_ANALYSIS.md). A night won opens the next vial;
Settings → Vial of wrath picks the one the next night is played under, from those opened. Seven vials are poured in
Revelation 16; chapter I pours five. The chapter is "The First Trumpet", which is why the rungs are not trumpets.

Each vial keeps every rule of the ones below it and adds one:

| Vial | Adds | Ash |
|---|---|---|
| I | a quarter of the possessed and the fallen guards rise as their elites | ×1.25 |
| II | one flask fewer | ×1.5 |
| III | every blow against the hero ×1.2 | ×1.75 |
| IV | an altar gives back half the bar, not all of it | ×2 |
| V | enemy HP ×1.25, and half of them rise as elites | ×2.5 |

On top of the difficulty mode, not instead of it: a vial is a new rule, the mode is a dial.

## Rules

- `data/vials`: `tier` 1..5, `ash`, `rules`. `Vials.rules(tier)` stacks them: `flasks` add, `enemy_damage` /
  `enemy_hp` multiply, `promote_chance` takes the highest, `rest_heal` the lowest, `promote` maps merge.
- `Game.vial` is set when a night starts (`Vials.for_new_night`: the chosen one, held to what the profile opened) and
  kept in saves. `Profile.data.vials_opened` rises on a dawn to the vial played + 1.
- Solo only: online the two bodies and the host's enemies would each carry their own. The practice yard has none.
- A dawn under vial N counts `wins_vial_N`; deeds `vial_first` and `vial_last` read them.
- The end screen names the vial played and the one a dawn opened.
- The angel greets a night under a vial (`ch1_intro`, router branch `{"vial": N}` = at least N): one line at
  I–II, another at III–IV, another at V, in place of the habit's line.

`scripts/run/vials.gd`, `vials_test.gd`.
