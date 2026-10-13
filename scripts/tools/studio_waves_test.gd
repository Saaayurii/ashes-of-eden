extends SceneTree
var failures := 0
var spawned: Array = []
var cleared_count := 0
func _init() -> void:
	call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("WAVE_FAIL: " + label)
func _spawn(id: String, at: Vector2, aware: bool):
	spawned.append([id, at, aware])
	return null
func _run() -> void:
	var room = load("res://scenes/rooms/graveyard_cross.tscn").instantiate()
	root.add_child(room)
	room.spawn_hook = _spawn
	room.waves_json = '[[["cultist",200,300]],[["possessed_villager",300,300],["cultist",400,300]]]'
	room.cleared.connect(func(): cleared_count += 1)
	room.populate()
	var first: int = room.alive
	_check(first > 0 and room._wave_index == 0, "original placements precede waves")
	for i in first: room._on_enemy_died(&"cultist", Vector2.ZERO)
	_check(room.alive == 1 and room._wave_index == 1 and not room.door.open, "first reinforcement keeps door closed")
	_check(spawned[-1][2] and spawned[-1][1] == room.global_position + Vector2(200,300), "reinforcement positions and awareness")
	room._on_enemy_died(&"cultist", Vector2.ZERO)
	_check(room.alive == 2 and room._wave_index == 2 and cleared_count == 0, "next wave follows prior deaths")
	room._on_enemy_died(&"cultist", Vector2.ZERO)
	room._on_enemy_died(&"cultist", Vector2.ZERO)
	_check(room.door.open and cleared_count == 1, "last wave opens door and rewards once")
	room.authoritative = false
	room.alive = 1
	room._on_enemy_died(&"cultist", Vector2.ZERO)
	_check(room.alive == 1, "watching peer cannot advance waves")
	room.queue_free()
	await process_frame
	print("STUDIO_WAVES_TEST " + ("PASSED" if failures == 0 else "FAILED"))
	quit(1 if failures else 0)
