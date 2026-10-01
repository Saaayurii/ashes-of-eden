# Deeds

Things a player did once, remembered by the profile: the first night, each boss, a dawn on each path, fifty
parries, every record behind the walls. They are the achievements a store will show one day. Until then they live
in the game: a line at the top of the screen when one is done, and a section at the end of the bestiary that lists
every deed by name, with how far along the player is.

## Data

`data/achievements/*.json`, one entry per deed:

```json
{"id": "parries", "name": "DEED_PARRIES", "description": "DEED_PARRIES_DESC", "ash": 10,
 "unlock": {"deeds": {"parries": 50}}}
```

The `id` is also the API name a store achievement will carry (Steam's), so it never changes once shipped. `ash` is
paid once, into the profile (0–50: permanent power stays small, docs/BALANCE.md). Every condition in `unlock` must
hold:

| Key | Reads | Example |
|---|---|---|
| `nights`, `wins`, `total_kills` | the Profile's own numbers | `{"nights": 10}` |
| `kills` | kills of each enemy, from the bestiary | `{"kills": {"ophanim": 1}}` |
| `known` | bestiary kinds slain, `"all"` or a number | `{"known": "all"}` |
| `notes` | records found in secret caches | `{"notes": "all"}` |
| `moves` | special moves pulled off (`data/techniques`), `"all"` or a list | `{"moves": ["lunge", "cleave"]}` |
| `deeds` | a counter `Profile.count` keeps | `{"deeds": {"parries": 50}}` |

The counters (`Achievements.COUNTERS`): `parries`, `backstabs`, `ripostes`, `unscathed` (rooms cleared without a
wound), `rests`, `curses_lifted` (a cursed chest's price paid off), `wins_omen` (a dawn under an omen), `refusals` (a hand of gifts turned down), and at dawn `wins_<path>` for the path the night leaned to (`Game.dominant_path`) and
`wins_judgment` on the hardest difficulty. A new counter goes into that list, into the code that calls
`Profile.count`, and the validator reads the list from the source.

## Rules

- Everything is read from the profile, the way a skin's unlock is: a deed is checked again whenever the profile
  changes (`Profile.check_achievements`), done once, stamped with the time, and never undone.
- Nothing counts in the practice yard, and a dedicated referee keeps no book.
- Online each player keeps their own book. The enemies live on the host, so a backstab or a riposte a guest lands is
  counted on the host's side; parries, clean rooms and rests are counted by the body that did them.
- A deed shows its name from the start: it is a goal, not a secret. The story's secrets stay in the story.

## Code

- `scripts/meta/achievements.gd` — reads the conditions (`met`, `progress`, `done`).
- `scripts/autoload/profile.gd` — the counters, `check_achievements`, the Ash.
- `scripts/ui/deed_toast.gd` — the line at the top of the run's screen (`EventBus.achievement_unlocked`).
- `scripts/ui/bestiary.gd` — the "Deeds" section, ids `deed:<id>`.
- `scripts/tools/validate_data.gd` — every condition names something that exists.
- `scripts/tools/achievements_test.gd` — each kind of condition, the Ash paid once, the yard ignored, the book.
