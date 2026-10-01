# The reliquary

Where the Ash goes. Before this, Ash was earned (bosses, clean rooms, caches, deeds, a vial's multiplier) and
never spent. Main menu → Reliquary: every relic, what it does, its price, the Ash in hand. Each is bought once
and kept by the profile (`Profile.data.relics`).

| Relic | Does | Ash |
|---|---|---|
| Pilgrim's Flask | one more flask every night | 120 |
| Tempered Skin | +10 health | 80 |
| Old Scars (after Tempered Skin) | +10 health again | 160 |
| Whetstone | +1 sword damage (≈ +10 %) | 150 |
| Light Boots | roll cooldown ×0.92 | 100 |
| Rosary | once a night, deal the gift cards again | 140 |
| *\<late gift\>*, early | that gift joins the pool before its night | 60 each |

Everything bought is about a quarter of a fresh body — the ceiling docs/BALANCE.md sets on permanent power. Past
that, Ash buys choices (the rosary) and knowledge (the early gifts), never more strength.

## Rules

- `data/relics`: `cost`, `effects` of type `stat` (a key of `Player.BASE_STATS`, capped by `AbilitySystem.CAPS`
  like a gift) or `reroll`, and an optional `needs` (another relic first).
- The "early" relics are made in `Relics.all()` from every gift with `unlock_nights`: a new late gift gets its relic
  without a line of data. `Run.gift_locked` lets an early one through.
- `Relics.apply` runs on our own body in `Run._on_player_ready`; a loaded save then puts its own stats back, so a
  relic is never counted twice. `Game.rerolls` is saved with the night.
- Never in a duel (another scene): both players start the same. Online each body carries its own player's relics.

`data/relics`, `scripts/meta/relics.gd`, `scripts/ui/reliquary.gd`, `relics_test.gd`.
