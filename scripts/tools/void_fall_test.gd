extends SceneTree
## Regression: falling beyond any room boundary is a fatal fall, even if the
## player owns an extra life. Run headless with -s scripts/tools/void_fall_test.gd.


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
	print("VOID FALL TEST %s" % ("PASSED" if passed else "FAILED"))
	quit(0 if passed else 1)
