extends SceneTree
## Headless check of the block (Player._apply_damage, Enemy.parried):
##   godot --headless -s scripts/tools/parry_test.gd
## A fresh press parries (no damage, the swing's owner left open, the next blow
## a riposte), a held block cuts a blow to a third, a blow from behind ignores
## the blade, mashing gives no window, a bolt turns round, and finally a real
## guard's swing is parried on its telegraph. Exit code 1 on any failure.
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

func _run() -> void:
	var room = load("res://scenes/rooms/graveyard.tscn").instantiate()
	root.add_child(room)
	var player = load("res://scenes/player/player.tscn").instantiate()
	room.add_child(player)
	player.global_position = Vector2(300, 300)
	var enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	enemy.enemy_id = "fallen_guard"
	room.add_child(enemy)
	enemy.global_position = Vector2(330, 300)
	await _frames(10)
	enemy.set_physics_process(false)  # no AI: the test decides when blows land

	# 1. a fresh press parries
	Input.action_press("block")
	await _frames(2)
	_check(player.is_blocking(), "block raised by the button")
	_check(player.body.animation == "guard", "guard pose playing (%s)" % player.body.animation)
	var hp0: float = player.hp
	player.take_damage(20.0, enemy)
	_check(is_equal_approx(player.hp, hp0), "parry takes nothing (%.1f -> %.1f)" % [hp0, player.hp])
	_check(enemy._open_left > 0.0 and enemy.state == 5, "parried enemy is open (state %d, open %.2f)" % [enemy.state, enemy._open_left])

	# 2. the riposte is worth half as much again
	Input.action_release("block")
	await _frames(2)
	var ehp: float = enemy.hp
	enemy.take_damage(10.0, player)
	var expected := 10.0 * 1.5 * (1.0 - float(enemy.stats.get("armor", 0.0)))
	_check(absf((ehp - enemy.hp) - expected) < 0.01, "riposte x1.5 (%.2f, expected %.2f)" % [ehp - enemy.hp, expected])
	ehp = enemy.hp
	enemy.take_damage(10.0, player)
	_check(absf((ehp - enemy.hp) - 10.0 * (1.0 - float(enemy.stats.get("armor", 0.0)))) < 0.01, "only one riposte per parry")

	# 3. a held block only cuts the blow
	await _frames(30)  # past the recovery
	Input.action_press("block")
	await create_timer(0.4).timeout  # past the parry window
	hp0 = player.hp
	player.take_damage(20.0, enemy)
	_check(absf((hp0 - player.hp) - 7.0) < 0.01, "held block takes 35%% (%.2f)" % (hp0 - player.hp))

	# 4. a blow from behind ignores the blade
	var behind = load("res://scenes/enemies/enemy.tscn").instantiate()
	behind.enemy_id = "cultist"
	room.add_child(behind)
	behind.global_position = Vector2(260, 300)
	await _frames(2)
	behind.set_physics_process(false)
	hp0 = player.hp
	player.take_damage(20.0, behind)
	_check(absf((hp0 - player.hp) - 20.0) < 0.01, "a blow from behind lands whole (%.2f)" % (hp0 - player.hp))
	_check(player.facing == -1 and player.body.flip_h, "hit reaction faces the attacker")
	player.facing = 1  # the remaining parry cases deliberately attack from the right
	player.body.flip_h = false
	player._turn_lock_left = 0.0
	Input.action_release("block")

	# 5. a held button after a release is not a parry (no mashing)
	Input.action_press("block")
	await _frames(1)
	_check(player._parry_left == 0.0, "re-press inside the recovery gives no parry window")
	Input.action_release("block")

	# 6. a parried bolt turns round and belongs to the player
	await create_timer(0.5).timeout
	Input.action_press("block")
	await _frames(1)
	hp0 = player.hp
	var bolt = load("res://scenes/fx/projectile.tscn").instantiate()
	bolt.direction = Vector2.LEFT
	bolt.speed = 170.0
	bolt.damage = 10.0
	room.add_child(bolt)
	bolt.global_position = player.global_position + Vector2(24, -6)
	await _frames(20)
	_check(is_instance_valid(bolt) and bolt.friendly and bolt.direction.x > 0.0, "bolt reflected")
	_check(is_equal_approx(player.hp, hp0), "reflected bolt did no harm")
	Input.action_release("block")

	# 7. the button path: attack out of a block drops it (riposte input)
	Input.action_press("block")
	await _frames(2)
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	Input.action_release("block")
	_check(not player.is_blocking(), "attack drops the block")

	# 8. the real thing: a guard's own swing, parried on its telegraph
	await create_timer(0.5).timeout
	var guard = load("res://scenes/enemies/enemy.tscn").instantiate()
	guard.enemy_id = "fallen_guard"
	room.add_child(guard)
	guard.global_position = player.global_position + Vector2(34, 0)
	enemy.queue_free()
	behind.queue_free()
	player.heal(1000.0)
	hp0 = player.hp
	var pressed := false
	var parried := false
	for i in 400:
		await physics_frame
		if not pressed and guard.state == 3 and guard._state_left < 0.12:  # WINDUP, about to land
			Input.action_press("block")
			pressed = true
		if pressed and guard._open_left > 0.0:
			parried = true
			break
	Input.action_release("block")
	_check(pressed, "the guard wound up a swing")
	_check(parried, "its swing was parried on the telegraph")
	_check(is_equal_approx(player.hp, hp0), "and nothing landed (%.1f -> %.1f)" % [hp0, player.hp])

	# block by toggling (Settings.block_toggle): a press raises the guard with a
	# parry in it, it stays up once let go, the next press lowers it
	var settings = root.get_node("Settings")
	var was_toggle: bool = settings.block_toggle
	guard.set_physics_process(false)
	settings.set_block_toggle(true)
	await _frames(40)  # past the last block's recovery
	Input.action_press("block")
	await _frames(2)
	Input.action_release("block")
	var parry_ready: bool = player._parry_left > 0.0
	await _frames(10)
	_check(player.is_blocking() and parry_ready, "toggled: a press raises the guard with a parry in it, and it stays up")
	Input.action_press("block")
	await _frames(2)
	Input.action_release("block")
	await _frames(1)
	_check(not player.is_blocking(), "  the next press lowers it")
	settings.set_block_toggle(was_toggle)
	_check(settings.block_toggle == was_toggle, "  the setting put back as it was")

	print("PARRY TEST %s" % ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
