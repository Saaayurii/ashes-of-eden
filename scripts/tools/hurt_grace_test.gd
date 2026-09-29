extends SceneTree
## Simultaneous combat hits are one wound, but hazards and blocked chip retain
## their own rules. Run with --headless --script res://scripts/tools/hurt_grace_test.gd.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var player = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(player)
	player.controls_enabled = false
	player.stats.armor = 0.0
	var attacker := Node2D.new()
	root.add_child(attacker)
	attacker.position = player.position + Vector2(24, 0)
	var hazard = load("res://scripts/rooms/hazard.gd").new()
	hazard.position = Vector2(1000, 1000)
	root.add_child(hazard)
	await physics_frame
	var hp_before: float = player.hp
	player.take_damage(10.0, attacker)
	player.take_damage(20.0, attacker)
	assert(is_equal_approx(player.hp, hp_before - 10.0), "overlapping combat hits stack in one reaction")
	assert(player._hurt_grace_left > 0.0, "a real wound did not start the grace period")
	player.take_damage(5.0, hazard)
	player.take_damage(3.0)
	assert(is_equal_approx(player.hp, hp_before - 18.0), "grace made hazards or scripted damage harmless")
	await create_timer(player.HURT_GRACE_TIME + 0.05).timeout
	player.take_damage(10.0, attacker)
	assert(is_equal_approx(player.hp, hp_before - 28.0), "combat damage did not resume after grace")

	player.revive(player.global_position)
	player.controls_enabled = false
	assert(player._hurt_grace_left <= 0.0, "revive retained stale invulnerability")
	attacker.position = player.position + Vector2(24, 0)
	player.facing = 1
	player._raise_block(false)
	player._parry_left = 0.0
	hp_before = player.hp
	player.take_damage(10.0, attacker)
	player.take_damage(10.0, attacker)
	assert(absf(hp_before - player.hp - 7.0) < 0.01, "block chip incorrectly granted wound grace")
	assert(player._hurt_grace_left <= 0.0)
	player._lower_block()
	player.take_damage(10.0, attacker)
	player._go_down()
	assert(player._hurt_grace_left <= 0.0, "death retained stale grace")
	player.revive(player.global_position)
	player.controls_enabled = false
	hp_before = player.hp
	# On a client the host's projectile may be gone before its hit RPC arrives.
	player._net_damage(10.0, player.position.x + 24.0, NodePath("/root/expired_projectile"))
	player._net_damage(20.0, player.position.x + 24.0, NodePath("/root/expired_projectile"))
	assert(is_equal_approx(player.hp, hp_before - 10.0), "expired network projectile bypassed combat grace")

	print("HURT_GRACE_OK")
	player.queue_free()
	attacker.queue_free()
	hazard.queue_free()
	await process_frame
	quit()
