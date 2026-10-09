extends SceneTree
## A villager on a noose (Enemy._hang, "hang" in data/enemies, EnemySpawn.hanging):
##   - the three rooms hang one each, in the air over its floor, on a rope;
##   - while it hangs no blow lands (the sword glances: impact "block");
##   - a player far off leaves it be; one walking under it snaps the rope;
##   - it falls, lands, holds "land" seconds, then hunts — never a backstab on the way;
##   - a neighbour's shout drops it too; an enemy without "hang" ignores the flag.
##   godot --headless --path . -s scripts/tools/hang_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _settle(seconds := 0.3) -> void:
	await create_timer(seconds, true, false, true).timeout


func _hangers() -> Array:
	return get_nodes_in_group("enemies").filter(func(e): return e._hanging)


func _run() -> void:
	var game = root.get_node("Game")
	game.vial = 0
	game.omen = ""
	for room_name in ["village_night", "graveyard_cross", "graveyard_tree"]:
		var scene: PackedScene = load("res://scenes/rooms/%s.tscn" % room_name)
		var marked := scene.instantiate().find_children("*", "EnemySpawn", true, false).filter(func(s): return s.hanging)
		_check(marked.size() == 1, "%s hangs one villager (%d)" % [room_name, marked.size()])

	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	run._load_room(run.ROOMS.find("res://scenes/rooms/village_night.tscn"))
	await _settle(0.4)
	run.cutscene.abort()
	game.cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false
	var player = run.player
	var hung: Array = _hangers()
	_check(hung.size() == 1, "the village's hanger is on its rope (%d)" % hung.size())
	if hung.is_empty():
		_finish()
		return
	var villager = hung[0]
	for node in get_nodes_in_group("enemies"):
		if node != villager:
			node.set_physics_process(false)
	_check(villager.has_node("Rope"), "a rope is drawn")
	var spawn_y: float = villager._home.y
	await _settle(0.5)
	_check(not villager.is_on_floor() and absf(villager.global_position.y - spawn_y) < 1.0,
		"it stays in the air where it was hung")

	# untouchable on the noose
	var hp: float = villager.hp
	villager.take_damage(500.0, player, {"sneak": 3.0})
	_check(villager.hp == hp and villager._hanging, "a blow on the noose does nothing")
	_check(villager.impact_sound() == &"block", "and sounds like a glance")

	# far off: it waits
	player.set_physics_process(false)
	player.global_position = villager.global_position + Vector2(300, 26)
	await _settle(0.5)
	_check(villager._hanging, "a player 300 px away leaves it hanging")

	# under it: the rope goes
	player.global_position = villager.global_position + Vector2(20, 30)
	await _settle(0.1)
	_check(not villager._hanging and villager._dropping, "a player under it snaps the rope")
	_check(not villager.is_unaware(), "it is awake on the way down (no backstab)")
	var fell := false
	for i in 120:
		await physics_frame
		if villager.is_on_floor():
			fell = true
			break
	_check(fell, "it falls to the floor")
	_check(villager.global_position.y > spawn_y + 10.0, "below where it hung")
	await _settle(0.3)
	_check(villager._dropping, "it lies a beat before it moves (hang.land)")
	hp = villager.hp
	villager.take_damage(5.0, player, {"sneak": 3.0})
	_check(is_equal_approx(hp - villager.hp, 5.0), "a blow now lands, and plainly")
	await _settle(0.8)
	_check(not villager._dropping and villager.state == villager.State.CHASE, "then it hunts")
	_check(not villager.has_node("Rope"), "the cut rope is gone")

	# a neighbour's shout drops another
	var other = run._spawn_enemy("possessed_villager", player.global_position + Vector2(140, -20), false, true)
	await process_frame
	_check(other._hanging, "spawned hanging, it hangs")
	var caller = run._spawn_enemy("possessed_villager", other.global_position + Vector2(30, 0), false)
	await process_frame
	caller.set_physics_process(false)
	caller._notice(player)
	_check(not other._hanging, "a neighbour's shout snaps its rope")

	# no "hang" in the data: the flag means nothing
	var cultist = run._spawn_enemy("cultist", player.global_position + Vector2(-140, -20), false, true)
	await process_frame
	_check(not cultist._hanging, "an enemy without \"hang\" does not hang")
	_finish()


func _finish() -> void:
	print("hang_test: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)
