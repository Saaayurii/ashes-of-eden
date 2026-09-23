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
	print("VOID FALL TEST %s" % ("PASSED" if passed else "FAILED"))
	current_scene = null
	room.queue_free()
	await process_frame
	quit(0 if passed else 1)
