extends Node
## Persistent player profile across runs (user://profile.json).
## Versioned so the schema can change without losing players' progress:
## bump VERSION and add a step to _migrate().

const PATH := "user://profile.json"
const VERSION := 2

var data: Dictionary = _defaults()


static func _defaults() -> Dictionary:
	return {
		"version": VERSION,
		"nights": 0,        # runs finished (won or died)
		"best_wave": 0,
		"total_kills": 0,
		"total_seconds": 0.0,
		"ash": 0,           # permanent currency (docs/BALANCE.md)
		"bestiary": {},     # enemy id -> {"seen": bool, "kills": int}; people as "npc:<id>" with "met" (scripts/ui/bestiary.gd)
		"menu_character": "elian",  # the figure shown on the main menu
	}


func _ready() -> void:
	load_profile()
	EventBus.enemy_died.connect(func(enemy_id: StringName, _pos: Vector2) -> void: record_kill(String(enemy_id)))


func load_profile() -> void:
	data = _defaults()
	if not FileAccess.file_exists(PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		data.merge(parsed, true)
		_migrate()


func record_run(wave: int, kills: int, seconds: float, ash := 0) -> void:
	data.nights += 1
	data.best_wave = maxi(data.best_wave, wave)
	data.total_kills += kills
	data.total_seconds += seconds
	data.ash += ash
	save()


## The bestiary fills in as the player meets things: a kind is "seen" the moment
## one spawns in the room they are in, "known" once one has died. Both happen on
## every peer of a session (spawns and deaths are replicated), so a guest keeps
## their own book. A dedicated referee has no book to keep.
func record_seen(enemy_id: String) -> void:
	if Net.dedicated or enemy_id == "":
		return
	var entry: Dictionary = data.bestiary.get(enemy_id, {})
	if entry.get("seen", false):
		return
	entry["seen"] = true
	entry["kills"] = int(entry.get("kills", 0))
	if Game.place != "":
		entry["place"] = Game.place  # where this one was first laid eyes on
	data.bestiary[enemy_id] = entry
	save()  # an unlock should survive a crash later in the night


func record_kill(enemy_id: String) -> void:
	if Net.dedicated or enemy_id == "":
		return
	var entry: Dictionary = data.bestiary.get(enemy_id, {})
	entry["seen"] = true
	entry["kills"] = int(entry.get("kills", 0)) + 1
	data.bestiary[enemy_id] = entry
	if entry.kills == 1:
		save()
		EventBus.bestiary_unlocked.emit(enemy_id)


## Talked to a person: their bestiary page opens. Ids are "npc:<id>".
func record_met(npc_id: String) -> void:
	if Net.dedicated or npc_id == "":
		return
	var entry: Dictionary = data.bestiary.get(npc_id, {})
	if entry.get("met", false):
		return
	entry["seen"] = true
	entry["met"] = true
	entry["kills"] = int(entry.get("kills", 0))
	data.bestiary[npc_id] = entry
	save()
	EventBus.bestiary_unlocked.emit(npc_id)


func bestiary_entry(enemy_id: String) -> Dictionary:
	return data.bestiary.get(enemy_id, {})


## Kinds the player has slain at least once.
func bestiary_known() -> int:
	var known := 0
	for id in data.bestiary:
		# only kinds that still exist: renamed or removed enemies must not inflate the count
		if Data.enemies.has(id) and int(data.bestiary[id].get("kills", 0)) > 0:
			known += 1
	return known


func save() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))


func _migrate() -> void:
	var from := int(data.get("version", 0))
	if from < 2 and not (data.get("bestiary") is Dictionary):
		data.bestiary = {}  # v2: the bestiary
	if from != VERSION:
		print("[Profile] migrated %d -> %d" % [from, VERSION])
	data.version = VERSION
