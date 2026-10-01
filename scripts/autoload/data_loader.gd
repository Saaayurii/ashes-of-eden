extends Node
## Loads all data-driven content at startup. Every *.json file holds either
## one object with an "id" or an array of them. See docs/DATA_FORMATS.md.
##
## Content roots, in order; a later root overrides an earlier one by id:
##   res://data            open-source content (this repository)
##   res://content/data    official content overlay: private repo checked out
##                         into ./content at build time (git-ignored here)
##   user://mods/<x>/data  player-installed mods

const ROOTS := ["res://data", "res://content/data"]
const MODS_ROOT := "user://mods"

var abilities: Dictionary = {}
var enemies: Dictionary = {}
var dialogues: Dictionary = {}
var cutscenes: Dictionary = {}
var chapters: Dictionary = {}
## Room scene path -> the chapter that claims it, built with the chapters.
var _room_chapters: Dictionary = {}
var npcs: Dictionary = {}
var props: Dictionary = {}
## Records found in secret caches (data/notes): a name, the caption dialogue that reads them.
var notes: Dictionary = {}
## What a chest can hold besides essence (data/items, scripts/combat/item_system.gd).
var items: Dictionary = {}
## Rest points, one per room at most, by room scene name (data/rest_points).
var rest_points: Dictionary = {}
## The hero's cloaks (data/skins): free ones unlock by play, a "sku" one only by a store.
var skins: Dictionary = {}
## The hero's moves as a list to learn (data/techniques, docs/TECHNIQUES.md):
## names and inputs for the practice yard; the moves themselves are Player's.
var techniques: Dictionary = {}
## Where the chapter's way splits (data/forks, scripts/run/route.gd).
var forks: Dictionary = {}
## Deeds the profile remembers (data/achievements, scripts/meta/achievements.gd).
var achievements: Dictionary = {}
## What gifts do together (data/resonances, scripts/combat/resonances.gd).
var resonances: Dictionary = {}
## The vials of wrath, the ladder above a dawn (data/vials, scripts/run/vials.gd).
var vials: Dictionary = {}
## What the Ash buys (data/relics, scripts/meta/relics.gd).
var relics: Dictionary = {}
## The omens a night may be drawn under (data/omens, scripts/run/omens.gd).
var omens: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	var roots := _roots()
	abilities = _load_collection("abilities", roots)
	enemies = _resolve_extends(_load_collection("enemies", roots))
	_apply_enemy_archetypes(roots)
	dialogues = _load_collection("dialogues", roots)
	cutscenes = _load_collection("cutscenes", roots)
	chapters = _load_collection("chapters", roots)
	_index_chapters()
	props = _load_collection("props", roots)
	npcs = _load_collection("npcs", roots)
	notes = _load_collection("notes", roots)
	items = _load_collection("items", roots)
	rest_points = _load_collection("rest_points", roots)
	skins = _load_collection("skins", roots)
	techniques = _load_collection("techniques", roots)
	forks = _load_collection("forks", roots)
	achievements = _load_collection("achievements", roots)
	resonances = _load_collection("resonances", roots)
	vials = _load_collection("vials", roots)
	relics = _load_collection("relics", roots)
	omens = _load_collection("omens", roots)
	print("[Data] abilities=%d enemies=%d dialogues=%d props=%d npcs=%d chapters=%d (roots: %s)" % [abilities.size(), enemies.size(), dialogues.size(), props.size(), npcs.size(), chapters.size(), roots])


## Each chapter (data/chapters/*.json) lists the rooms it covers; the run asks
## the other way round — which place is this scene in — so the map is built once.
func _index_chapters() -> void:
	_room_chapters.clear()
	for id in chapters:
		for scene in chapters[id].get("rooms", []):
			if _room_chapters.has(scene):
				push_error("[Data] %s is claimed by both %s and %s" % [scene, _room_chapters[scene].id, id])
				continue
			_room_chapters[scene] = chapters[id]


## The place a room belongs to, or {} for a room no chapter claims (a room
## played straight from the editor, a mod that only ships scenes).
func chapter_for(scene_path: String) -> Dictionary:
	return _room_chapters.get(scene_path, {})


## Optional second layer for large bestiary upgrades.  It keeps combat numbers
## readable in the base files while families, portraits, expanded movesets and
## ability copy can grow independently like a content tree.
func _apply_enemy_archetypes(roots: Array[String]) -> void:
	var overlays := _load_collection("enemy_archetypes", roots)
	for id in overlays:
		if not enemies.has(id):
			push_error("[Data] archetype extends unknown enemy: %s" % id)
			continue
		_deep_merge(enemies[id], overlays[id])
		# An expanded list supersedes the legacy single move. Without erasing it,
		# Enemy's backwards-compatibility path would intentionally choose only the
		# old object and the new move tree would be merely decorative.
		if overlays[id].has("attacks"):
			enemies[id].erase("attack")


func _deep_merge(base: Dictionary, overlay: Dictionary) -> void:
	for key in overlay:
		if key in ["id", "_source"]:
			continue
		if base.get(key) is Dictionary and overlay[key] is Dictionary:
			_deep_merge(base[key], overlay[key])
		else:
			base[key] = overlay[key].duplicate(true) if overlay[key] is Array or overlay[key] is Dictionary else overlay[key]


func _roots() -> Array[String]:
	var roots: Array[String] = []
	for root in ROOTS:
		if DirAccess.dir_exists_absolute(root):
			roots.append(root)
	var mods := DirAccess.open(MODS_ROOT)
	if mods:
		for mod in mods.get_directories():
			roots.append(MODS_ROOT.path_join(mod).path_join("data"))
	return roots


func _load_collection(folder: String, roots: Array[String]) -> Dictionary:
	var result := {}
	for root in roots:
		var dir_path := root.path_join(folder)
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file_name in dir.get_files():
			if file_name.ends_with(".json"):
				_merge_file(dir_path.path_join(file_name), result)
	return result


func _merge_file(path: String, into: Dictionary) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		push_error("[Data] invalid JSON: %s" % path)
		return
	var entries: Array = parsed if parsed is Array else [parsed]
	for entry in entries:
		if not (entry is Dictionary) or not entry.has("id"):
			push_error("[Data] entry without \"id\" in %s" % path)
			continue
		if into.has(entry.id):
			print_verbose("[Data] %s: \"%s\" overrides %s" % [path, entry.id, into[entry.id]._source])
		entry["_source"] = path
		into[entry.id] = entry


## {"id": "elite_possessed", "extends": "possessed_villager", ...} — copies the base
## entry and lays the overrides on top (one level deep for nested dictionaries).
func _resolve_extends(collection: Dictionary) -> Dictionary:
	for id in collection:
		var entry: Dictionary = collection[id]
		if not entry.has("extends"):
			continue
		var base: Dictionary = collection.get(entry.extends, {})
		if base.is_empty():
			push_error("[Data] %s extends unknown id %s" % [id, entry.extends])
			continue
		var merged: Dictionary = base.duplicate(true)
		for key in entry:
			if merged.has(key) and merged[key] is Dictionary and entry[key] is Dictionary:
				merged[key].merge(entry[key], true)
			else:
				merged[key] = entry[key]
		collection[id] = merged
	return collection
