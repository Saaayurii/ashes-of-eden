extends RefCounted
class_name Relics
## The reliquary (data/relics, docs/RELIQUARY.md): where the Ash goes. Each
## relic is bought once, from the main menu, and kept by the profile
## (Profile.data.relics). Three kinds:
##   stat      a little permanent strength, applied as a night begins
##             (Run._on_player_ready) — all of them together stay near the
##             quarter of a fresh body docs/BALANCE.md allows;
##   reroll    the gift cards may be dealt again, that many times a night;
##   early     a gift that arrives on a later night (unlock_nights), in the
##             pool now. One per such gift, made here from the gifts
##             themselves, so a new late gift gets its relic for free.
## Never in a duel: both players start the same.

const EARLY_PREFIX := "early_"
const EARLY_COST := 60


## Every relic: the data's, then one "early" per late gift.
static func all() -> Array:
	var out: Array = Data.relics.values()
	var late: Array = Data.abilities.values().filter(func(a: Dictionary) -> bool: return int(a.get("unlock_nights", 0)) > 0)
	late.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.unlock_nights) < int(b.unlock_nights))
	for gift in late:
		out.append({"id": EARLY_PREFIX + str(gift.id), "name": str(gift.name), "early": str(gift.id),
			"description": "RELIC_EARLY_DESC", "cost": EARLY_COST})
	return out


static func spec(id: String) -> Dictionary:
	for relic in all():
		if relic.id == id:
			return relic
	return {}


static func owned(id: String) -> bool:
	return Profile.data.get("relics", {}).has(id)


## Whether [param id] can be bought now: not owned, its "needs" owned, the Ash there.
static func can_buy(id: String) -> bool:
	var relic := spec(id)
	if relic.is_empty() or owned(id):
		return false
	if relic.has("needs") and not owned(str(relic.needs)):
		return false
	return int(Profile.data.get("ash", 0)) >= int(relic.get("cost", 0))


static func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	Profile.data.ash = int(Profile.data.ash) - int(spec(id).cost)
	if not (Profile.data.get("relics") is Dictionary):
		Profile.data.relics = {}
	Profile.data.relics[id] = true
	Profile.save()
	return true


## The stat relics on [param body] at the start of a night, and the night's rerolls.
static func apply(body: Player) -> void:
	Game.rerolls = 0
	for relic in all():
		if not owned(relic.id):
			continue
		for effect in relic.get("effects", []):
			match str(effect.get("type", "")):
				"stat":
					AbilitySystem._apply_stat(body, effect)
				"reroll":
					Game.rerolls += int(effect.get("value", 1))
	AbilitySystem._clamp(body)
	body.hp = body.stats.max_hp
	body.heal_charges = int(body.stats.heal_charges)
	body.refresh_stats()


## A late gift whose early relic is owned is in the pool whatever the night.
static func early(gift_id: String) -> bool:
	return owned(EARLY_PREFIX + gift_id)
