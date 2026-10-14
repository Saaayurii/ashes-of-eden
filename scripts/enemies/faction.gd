class_name Faction
## Two armies (docs/CHAPTER3.md §2, §9): an enemy's "faction" in its JSON puts it
## on a side, and data/factions.json says which sides fight each other and
## which story flag makes one of them spare the hero.
##
## - Two bodies without a side never fight (chapters I–II are unchanged); a body
##   without a side is hostile to every body with one; two sides fight when
##   factions.json says so (the validator wants it symmetric). Bosses are no
##   side's quarry and hunt nobody but the hero.
## - A spared soldier (its side's "spares_on" flag is set) treats the hero like a
##   waiter of Seir: it does not see, hear or feel him, and it does not keep the
##   door shut — until he strikes it. Then it and the comrades of its side within
##   "shout_radius" who see it turn on him for the rest of the room, hold the
##   door again, and the night's flag truce_broken is set (read by ch3_finale).
## - Blows between bodies are worth "damage_between", and a body felled by
##   another pays "essence_between" of its essence and counts for nobody's
##   bestiary, profile or kills: [member dying] names the body while
##   EventBus.enemy_died is sent, so the listeners can ask [method felled_by_soldier].
## Everything is the host's: the bodies are simulated there.

const PATH := "factions.json"
const TRUCE_FLAG := "truce_broken"

## The body whose death is being announced (set by Enemy._die around enemy_died).
static var dying: Node = null
## Bodies with a side in the tree: zero keeps every check of chapters I–II cold.
static var soldiers := 0
static var _doc: Dictionary = {}


static func doc() -> Dictionary:
	if _doc.is_empty():
		_doc = DataDoc.doc(PATH)
		if _doc.is_empty():
			_doc = {"factions": {}}
	return _doc


## Forget the document (a test lays its own, the studio reloads data).
static func reload() -> void:
	_doc = {}


static func spec(faction: String) -> Dictionary:
	return doc().get("factions", {}).get(faction, {})


static func of_id(enemy_id: String) -> String:
	return str(Data.enemies.get(enemy_id, {}).get("faction", ""))


## The side of [param enemy] ("" for none).
static func of(enemy: Node) -> String:
	if enemy == null or not "stats" in enemy:
		return ""
	return str(enemy.stats.get("faction", ""))


static func hostile(a: String, b: String) -> bool:
	if a == "" and b == "":
		return false
	if a == "" or b == "":
		return true
	if a == b:
		return false
	return spec(a).get("hostile", []).has(b)


## Whether bodies of [param faction] spare the hero tonight.
static func spares(faction: String) -> bool:
	if faction == "":
		return false
	var flag := str(spec(faction).get("spares_on", ""))
	return flag != "" and Game.flags.has(flag)


static func damage_between() -> float:
	return clampf(float(doc().get("damage_between", 0.5)), 0.0, 1.0)


static func essence_between() -> float:
	return clampf(float(doc().get("essence_between", 0.5)), 0.0, 1.0)


static func shout_radius() -> float:
	return float(doc().get("shout_radius", 160.0))


static func color(faction: String) -> Color:
	return Color(str(spec(faction).get("color", "#ffffff")))


## Every flag some side spares on (read by the validator as flags read).
static func spare_flags() -> Array:
	var out: Array = []
	for faction in doc().get("factions", {}):
		var flag := str(spec(str(faction)).get("spares_on", ""))
		if flag != "":
			out.append(flag)
	return out


## The body now falling was felled by another body, not by a player.
static func felled_by_soldier() -> bool:
	return dying != null and is_instance_valid(dying) and bool(dying.get("felled_by_soldier"))


## A story flag was set (Game.set_flag): a side chosen at the parley takes hold
## at once, on every body already standing (host).
static func flag_set(flag: String) -> void:
	if soldiers <= 0 or not spare_flags().has(flag):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for node in tree.get_nodes_in_group("enemies"):
		if node.has_method("refresh_spared"):
			node.refresh_spared()


## The hero struck a body that was sparing him: it turns, and so do the comrades
## of its side within shout_radius that see it. Host only.
static func break_truce(struck: Node) -> void:
	if struck == null or not struck.has_method("turn_on_hero"):
		return
	var side := of(struck)
	struck.turn_on_hero()
	var tree := struck.get_tree()
	for node in tree.get_nodes_in_group("enemies"):
		if node == struck or of(node) != side or not node.has_method("turn_on_hero") or node.call("is_dead"):
			continue
		if not bool(node.get("spared")):
			continue
		if node.global_position.distance_to(struck.global_position) <= shout_radius() and node.call("sees", struck):
			node.turn_on_hero()
	Game.set_flag(TRUCE_FLAG)
