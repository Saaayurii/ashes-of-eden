extends SceneTree
## The wailer (docs/CHAPTER2.md, data/enemies/wailer.json, attack "wail"):
##   - she waits like the rest: unaware, not counted against the door;
##   - struck awake, she does not come at the hero — she draws breath (a wind-up
##     of a full second) and wails;
##   - the wail wakes every waiter within its radius and leaves the rest asleep,
##     and those it woke were not struck: no waiter_struck from them;
##   - with nobody left asleep around her she has no reason to wail again.
##   godot --headless --path . -s scripts/tools/wailer_test.gd

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
	var wail := {}
	for attack in data.enemies["wailer"].get("attacks", []):
		if attack.get("type") == "wail":
			wail = attack
	_check(not wail.is_empty() and bool(data.enemies["wailer"].get("waits", false)), "the wailer waits and can wail")
	var radius := float(wail.get("radius", 0))

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
	var room = run.room
	for attempt in 8:
		for body in get_nodes_in_group("enemies"):
			if not body.is_dead():
				body.take_damage(99999.0)
		await _frames(6)
		if room.alive == 0 and room.door.open:
			break
	# the cleared room's outro would freeze everybody (Game.cutscene)
	await _frames(4)
	run.cutscene.abort()
	game.cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false
	player.stats.max_hp = 1e9
	player.hp = 1e9
	var alive_before: int = room.alive

	var at: Vector2 = player.global_position + Vector2(160, -20)
	var she = room.spawn_enemy("wailer", at)
	var near_a = room.spawn_enemy("waiting_townsman", at + Vector2(-radius * 0.5, 0))
	var near_b = room.spawn_enemy("waiting_townsman", at + Vector2(radius * 0.6, 0))
	var far = room.spawn_enemy("waiting_townsman", at + Vector2(radius + 160.0, 0))
	await _frames(20)
	_check(she.is_unaware() and room.alive == alive_before, "she waits, unaware, and holds no door")
	_check(far.global_position.distance_to(she.global_position) > radius, "one stands beyond her voice")

	she.take_damage(1.0, player, {"sneak": 1.0})
	game.flags.erase("waiter_struck")
	await _frames(2)
	_check(not she.is_unaware(), "a blow wakes her")

	she._attack_cd = 0.0
	var windup := -1.0
	for i in 300:
		await physics_frame
		if she.state == she.State.WINDUP:
			windup = she._state_left
			break
	_check(she._attack.get("type") == "wail", "awake, she wails (%s)" % she._attack.get("type"))
	_check(windup >= 0.8, "after a breath the eye can read (%.2f s)" % windup)
	_check(near_a.is_unaware() and near_b.is_unaware(), "nobody stirs while she draws it")

	await _settle(windup + 0.8)  # past the "!" beat (ALERT still counts as unaware)
	_check(not near_a.is_unaware() and not near_b.is_unaware(), "the wail wakes the waiters around her")
	_check(far.is_unaware(), "and leaves the one out of earshot waiting")
	_check(not game.flags.get("waiter_struck", false), "woken by her voice, not struck: no waiter_struck")
	_check(room.alive == alive_before and room.door.open, "the woken still hold no door")
	far.queue_free()
	await _frames(2)
	_check(not she._in_attack_range(wail, player.global_position - she.global_position),
		"with nobody asleep near her, no reason to wail again")
	var sleeper = room.spawn_enemy("waiting_townsman", she.global_position + Vector2(40, -20))
	await _frames(4)
	_check(she._in_attack_range(wail, Vector2(60, 0)), "one more waiter beside her, and she would")

	for body in [she, near_a, near_b, sleeper]:
		if is_instance_valid(body):
			body.queue_free()
	if had_flag:
		game.flags["waiter_struck"] = true
	else:
		game.flags.erase("waiter_struck")
	print("wailer_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)
