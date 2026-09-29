class_name ItemSystem
## Items (data/items): what a chest can hold besides essence. Not bigger
## numbers — each one changes how something already in the game behaves (the
## flask, the parry, a chest, a backstab, a clean room, a wound, a crit near
## death), through a mechanic stat in Player.BASE_STATS that is zero without it.
## A run finds a handful: iron and cursed chests hold a common one, a gold
## chest a rare one (a common one once the rares are gone); each item at most
## once a night (docs/BALANCE.md).

const RARITIES := ["common", "rare"]


## One item this run does not have yet, of [param rarity] (a rare falls back to
## a common), or "" when there is none left to find.
static func roll(rarity: String, rng: RandomNumberGenerator) -> String:
	for wanted in ([rarity, "common"] if rarity == "rare" else [rarity]):
		var pool: Array = []
		for id in Data.items:
			if str(Data.items[id].get("rarity", "common")) == wanted and not Game.items.has(id):
				pool.append(id)
		if not pool.is_empty():
			pool.sort()  # the same seed finds the same item on every machine
			return str(pool[rng.randi() % pool.size()])
	return ""


static func give(player: Player, id: String) -> void:
	var item: Dictionary = Data.items.get(id, {})
	if item.is_empty() or Game.items.has(id):
		return
	for effect in item.get("effects", []):
		if effect.get("type", "") == "stat":
			AbilitySystem._apply_stat(player, effect)
	AbilitySystem._clamp(player)
	player.refresh_stats()
	Game.items.append(id)
	EventBus.item_found.emit(item)
