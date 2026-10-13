extends SceneTree
## Any game on this engine plays (docs/GAME_PACKS.md) — the one test a game
## pack's CI runs besides the validator, so it knows nothing of Ashes' story:
##   godot --headless -s scripts/tools/game_smoke_test.gd
## A night opens on game.json's first room with the hero on his feet, then every
## room of the game and its practice yard loads with a body in it, every
## creature in a room is one the game has, and a door leads on. Exit code 1 on
## any failure. Deliberately untyped w.r.t. game classes.

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failed = true


func _settle(frames := 20) -> void:
	for i in frames:
		await process_frame


func _run() -> void:
	var data = root.get_node("Data")
	var game: Dictionary = data.game
	print("game: %s (%d rooms)" % [game.get("name", game.get("id", "?")), data.rooms.size()])
	_check(not data.rooms.is_empty(), "game.json names its rooms")
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(30)
	var run = current_scene
	_check(run != null and run.room != null and run.room_index == 0, "a night opens on the first room")
	for index in data.rooms.size():
		run._load_room(index)
		await _settle()
		var name: String = str(data.rooms[index]).get_file().get_basename()
		_check(run.room != null and run.room_index == index, "%s loads" % name)
		var bodies := get_nodes_in_group("player")
		_check(bodies.size() == 1 and run.room.is_ancestor_of(bodies[0]) == false and bodies[0].is_inside_tree(),
			"%s: the hero is in it" % name)
		var strangers := get_nodes_in_group("enemies").filter(func(e) -> bool: return not data.enemies.has(e.enemy_id))
		_check(strangers.is_empty(), "%s: every creature is the game's own (%d)" % [name, get_nodes_in_group("enemies").size()])
		_check(run.room.get("door") != null or index == data.rooms.size() - 1, "%s: a door leads on" % name)
	root.get_node("Game").practice = "training_dummy"
	run._load_room(run.PRACTICE_INDEX)
	await _settle()
	_check(run.room != null and run.room.scene_file_path == str(game.get("practice_room", run.PRACTICE_ROOM)), "the practice yard loads")
	root.get_node("Game").practice = ""
	print("game_smoke_test: %s" % ("FAILED" if _failed else "passed"))
	quit(1 if _failed else 0)
