# Monetization

**Free. Open source. No pay-to-win. No loot boxes.** These four lines go on the store page.

The game is free-to-play and fully completable for free, with no forced ads. Open source is not an
obstacle to revenue — it is the trust that makes buying cosmetics and supporter packs feel good.

## What is never sold

- Power: no stat boosts, no gifts behind a paywall, no paid characters stronger than free ones.
- Energy, lives, timers, "wait or pay".
- Loot boxes, gacha, random drops for money.
- Forced ads. Never "boss killed → ad". Optional ads at most, for cosmetic currency, and probably not even that.
- Premium currency. Prices are real prices: *Fallen Pilgrim — $2.99*, not *650 Soul Crystals*.
- FOMO. No seasons, no "ends October 14th". Everything bought is available forever.
- The ending. The main story always has a full, free conclusion.

## What is sold

| Category | Examples | Price band | Notes |
|---|---|---|---|
| Hero skins | Ashen Wanderer, Fallen Paladin, Herald of the Seraphim, Vestment of the Abyss, Armour of Repentance, The Last Human | $1.99–4.99 | visual only; cheap to make in pixel art |
| Weapon skins | iron / burning / angelic / obsidian / blood / celestial; *Heaven Arsenal*, *Abyss Arsenal* packs | $2.99 per pack | same stats |
| Ability VFX | *Heavenly Spear*: free = gold beam; paid = white-gold flame + feathers + new sound | $1.99–2.99 | the VFX is the product, not the ability |
| Finishers | *Judgement* (a sword falls from the sky), *Abyss* (hands drag the body under), *Ashes* | $1.99–2.99 | short-video friendly |
| Companions | cherub, raven, fire spirit, floating eye, black lamb, dove, tiny ophanim | $1.99–3.99 | idle animations, no gameplay |
| Story expansions | *The Fall*, *The Watchers*, *Seven Seals*, *The Last Prophet* | $4.99–6.99 | standalone stories after the free campaign; expand the world, never gate the ending |
| Alternative heroes | Miriam (ranged + control), Jonah (heavy weapons), Azariel (fallen angel, mobility) | $3.99–6.99 | sidegrades, never upgrades |
| Chronicles | *Chronicle I — The First Sin*: 30 tiers of cosmetic progression | $4.99 | a battle pass without seasons or deadlines; buy it in two years, still complete it |
| Lore packs | *Codex of Heaven*: extra entries, concept art, maps, dev commentary | $2.99 | key story beats stay free |
| Supporter packs | *Supporter Pack* (skin, frame, name in credits, OST, artbook, badge) / *Founder's Pack* | $9.99 / $19.99 | "I like this project" purchases; the most natural fit for open source |
| OST | FLAC/MP3, covers, bonus tracks | $4.99–7.99 | Steam/GOG/site; music stays in the game regardless |
| Artbook | *Ashes of Eden — Art & Scripture*: concepts, world architecture, biblical sources, commentary | $5–10 | PDF |

### Store layout

```
STORE
  APPEARANCE     Fallen Pilgrim $2.99 · Seraph Armour $3.99 · Ashen Knight $2.99
  WEAPON SKINS   Heaven Arsenal $2.99 · Abyss Arsenal $2.99
  COMPANIONS     Cherub $1.99 · Raven $1.99 · Ophanim $2.99
  EXPANSIONS     The Watchers $4.99 · The Fall $5.99
  SUPPORT        Supporter Pack $9.99 · Founder's Pack $19.99
```

The player must never wonder what they get for the money.

### Five revenue streams, fixed

1. Cosmetics — hero, weapon, VFX, finishers, companions.
2. Story expansions.
3. Supporter packs.
4. OST + artbook (Steam / GOG / site).
5. Alternative heroes, sidegrade only.

### Rough economics

100 000 installs → most pay nothing, and that is fine. 5 % buy something, average $6 → $30 000 gross,
minus store cut, tax, refunds. The point is the long tail: an open-source community keeps the game alive
for years, and expansions + supporter packs keep selling over that whole life.

## How open source and revenue coexist

"Can someone build the APK for free from GitHub?" Yes. That is fine. What they cannot do is take the
product, rename it and sell it with our assets, because the assets are not the code:

| What | License | Where |
|---|---|---|
| Game code, tools, mod API, localization system | MIT | this repo |
| Community translations | CC BY 4.0 | this repo, `localization/` |
| Community-contributed assets | CC BY 4.0 (contributor's choice, listed in `assets/CREDITS.md`) | this repo |
| Placeholder / CC0 assets | as credited | this repo |
| Official artwork, music, logo, character designs | All Rights Reserved | private repo `ashes-of-eden-content` |
| Commercial DLC, master files (Aseprite, PSD, DAW projects), marketing | All Rights Reserved | private repo |
| "Ashes of Eden" name and mark | trademark, All Rights Reserved | — |

### Two repositories

```
ashes-of-eden            public, MIT       Godot project, gameplay, AI, saves, combat, UI, mod API, i18n
ashes-of-eden-content    private           official art, music, DLC, source files, marketing
```

The private repo is checked out into `./content` at build time (git-ignored here). The data loader
already treats `res://content/data` as an overlay root that overrides `res://data` by id, and
`user://mods/*/data` as a further overlay for player mods — so official DLC and community mods use
exactly the same mechanism. A build without `./content` is the fully playable community edition
with placeholder art.

## Technical implications (what this means for the code)

- **Entitlements, not flags in save files.** Owned cosmetics are a list of ids verified against the
  store receipt (Play / App Store / Steam). Never trust `user://` for this; but always degrade
  gracefully offline (last verified list cached).
- **Cosmetics are data.** `data/skins`, `data/companions`, `data/vfx` — same JSON pattern as gifts,
  with a `price` and `sku` field on paid entries. A free skin and a paid skin differ only by `sku`.
- **Telemetry is server-side and opt-in.** Balance data (which gifts, which wave people die on) and
  choice statistics ("73 % killed the stranger") go to a small backend, never a local DB.
- **Store UI is one screen.** Category, name, price, buy. No carousels, no timers.

## Sequencing

Nothing here is built before the core loop is fun (`CORE_LOOP.md`). Order: skins system as data (v0.2)
→ supporter pack + OST on itch/Steam (v0.6) → first expansion after the free campaign ships (v1.x).
