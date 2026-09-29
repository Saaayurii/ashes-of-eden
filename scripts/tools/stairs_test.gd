extends SceneTree
## Walk every painted stair of every room of the run, up and back down,
## on foot — no jump — without enemies or input UI. A stair you can climb
## but not come back down (or the reverse) turns a room into a one-way trip.
## godot --headless --fixed-fps 60 --path . -s scripts/tools/stairs_test.gd


func _init() -> void:
	call_deferred("_run")


## Walks from one end of the stair toward the other; the position where the
## body stood when it got there, or null when it never did.
func _walk(hero: CharacterBody2D, from: Vector2, to: Vector2) -> Variant:
	var dir := signf(to.x - from.x)
	hero.place_in_room(from + Vector2(dir * 4.0, -16.0))
	for settle in 12:
		await physics_frame
	var action := "move_right" if dir > 0.0 else "move_left"
	Input.action_press(action)
	var arrived: Variant = null
	for frame in 240:
		await physics_frame
		# over the last tread (some stairs end at a wall or a drop, not a landing)
		if (hero.global_position.x - from.x) * dir >= absf(to.x - from.x) - 8.0 and hero.is_on_floor():
			arrived = hero.global_position
			break
	Input.action_release(action)
	if arrived == null:
		print("       stopped at ", hero.global_position, " on the floor: ", hero.is_on_floor())
	for settle in 4:
		await physics_frame
	return arrived


func _run() -> void:
	var failures: Array[String] = []
	var rooms: Array = load("res://scripts/run/run.gd").get_script_constant_map()["ROOMS"]
	for path in rooms:
		var name: String = path.get_file().get_basename()
		var room: Node2D = load(path).instantiate()
		root.add_child(room)
		current_scene = room
		var hero: CharacterBody2D = load("res://scenes/player/player.tscn").instantiate()
		room.add_child(hero)
		await physics_frame
		hero.controls_enabled = true
		for ramp in room.get_node("Geometry").get_children():
			if not ramp is CollisionPolygon2D:
				continue
			var top_count := int(ramp.polygon.size() / 2)
			var left: Vector2 = ramp.to_global(ramp.polygon[0])
			var right: Vector2 = ramp.to_global(ramp.polygon[top_count - 1])
			var low: Vector2 = left if left.y > right.y else right
			var high: Vector2 = right if left.y > right.y else left
			var label := "%s/%s" % [name, ramp.name]
			var up: Variant = await _walk(hero, low, high)
			# on the far landing: most of the stair's height away from where it
			# started (a landing may sit a tread off the stair's last point)
			var drop := absf(low.y - high.y)
			var climbed: bool = up != null and up.y + 15.0 < low.y - drop * 0.6
			var down: Variant = await _walk(hero, high, low) if climbed else null
			var descended: bool = down != null and down.y + 15.0 > high.y + drop * 0.6
			if climbed and descended:
				print("STAIRS_OK ", label)
			else:
				failures.append(label)
				print("STAIRS_FAIL ", label, " low=", low, " high=", high, " up=", up, " down=", down)
		current_scene = null
		room.queue_free()
		await physics_frame
	# The old test started on the stair itself. The reported failure was at its
	# landings, so cross the whole first-room stair from both adjacent floors.
	var village: Node2D = load("res://scenes/rooms/village_night.tscn").instantiate()
	root.add_child(village)
	var walker: CharacterBody2D = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(walker)
	walker.controls_enabled = true
	walker.global_position = Vector2(330, 512)
	for settle in 3:
		await physics_frame
	Input.action_press("move_left")
	for frame in 160:
		await physics_frame
	Input.action_release("move_left")
	if walker.global_position.x > 190.0 or walker.global_position.y > 420.0:
		failures.append("village_night lower stair landing")
		print("STAIRS_FAIL lower landing player=", walker.global_position)
	else:
		print("STAIRS_OK village_night lower landing")
	walker.global_position = Vector2(168, 405)
	walker.velocity = Vector2.ZERO
	for settle in 3:
		await physics_frame
	Input.action_press("move_right")
	for frame in 160:
		await physics_frame
	Input.action_release("move_right")
	if walker.global_position.x < 310.0 or walker.global_position.y < 495.0:
		failures.append("village_night upper stair landing")
		print("STAIRS_FAIL upper landing player=", walker.global_position)
	else:
		print("STAIRS_OK village_night upper landing")
	walker.queue_free()
	village.queue_free()
	await physics_frame
	print("STAIRS_TEST_PASSED" if failures.is_empty() else "STAIRS_TEST_FAILED " + str(failures))
	quit(0 if failures.is_empty() else 1)
