extends RefCounted
class_name Achievements
## Deeds (data/achievements, docs/ACHIEVEMENTS.md): things a player did once,
## remembered by the profile. Each is read from what the Profile already keeps,
## the way a skin's unlock is, so a deed can never be earned twice nor lost:
##   nights / wins / total_kills  a Profile number, at least N
##   kills     {enemy id: N}       slain at least N of each
##   known     N or "all"          bestiary kinds slain (the practice dummy aside)
##   notes     N or "all"          records found in secret caches
##   items     N or "all"          items found at least once (the codex, "item:<id>")
##   affixes   N or "all"          elite affixes beaten, on any elite (bestiary "affixes")
##   moves     [ids] or "all"      special moves pulled off (data/techniques)
##   deeds     {counter: N}        a counter Profile.count keeps (COUNTERS)
##   fast      {boss id: seconds}  laid low within that long (its best_time)
## Several keys in one "unlock" must all hold. The id is also the name a store
## achievement will carry (Steam's API name), so it never changes once shipped.

## What Profile.count may keep. A new one → here, the code that counts it,
## and the validator reads this list (validate_data.gd).
const COUNTERS := ["parries", "backstabs", "ripostes", "unscathed", "rests", "curses_lifted", "wins_omen", "refusals", "daily_streak", "blood_paid", "elites",
	"wins_grace", "wins_temptation", "wins_will", "wins_judgment",
	"wins_vial_1", "wins_vial_2", "wins_vial_3", "wins_vial_4", "wins_vial_5"]


static func spec(id: String) -> Dictionary:
	return Data.achievements.get(id, {})


## Every deed in data order: the order the book lists them.
static func ids() -> Array:
	return Data.achievements.keys()


static func done(id: String) -> bool:
	return Profile.data.get("achievements", {}).has(id)


## [have, need] for the bar on the deed's page, over every condition at once.
## A deed with several conditions reports the one furthest from done.
static func progress(id: String) -> Array:
	var unlock: Dictionary = spec(id).get("unlock", {})
	var worst := [1, 1]
	var worst_share := 2.0
	for part in _parts(unlock):
		var need: int = maxi(1, part[1])
		var share := float(mini(part[0], need)) / need
		if share < worst_share:
			worst_share = share
			worst = [mini(part[0], need), need]
	return worst


static func met(id: String) -> bool:
	var unlock: Dictionary = spec(id).get("unlock", {})
	if unlock.is_empty():
		return false  # a deed with no condition is a typo, not a gift
	for part in _parts(unlock):
		if part[0] < part[1]:
			return false
	return true


## Each condition as [have, need].
static func _parts(unlock: Dictionary) -> Array:
	var parts := []
	var data: Dictionary = Profile.data
	for key in ["nights", "wins", "total_kills"]:
		if unlock.has(key):
			parts.append([int(data.get(key, 0)), int(unlock[key])])
	for enemy_id in unlock.get("kills", {}):
		parts.append([int(data.bestiary.get(enemy_id, {}).get("kills", 0)), int(unlock.kills[enemy_id])])
	if unlock.has("known"):
		var kinds: Array = Data.enemies.keys().filter(func(id: String) -> bool: return Data.enemies[id].get("bestiary", true))
		var need: int = kinds.size() if str(unlock.known) == "all" else int(unlock.known)
		var have := 0
		for id in kinds:
			if int(data.bestiary.get(id, {}).get("kills", 0)) > 0:
				have += 1
		parts.append([have, need])
	if unlock.has("notes"):
		var need: int = Data.notes.size() if str(unlock.notes) == "all" else int(unlock.notes)
		var have := 0
		for id in Data.notes:
			if data.bestiary.get("note:" + id, {}).get("met", false):
				have += 1
		parts.append([have, need])
	if unlock.has("items"):
		var need: int = Data.items.size() if str(unlock.items) == "all" else int(unlock.items)
		var have := 0
		for id in Data.items:
			if data.bestiary.get("item:" + id, {}).get("met", false):
				have += 1
		parts.append([have, need])
	if unlock.has("affixes"):
		var need: int = Data.affixes.size() if str(unlock.affixes) == "all" else int(unlock.affixes)
		var beaten := {}
		for id in data.bestiary:
			var met = data.bestiary[id].get("affixes", []) if data.bestiary[id] is Dictionary else []
			for a in met:
				if Data.affixes.has(str(a)):
					beaten[str(a)] = true
		parts.append([beaten.size(), need])
	if unlock.has("moves"):
		var moves: Array = Data.techniques.keys() if str(unlock.moves) == "all" else unlock.moves
		var have := 0
		for id in moves:
			if data.get("moves_done", {}).has(id):
				have += 1
		parts.append([have, moves.size()])
	for counter in unlock.get("deeds", {}):
		parts.append([int(data.get("deeds", {}).get(counter, 0)), int(unlock.deeds[counter])])
	# a boss's best fight (Profile.record_boss_time) within the time: done or not
	for boss_id in unlock.get("fast", {}):
		var best := float(data.bestiary.get(boss_id, {}).get("best_time", 0.0))
		parts.append([1 if best > 0.0 and best <= float(unlock.fast[boss_id]) else 0, 1])
	return parts
