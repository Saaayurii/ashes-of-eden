# The practice yard

A cloister at dusk where the dead are fought again, and the moves are learnt
without a night at stake. Dead Cells has its training room; this is ours
(docs/DEAD_CELLS_GAP_ANALYSIS.md).

## Getting there

- **Main menu → Practice yard**: the straw man (`training_dummy`), for the
  moves themselves. It takes any blow, shows the number, rocks on its post and
  never falls; left alone for two seconds it is whole again.
- **Bestiary → a creature's page → Spar with it**: any kind the player has
  *seen*, bosses included, bar the Ophanim's seals. Only from the main menu's
  bestiary: from the pause menu it would walk out of the night being played.
- **The night's end → Spar with it: <name>**: after a death to anything the
  yard can stand up, the end screen offers that very creature (solo only; not
  the lava, the drop or a seal). The night is already over, so nothing is lost
  by going.

All three set `Game.practice` to an enemy id and start the Run, which opens
`scenes/rooms/practice_yard.tscn` (`Run.PRACTICE_ROOM`, room index
`Run.PRACTICE_INDEX`) instead of the chapter. Leaving through the pause menu
clears it.

## Drills

`interact` (E, the pad's button, the touch pad's talk button — shown
everywhere in the yard) changes what stands across from the hero
(`scripts/run/practice_drills.gd`, `Run.drills`):

- **Spar** — the foe the yard was opened for (the straw man from the menu).
- **Guard** — a foe that swings: hold Block into the blow, raise it as the
  blow lands to parry. The straw man, a boss or a seal is stood in for by the
  fallen guard, whose wind-up is the slowest of the walkers.
- **Volley** — a foe that shoots (the zealot, unless the yard's own foe does):
  a parry sends the bolt back, a roll goes through it.
- **Stalk** — a foe pacing its patch with its back to the hero, set down on
  the spot of the floor farthest from him. Once it knows he is there — seen,
  or struck — it is put back unaware `STALK_RESET` seconds later, elsewhere.

The move list counts blocks (`EventBus.player_blocked`), parries and
backstabs, and the parries in a row since the last wound with the best such
run. One foe at a time: changing the drill clears the floor and gives the
room's count back by hand, so a respawn already due does not stand up a
second. `practice_drills_test.gd`.

## Nothing counts

A practice kill pays no essence and no Ash, writes nothing in the bestiary or
the profile (so it cannot unlock a cloak either), the yard is never
autosaved, the playtest log ignores it, and the run clock hardens nobody. The
foe stands up again `PRACTICE_RESPAWN` seconds after it falls; the hero cannot
lose and gets up at the gate. Anything new that rewards or records play has to
check `Game.practice` too — `practice_test.gd` checks the ones there are. The one thing the yard does write is what it is for: a move done there is
known (`Profile.data.moves_done`), so the night stops hinting at it.

## The room

Painted in code by `tools/art/make_practice_yard.py` (backdrop, straw man,
weapon rack, the dummy's strips), in the limited palette of the other
backdrops; the room itself is a `practice_yard` table in
`tools/rooms/generate_rooms.py`: a flat floor for footwork, a ledge each side
and one over the middle for the moves in the air. The Ophanim's seal points
include it, so its seal phase plays here too.
