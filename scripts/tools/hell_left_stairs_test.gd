extends SceneTree
## Both landings of the hand-traced hell stair must be walkable without jumping.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var room: Node2D = load("res://scenes/rooms/hell_gate.tscn").instantiate()
	root.add_child(room)
	var hero: CharacterBody2D = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(hero)
	hero.controls_enabled = true
	var failures := 0
	for pair in [["LeftReturnShape", "LeftReturnCornice"], ["LeftReturnLowerShape", "LeftReturnLowerCornice"]]:
		var shape := room.get_node("Ledges/" + pair[0]) as CollisionShape2D
		var art := room.get_node("Terrain/" + pair[1]) as Sprite2D
		var rect := Rect2(shape.position - shape.shape.size / 2.0, shape.shape.size)
		var art_width := art.region_rect.size.x * art.scale.x
		if not shape.one_way_collision or rect.position != art.position or absf(rect.size.x - art_width) > 0.01:
			failures += 1
			push_error("Hell return cornice art and collision differ: " + pair[0])
	for uphill in [true, false]:
		hero.global_position = Vector2(385, 224) if uphill else Vector2(250, 161)
		hero.velocity = Vector2.ZERO
		for settle in 4:
			await physics_frame
		var action := "move_left" if uphill else "move_right"
		Input.action_press(action)
		var passed := false
		for frame in 100:
			await physics_frame
			if (uphill and hero.position.x < 260.0) or (not uphill and hero.position.x > 385.0):
				passed = true
				break
		Input.action_release(action)
		for settle in 8:
			await physics_frame
		var expected_y := 161.0 if uphill else 224.0
		passed = passed and absf(hero.position.y - expected_y) < 2.0 and hero.is_on_floor()
		print("HELL_STAIR_", "OK" if passed else "FAIL", " uphill=", uphill, " hero=", hero.position)
		if not passed:
			failures += 1
	hero.queue_free()
	room.queue_free()
	await physics_frame
	quit(0 if failures == 0 else 1)
