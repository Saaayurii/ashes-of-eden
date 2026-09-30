extends Node
## Saved games: the autosave and three slots in user://saves/, plus export
## and import so a night can move between machines (a file, or a text code
## for the clipboard — the code works everywhere, the Web and phones too).
##
## A save is a checkpoint, never a moment: the state of the run as it stood
## when the current room was entered (the Run keeps it, see run.gd). Loading
## puts the hero back at that room's entrance with the health, gifts, essence
## and choices he walked in with; the room itself starts over. So a save
## cannot be used to farm a room, and there is nothing half-fought to restore.
##
## Solo only: a session's rooms belong to the host (docs/MULTIPLAYER.md).
## Saves are separate from Profile (the bestiary, Ash, records), which is
## permanent and never rolled back.

const DIR := "user://saves/"
const FORMAT := 1
const GAME_ID := "ashes_of_eden"
const AUTO := "auto"
const SLOTS := ["auto", "1", "2", "3"]
const MANUAL := ["1", "2", "3"]
## Export code prefix: tells a pasted code from any other text on the clipboard.
const CODE_PREFIX := "AOE1:"
const EXTENSION := "aoesave"
const RUN_SCRIPT := "res://scripts/run/run.gd"

signal changed

## Handed from a menu to the Run scene: the save to start from. Empty = new run.
var pending: Dictionary = {}
## Where the slots live. The headless tests point it elsewhere (use_dir) so a
## test run never touches the player's own nights.
var dir := DIR


func _ready() -> void:
	# A tool script (-s: the smoke test, the screenshot helpers) plays real
	# runs, and a run autosaves: keep those nights out of the player's slots.
	var args := OS.get_cmdline_args()
	if args.has("-s") or args.has("--script"):
		dir = "user://saves_tools/"
	DirAccess.make_dir_recursive_absolute(dir)


func use_dir(path: String) -> void:
	dir = path
	DirAccess.make_dir_recursive_absolute(dir)


# ------------------------------------------------------------------ slots ---

func path_of(slot: String) -> String:
	return dir + slot + ".json"


func has(slot: String) -> bool:
	return FileAccess.file_exists(path_of(slot))


func any() -> bool:
	return SLOTS.any(has)


func read(slot: String) -> Dictionary:
	if not has(slot):
		return {}
	return validate(_json(FileAccess.get_file_as_string(path_of(slot))))


func write(slot: String, data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var stamped := data.duplicate(true)
	stamped["saved_at"] = int(Time.get_unix_time_from_system())
	var file := FileAccess.open(path_of(slot), FileAccess.WRITE)
	if file == null:
		push_warning("[Saves] cannot write %s: %s" % [slot, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(stamped, "\t"))
	file.close()
	changed.emit()
	return true


func delete(slot: String) -> void:
	if has(slot):
		DirAccess.remove_absolute(path_of(slot))
		changed.emit()


## The most recent save of all: what "Continue" picks up.
func latest_slot() -> String:
	var best := ""
	var best_time := -1
	for slot in SLOTS:
		var data := read(slot)
		if not data.is_empty() and int(data.get("saved_at", 0)) > best_time:
			best_time = int(data.saved_at)
			best = slot
	return best


func first_free_manual() -> String:
	for slot in MANUAL:
		if not has(slot):
			return slot
	return ""


## Queues a save for the Run scene and opens it.
func start(data: Dictionary) -> void:
	pending = data
	Curtain.change_scene("res://scenes/run/run.tscn", true,
		func() -> void: get_tree().paused = false)


func take_pending() -> Dictionary:
	var data := pending
	pending = {}
	return data


# --------------------------------------------------------- export/import ---

func to_code(data: Dictionary) -> String:
	return CODE_PREFIX + Marshalls.utf8_to_base64(JSON.stringify(data))


## A pasted code, a file's text or a bare JSON: whichever it is, a save or {}.
func parse(text: String) -> Dictionary:
	text = text.strip_edges()
	if text.begins_with(CODE_PREFIX):
		text = Marshalls.base64_to_utf8(text.substr(CODE_PREFIX.length()).strip_edges())
	return validate(_json(text))


## Quiet JSON: pasted garbage is an everyday input here, not an engine error.
func _json(text: String) -> Variant:
	var parser := JSON.new()
	return parser.data if parser.parse(text) == OK else null


func to_file(data: Dictionary, path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


func from_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return parse(FileAccess.get_file_as_string(path))


## Checks a save that may come from anywhere (another machine, an older game,
## a hand-edited file): the right game, a known format, a room that still
## exists, numbers where numbers belong. Gifts that were removed from the data
## since are dropped rather than refusing the whole night.
func validate(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var data: Dictionary = raw
	if data.get("game", "") != GAME_ID or int(data.get("format", 0)) < 1 or int(data.format) > FORMAT:
		return {}
	for field in ["room", "game_state", "player"]:
		if not data.has(field):
			return {}
	if not data.room is String or room_index(data.room) < 0:
		return {}
	if not data.game_state is Dictionary or not data.player is Dictionary:
		return {}
	var state: Dictionary = data.game_state
	var gifts: Array = []
	for id in state.get("abilities", []):
		if id is String and Data.abilities.has(id):
			gifts.append(id)
	state["abilities"] = gifts
	var found: Array = []
	for id in state.get("items", []):
		if id is String and Data.items.has(id):
			found.append(id)
	state["items"] = found  # an item that no longer exists is dropped, not fatal
	for key in ["level", "essence", "elapsed", "kills"]:
		if not (state.get(key, 0) is float or state.get(key, 0) is int):
			return {}
	var body: Dictionary = data.player
	if not (body.get("hp", 0) is float or body.get("hp", 0) is int) or not body.get("stats", {}) is Dictionary:
		return {}
	return data


## Rooms are saved by scene path, so reordering the chain does not break saves.
func room_index(path: String) -> int:
	var run: GDScript = load(RUN_SCRIPT)
	return (run.get_script_constant_map().get("ROOMS", []) as Array).find(path)


# ---------------------------------------------------------------- capture ---

## A snapshot of the run as it stands now. The Run calls this on entering a
## room; that snapshot is the checkpoint every save writes.
func capture(room_path: String, kills: int, elapsed: float, body: Player) -> Dictionary:
	return {
		"game": GAME_ID,
		"format": FORMAT,
		"room": room_path,
		"room_number": Route.step(Route.rooms(), room_index(room_path)) + 1,
		"game_state": {
			"alignment": Game.alignment.duplicate(),
			"flags": Game.flags.duplicate(),
			"abilities": Game.abilities.map(func(a: Dictionary) -> String: return a.id),
			"items": Game.items.duplicate(),
			"rested": Game.rested.keys(),
			"essence": Game.essence,
			"level": Game.level,
			"ash": Game.ash_earned,
			"unscathed": Game.unscathed,
			"elapsed": elapsed,
			"kills": kills,
			"difficulty": Settings.difficulty,
		},
		"player": {
			"hp": body.hp,
			"heal_charges": body.heal_charges,
			"stats": body.stats.duplicate(),
			"skill": body.skill.duplicate(),
		},
	}


## Puts a checkpoint back into Game and onto the body. The room itself is the
## Run's to load.
func restore(data: Dictionary, body: Player) -> void:
	var state: Dictionary = data.game_state
	Game.new_run()
	for path in Game.PATHS:
		Game.alignment[path] = int(state.get("alignment", {}).get(path, 0))
	Game.flags = state.get("flags", {}).duplicate()
	for id in state.get("abilities", []):
		Game.abilities.append(Data.abilities[id])
	# their resonances are already in the body's stats below: only the list
	Game.resonances = Resonances.active(Game.abilities)
	# the items' effects are in the body's stats below; this is the list of them
	for id in state.get("items", []):
		if id is String and Data.items.has(id):
			Game.items.append(id)
	for path in state.get("rested", []):
		if path is String:
			Game.rested[path] = true
	Game.level = maxi(1, int(state.get("level", 1)))
	Game.essence = maxf(0.0, float(state.get("essence", 0.0)))
	Game.ash_earned = int(state.get("ash", 0))
	Game.unscathed = maxi(0, int(state.get("unscathed", 0)))
	Game.elapsed = float(state.get("elapsed", 0.0))
	# The stats are the body's whole story (gifts applied, extra lives spent):
	# restored as they were rather than replayed gift by gift.
	var saved_stats: Dictionary = data.player.get("stats", {})
	for key in body.stats:
		if saved_stats.has(key) and (saved_stats[key] is float or saved_stats[key] is int):
			body.stats[key] = saved_stats[key]
	Game.essence_bonus = float(body.stats.get("essence_bonus", 0.0))
	var saved_skill = data.player.get("skill", {})
	body.skill = saved_skill.duplicate() if saved_skill is Dictionary else {}
	body.heal_charges = clampi(int(data.player.get("heal_charges", body.heal_charges)), 0, int(body.stats.heal_charges))
	body.hp = clampf(float(data.player.get("hp", body.stats.max_hp)), 1.0, float(body.stats.max_hp))
	body.refresh_stats()
	EventBus.essence_changed.emit(Game.essence, Game.essence_needed(), Game.level)
	EventBus.alignment_changed.emit(Game.alignment.duplicate())
	EventBus.run_restored.emit()


## "Area 7 · Lv. 4 · 12:31" for a slot row.
func summary(data: Dictionary) -> String:
	var state: Dictionary = data.get("game_state", {})
	var seconds := int(state.get("elapsed", 0))
	var clock := "%d:%02d" % [seconds / 60, seconds % 60]
	# The place reads better than its number, when the room belongs to one.
	var chapter: Dictionary = Data.chapter_for(str(data.get("room", "")))
	if chapter.has("title"):
		return tr("SAVE_SUMMARY_PLACE") % [tr(chapter.title), int(state.get("level", 1)), clock]
	return tr("SAVE_SUMMARY") % [int(data.get("room_number", room_index(data.get("room", "")) + 1)),
		int(state.get("level", 1)), clock]


func saved_at_text(data: Dictionary) -> String:
	var when := Time.get_datetime_dict_from_unix_time(int(data.get("saved_at", 0)) + _utc_offset())
	return "%02d.%02d.%d %02d:%02d" % [when.day, when.month, when.year, when.hour, when.minute]


func _utc_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
