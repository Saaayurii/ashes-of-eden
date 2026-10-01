# The night of the day

Main menu → Night of the day (beside Play). One night a calendar day (UTC), the same for everyone who plays it:

- **the same deal**: the gift cards come from the day's seed (`Daily.seed_of`, `Run._gift_rng`), so the same choices
  bring the same cards in the same order;
- **one vial of wrath**, chosen by the day from the lower three (`Daily.vial_of`) — played whether or not this profile
  has opened it, and a dawn under it opens no vial and counts for no vial deed;
- **nothing a profile carries that another's would not**: no relics, every late gift in the pool;
- **once through**: no autosave and no save slot, so a room cannot be retried by loading.

The day's best is kept in `Profile.data.daily` (`Daily.record`): further is better; as far, a dawn beats a death; as
both, sooner is better. Every try is counted. The end screen says whether this one was the day's best. Ash, deeds,
the bestiary and the habit count as in any night.

There is no shared leaderboard — that needs a server (docs/ROADMAP.md: telemetry). What the seed gives already is the
thing a leaderboard would need: two players of the same day played the same night.

`scripts/run/daily.gd`, `daily_test.gd`.
