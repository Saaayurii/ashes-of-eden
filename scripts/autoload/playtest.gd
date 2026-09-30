extends Node
## A quiet flight recorder for playtests: what docs/BALANCE.md says we must
## judge by, measured on real hands instead of the bot in
## scripts/tools/balance_probe.gd. One JSON Lines file per run in
## user://playtest/, nothing sent anywhere. The probe reads them back and puts
## "estimate vs reality" in docs/BALANCE_PROBE.md.
##
## Events (one per line, "t" = seconds since the run started):
##   run_start, room_start {room, index}, room_clear {room, seconds, damage, deaths},
##   hurt {room, fraction}, death {room, x, y}, boss {room, id, seconds},
##   gift {id, rarity, path}, level {level}, choice {dialogue, choice}, secret {room, note, first},
##   run_end {won, seconds}
##
## Off in tool scripts (-s) and in online sessions' non-host peers; turn it off
## entirely with Settings "playtest_log" = false.

const DIR := "user://playtest"

var _file: FileAccess
var _clock := 0.0
var _room := ""
var _room_start := 0.0
var _room_damage := 0.0
var _room_deaths := 0
var _boss_start := -1.0
var _active := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _is_tool():
		return
	EventBus.room_started.connect(_on_room_started)
	EventBus.room_cleared.connect(_on_room_cleared)
	EventBus.player_unscathed.connect(_on_unscathed)
	# which special moves real hands use (docs/TECHNIQUES.md), for the probe
	EventBus.technique_performed.connect(func(id: String) -> void: _write("move", {"room": _room, "id": id}))
	EventBus.player_hurt.connect(_on_hurt)
	EventBus.player_died.connect(_on_died)
	EventBus.boss_hp_changed.connect(_on_boss_hp)
	EventBus.boss_died.connect(_on_boss_died)
	EventBus.ability_acquired.connect(_on_gift)
	EventBus.level_up.connect(func(level: int) -> void: _write("level", {"level": level}))
	EventBus.choice_made.connect(func(d: String, c: String) -> void: _write("choice", {"dialogue": d, "choice": c}))
	EventBus.note_found.connect(func(n: String, first: bool) -> void: _write("secret", {"room": _room, "note": n, "first": first}))
	get_tree().node_added.connect(_on_node_added)
	# The main scene may already be in the tree before this autoload is ready
	# (started straight into the run): catch it once, deferred.
	_catch_existing.call_deferred()


func _catch_existing() -> void:
	var run := _run_scene()
	if run != null and not _active:
		_on_node_added(run)


func _process(delta: float) -> void:
	if _active and not get_tree().paused:
		_clock += delta


## A run scene entering the tree starts a new file; leaving it closes it.
func _on_node_added(node: Node) -> void:
	# current_scene is assigned only after the scene enters the tree, so the
	# run is recognised by its file and by being a direct child of the root.
	if node.get_parent() == get_tree().root and node.scene_file_path == "res://scenes/run/run.tscn":
		_begin()
		node.tree_exiting.connect(_end.bind(false), CONNECT_ONE_SHOT)


func _begin() -> void:
	if not bool(Settings.get("playtest_log") if Settings.get("playtest_log") != null else true):
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	_file = FileAccess.open("%s/%s.jsonl" % [DIR, stamp], FileAccess.WRITE)
	if _file == null:
		return
	_clock = 0.0
	_active = true
	_write("run_start", {"version": ProjectSettings.get_setting("application/config/version", ""),
		"difficulty": str(Settings.get("difficulty")), "platform": OS.get_name()})
	var run := _run_scene()
	if run != null and int(run.get("room_index")) >= 0:
		_on_room_started(int(run.room_index) + 1)  # the first room began before we did


func _end(won: bool) -> void:
	if not _active:
		return
	_write("run_end", {"won": won, "seconds": snappedf(_clock, 0.1), "level": Game.level,
		"gifts": Game.abilities.size(), "alignment": Game.alignment})
	_active = false
	_file = null


func _on_room_started(index: int) -> void:
	var run := _run_scene()
	var rooms = run.get("ROOMS") if run else null
	_room = str(rooms[index - 1]).get_file().get_basename() if rooms is Array and index - 1 < rooms.size() else str(index)
	_room_start = _clock
	_room_damage = 0.0
	_room_deaths = 0
	_write("room_start", {"room": _room, "index": index})


func _on_room_cleared(_index: int) -> void:
	_write("room_clear", {"room": _room, "seconds": snappedf(_clock - _room_start, 0.1),
		"damage": snappedf(_room_damage, 0.01), "deaths": _room_deaths})


func _on_unscathed(_index: int) -> void:
	_write("unscathed", {"room": _room})


func _on_hurt(fraction: float) -> void:
	_room_damage += fraction
	_write("hurt", {"room": _room, "fraction": snappedf(fraction, 0.001)})


func _on_died() -> void:
	_room_deaths += 1
	var at := Vector2.ZERO
	for node in get_tree().get_nodes_in_group("player"):
		if node.is_multiplayer_authority():
			at = node.global_position
	_write("death", {"room": _room, "x": int(at.x), "y": int(at.y)})
	_end(false)


func _on_boss_hp(_name: String, hp: float, max_hp: float) -> void:
	if _boss_start < 0.0 and hp >= max_hp:
		_boss_start = _clock


func _on_boss_died() -> void:
	var seconds := _clock - _boss_start if _boss_start >= 0.0 else -1.0
	_write("boss", {"room": _room, "seconds": snappedf(seconds, 0.1)})
	_boss_start = -1.0
	var run := _run_scene()
	if run and run.get("room_index") != null and run.get("ROOMS") is Array and int(run.room_index) + 1 >= run.ROOMS.size():
		_end(true)


func _on_gift(ability: Dictionary) -> void:
	_write("gift", {"id": ability.get("id", ""), "rarity": ability.get("rarity", ""), "path": ability.get("path", "")})


func _write(kind: String, fields: Dictionary) -> void:
	if not _active or _file == null or Game.practice != "":  # practice is not a night
		return
	fields["e"] = kind
	fields["t"] = snappedf(_clock, 0.1)
	_file.store_line(JSON.stringify(fields))
	_file.flush()  # a crash or a force-quit must not lose the run


func _run_scene() -> Node:
	for child in get_tree().root.get_children():
		if child.scene_file_path == "res://scenes/run/run.tscn":
			return child
	return null


static func _is_tool() -> bool:
	# `godot -s script.gd`: the tests and the probe must not pollute the logs.
	for arg in OS.get_cmdline_args():
		if arg == "-s" or arg == "--script":
			return true
	return false
