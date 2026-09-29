extends SceneTree
## The new foothold must actually hold, warn, give way, and come back.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var platform = load("res://scripts/rooms/crumbling_platform.gd").new()
	platform.walk_width = 72.0
	root.add_child(platform)
	var player := CharacterBody2D.new()
	player.collision_layer = 2
	player.collision_mask = 16
	player.add_to_group("player")
	var body := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(14, 30)
	body.shape = rect
	player.add_child(body)
	player.position = Vector2(36, -17)
	root.add_child(player)
	var stood := false
	var warned := false
	var vanished := false
	var returned := false
	for frame in 360:
		await physics_frame
		player.velocity.y = 1100.0 / 60.0 if player.is_on_floor() else player.velocity.y + 1100.0 / 60.0
		player.move_and_slide()
		if player.is_on_floor():
			stood = true
		if platform._remaining >= 0.0:
			warned = true
		if platform._rebuild >= 0.0:
			vanished = true
		if vanished and platform._rebuild < 0.0 and not platform._shape.disabled:
			returned = true
			break
	var ok := stood and warned and vanished and returned
	print("CRUMBLING PLATFORM TEST %s" % ("PASSED" if ok else "FAILED"))
	quit(0 if ok else 1)
