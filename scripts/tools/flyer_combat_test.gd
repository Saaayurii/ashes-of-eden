extends SceneTree
## Regressions: flyers must not trap bodies or accelerate from repeated push;
## up + attack must hit a target above Elian's normal horizontal sword reach.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var net = root.get_node("Net")
	var was_dedicated: bool = net.dedicated
	net.dedicated = true  # this isolated physics check must not unlock a bestiary entry
	var player = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(player)
	player.global_position = Vector2(300, 220)
	var enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	enemy.enemy_id = "shade"
	root.add_child(enemy)
	enemy.global_position = player.global_position + Vector2(0, -46)
	await physics_frame
	enemy.set_physics_process(false)
	assert((player.collision_mask & enemy.collision_layer) == 0,
		"Flyer still physically pins player")
	assert((player.hitbox.collision_mask & enemy.collision_layer) != 0,
		"Removing body collision also removed the player's sword hit")
	enemy._knockback = Vector2(190, -35)
	enemy.velocity = Vector2(500, 0)
	enemy._hold(1.0 / 60.0)
	assert(enemy.velocity == enemy._knockback, "Flyer push accumulates in recovery")
	enemy._knockback = Vector2.ZERO
	enemy.velocity = Vector2.ZERO
	var hp_before: float = enemy.hp
	player.stats.crit_chance = 0.0
	Input.action_press("move_up")
	player._attack()
	assert(player.body.animation == "rising", "Up + attack did not use rising slash")
	assert(player.hitbox_collision.position.y < -30.0, "Upward sword reach is still horizontal")
	for i in 4:
		await physics_frame
	Input.action_release("move_up")
	assert(enemy.hp < hp_before, "Upward slash did not hit the flyer above")
	assert(player.hitbox_collision.position == Vector2(24, -4), "Sword reach did not reset")
	enemy.take_damage(0.1, player, {"crit": true, "knockback": 10.0})
	assert(absf(enemy._knockback.x) <= 190.0, "Flyer can still be launched too far")
	enemy._knockback = Vector2.ZERO
	enemy.global_position = player.global_position + Vector2(-42, -46)
	enemy._fly_phase_left = 999.0
	enemy._fly_phase = 0
	enemy._chase(player.global_position - enemy.global_position, 1.0 / 60.0)
	assert(enemy.velocity.x > 0.0, "Flyer does not approach in its near phase")
	enemy._fly_phase = 1
	enemy._chase(player.global_position - enemy.global_position, 1.0 / 60.0)
	assert(enemy.velocity.x < 0.0, "Flyer does not retreat in its far phase")
	print("FLYER_COMBAT_OK")
	player.queue_free()
	enemy.queue_free()
	await process_frame
	net.dedicated = was_dedicated
	quit()
