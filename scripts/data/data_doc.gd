class_name DataDoc
extends RefCounted
## The data roots and the single-document files read from them
## (docs/GAME_PACKS.md). A game is the engine's res://data with its own pack
## laid over it — res://content/data, a checkout of the game's repository —
## and then any mods; a later root wins. Collections (data/enemies, …) overlay
## by id in Data; one-document files (projectiles.json, gore.json, …) come
## here and are deep-merged, so a pack names only the keys it changes.
## Static and autoload-free, because the Fx/Gore/Projectile tables are asked
## for from tool scripts and the studio's tests before Data is up.

const ROOTS := ["res://data", "res://content/data"]
const MODS_ROOT := "user://mods"
const ENGINE_ROOT := "res://data/"


## Every root that is there, in order: the engine's, the game pack's, each mod's.
static func roots() -> Array[String]:
	var out: Array[String] = []
	for root in ROOTS:
		if DirAccess.dir_exists_absolute(root):
			out.append(root)
	var mods := DirAccess.open(MODS_ROOT)
	if mods:
		for mod in mods.get_directories():
			out.append(MODS_ROOT.path_join(mod).path_join("data"))
	return out


## The roots a collection (data/enemies, data/dialogues, …) is read from. A game
## pack's game.json may list in "inherit" the collections it takes from the
## engine's own data — "abilities", "enemies", … — and every other collection
## then comes from the pack alone, so a new game does not start with Ashes'
## story in it. Without "inherit" everything is inherited (Ashes itself).
static func collection_roots(folder: String, from: Array[String], game: Dictionary) -> Array[String]:
	if not game.get("inherit") is Array or (game.inherit as Array).has(folder):
		return from
	var out: Array[String] = []
	for root in from:
		if root != ROOTS[0]:
			out.append(root)
	return out


## A file name inside the roots, from either "gore.json" or "res://data/gore.json".
static func relative(path: String) -> String:
	return path.trim_prefix(ENGINE_ROOT)


static func exists(path: String, from: Array[String] = []) -> bool:
	for root in (from if not from.is_empty() else roots()):
		if FileAccess.file_exists(root.path_join(relative(path))):
			return true
	return false


## The document as the game sees it: every root's copy deep-merged over the
## one before (a list is replaced whole, a table key by key). {} when no root
## has it; a copy that is not a JSON object is reported and skipped.
static func doc(path: String, from: Array[String] = []) -> Dictionary:
	var out := {}
	for root in (from if not from.is_empty() else roots()):
		var file := root.path_join(relative(path))
		if not FileAccess.file_exists(file):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(file))
		if parsed is Dictionary:
			merge(out, parsed)
		else:
			push_error("[Data] invalid JSON: %s" % file)
	return out


## Lays `overlay` onto `base` in place: tables merge key by key, everything
## else (lists included) is replaced by a copy. An "id" or "_source" is kept.
static func merge(base: Dictionary, overlay: Dictionary) -> void:
	for key in overlay:
		if key in ["id", "_source"]:
			continue
		if base.get(key) is Dictionary and overlay[key] is Dictionary:
			merge(base[key], overlay[key])
		else:
			base[key] = overlay[key].duplicate(true) if overlay[key] is Array or overlay[key] is Dictionary else overlay[key]
