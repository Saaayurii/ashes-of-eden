# Elian's moves

The core loop stays dumb — move, attack, roll, block, pick a gift — and the
depth goes into what those buttons do together. Every move below is made of
the buttons the player already has, so nothing needs a new key or a new touch
button: the stick presses the same `move_*` actions the keys do.

| Move | Input | What it does |
|---|---|---|
| **Lunge** | back, forward + Attack (each within 0.3 s) | a rush of `LUNGE_TIME` at `LUNGE_SPEED` that runs the blade through everything in its path, ×1.6 |
| **Cleave** | hold Attack after a swing; let go once it glows | the blade drawn back (slow feet), then the hardest blow there is: ×2.4, a wide reach, knocks back hard and staggers |
| **Sweep** | down + Attack on the ground | a low cut at the feet, ×0.8, that takes a walker off its feet (stagger) |
| Rising cut | up + Attack, or Attack in the air | the anti-air swing |
| Strike from the roll | roll, then Attack | the roll's swing |
| Slam | down in the air | the plunge (`_start_slam`) |
| Wall jump | hold into a wall, Jump | off the wall, the air jump back |
| Riposte | block as it lands, then Attack | the parry's opening (`Enemy._open_left`) |
| Backstab | attack one who has not seen you | the sneak blow (`Enemy.is_unaware`) |

The first three are new; the rest were always there and are listed so the
practice yard can teach them.

## How they are built

- `Player._read_technique_input` reads the taps and the held button every
  frame of our own body; `_technique_for_press` turns an attack press into a
  move; `_technique` poses the body, sizes the hitbox and hands over to
  `_land_hits`, the same hit resolution the three-blow chain uses. So crits,
  lifesteal, the dodge counter, wrath, backstabs, executes, items and gifts
  all apply to a lunge exactly as to a swing.
- The lunge is two taps the opposite ways: the second tap's direction is the
  one it goes, whatever way he faced, because by the time the input is read
  the first tap has already turned him.
- The cleave's charge starts `CHARGE_AFTER` into a held attack once the swing
  that press made has finished, and is ready at `CHARGE_FULL` (a flash, a
  sparkle, the draw of a blade). Let go before that and nothing happens; a
  wound, a jump, a roll or a heal breaks it.
- Every move reports itself with `EventBus.technique_performed(id)`; riposte
  and backstab are reported by the enemy they land on.
- The animations are drawn from Elian's own frames by
  `tools/art/make_elian_moves.py` — the lunge is the thrust with after-images
  and speed lines, the charge the slam's raised blade with a breathing gold
  edge, the cleave the slam with its arc turned to hot gold, the sweep the
  roll's low cut between a crouch and a rise — and listed in
  `tools/art/build_elian_frames.py`. Both are in `check_generators.py`.

## The list

`data/techniques` names each move and its keys. The practice yard
(docs/PRACTICE.md) shows them in a panel (`scripts/ui/move_list.gd`): dim
until done once, then gold and ticked, and each move's name over the hero's
head as it comes off. A night never shows the list. `techniques_test.gd`
presses the keys as a player would and measures what comes out.
