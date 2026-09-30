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
		# Elian's opening monologue plays in full once. Every night after that
		# he says the first line and the last one and gets up (run.gd _begin).
		# An older profile without the key reads false and hears it once more.
		"prologue_seen": false,
		# The special moves (docs/TECHNIQUES.md) this player has pulled off at
		# least once, and the in-night hints already given (MoveHints): a hint
		# comes once, and never for a move already known. Learning in the
		# practice yard counts here — knowing a move is not a reward.
		"moves_done": {},
		"hints_shown": {},
	}


func _ready() -> void:
	load_profile()
	EventBus.enemy_died.connect(func(enemy_id: StringName, _pos: Vector2) -> void: record_kill(String(enemy_id)))
	EventBus.technique_performed.connect(record_move)


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
	if Net.dedicated or enemy_id == "" or Game.practice != "":
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


func record_move(technique_id: String) -> void:
	if Net.dedicated or technique_id == "" or data.moves_done.has(technique_id):
		return
	data.moves_done[technique_id] = true
	save()


func mark_hint(technique_id: String) -> void:
	if Net.dedicated or data.hints_shown.has(technique_id):
		return
	data.hints_shown[technique_id] = true
	save()


func record_kill(enemy_id: String) -> void:
	# a practice kill fills no book and unlocks no cloak (skins count kills)
	if Net.dedicated or enemy_id == "" or Game.practice != "":
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


## A record from a secret cache: its page opens in the bestiary as "note:<id>".
## Returns true the first time, which is when the cache pays its Ash.
func record_note(note_id: String) -> bool:
	if Net.dedicated or note_id == "":
		return false
	var key := "note:" + note_id
	if data.bestiary.get(key, {}).get("met", false):
		return false
	data.bestiary[key] = {"seen": true, "met": true, "kills": 0}
	save()
	EventBus.bestiary_unlocked.emit(key)
	return true


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
