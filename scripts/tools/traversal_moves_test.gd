extends SceneTree
## Headless check of the two moves added in v0.2 (Player: ground slam, wall grab):
##   godot --headless -s scripts/tools/traversal_moves_test.gd
## Down in the air drops him fast and hurts what he lands on; down with no room
## below does nothing; holding into a wall slows the fall and jump pushes off
## it away from the wall. Exit code 1 on any failure.
## Deliberately untyped w.r.t. game classes, like every -s tool script.

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failed = true


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _release_all() -> void:
	for action in ["move_left", "move_right", "move_down", "jump", "attack", "dash"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)


func _run() -> void:
	var room = load("res://scenes/rooms/graveyard.tscn").instantiate()
	root.add_child(room)
	var player = load("res://scenes/player/player.tscn").instantiate()
	room.add_child(player)
	player.global_position = Vector2(300, 220)
	await _frames(40)
	var floor_y: float = player.global_position.y
	_check(player.is_on_floor(), "the body settles on the floor first")

	# --- ground slam ---
	# Put him well above it: the move needs room beneath it by design, and a
	# nudge upward is not height.
	player.global_position = Vector2(300, floor_y - 100.0)
	await _frames(2)
	var falling_before: float = player.velocity.y
	Input.action_press("move_down")
	await _frames(2)
	Input.action_release("move_down")
	await _frames(2)
	_check(player.velocity.y > falling_before + 300.0,
		"down in the air drops him far faster than gravity")

	var enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	enemy.enemy_id = "possessed_villager"
	room.add_child(enemy)
	await _frames(2)
	enemy.set_physics_process(false)  # no AI: it stands where it is put
	enemy.global_position = player.global_position + Vector2(20, 60)
	var hp_before: float = enemy.hp
	# Let him arrive.
	await _frames(90)
	_check(player.is_on_floor(), "the slam reaches the floor")
	_check(enemy.hp < hp_before, "what he lands beside is hit (%.0f -> %.0f)"
		% [hp_before, enemy.hp])
	enemy.queue_free()
	await _frames(4)

	# Standing on the floor, down is the drop-through, never a slam.
	await _frames(30)
	var y_before: float = player.velocity.y
	Input.action_press("move_down")
	await _frames(2)
	Input.action_release("move_down")
	_check(absf(player.velocity.y - y_before) < 200.0,
		"down on the ground does not start a slam")
	await _frames(10)

	# --- wall grab ---
	# A wall of the test's own, so this measures the move and not the shape of
	# whichever room it happens to run in.
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(24, 160)
	shape.shape = box
	wall.add_child(shape)
	room.add_child(wall)
	wall.global_position = Vector2(340, floor_y - 60.0)
	await _frames(4)

	player.global_position = Vector2(320, floor_y - 70.0)
	player.velocity = Vector2(0, 40)
	Input.action_press("move_right")  # hold into the wall
	await _frames(20)
	_check(player.is_on_wall(), "he reaches the wall")
	var sliding: float = player.velocity.y
	_check(sliding > 0.0 and sliding <= 90.0,
		"held into the wall he slides instead of falling (%.0f px/s)" % sliding)

	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	_check(player.velocity.x < -80.0, "the wall jump pushes away from the wall (%.0f)"
		% player.velocity.x)
	_check(player.velocity.y < -100.0, "the wall jump carries him up (%.0f)"
		% player.velocity.y)
	_release_all()

	_finish()


func _finish() -> void:
	print("TRAVERSAL MOVES TEST " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
