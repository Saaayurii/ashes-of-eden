class_name Weapons
## Weapons (data/weapons, docs/WEAPONS.md): what the hero swings. A weapon is
## a chain of steps drawn with the frames he already has — the swings, the
## thrust, the roll's stab — plus its reach (the hitbox), and a few numbers
## laid on every blow: damage, backstab, poise. Every blow still goes through
## Player._land_hits, so gifts, items, resonances and techniques all apply.
##
## The sword is the default and every night's first. Its steps name only their
## animation: a key a step leaves out is the hero's own for that step (hero.json
## combo_*, player_actions.json attack/attack2/attack3), so the sword plays
## exactly as it did before weapons and the studio's «Боёвка» still tunes it.
##
## One is found a night, laid beside the first chest with `"weapon": true`
## (Prop._pay_out); taking it lays the one in hand where it lay (WeaponDrop).

const DEFAULT := "sword"
## The keys a step may carry, by what the validator bounds them to.
const STEP_KEYS := ["animation", "multiplier", "recovery", "wind", "knockback", "heavy", "stagger",
	"arc", "animation_time", "speed", "hitbox", "offset", "hit_frame", "sfx"]
## The poses a step may be drawn with: frames Elian has (docs/WEAPONS.md).
const ANIMATIONS := ["attack", "attack2", "attack3", "thrust", "rising", "dash_strike"]
const ARCS := ["white", "gold", "red", "heavy", "path"]


static func spec(id: String) -> Dictionary:
	var found: Dictionary = Data.weapons.get(id, {})
	return found if not found.is_empty() else Data.weapons.get(DEFAULT, {})


## The weapon id a save or the network handed us, or the sword for one the
## game does not have (an old save, a pack without it).
static func known(id: String) -> String:
	return id if Data.weapons.has(id) else DEFAULT


static func chain(id: String) -> Array:
	var steps: Array = spec(id).get("chain", [])
	return steps if not steps.is_empty() else [{"animation": "attack"}, {"animation": "attack2"}, {"animation": "attack3"}]


## Step [param index] of the chain (wrapping), as written.
static func step(id: String, index: int) -> Dictionary:
	var steps := chain(id)
	return steps[posmod(index, steps.size())]


## A number laid on every blow: "damage" (×), "backstab" (+ on the hero's
## multiplier), "poise" (share of a wound not taken while a swing is out).
static func number(id: String, key: String, fallback: float) -> float:
	return float(spec(id).get(key, fallback))


## What the weapon changes about a special move (lunge, cleave, sweep): the
## same keys as player_actions.json, laid over the move's own.
static func technique(id: String, move: String) -> Dictionary:
	return spec(id).get("techniques", {}).get(move, {})


## One weapon the hero does not hold, for a chest; "" when there is none.
## Sorted first, so the same seed lays the same weapon on every machine.
static func roll(holding: String, rng: RandomNumberGenerator) -> String:
	var pool: Array = []
	for id in Data.weapons:
		if id != holding:
			pool.append(str(id))
	if pool.is_empty():
		return ""
	pool.sort()
	return str(pool[rng.randi() % pool.size()])


## Seconds a whole chain takes at [param attack_cooldown] (a wind-up delays
## the bite inside its step's recovery, not the next step), and the damage it
## deals (×attack_damage): what weapon_test measures and docs/WEAPONS.md tabulates.
static func chain_time(id: String, attack_cooldown: float) -> float:
	var total := 0.0
	var steps := chain(id)
	for i in steps.size():
		total += attack_cooldown * float(steps[i].get("recovery", Player.COMBO_RECOVERY[mini(i, Player.COMBO_RECOVERY.size() - 1)]))
	return total


static func chain_damage(id: String) -> float:
	var total := 0.0
	var steps := chain(id)
	for i in steps.size():
		total += float(steps[i].get("multiplier", Player.COMBO_MULTIPLIERS[mini(i, Player.COMBO_MULTIPLIERS.size() - 1)]))
	return total * number(id, "damage", 1.0)
