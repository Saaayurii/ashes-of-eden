extends SceneTree
## The physical ends of painted chapter passages must not leave the player
## walking into a doorway or appearing over a gap.

const PAIRS := [
	["swamp_crypt", "catacombs_1"],
	["catacombs_3", "crypt_threshold"],
	["catacombs_2", "crypt_threshold"],
	["crypt_threshold", "crypt_skulls"],
]

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for pair in PAIRS:
		await _check_marker(pair[0], "Door")
		await _check_marker(pair[1], "PlayerSpawn")
	await _walk_passage()
	print("CHAPTER_THRESHOLD_%s" % ("OK" if failures == 0 else "FAILED"))
	quit(0 if failures == 0 else 1)


func _check_marker(room_name: String, marker_name: String) -> void:
	var room = load("res://scenes/rooms/%s.tscn" % room_name).instantiate()
	root.add_child(room)
	current_scene = room
	await physics_frame
	await physics_frame
	var marker: Node2D = room.get_node(marker_name)
	var at := marker.global_position
	var ray := PhysicsRayQueryParameters2D.create(at, at + Vector2(0, 72), 17)
	var hit: Dictionary = room.get_world_2d().direct_space_state.intersect_ray(ray)
	var supported: bool = not hit.is_empty() and float(hit.position.y) > at.y + 4.0
	if not supported:
		failures += 1
		printerr("CHAPTER_THRESHOLD_FAIL: %s/%s has no floor below %s" % [room_name, marker_name, at])
	else:
		print("  ok   %s/%s floor at %.1f" % [room_name, marker_name, hit.position.y])
	current_scene = null
	room.queue_free()
	await physics_frame


func _walk_passage() -> void:
	var room = load("res://scenes/rooms/crypt_threshold.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	var hero = load("res://scenes/player/player.tscn").instantiate()
	room.add_child(hero)
	hero.camera.enabled = false
	hero.place_in_room(room.player_spawn.global_position)
	hero.controls_enabled = true
	room.populate()
	var reached := [false]
	room.exited.connect(func() -> void: reached[0] = true)
	Input.action_press("move_right")
	for frame in 720:
		await physics_frame
		if reached[0]:
			break
		if frame > 10 and hero.global_position.x > 65.0 and not hero.is_on_floor():
			failures += 1
			printerr("CHAPTER_THRESHOLD_FAIL: hero lost the passage floor at %s" % hero.global_position)
			break
	Input.action_release("move_right")
	if not reached[0]:
		failures += 1
		printerr("CHAPTER_THRESHOLD_FAIL: hero could not walk into painted exit (at %s)" % hero.global_position)
	else:
		print("  ok   crossed the painted passage into its exit")
	current_scene = null
	room.queue_free()
	await physics_frame
