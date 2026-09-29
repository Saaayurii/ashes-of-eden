extends SceneTree
## Locked exits must accept a waiting hero on unlock, exactly once.

var count := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	for room_name in ["hell_gate", "village_night", "crypt_lava"]:
		var room: Node2D = load("res://scenes/rooms/%s.tscn" % room_name).instantiate()
		root.add_child(room)
		var door = room.get_node("Door")
		count = 0
		door.entered.connect(func(): count += 1)
		var hero = load("res://scenes/player/player.tscn").instantiate()
		room.add_child(hero)
		hero.controls_enabled = false
		hero.place_in_room(door.global_position + Vector2(0, 17))
		for frame in 8:
			await physics_frame
		_check(door.get_overlapping_bodies().has(hero), room_name + ": hero must overlap the locked door")
		_check(count == 0, room_name + ": locked door emitted transition")
		door.open = true
		for frame in 4:
			await physics_frame
		_check(count == 1, room_name + ": waiting hero was not accepted on unlock")
		door.open = true
		door._on_body_entered(hero)
		for frame in 4:
			await physics_frame
		_check(count == 1, room_name + ": repeated signal emitted duplicate transition")
		# A queued entry from before teleport must not trigger another room.
		door.open = false
		hero.place_in_room(room.player_spawn.global_position)
		door.open = true
		door._on_body_entered(hero)
		for frame in 4:
			await physics_frame
		_check(count == 1, room_name + ": stale entry after teleport was accepted")
		hero.place_in_room(door.global_position + Vector2(0, 17))
		for frame in 8:
			await physics_frame
		_check(count == 2, room_name + ": reopened door failed to accept a new entry")
		door.open = false
		hero.set("_dead", true)
		door.open = true
		for frame in 4:
			await physics_frame
		_check(count == 2, room_name + ": dead hero triggered the exit")
		print("DOOR_WAITING_CHECK ", room_name, " transitions=", count)
		# Finish short opening effects before freeing their target nodes.
		await create_timer(0.6).timeout
		room.queue_free()
		await physics_frame
	print("DOOR_WAITING_TEST_PASSED" if failures == 0 else "DOOR_WAITING_TEST_FAILED")
	quit(0 if failures == 0 else 1)
