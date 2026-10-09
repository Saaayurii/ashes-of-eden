extends SceneTree
## A room cleared without a wound pays a little Ash (Run._on_unscathed):
##   - a clean clear pays UNSCATHED_ASH and counts, once;
##   - a clear after a wound pays nothing;
##   - where a boss stood it pays UNSCATHED_BOSS_ASH;
##   - a client's claim reaches the host's count, clamped;
##   - a save keeps the count.
##   godot --headless --path . -s scripts/tools/unscathed_test.gd

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


func _load(run, name: String) -> void:
	run._load_room(run.ROOMS.find("res://scenes/rooms/%s.tscn" % name))
	await _settle(0.4)
	run.cutscene.abort()
	root.get_node("Game").cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false
	await _frames(4)


func _clear_room() -> void:
	for body in get_nodes_in_group("enemies"):
		if not body.is_dead():
			if body.get("_hanging"):  # on a noose nothing lands (Enemy._hang): cut it down first
				body._snap(get_first_node_in_group("player"))
			body.take_damage(99999.0)
	await _frames(6)


func _run() -> void:
	var game = root.get_node("Game")
	var saves = root.get_node("Saves")
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	var player = run.player

	await _load(run, "graveyard_tree")
	var ash_before: int = game.ash_earned
	await _clear_room()
	_check(run.room.door.open, "graveyard_tree cleared")
	_check(game.ash_earned == ash_before + run.UNSCATHED_ASH, "a clean clear pays %d Ash (%d -> %d)"
		% [run.UNSCATHED_ASH, ash_before, game.ash_earned])
	_check(game.unscathed == 1, "and counts one room")
	await _clear_room()
	_check(game.unscathed == 1, "once: the same room does not pay twice")

	await _load(run, "catacombs_1")
	ash_before = game.ash_earned
	player._hurt_grace_left = 0.0
	player.take_damage(5.0)
	await _frames(2)
	await _clear_room()
	_check(run.room.door.open, "catacombs_1 cleared")
	_check(game.ash_earned == ash_before and game.unscathed == 1, "a clear after a wound pays nothing")

	await _load(run, "hell_gate")
	ash_before = game.ash_earned
	run._on_unscathed(run.room_index + 1)
	_check(game.ash_earned == ash_before + run.UNSCATHED_BOSS_ASH, "where a boss stood: %d Ash" % run.UNSCATHED_BOSS_ASH)

	ash_before = game.ash_earned
	run._net_unscathed(3)
	run._net_unscathed(500)
	_check(game.ash_earned == ash_before + 3 + run.UNSCATHED_BOSS_ASH, "a client's claim is counted, and clamped")

	var saved: Dictionary = saves.capture(run.ROOMS[run.room_index], 0, 0.0, player)
	saved = saves.validate(JSON.parse_string(JSON.stringify(saved)))
	var count: int = game.unscathed
	game.unscathed = 0
	saves.restore(saved, player)
	_check(game.unscathed == count, "a save keeps the count (%d)" % game.unscathed)

	print("UNSCATHED TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	current_scene = null
	run.queue_free()
	await process_frame
	for voice in root.get_node("Audio").get_children():
		if voice is AudioStreamPlayer:
			voice.stop()
	await create_timer(0.15, true, false, true).timeout
	quit(0 if failures == 0 else 1)
