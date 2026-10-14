extends SceneTree
## The Watchman's patience (docs/CHAPTER2.md, "patience" in his JSON,
## Enemy._begin_tend):
##   - between blows, every 8–10 s, he turns his back on the hero to tend the
##     fire, for patience.turn seconds;
##   - a blow then lands as a backstab and does not turn him round (no hurt pose);
##   - he remembers it: his next wind-up is patience.quicken as long, never
##     under patience.min_windup — and only that one;
##   - outside the window a blow on him is an ordinary blow.
##   godot --headless --path . -s scripts/tools/watchman_test.gd

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
	var spec: Dictionary = data.enemies["watchman"].get("patience", {})
	_check(not spec.is_empty(), "the Watchman's data has patience")

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
		body.queue_free()
	await _frames(2)
	player.stats.max_hp = 1e9
	player.hp = 1e9
	var sneak := float(player.stats.backstab_multiplier)
	var armor := float(data.enemies["watchman"].get("armor", 0.0))

	var w = run.room.spawn_enemy("watchman", player.global_position + Vector2(240, -20))
	await _frames(10)
	var every: Array = spec.get("every", [8, 10])
	_check(w._patience_left >= float(every[0]) - 0.5 and w._patience_left <= float(every[1]),
		"his first turn is %.1f s off, within %s" % [w._patience_left, every])
	_check(not w.is_unaware(), "a boss starts awake")

	# a plain blow, his face to us
	w._attack_cd = 99.0
	var hp: float = w.hp
	w.take_damage(10.0, player, {"sneak": sneak})
	await _frames(2)
	_check(absf((hp - w.hp) - 10.0 * (1.0 - armor)) < 0.01, "outside the window a blow is ordinary (%.1f)" % (hp - w.hp))

	# the turn to the fire
	w._attack_cd = 99.0
	w._patience_left = 0.01
	await _frames(20)
	_check(w.is_tending(), "the time come, he turns to the fire")
	var away := signf(w.global_position.x - player.global_position.x)
	_check(float(w.facing) == away, "his back to the hero (facing %d)" % w.facing)
	_check(w.sprite.animation == str(spec.get("animation", "special")), "in the pose of the fire (%s)" % w.sprite.animation)

	hp = w.hp
	w.take_damage(10.0, player, {"sneak": sneak})
	await _frames(2)
	_check(absf((hp - w.hp) - 10.0 * sneak * (1.0 - armor)) < 0.01,
		"a blow in the window is a backstab (%.1f of %.1f)" % [hp - w.hp, 10.0 * sneak * (1.0 - armor)])
	_check(w.is_tending() and float(w.facing) == away, "and does not turn him round")
	_check(w.sprite.animation != "hurt", "nor make him flinch")
	_check(w._patience_struck, "he remembers it")

	await _settle(float(spec.get("turn", 1.2)) + 0.2)
	_check(not w.is_tending(), "the turn ends after %.1f s" % float(spec.get("turn", 1.2)))
	_check(w._patience_left >= float(every[0]) - 0.5, "and the next is a while off (%.1f s)" % w._patience_left)

	# the next wind-up is the shorter for it, and still readable
	w._attack_cd = 0.0
	var started := -1.0
	var attack := {}
	for i in 600:
		await physics_frame
		if w.state == w.State.WINDUP:
			started = w._state_left
			attack = w._attack
			break
	var full := float(attack.get("windup", 0.0))
	var want := maxf(minf(full, float(spec.get("min_windup", 0.5))), full * float(spec.get("quicken", 0.6)))
	_check(started > 0.0 and absf(started - want) < 0.05,
		"his next wind-up comes sooner: %.2f s of %.2f" % [started, full])
	_check(started >= minf(full, float(spec.get("min_windup", 0.5))) - 0.05 and started >= 0.45, "but never unreadable")
	_check(not w._patience_struck, "remembered once")
	_check(is_equal_approx(w._windup_of(attack), full), "the one after is whole again")

	# an untouched turn costs nothing
	w._patience_struck = false
	_check(is_equal_approx(w._windup_of(attack), full), "a turn left alone shortens nothing")

	w.queue_free()
	print("watchman_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)
