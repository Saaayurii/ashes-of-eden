extends SceneTree
## The chapter's variants on old strips (data/enemies, docs/CHAPTER1.md):
##   - the shield-bearer turns a blow at its face, not one at its back, nor one
##     while it swings, nor a backstab;
##   - the hollow wraith comes apart into two shades, awake, and the room's door
##     waits for them too;
##   - the cult slinger is a caster that throws.
## Puts the profile back as it found it.
##   godot --headless --path . -s scripts/tools/variants_test.gd

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


func _run() -> void:
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	var profile = root.get_node("Profile")
	var saved = profile.data.duplicate(true)
	game.vial = 0
	game.omen = ""
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	run._load_room(run.ROOMS.find("res://scenes/rooms/graveyard_tree.tscn"))
	await _settle(0.4)
	run.cutscene.abort()
	game.cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false
	for node in get_nodes_in_group("enemies"):
		node.queue_free()
	await _settle(0.1)
	var player = run.player
	var at: Vector2 = player.global_position

	# the shield-bearer, facing the hero: a blow from the front is turned
	var bearer = run._spawn_enemy("shield_bearer", at + Vector2(60, -20), true)
	await process_frame
	bearer.set_physics_process(false)
	bearer.facing = -1  # towards the hero, who stands to its left
	bearer.state = bearer.State.CHASE
	bearer._guard_down = false
	var shield: float = float(bearer.stats.shield)
	var armor: float = float(bearer.stats.get("armor", 0.0))
	var hp: float = bearer.hp
	bearer._apply_damage(20.0, at, false, false, 1.0)
	var front: float = hp - bearer.hp
	_check(is_equal_approx(front, 20.0 * (1.0 - shield) * (1.0 - armor)), "shield-bearer: a blow at its face is turned (%.1f)" % front)
	# from behind
	bearer.state = bearer.State.CHASE
	hp = bearer.hp
	bearer._apply_damage(20.0, bearer.global_position + Vector2(60, 0), false, false, 1.0)
	_check(is_equal_approx(hp - bearer.hp, 20.0 * (1.0 - armor)), "shield-bearer: its back is open (%.1f)" % (hp - bearer.hp))
	# while it winds up, and through the recovery after its blow
	bearer._set_state(bearer.State.WINDUP, 0.5)
	hp = bearer.hp
	bearer._apply_damage(20.0, at, false, false, 1.0)
	_check(is_equal_approx(hp - bearer.hp, 20.0 * (1.0 - armor)), "shield-bearer: open while it winds up")
	bearer._set_state(bearer.State.RECOVER, 0.5)
	hp = bearer.hp
	bearer._apply_damage(20.0, at, false, false, 1.0)
	_check(is_equal_approx(hp - bearer.hp, 20.0 * (1.0 - armor)), "shield-bearer: still open recovering from its blow")
	bearer._set_state(bearer.State.CHASE, 0.0)
	hp = bearer.hp
	bearer._apply_damage(20.0, at, false, false, 1.0)
	_check(hp - bearer.hp < 20.0 * (1.0 - armor) * 0.5, "shield-bearer: the shield is up again once it walks")
	# unaware: a backstab goes round it
	bearer.state = bearer.State.PATROL
	hp = bearer.hp
	bearer._apply_damage(10.0, at, false, false, 1.0, 2.0)
	_check(hp - bearer.hp >= 10.0 * 2.0 * (1.0 - armor) - 0.01, "shield-bearer: a backstab is not turned")
	bearer.queue_free()
	await _settle(0.1)

	# the hollow wraith: two shades, awake, and the door waits for them
	run.room.door.open = false
	var alive_before: int = run.room.alive
	var hollow = run._spawn_enemy("hollow_wraith", at + Vector2(80, -60), true)
	run.room.alive += 1  # spawned past the room, as the run's own spawn would not count
	await process_frame
	hollow.set_physics_process(false)
	hollow.take_damage(100000.0)
	await _settle(0.3)
	var shades := []
	for node in get_nodes_in_group("enemies"):
		if node.enemy_id == "shade" and not node.is_dead():
			shades.append(node)
	var death: Dictionary = data.enemies.hollow_wraith.on_death
	_check(shades.size() == int(death.count), "hollow wraith: comes apart into %d shades (%d)" % [int(death.count), shades.size()])
	_check(shades.all(func(s) -> bool: return s.aware), "hollow wraith: the shades are awake")
	_check(run.room.alive == alive_before + shades.size() and not run.room.door.open, "hollow wraith: the door waits for its pieces")
	for s in shades:
		s.take_damage(100000.0)
	await _settle(0.3)
	_check(run.room.alive == alive_before, "hollow wraith: the count comes back once they are down")

	# the slinger keeps back and throws
	var slinger: Dictionary = data.enemies.cult_slinger
	_check(slinger.behaviour == "caster" and slinger.attack.type == "ranged" and float(slinger.attack.windup) >= 0.6,
		"cult slinger: a caster that throws, with a wind-up to read")
	profile.data = saved
	profile.save()
	print("VARIANTS TEST PASSED" if failures == 0 else "VARIANTS TEST FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)
