extends SceneTree
## Walk the player uphill over every painted stair, without enemies or input UI.
## godot --headless --fixed-fps 60 --path . -s scripts/tools/stairs_test.gd

const ROOMS := [
	"village_night", "graveyard_cross", "graveyard_arches", "swamp_crypt",
	"catacombs_1", "catacombs_2", "catacombs_3", "crypt_skulls", "crypt_lava", "hell_gate",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	for name in ROOMS:
		var room: Node2D = load("res://scenes/rooms/%s.tscn" % name).instantiate()
		root.add_child(room)
		var ramp := room.get_node("Geometry/Ramp1") as CollisionPolygon2D
		var top_count := int(ramp.polygon.size() / 2)
		var left := ramp.polygon[0]
		var right := ramp.polygon[top_count - 1]
		var low: Vector2 = left if left.y > right.y else right
		var high: Vector2 = right if left.y > right.y else left
		var dir := signf(high.x - low.x)
		var hero: CharacterBody2D = load("res://scenes/player/player.tscn").instantiate()
		root.add_child(hero)
		hero.controls_enabled = true
		hero.global_position = low + Vector2(dir * 3.0, -15.0)
		hero.velocity = Vector2.ZERO
		for settle in 3:
			await physics_frame
		Input.action_press("move_right" if dir > 0.0 else "move_left")
		var crossed := false
		var at_crossing := hero.global_position
		for frame in 110:
			await physics_frame
			if (hero.global_position.x - low.x) * dir >= absf(high.x - low.x) * 0.75:
				crossed = true
				at_crossing = hero.global_position
				break
		Input.action_release("move_right" if dir > 0.0 else "move_left")
		var climbed: bool = crossed and at_crossing.y < low.y - 15.0 - absf(low.y - high.y) * 0.45
		if not climbed:
			failures.append(name)
			print("STAIRS_FAIL ", name, " from=", low, " to=", high, " player=", at_crossing)
		else:
			print("STAIRS_OK ", name)
		hero.queue_free()
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
