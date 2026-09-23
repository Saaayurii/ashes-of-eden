extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _solid(at: Vector2, size: Vector2, layer: int = 1) -> void:
	var body := StaticBody2D.new()
	body.position = at
	body.collision_layer = layer
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	body.add_child(shape)
	root.add_child(body)


func _run() -> void:
	_solid(Vector2(140, 110), Vector2(80, 20), 16)
	var hero = load("res://scenes/player/player.tscn").instantiate()
	hero.position = Vector2(85, 145)
	hero.controls_enabled = false
	root.add_child(hero)
	await physics_frame
	hero.facing = 1
	assert(hero._try_mantle(), "Third-jump mantle did not find a reachable ledge")
	for i in 20:
		await physics_frame
	assert(hero.global_position.y < 100, "Mantle did not land on the platform")
	hero.queue_free()
	await physics_frame
	_solid(Vector2(160, 220), Vector2(320, 20))
	_solid(Vector2(106, 205), Vector2(18, 10))
	var stepper = load("res://scenes/player/player.tscn").instantiate()
	stepper.position = Vector2(87, 195)
	stepper.controls_enabled = false
	root.add_child(stepper)
	await physics_frame
	await physics_frame
	stepper._try_step_up(stepper.global_position, 1.0)
	assert(stepper.global_position.y < 195, "Low stone step was not traversed")
	stepper.global_position = Vector2(87, 195)
	stepper.controls_enabled = true
	Input.action_press("move_right")
	for i in 30:
		await physics_frame
	Input.action_release("move_right")
	assert(stepper.global_position.x > 110, "Running into a low step still blocks the hero")
	print("TRAVERSAL_TEST_OK")
	quit()
