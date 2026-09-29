extends SceneTree
## The Ophanim's seal phase, fought in its own room (docs/BALANCE.md):
## at half health it closes its eyes and nothing hurts it; three seals hang
## where the hero can reach them; breaking the last one opens it to a damage
## phase with no attacks and a bonus on every blow; then it fights again and
## can die.
##   godot --headless --path . -s scripts/tools/seal_phase_test.gd

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


func _run() -> void:
	change_scene_to_file("res://scenes/run/run.tscn")
	await process_frame
	await process_frame
	var run = current_scene
	run.transition.instant = true
	var index: int = run.ROOMS.find("res://scenes/rooms/hell_gate.tscn")
	run._load_room(index)
	for frame in 30:
		await process_frame
	run.cutscene.abort()
	root.get_node("Game").cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false
	await _frames(4)
	var boss = null
	for node in get_nodes_in_group("enemies"):
		if node.enemy_id == "ophanim":
			boss = node
	_check(boss != null, "the Ophanim is in its room")
	if boss == null:
		_finish(run)
		return
	var phase: Dictionary = boss.stats.seal_phase
	var at_hp: float = boss._max_hp * float(phase.at_hp)
	# a blow far bigger than what is left above the threshold
	boss.take_damage(boss.hp - at_hp + 400.0)
	await _frames(3)
	_check(is_equal_approx(boss.hp, at_hp), "the threshold is a floor: no blow skips the phase (%s)" % boss.hp)
	_check(boss._sealed, "at half health it closes its eyes")
	var before: float = boss.hp
	boss.take_damage(200.0)
	await _frames(2)
	_check(boss.hp == before and boss._sealed, "sealed, nothing hurts it")
	var seals: Array = []
	for node in get_nodes_in_group("enemies"):
		if node.enemy_id == str(phase.seal) and not node.is_dead():
			seals.append(node)
	_check(seals.size() == 3, "three seals appear (%d)" % seals.size())
	# each seal hangs where a standing hero's blade reaches it: a floor just under it
	var space: PhysicsDirectSpaceState2D = run.room.get_world_2d().direct_space_state
	for seal in seals:
		var ray := PhysicsRayQueryParameters2D.create(seal.global_position, seal.global_position + Vector2(0, 40), 17)
		var hit: Dictionary = space.intersect_ray(ray)
		_check(not hit.is_empty() and hit.position.y - seal.global_position.y <= 30.0,
			"the seal at %s hangs within a blade's reach of a floor" % seal.global_position)
	var p0: Vector2 = seals[0].global_position if not seals.is_empty() else Vector2.ZERO
	await _frames(30)
	_check(seals.is_empty() or seals[0].global_position == p0, "a seal stays where it was put")
	# the boss only uses its sealed attacks meanwhile
	var picked := {}
	for i in 60:
		boss._attack_cd = 0.0
		var choice: int = boss._choose_attack(Vector2(0, 20))
		if choice >= 0:
			picked[boss._attacks[choice].type] = true
	_check(picked.keys() == ["ranged"], "sealed, it only casts its sealed attacks (%s)" % [picked.keys()])
	# a real swing from the floor under a seal reaches it
	if not seals.is_empty():
		var hero = run.player
		var ray := PhysicsRayQueryParameters2D.create(seals[0].global_position, seals[0].global_position + Vector2(0, 40), 17)
		var floor_y: float = space.intersect_ray(ray).position.y
		hero.controls_enabled = true
		hero.place_in_room(Vector2(seals[0].global_position.x - 22.0, floor_y - 15.0))
		hero.facing = 1
		await _frames(10)
		var seal_hp: float = seals[0].hp
		Input.action_press("attack")
		await _frames(2)
		Input.action_release("attack")
		await _frames(20)
		_check(seals[0].hp < seal_hp, "the hero's own swing from the floor breaks into it (%s -> %s)" % [seal_hp, seals[0].hp])
	for i in seals.size():
		var seal = seals[i]
		while not seal.is_dead():
			seal.take_damage(25.0)
		await _frames(2)
		if i < seals.size() - 1:
			_check(boss._sealed, "still sealed with %d seal(s) left" % (seals.size() - 1 - i))
	await _frames(2)
	_check(not boss._sealed and boss._exposed_left > 0.0, "the last seal opens it: the damage phase")
	_check(boss._choose_attack(Vector2(0, 20)) == -1, "exposed, it does not attack")
	before = boss.hp
	boss.take_damage(100.0)
	var taken: float = before - boss.hp
	var expected := 100.0 * (1.0 + float(phase.exposed_bonus)) * (1.0 - float(boss.stats.get("armor", 0.0)))
	_check(absf(taken - expected) < 0.01, "exposed, every blow lands harder (%s of %s)" % [taken, expected])
	boss._exposed_left = 0.01
	# the break's hit-stop slows time for a moment of real time
	await create_timer(0.4, true, false, true).timeout
	await _frames(3)
	var fights := false
	for i in 30:
		if boss._choose_attack(Vector2(0, 20)) >= 0:
			fights = true
	_check(fights, "after the damage phase it fights again")
	boss.take_damage(99999.0)
	await _frames(2)
	_check(boss.is_dead() and not boss._sealed, "and it can die; the phase comes once")
	_finish(run)


func _finish(run) -> void:
	print("SEAL PHASE TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	current_scene = null
	run.queue_free()
	await process_frame
	for voice in root.get_node("Audio").get_children():
		if voice is AudioStreamPlayer:
			voice.stop()
	await create_timer(0.15, true, false, true).timeout
	quit(0 if failures == 0 else 1)
