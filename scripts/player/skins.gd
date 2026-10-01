class_name Skins
## The hero's cloaks (data/skins, docs/MONETIZATION.md: cosmetics are data).
## A free skin unlocks by playing — nights survived, a boss put down, the dead
## put to rest — read from the Profile each time, so nothing extra is stored
## and an older profile that already did it has it at once. A skin with a
## "sku" belongs to a store: unlocked only while the store says it is owned
## (StoreBridge.owns), whatever the profile holds.

const DEFAULT := "pilgrim"


static func spec(id: String) -> Dictionary:
	return Data.skins.get(id, {})


static func unlocked(id: String) -> bool:
	var entry := spec(id)
	if entry.is_empty():
		return false
	if str(entry.get("sku", "")) != "":
		return StoreBridge.owns(str(entry.sku))
	var rule: Dictionary = entry.get("unlock", {})
	if int(Profile.data.get("nights", 0)) < int(rule.get("nights", 0)):
		return false
	if int(Profile.data.get("total_kills", 0)) < int(rule.get("total_kills", 0)):
		return false
	var kills: Dictionary = rule.get("kills", {})
	for enemy in kills:
		if int(Profile.bestiary_entry(enemy).get("kills", 0)) < int(kills[enemy]):
			return false
	return true


## Every skin in a stable order: the default first, then by id.
static func ids() -> Array:
	var all: Array = Data.skins.keys()
	all.sort()
	all.erase(DEFAULT)
	return [DEFAULT] + all


## What Settings may keep: the chosen skin while it is unlocked, else the default.
static func worn(id: String) -> String:
	return id if unlocked(id) else DEFAULT
