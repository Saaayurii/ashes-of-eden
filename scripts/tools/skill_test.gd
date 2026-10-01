extends SceneTree
## The active skills, headless, on a room of their own:
##   godot --headless --path . -s scripts/tools/skill_test.gd
## For each skill gift: the body gets it, an enemy stands in front, the skill
## button fires it, and the enemy is hurt (and the drain heals, the nova heals,
## the bell stops it, the hex makes it take more, the stride carries him past).

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var data_loader = root.get_node("Data")
	var room = load("res://scenes/rooms/church.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	var player = load("res://scenes/player/player.tscn").instantiate()
	room.add_child(player)
	await _settle(0.3)
	var ability_system = load("res://scripts/combat/ability_system.gd")
	for gift_id in ["radiance", "blood_lash", "ash_spear", "tolling_bell", "hex_of_ashes", "unbroken_stride"]:
		var enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
		enemy.enemy_id = "fallen_guard"
		enemy.start_aware = false
		room.add_child(enemy)
		player.global_position = Vector2(300, 360)
		player.facing = 1
		enemy.global_position = Vector2(340, 360)
		await _settle(0.4)
		ability_system.apply(player, data_loader.abilities[gift_id])
		player.hp = 50.0
		player._skill_cd = 0.0
		var before: float = enemy.hp
		_assert(player.skill_ready_ratio() >= 1.0, "%s: ready once given" % gift_id)
		Input.action_press("skill")
		await physics_frame
		await physics_frame
		Input.action_release("skill")
		await _settle(0.6)
		_assert(enemy.hp < before or enemy.is_dead(), "%s: the enemy is hurt (%.0f -> %.0f)" % [gift_id, before, enemy.hp])
		_assert(player.skill_ready_ratio() < 1.0, "%s: on cooldown after the cast" % gift_id)
		if gift_id in ["radiance", "blood_lash"]:
			_assert(player.hp > 50.0, "%s: heals (%.0f)" % [gift_id, player.hp])
		match gift_id:
			"tolling_bell":
				_assert(enemy.state == enemy.State.RECOVER or enemy.is_dead(),
					"tolling_bell: the enemy stops where it stands")
			"hex_of_ashes":
				_assert(enemy.is_hexed(), "hex_of_ashes: the enemy is hexed")
				var hexed_hp: float = enemy.hp
				enemy.take_damage(10.0, player)
				await physics_frame
				var expected: float = 15.0 * (1.0 - float(enemy.stats.get("armor", 0.0)))  # armour still takes its share
				_assert(absf((hexed_hp - enemy.hp) - expected) < 0.6 or enemy.is_dead(),
					"hex_of_ashes: a blow on it lands half again (%.1f)" % (hexed_hp - enemy.hp))
			"unbroken_stride":
				_assert(player.global_position.x > 330.0, "unbroken_stride: he is past where he stood (%.0f)" % player.global_position.x)
		enemy.queue_free()
		await _settle(0.1)
	print("SKILL TEST PASSED" if failures == 0 else "SKILL TEST FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)


func _settle(seconds: float) -> void:
	await create_timer(seconds).timeout


func _assert(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		failures += 1
