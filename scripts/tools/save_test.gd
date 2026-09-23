extends SceneTree
## Saves end to end, headless:
##   godot --headless -s scripts/tools/save_test.gd
## Runs into room 3 with a gift and some damage, saves, loads, and checks the
## night came back as it was; then the export code and file round-trip, and
## that garbage and foreign files are refused. Tool scripts save into
## user://saves_tools/ (see Saves._ready): the player's own slots are safe.

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var saves = root.get_node("Saves")
	var game = root.get_node("Game")
	var data_loader = root.get_node("Data")
	var backup: Dictionary = saves.read("3")

	var run = load("res://scenes/run/run.tscn").instantiate()
	root.add_child(run)
	current_scene = run
	run.transition.instant = true  # no curtain between the rooms of a test
	await _settle(0.5)
	_assert(saves.has(saves.AUTO), "entering the first room autosaves")

	# a night with something in it: a gift, a flag, damage, two rooms on
	var gift_id: String = data_loader.abilities.keys()[0]
	root.get_node("EventBus")  # autoloads are there
	var ability_system = load("res://scripts/combat/ability_system.gd")
	ability_system.apply(run.player, data_loader.abilities[gift_id])
	game.flags["save_test"] = true
	game.alignment["will"] = 3
	game.add_essence(40.0)
	run.player.hp = 37.0
	run.kills = 5
	run._load_room(2)
	await _settle(0.4)
	var checkpoint: Dictionary = run.checkpoint
	_assert(checkpoint.room == run.ROOMS[2], "checkpoint is the room just entered")
	_assert(saves.write("3", checkpoint), "writes slot 3")
	var level_before: int = game.level
	var essence_before: float = game.essence
	var max_hp_before: float = run.player.stats.max_hp

	# load it: a fresh Run scene picks the pending save up
	run.queue_free()
	await process_frame
	game.new_run()
	saves.pending = saves.read("3")
	run = load("res://scenes/run/run.tscn").instantiate()
	root.add_child(run)
	current_scene = run
	await _settle(0.5)
	_assert(run.room_index == 2, "loads into the saved room (%d)" % run.room_index)
	_assert(is_equal_approx(run.player.hp, 37.0), "health back (%.1f)" % run.player.hp)
	_assert(is_equal_approx(run.player.stats.max_hp, max_hp_before), "stats back")
	_assert(game.abilities.size() == 1 and game.abilities[0].id == gift_id, "gift back")
	_assert(game.flags.get("save_test", false) and game.alignment.will == 3, "choices back")
	_assert(game.level == level_before and is_equal_approx(game.essence, essence_before), "essence back")
	_assert(run.kills == 5, "kills back")
	_assert(run.player.global_position.distance_to(run.room.player_spawn.global_position) < 40.0, "at the room's entrance")

	# export / import
	var code: String = saves.to_code(checkpoint)
	_assert(code.begins_with(saves.CODE_PREFIX), "code has its prefix")
	_assert(saves.parse(code).room == checkpoint.room, "code round-trips")
	var file := "user://save_test_export.aoesave"
	_assert(saves.to_file(checkpoint, file) and saves.from_file(file).room == checkpoint.room, "file round-trips")
	DirAccess.remove_absolute(file)
	_assert(saves.parse("hello").is_empty(), "garbage refused")
	_assert(saves.parse('{"game": "other", "format": 1}').is_empty(), "another game's file refused")
	var broken := checkpoint.duplicate(true)
	broken.room = "res://scenes/rooms/nowhere.tscn"
	_assert(saves.parse(JSON.stringify(broken)).is_empty(), "a save of a room that no longer exists is refused")
	var stale := checkpoint.duplicate(true)
	stale.game_state.abilities.append("gift_that_was_removed")
	_assert(saves.parse(JSON.stringify(stale)).game_state.abilities.size() == 1, "removed gifts are dropped, not fatal")

	if backup.is_empty():
		saves.delete("3")
	else:
		saves.write("3", backup)
	print("SAVE TEST PASSED" if failures == 0 else "SAVE TEST FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)


func _settle(seconds: float) -> void:
	await create_timer(seconds).timeout


func _assert(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		failures += 1
