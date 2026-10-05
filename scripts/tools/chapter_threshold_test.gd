extends SceneTree
## The physical ends of painted chapter passages must not leave the player
## walking into a doorway or appearing over a gap.

const PAIRS := [
	["swamp_crypt", "catacombs_1"],
	["catacombs_3", "crypt_skulls"],
]

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for pair in PAIRS:
		await _check_marker(pair[0], "Door")
		await _check_marker(pair[1], "PlayerSpawn")
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
