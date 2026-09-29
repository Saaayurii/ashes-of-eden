# How enemies fight

The rule is simple: an enemy is dangerous because of what it does when it
steps in, not because it stands in the hero's face. Every creature keeps a
distance, comes in to strike, and gives ground afterwards. All of it lives in
`scripts/enemies/enemy.gd` and runs on the host; bodies are replicated by
position, so none of it needs an RPC.

## Walkers

- **Between blows** (`_keep_distance`) a walker holds a band just outside its
  melee reach: from `reach + 12` to that plus `_band_depth` (26–52 px, rolled
  per body). Every 0.6–1.4 s it picks a new spot in the band and walks there,
  forward or backing off while still facing the hero. That pacing is what
  makes a fight read as footwork instead of a queue at the counter.
- **Stepping in.** Only when an attack is nearly ready (`_attack_cd <= 0.3`)
  and it holds one of the `ATTACKERS_PER_SIDE` (2) slots on its side of the
  hero. The rest wait in the band, `CROWD_STEP` (22 px) further back for each
  of its kind ahead of it (`_count_crowd`, recounted with the target every
  0.4 s). A crowd forms a queue, not a stack; a waiting body still uses a
  lunge or a nova if the hero is in its range.
- **Giving ground.** After a melee blow or a lunge (`_disengage_left`), and
  sometimes after taking a hit (`hit_retreat`, default 0.35, in the enemy's
  JSON), it backs off before coming again. It never backs off a ledge.
- **Changing attacks.** `_choose_attack` already made a repeat less likely;
  now an attack used twice running is refused a third time while anything
  else is in range.
- Shooters (no melee move) hold their range; bosses simply come on.

## Flyers

- **Hovering.** A flyer circles on a ring at least `FLYER_MIN_GAP` (48 px)
  out, alternating near and far on its own timing (`_fly_phase`); each flyer
  after the first hunting the same player hovers 16 px further out and 10 px
  higher, so a flock reads as several birds.
- **Striking.** It closes in only to strike: a melee peck is an attack run to
  its beak's reach at head height; a lunge goes through. Afterwards it flies
  out and up (`_disengage_left`) before anything else.
- **Never parked on the body.** Outside an attack run, a flyer inside the
  hero's `PERSONAL_SPACE` (36 px from the chest) is pushed off, harder the
  deeper it is (`_personal_space`), including while it recovers from a lunge
  that ended on him. Flyers keep `FLOCK_SPACE` (30 px) from one another.
  Bodies were never solid to the hero (`flyer_combat_test.gd`); this is about
  not hiding him either.

## Measured

`scripts/tools/enemy_spacing_test.gd` stands a hero who cannot die on a floor
and lets real enemies at him. Against the code before this pass it fails: the
guard spent 77 % of its time in the hero's face (now under 40 %), three
cultists bunched into 26 px (now a 49 px queue), a shade sat on his body for
36 frames at a time (now at most a frame or two).
