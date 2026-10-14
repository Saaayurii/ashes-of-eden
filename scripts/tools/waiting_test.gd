extends SceneTree
## Chapter II's waiting (docs/CHAPTER2.md, "waits" in an enemy's JSON):
##   - one that waits does not hold the door, so a cleared room stays open;
##   - it does not see, feel a touch or hear a shout: it stays unaware;
##   - a blow wakes it, lands as a backstab and sets waiter_struck;
##   - a boss that waits starts unaware too;
##   - a choice's "flask": -1 takes a flask, never below none.
## The chapter's enemies are drafts the game does not load, so the test lays
## two stand-ins into Data.enemies and takes them out again.
##   godot --headless --path . -s scripts/tools/waiting_test.gd

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


func _run() -> void:
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	var had_flag: bool = game.flags.has("waiter_struck")
	var waiter: Dictionary = data.enemies["possessed_villager"].duplicate(true)
	waiter["id"] = "test_waiter"
	waiter["waits"] = true
	waiter.erase("aware")
	data.enemies["test_waiter"] = waiter
	var boss: Dictionary = data.enemies["knight_of_ash"].duplicate(true)
	boss["id"] = "test_waiting_boss"
	boss["waits"] = true
	data.enemies["test_waiting_boss"] = boss

	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	var player = run.player
	run._load_room(run.ROOMS.find("res://scenes/rooms/graveyard_tree.tscn"))
	await _settle(0.4)
	run.cutscene.abort()
	game.cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false
	await _frames(4)
	for body in get_nodes_in_group("enemies"):
		if not body.is_dead():
			body.take_damage(99999.0)
	await _frames(6)
	var room = run.room
	_check(room.door.open, "graveyard_tree cleared, door open")

	var alive_before: int = room.alive
	var one = room.spawn_enemy("test_waiter", player.global_position + Vector2(6, 0))
	await _frames(30)
	_check(room.alive == alive_before, "a waiter is not counted against the door (%d -> %d)" % [alive_before, room.alive])
	_check(room.door.open, "and the door stays open")
	_check(one.is_unaware(), "standing on the hero, it has not noticed him")
	one._notice(player)
	_check(one.is_unaware(), "a shout does not wake it")

	game.flags.erase("waiter_struck")
	var hp: float = one.hp
	one.take_damage(4.0, player, {"sneak": float(player.stats.backstab_multiplier)})
	await _frames(4)
	_check(not one.is_unaware(), "a blow wakes it")
	_check(game.flags.get("waiter_struck", false), "and sets waiter_struck")
	_check(hp - one.hp > 4.0, "the blow landed as a backstab (%.1f taken)" % (hp - one.hp))
	_check(room.door.open, "a waiter woken does not shut the door")
	one.take_damage(99999.0)
	await _frames(6)
	_check(room.door.open and room.alive == alive_before, "its death leaves the count alone")

	var big = room.spawn_enemy("test_waiting_boss", player.global_position + Vector2(200, 0))
	await _frames(4)
	_check(big.is_unaware(), "a boss that waits starts unaware")
	big.queue_free()

	var full: int = player.heal_charges
	game.apply_effect({"flask": -1})
	await _frames(1)
	_check(player.heal_charges == full - 1, "a choice's flask: -1 takes one (%d -> %d)" % [full, player.heal_charges])
	player.heal_charges = 0
	game.apply_effect({"flask": -1})
	await _frames(1)
	_check(player.heal_charges == 0, "and never below none")
	game.apply_effect({"flask": 5})
	await _frames(1)
	_check(player.heal_charges == int(player.stats.heal_charges), "a given flask never goes past full")

	if had_flag:
		game.flags["waiter_struck"] = true
	else:
		game.flags.erase("waiter_struck")
	data.enemies.erase("test_waiter")
	data.enemies.erase("test_waiting_boss")
	print("waiting_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)
