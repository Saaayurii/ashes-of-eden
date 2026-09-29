# Baseline balance

*Fixed on 2026-09-20 as the starting point. Every number here is a hypothesis to be corrected by playtest
data (TTK, damage taken, boss time, death rate) — not by feel. The source of truth for live values is
`data/` and `Player.BASE_STATS`; this document explains the intent behind them.*

*Tuned against measurements: `scripts/tools/balance_probe.gd` → `docs/BALANCE_PROBE.md` (re-run it after changing any number here).*

## Feel targets

| Minutes | Player should feel | Difficulty |
|---|---|---|
| 0–3 | "I am strong" | easy |
| 3–8 | build starts to form | medium |
| 8–10 | first elite | visible step up |
| 10–16 | build comes together | medium-high |
| 16–18 | mini-boss | high |
| 18–24 | final stretch | high |
| 24–30 | boss | peak |

**The one number to watch: time-to-kill of a common enemy.** Start 2–3 s, middle 1.5–3 s, end 1–2 s.
Enemies get stronger, the build gets stronger faster: the player ends the run feeling like a monster.

## Player

| | Value | In code |
|---|---|---|
| HP | 100 | `max_hp` |
| Sword damage | 10 · 11 · 16 (3-hit combo, third hit knocks back) | `attack_damage`, `COMBO_MULTIPLIERS` |
| Attack speed | 1.25/s | `attack_cooldown = 0.8` |
| Crit | 5 %, ×1.75 | `crit_chance`, `crit_multiplier` |
| Roll | 2.2 s cooldown, 0.30 s i-frames, ~2.5 body lengths | `dash_cooldown`, `dash_time`, `dash_speed` |
| Backstab | ×2.5, always a crit, on an enemy that has not noticed anyone | `backstab_multiplier` |
| Block | held: a blow from the front costs 35 %, you shuffle at 35 % speed; a blow from behind lands whole | `BLOCK_REDUCTION`, `BLOCK_SPEED` |
| Parry | the first 0.22 s of a fresh press: nothing lands, the enemy is open 0.9 s (a boss 0.45 s), the next blow on it is a riposte ×1.5 and a crit; bolts fly back ×1.5. Re-press only after 0.35 s down — a parry re-arms at once | `PARRY_WINDOW`, `BLOCK_RECOVERY`, `Enemy.PARRY_OPENING`, `RIPOSTE_MULTIPLIER` |
| Armor, regen, lifesteal | 0 | `armor`, `lifesteal` |
| Healing | 3 charges × 35 HP, 1 s channel; refilled by a boss kill | `heal_charges`, `HEAL_AMOUNT` |
| Counterattack recovery | for 2.4 s, 35 % of a wound is recoverable (max 15 % max HP); each sword hit returns up to 40 % of its damage from that pool | `RALLY_*` |

Base DPS ≈ 13. Target growth: ×4 over a full run (≈ 25 at 10 min, 40 at 20 min, 50–60 before the boss). Never ×30.

### Soft caps (enforced in `AbilitySystem`)

attack speed +100 % · crit 50 % · move speed +60 % · roll cooldown ≥ 1.2 s · lifesteal 15 % · armor 50 %.

## Enemies

`FinalDamage = BaseDamage × (1 − armor)`. Nothing more complicated.

| Enemy | HP | Damage | Armor | Notes |
|---|---|---|---|---|
| Possessed | 48 | 8 | 0 | dies to ~5 hits (≈2.2 s); wind-up 0.5 s, cooldown 1.7 s. Was 30 = 3 hits = 1.3 s, under target |
| Spirit (wraith) | 36 | 10 (projectile) | 0 | fragile; the player should want it dead first |
| Fallen guard | 80 | 15 | 15 % | slow, readable; ~9–10 hits |
| Elite (any) | ×1.8 | ×1.35 | — | speed ×1.1 **and one new mechanic**, never just more HP (`extends` + `on_death`) |
| Blind preacher (mini-boss) | 900 | 18 / 15 / 35 | 10 % | second phase at 50 % changes behaviour, not HP |
| Ophanim (boss) | 1800 | 20 / 12 / 45 | 15 % | 3 phases at 66 % / 32 %; 3–4 min, not more (2200 measured at ~4.6 min) |

Boss attacks: normal 18–25, strong 30–40, telegraphed ultimate 45–60 with 1.3–1.5 s wind-up, obvious area,
fully avoidable. A boss attack never removes 70–100 % HP.

### Stealth

Enemies patrol until they see a player (a cone ahead, ~210 px for walkers, cut by geometry) or are touched, hit, or
within 90 px of one that just woke up. Waking costs them a 0.4 s "!" beat before the first step. The reward for
getting behind one is the backstab above: a possessed villager (30 HP) is left with 5 after one sneak hit
(10 × 2.5 = 25) and dies to the second swing, a guard (80 HP) loses a third of its bar. A sleeper never deals contact
damage.

### Telegraphs

normal 0.3–0.5 s · strong 0.7–1.0 s · boss 0.8–1.5 s. The stronger, the longer the warning.

### Scaling over a run

Enemy HP +6 % and damage +4 % every 3 minutes (≈ +48 % / +32 % at 24 min). Difficulty beyond that comes
from new enemy combinations, ranged mobs, hazards and elites — not from multipliers.
Group size: 2–3 → 4–5 (5 min) → 5–7 (10 min) → 6–9 (20 min); never more than 12 active on mobile.

### Difficulty modes (no story or loot changes)

| Mode | Enemy HP | Enemy damage |
|---|---|---|
| Pilgrim | ×0.8 | ×0.75 |
| Standard | ×1.0 | ×1.0 |
| Judgment | ×1.25 | ×1.35 |

## Progression inside a run

- **Essence** from kills fills a bar; each level offers 1 of 3 gifts. `RequiredEssence = 140 × 1.3^(level−1)` (was 100 × 1.28, tuned 2026-09-23 from `docs/BALANCE_PROBE.md`).
  Possessed 12 · Spirit 15 · Guard 25 · Elite 50 · Mini-boss 150 · Boss 400 → a level every 1.5–2.5 minutes.
- A door grants a gift only where a place ends (`data/chapters`: graveyard → swamp → catacombs …), not after every room. Target: 10–14 upgrades per run in total.
- Common gift +8–20 %, rare +20–35 %. No "+200 % damage" except cursed gifts with a real downside.
- Rarity (implemented, `rarity` in `data/abilities/`): common 55 % · rare 30 % · epic 12 % · legendary 3 %. Legendary changes a mechanic ("every third hit
  fires a beam of light"), it is not a bigger number.
- Paths: **Grace** = defence, control, healing, area · **Temptation** = damage, lifesteal, crit, DoT, with risks ·
  **Will** = attack speed, movement, roll, mastery, parry — the stable path.

## Meta progression

**Ash** (permanent, from bosses / achievements / clears) vs **Essence** (this run only). Permanent power is
capped at ~25–30 %; everything else unlocked is new mechanics, gifts, weapons, characters. Two currencies only:
Ash (unlocks) and Silver (shop, consumables, cosmetics). No paid stats, ever (see `MONETIZATION.md`).

Death keeps: Ash, codex entries, story knowledge, achievements, unlocks. Death loses: build, Essence, items.

Where Ash comes from in a night: a boss 10–25, a record cache 15, and 3 for every room cleared without a wound
(9 where a boss stood, `Run.UNSCATHED_ASH`). Fifteen clean rooms are worth about one boss: a tip for clean play,
never a reason to crawl.

## Not yet implemented (roadmap)

Silver / shop · legendary items.

**Rest points** (`data/rest_points`, `scripts/rooms/rest_point.gd`): three in chapter I — the praying statue in
`graveyard_tree`, the knight's niche in `catacombs_1`, the church altar. With no awake enemy within 220 px,
`interact` rests: full health, every flask full, the autosave remembers it; the room's common dead stand up where
they first stood and the door shuts until they are down again. Elites and bosses stay dead. Once a night each.

**Items** (`data/items`, `scripts/combat/item_system.gd`): what a chest holds besides essence. Iron and cursed
chests hold a common item, a gold chest a rare one (a common one once the rares are gone); each item once a night,
so a run finds about 3–5 commons and 1–2 rares. Every one changes how something behaves — the flask scorches
(18), a parry stops everyone near (0.8 s), a chest heals (14), a backstab returns the roll, a clean room refills a
flask, a wound makes the next swing ×1.8, a crit under a third of the bar heals (6) — never "+3 damage".

The Ophanim's seal phase is in (`seal_phase` in `data/enemies/ophanim.json`): at 50 % it closes its eyes and is
untouchable; three seals of 45 HP hang over the arena's floors; while they stand it keeps out of reach and only
throws a three-eye volley every 3.8 s; the last seal broken opens it for 6 s, low, silent and taking +50 % —
the fight's damage window.
