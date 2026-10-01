extends RefCounted
class_name Resonances
## Resonances (data/resonances, docs/RESONANCES.md): what gifts do together
## that none does alone. Two kinds, both read from the gifts taken this night:
##   {"path": "grace", "count": 3}         that many gifts of one path;
##   {"gifts": ["executioner", "severing_arc"]}  every one of these gifts.
## A resonance is a mechanic, never a bigger number: its effects are stats from
## Player.BASE_STATS that change how something behaves, capped by
## AbilitySystem.CAPS like any gift. It wakes once, the moment its last gift is
## taken (AbilitySystem.apply), and stays for the night.


static func spec(id: String) -> Dictionary:
	return Data.resonances.get(id, {})


## The resonances [param abilities] (gift dictionaries) hold between them.
static func active(abilities: Array) -> Array[String]:
	var ids := {}
	var per_path := {}
	for ability in abilities:
		ids[str(ability.get("id", ""))] = true
		var path := str(ability.get("path", ""))
		per_path[path] = int(per_path.get(path, 0)) + 1
	var out: Array[String] = []
	for id in Data.resonances:
		var needs: Dictionary = Data.resonances[id].get("needs", {})
		if needs.has("path"):
			if int(per_path.get(str(needs.path), 0)) >= int(needs.get("count", 3)):
				out.append(id)
		elif not needs.get("gifts", []).is_empty():
			var all := true
			for gift in needs.gifts:
				all = all and ids.has(str(gift))
			if all:
				out.append(id)
	return out


## The resonances [param taken] stands one gift short of, not yet woken:
## [{id, path} or {id, gift}] — the path of which one more gift would wake it,
## or the one gift still missing from its set. The pause menu's Gifts page
## shows them, so a choice at the next cards can be made with them in mind.
static func near(taken: Array) -> Array[Dictionary]:
	var ids := {}
	var per_path := {}
	for ability in taken:
		ids[str(ability.get("id", ""))] = true
		var path := str(ability.get("path", ""))
		per_path[path] = int(per_path.get(path, 0)) + 1
	var awake := active(taken)
	var keys: Array = Data.resonances.keys()
	keys.sort()
	var out: Array[Dictionary] = []
	for id in keys:
		if awake.has(id):
			continue
		var needs: Dictionary = Data.resonances[id].get("needs", {})
		if needs.has("path"):
			if int(per_path.get(str(needs.path), 0)) == int(needs.get("count", 3)) - 1:
				out.append({"id": id, "path": str(needs.path)})
		elif not needs.get("gifts", []).is_empty():
			var missing: Array = needs.gifts.filter(func(g) -> bool: return not ids.has(str(g)))
			if missing.size() == 1 and Data.abilities.has(str(missing[0])):
				out.append({"id": id, "gift": str(missing[0])})
	return out


## The resonances taking [param ability] would wake on top of [param taken]:
## what the gift card says it completes.
static func completes(ability: Dictionary, taken: Array) -> Array[String]:
	var before := active(taken)
	var out: Array[String] = []
	for id in active(taken + [ability]):
		if not before.has(id):
			out.append(id)
	return out
