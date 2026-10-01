extends SceneTree
## Where he fell last night (LastFall, Profile.data.last_fall):
##   - a night that ends in a death to something leaves the spot for tomorrow;
##     the lava, the drop, the practice yard and the night of the day do not;
##   - the next night that room shows the body; walking over it says what laid
##     him low and gives back some essence, once;
##   - a dawn clears it.
## Puts the profile back as it found it.
##   godot --headless --path . -s scripts/tools/last_fall_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _settle(seconds := 0.3) -> void:
	await create_timer(seconds, true, false, true).timeout


func _quiet(run) -> void:
	run.cutscene.abort()
	root.get_node("Game").cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false


func _run() -> void:
	var game = root.get_node("Game")
	var profile = root.get_node("Profile")
	var saved: Dictionary = profile.data.duplicate(true)
	var last_fall = load("res://scripts/rooms/last_fall.gd")
	var tree_room := "res://scenes/rooms/graveyard_tree.tscn"

	profile.data.last_fall = {}
	last_fall.remember(tree_room, Vector2(400, 300), "lava")
	last_fall.remember(tree_room, Vector2(400, 300), "fall")
	_check(profile.data.last_fall.is_empty(), "the lava and the drop leave no body to find")
	game.practice = "cultist"
	last_fall.remember(tree_room, Vector2(400, 300), "zealot")
	game.practice = ""
	game.daily = "2026-10-01"
	last_fall.remember(tree_room, Vector2(400, 300), "zealot")
	game.daily = ""
	_check(profile.data.last_fall.is_empty(), "  nor the practice yard, nor the night of the day")

	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	var player = run.player
	run._load_room(run.ROOMS.find(tree_room))
	await _settle(0.4)
	_quiet(run)
	for node in get_nodes_in_group("enemies"):
		node.set_physics_process(false)
		node.set_process(false)
	await _frames(2)

	# tonight he falls here, to a zealot
	var spot: Vector2 = player.global_position + Vector2(120, 0) - run.room.global_position
	player.global_position = spot + run.room.global_position
	game.slain_by = "zealot"
	run._show_end(false, run.room_index + 1, 3, 200.0, 0)
	await _settle(0.2)
	_check(str(profile.data.last_fall.get("room", "")) == tree_room and str(profile.data.last_fall.get("by", "")) == "zealot",
		"a death leaves the spot for tomorrow (%s)" % profile.data.last_fall)

	# the next night, the same room
	game.new_run()
	run._finished = false
	run.run_end.visible = false
	player.revive(spot + run.room.global_position - Vector2(120, 0))  # at the entrance, not on the body
	run._load_room(run.ROOMS.find(tree_room))
	await _settle(0.4)
	_quiet(run)
	for node in get_nodes_in_group("enemies"):
		node.set_physics_process(false)
		node.set_process(false)
	var body = run.room.get_node_or_null("LastFall")
	await _frames(2)
	# where he fell, come to rest on the floor below it (a death in the air does not hang there)
	_check(body != null and absf(body.position.x - spot.x) < 1.0 and body.position.y >= spot.y - 1.0,
		"the body lies where he fell, on the floor (%s from %s)" % [body.position if body else null, spot])
	_check(body != null and body.killer == "zealot", "  and remembers what laid him low")
	_check(not game.flags.has("last_fall_found"), "  untouched until he walks to it")
	var before: float = game.essence
	var level_before: int = game.level
	player.global_position = body.global_position + Vector2(0, -2) if body != null else player.global_position
	await _frames(30)
	_check(game.flags.has("last_fall_found") and (game.essence > before or game.level > level_before),
		"walking over it gives back some essence (%s, %.1f -> %.1f)" % [game.flags.has("last_fall_found"), before, game.essence])
	_check(profile.data.last_fall.is_empty(), "  once: it does not lie there another night")
	_check(run.dialogue.is_open(), "  and Elian says a word over it")
	await _settle(1.5)
	run._load_room(run.ROOMS.find(tree_room))
	await _settle(0.3)
	_check(run.room.get_node_or_null("LastFall") == null, "back in the room, it is gone")

	# a dawn clears whatever was left
	profile.data.last_fall = {"room": tree_room, "x": 0, "y": 0, "by": "zealot"}
	run._finished = false
	run._show_end(true, 15, 3, 200.0, 0)
	await _settle(0.2)
	_check(profile.data.last_fall.is_empty(), "a dawn clears it")

	game.new_run()
	profile.data = saved
	profile.save()
	await process_frame
	print("LAST FALL TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
