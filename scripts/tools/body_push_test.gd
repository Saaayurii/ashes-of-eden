extends SceneTree
## A chasing walker must not move a stationary player before an attack lands.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var net = root.get_node("Net")
	var was_dedicated: bool = net.dedicated
	net.dedicated = true  # no bestiary/profile writes in this isolated test
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(600, 20)
	floor_shape.shape = rectangle
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	floor_body.global_position = Vector2(300, 250)  # top at y=240
	var player = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(player)
	player.global_position = Vector2(280, 225)
	player.controls_enabled = false
	var enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	enemy.enemy_id = "possessed_villager"
	enemy.start_aware = true
	root.add_child(enemy)
	enemy.global_position = Vector2(335, 229)
	enemy._attack_cd = 999.0  # isolate movement, not a completed attack
	for frame in 120:
		await physics_frame
	assert(absf(player.global_position.x - 280.0) < 1.0,
		"Idle enemy shoved player from x=280 to x=%.2f" % player.global_position.x)
	assert((player.hitbox.collision_mask & enemy.collision_layer) != 0,
		"Removing body collision also removed the player's sword hit")
	assert((enemy.contact_area.collision_mask & player.collision_layer) != 0,
		"Removing body collision also removed enemy attack contact")
	var hp_before: float = player.hp
	enemy._attack_cd = 0.0
	for frame in 90:
		await physics_frame
	assert(player.hp < hp_before, "Walker stopped pushing but its melee attack no longer hits")
	enemy.set_physics_process(false)
	enemy._knockback = Vector2.ZERO
	enemy.global_position = player.global_position + Vector2(28, 4)
	enemy._disengage_left = 0.6
	enemy._attack_cd = 1.0
	enemy._chase(player.global_position - enemy.global_position, 1.0 / 60.0)
	assert(enemy.velocity.x > 0.0, "Walker does not backstep during recovery")
	enemy._disengage_left = 0.0
	enemy._attack_cd = 0.1
	enemy.global_position.x = player.global_position.x + 50.0
	enemy._chase(player.global_position - enemy.global_position, 1.0 / 60.0)
	assert(enemy.velocity.x < 0.0, "Walker does not approach for the next attack")
	player.global_position = Vector2(567, 225)
	enemy.global_position = Vector2(595, 229)  # the floor ends at x=600
	enemy._disengage_left = 0.6
	enemy._attack_cd = 1.0
	enemy._chase(player.global_position - enemy.global_position, 1.0 / 60.0)
	assert(is_zero_approx(enemy.velocity.x), "Backstep walked off a ledge")
	player.global_position = Vector2(280, 225)
	var caster = load("res://scenes/enemies/enemy.tscn").instantiate()
	caster.enemy_id = "cult_caller"
	root.add_child(caster)
	caster.set_physics_process(false)
	caster.global_position = Vector2(430, 229)
	caster._disengage_left = 0.6
	caster._chase(player.global_position - caster.global_position, 1.0 / 60.0)
	assert(caster.velocity.x > 0.0, "Caster does not retreat after casting")
	caster._disengage_left = 0.0
	caster.global_position.x = 500.0
	caster._chase(player.global_position - caster.global_position, 1.0 / 60.0)
	assert(caster.velocity.x < 0.0, "Caster does not return to casting range")
	print("BODY_PUSH_OK")
	player.queue_free()
	enemy.queue_free()
	caster.queue_free()
	floor_body.queue_free()
	await process_frame
	net.dedicated = was_dedicated
	quit()
