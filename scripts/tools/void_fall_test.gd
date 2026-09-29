extends SceneTree
## Regression: falling beyond any room boundary is a fatal fall, even if the
## player owns an extra life. Run headless with -s scripts/tools/void_fall_test.gd.
##
## Then every room of the run, every open column of its bottom edge: wherever
## nothing solid stands between the body and the edge of the map, a body that
## falls there dies the moment it crosses the room's death line — with an
## extra life in hand, and without first landing on anything it cannot see.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var room = load("res://scenes/rooms/village_night.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	var player = load("res://scenes/player/player.tscn").instantiate()
	room.add_child(player)
	await process_frame
	player.stats.extra_lives = 2
	var deaths := [0]
	player.died.connect(func(_body): deaths[0] += 1)
	player.global_position = room.to_global(Vector2(room.width / 2.0, room.height + 80.0))
	await physics_frame
	await physics_frame
	var passed: bool = player.is_dead() and player.hp == 0.0 \
			and player.fell_outside_room and deaths[0] == 1
	# The bone mound below the first painted stair has no invisible floor.
	var pit_player = load("res://scenes/player/player.tscn").instantiate()
	room.add_child(pit_player)
	await process_frame
	pit_player.global_position = room.to_global(Vector2(120.0, 480.0))
	for frame in 90:
		if pit_player.is_dead():
			break
		await physics_frame
	passed = passed and pit_player.is_dead() and pit_player.fell_outside_room
	current_scene = null
	room.queue_free()
	await process_frame

	# The second graveyard panel has a painted bone mound below the bridge.
	# It must not behave like an invisible safety floor: falling into that
	# part of the illustration ends the run at its room-specific death line.
	var cross = load("res://scenes/rooms/graveyard_cross.tscn").instantiate()
	root.add_child(cross)
	current_scene = cross
	var falling_player = load("res://scenes/player/player.tscn").instantiate()
	cross.add_child(falling_player)
	await process_frame
	falling_player.global_position = cross.to_global(Vector2(cross.width - 70.0, 620.0))
	for frame in 90:
		if falling_player.is_dead():
			break
		await physics_frame
	passed = passed and falling_player.is_dead() and falling_player.fell_outside_room
	current_scene = null
	cross.queue_free()
	await process_frame
	for key in ["graveyard_arches", "graveyard_tree", "swamp_moon", "swamp_red", "swamp_crypt"]:
		var panel = load("res://scenes/rooms/%s.tscn" % key).instantiate()
		root.add_child(panel)
		current_scene = panel
		var body = load("res://scenes/player/player.tscn").instantiate()
		panel.add_child(body)
		await process_frame
		body.place_in_room(Vector2(1100, 665))
		for frame in 90:
			if body.is_dead():
				break
			await physics_frame
		passed = passed and body.is_dead() and body.fell_outside_room
		current_scene = null
		panel.queue_free()
		await process_frame
	passed = await _every_open_column() and passed
	print("VOID FALL TEST %s" % ("PASSED" if passed else "FAILED"))
	quit(0 if passed else 1)


func _every_open_column() -> bool:
	var ok := true
	var rooms: Array = load("res://scripts/run/run.gd").get_script_constant_map()["ROOMS"]
	for path in rooms:
		var room = load(path).instantiate()
		root.add_child(room)
		current_scene = room
		await physics_frame
		await physics_frame
		var limit: float = room.void_kill_y if room.void_kill_y >= 0.0 else float(room.height) + 24.0
		var space: PhysicsDirectSpaceState2D = room.get_world_2d().direct_space_state
		var columns := 0
		for x in range(24, int(room.width) - 23, 32):
			# open: nothing solid or one-way from well above the line to past it
			var ray := PhysicsRayQueryParameters2D.create(room.to_global(Vector2(x, limit - 70.0)),
				room.to_global(Vector2(x, limit + 60.0)), 17)
			if not space.intersect_ray(ray).is_empty():
				continue
			# lava is not the edge of the map: it burns and puts the body back
			var over_lava := false
			for child in room.get_children():
				if child is Area2D and child.has_method("danger_rect") and child.danger_rect().has_point(Vector2(x, child.danger_rect().position.y + 1.0)):
					over_lava = true
			if over_lava:
				continue
			columns += 1
			var body = load("res://scenes/player/player.tscn").instantiate()
			room.add_child(body)
			await process_frame
			body.controls_enabled = false
			body.stats.extra_lives = 2
			var deaths := [0]
			body.died.connect(func(_b): deaths[0] += 1)
			body.place_in_room(Vector2(x, limit - 50.0))
			var late := false
			for frame in 60:
				await physics_frame
				if body.is_dead():
					break
				# one frame of travel past the line is the most a death may lag
				if room.to_local(body.global_position).y > limit + 20.0:
					late = true
			if late or not body.is_dead() or not body.fell_outside_room or deaths[0] != 1:
				ok = false
				print("  FAIL %s: a fall at x=%d %s" % [path.get_file().get_basename(), x,
					"outlived the edge of the map" if late or not body.is_dead() else "was not a fall out of the room"])
			body.queue_free()
			await physics_frame
		print("  %s %s: %d open columns" % ["ok  " if ok else "....", path.get_file().get_basename(), columns])
		current_scene = null
		room.queue_free()
		await process_frame
	return ok
