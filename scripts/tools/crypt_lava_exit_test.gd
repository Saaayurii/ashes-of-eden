extends SceneTree
## The exit belongs inside its painted arch; the adjacent stair is not a flat shelf.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var room = load("res://scenes/rooms/crypt_lava.tscn").instantiate()
	root.add_child(room)
	var hero = load("res://scenes/player/player.tscn").instantiate()
	room.add_child(hero)
	hero.controls_enabled = true
	var failures := 0
	for pair in [["LowerReturnShape", "LowerReturnCornice"], ["GalleryReturnShape", "GalleryReturnCornice"]]:
		var shape := room.get_node("Ledges/" + pair[0]) as CollisionShape2D
		var art := room.get_node("Terrain/" + pair[1]) as Sprite2D
		var top: Vector2 = shape.position - shape.shape.size * 0.5
		if not shape.one_way_collision or top != art.position or shape.shape.size != art.region_rect.size:
			failures += 1
			push_error("Crypt return art/collision mismatch: " + pair[0])
	if room.door.position != Vector2(1450, 176) or not room.door.painted_arch:
		failures += 1
	for uphill in [true, false]:
		hero.place_in_room(Vector2(1440, 193) if uphill else Vector2(1576, 107))
		for settle in 8:
			await physics_frame
		var action := "move_right" if uphill else "move_left"
		Input.action_press(action)
		var crossed := false
		for frame in 120:
			await physics_frame
			if (uphill and hero.position.x > 1574) or (not uphill and hero.position.x < 1440):
				crossed = true
				break
		Input.action_release(action)
		for settle in 8:
			await physics_frame
		var correct_height: bool = hero.position.y < 120 if uphill else absf(hero.position.y - 193) < 2
		if not crossed or not correct_height or not hero.is_on_floor():
			failures += 1
			push_error("Crypt exit stair failed: " + str(hero.position))
		print("CRYPT_EXIT_STAIR uphill=", uphill, " hero=", hero.position)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		hero.controls_enabled = false
		hero.camera.enabled = false
		hero.place_in_room(Vector2(1450, 193))
		var camera := Camera2D.new()
		camera.position = Vector2(1280, 180)
		root.add_child(camera)
		camera.make_current()
		for frame in 12:
			await physics_frame
		await process_frame
		await process_frame
		await create_timer(0.35).timeout
		var status := root.get_texture().get_image().save_png(args[0])
		if status != OK:
			failures += 1
		camera.queue_free()
	room.queue_free()
	await physics_frame
	print("CRYPT_EXIT_TEST_PASSED" if failures == 0 else "CRYPT_EXIT_TEST_FAILED")
	quit(0 if failures == 0 else 1)
