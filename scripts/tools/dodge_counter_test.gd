extends SceneTree
## A roll only earns one short-lived counter from a real enemy hit, and the
## bonus belongs to the first sword blow that reaches a living enemy.

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		_failed = true


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	var room = load("res://scenes/rooms/graveyard.tscn").instantiate()
	root.add_child(room)
	var player = load("res://scenes/player/player.tscn").instantiate()
	room.add_child(player)
	player.global_position = Vector2(300, 300)
	var enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	enemy.enemy_id = "fallen_guard"
	room.add_child(enemy)
	enemy.global_position = Vector2(326, 300)
	await _frames(10)
	enemy.set_physics_process(false)
	player.stats.crit_chance = 0.0
	player.stats.backstab_multiplier = 1.0
	player.stats.execute = 0.0
	player.stats.lifesteal = 0.0
	player._combo = 0

	var hp_before: float = player.hp
	player._roll()
	player.take_damage(10.0, room)
	_check(player._dodge_counter_left <= 0.0, "scenery cannot charge a counter")
	player.take_damage(10.0, enemy)
	_check(is_equal_approx(player.hp, hp_before), "the roll still avoids damage")
	_check(player._dodge_counter_left > 0.0, "enemy blow charges the counter")
	var first_charge: float = player._dodge_counter_left
	player.take_damage(10.0, enemy)
	_check(is_equal_approx(player._dodge_counter_left, first_charge), "one charge per roll")

	player._dash_left = 0.0
	player.velocity = Vector2.ZERO
	player.facing = 1
	player.body.flip_h = false
	player._attack_cd = 0.0
	var enemy_hp: float = enemy.hp
	player._attack()
	await _frames(4)
	var expected: float = player.stats.attack_damage * player.COMBO_MULTIPLIERS[0] \
			* (1.0 + player.DODGE_COUNTER_BONUS) * (1.0 - float(enemy.stats.get("armor", 0.0)))
	_check(absf(enemy_hp - enemy.hp - expected) < 0.1, "first sword hit receives the bonus")
	_check(player._dodge_counter_left <= 0.0, "a sword hit spends the charge")

	player._roll()
	player.take_damage(10.0, enemy)
	player._dash_left = 0.0
	player._dodge_counter_left = 0.001
	await _frames(2)
	_check(player._dodge_counter_left <= 0.0, "unused counter expires")
	player._roll()
	player.take_damage(10.0, enemy)
	player.revive(player.global_position)
	_check(player._dodge_counter_left <= 0.0 and not player._dodge_counted, "revive clears the counter")

	room.queue_free()
	await _frames(2)
	print("DODGE_COUNTER_%s" % ("FAILED" if _failed else "OK"))
	quit(1 if _failed else 0)
