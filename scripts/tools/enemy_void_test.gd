extends SceneTree
## Enemies lost below or beside a room must die through the same signal as a
## sword kill, or Room.alive leaves the exit chained forever.
## godot --headless --path . -s scripts/tools/enemy_void_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("ENEMY_VOID_FAIL: " + label)


func _run() -> void:
	for room_name in ["graveyard_tree", "crypt_skulls"]:
		var room = load("res://scenes/rooms/%s.tscn" % room_name).instantiate()
		root.add_child(room)
		current_scene = room
		var walker = room.spawn_enemy("possessed_villager", Vector2(600, 390))
		var flyer = room.spawn_enemy("shade", Vector2(700, 300))
		await physics_frame
		_check(room.alive == 2 and not room.door.open, "%s starts with a locked exit" % room_name)
		var bottom: float = room.void_kill_y if room.void_kill_y >= 0.0 else float(room.height) + 24.0
		walker.global_position = room.to_global(Vector2(600, bottom + 4.0))
		await physics_frame
		await physics_frame
		_check(walker.is_dead() and room.alive == 1 and not room.door.open,
			"%s falling walker decrements the room once" % room_name)
		flyer.global_position = room.to_global(Vector2(float(room.width) + 100.0, 300.0))
		await physics_frame
		await physics_frame
		_check(flyer.is_dead() and room.alive == 0 and room.door.open,
			"%s lost flyer opens the exit" % room_name)
		current_scene = null
		room.queue_free()
		await process_frame
	print("ENEMY_VOID_TEST %s" % ("PASSED" if failures == 0 else "FAILED"))
	quit(0 if failures == 0 else 1)
