extends SceneTree
## Body overlap is harmless until a telegraphed lunge; melee owns its hitbox.


func _init() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	var net = root.get_node("Net")
	var was_dedicated: bool = net.dedicated
	net.dedicated = true
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(600, 20)
	floor_shape.shape = rectangle
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	floor_body.global_position = Vector2(300, 250)
	var player = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(player)
	player.global_position = Vector2(280, 225)
	player.controls_enabled = false
	player.stats.armor = 0.0
	var enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	enemy.enemy_id = "possessed_villager"
	enemy.start_aware = true
	root.add_child(enemy)
	enemy.global_position = Vector2(292, 229)
	enemy.stats.speed = 0.0
	enemy._attack_cd = 10.0
	enemy.facing = -1
	await _frames(5)
	assert(enemy.contact_area.get_overlapping_bodies().has(player), "test actors do not overlap")
	var hp_before: float = player.hp
	await _frames(30)
	assert(is_equal_approx(player.hp, hp_before), "chasing body inflicted untelegraphed touch damage")

	enemy._attack = enemy._attacks[0]
	enemy._set_state(enemy.State.WINDUP, 0.5)
	await _frames(5)
	assert(is_equal_approx(player.hp, hp_before), "wind-up inflicted touch damage before the swing")
	enemy._strike(player.global_position - enemy.global_position)
	await _frames(5)
	var melee_damage: float = float(enemy._attack.get("damage", 0.0))
	assert(absf(hp_before - player.hp - melee_damage) < 0.01,
		"melee must hit once, not add contact damage (lost %.1f, expected %.1f)" % [hp_before - player.hp, melee_damage])
	await _frames(20)
	assert(absf(hp_before - player.hp - melee_damage) < 0.01, "recovery inflicted extra touch damage")

	enemy._attack = {"type": "lunge", "damage": 7.0, "lunge_speed": 0.0}
	enemy._contact_cd = 0.0
	enemy._state_left = 0.5
	enemy._set_state(enemy.State.STRIKE, 0.5)
	await _frames(3)
	assert(absf(hp_before - player.hp - melee_damage - 7.0) < 0.01,
		"a telegraphed lunge still damages on contact")

	print("CONTACT_FAIRNESS_OK")
	player.queue_free()
	enemy.queue_free()
	floor_body.queue_free()
	await process_frame
	net.dedicated = was_dedicated
	quit()
