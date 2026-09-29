extends SceneTree
## The special moves (docs/TECHNIQUES.md), pressed as a player presses them,
## in the practice yard against the straw man:
##   - lunge: back, forward, attack — a rush forward, harder than a swing;
##   - sweep: down + attack — a low cut that stops a walker;
##   - cleave: attack held until it glows, let go — the hardest blow there is;
##     let go too early and nothing comes of it;
##   - the yard's move list ticks each one, and only the yard has the list.
##   godot --headless --fixed-fps 60 --path . -s scripts/tools/techniques_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _tap(action: String, hold := 2) -> void:
	Input.action_press(action)
	await _frames(hold)
	Input.action_release(action)
	await _frames(1)


func _settle(seconds := 0.3) -> void:
	await create_timer(seconds, true, false, true).timeout


func _reset(hero, dummy, gap := 44.0) -> void:
	await _settle(0.5)
	hero.global_position = dummy.global_position + Vector2(-gap, -4)
	hero.velocity = Vector2.ZERO
	hero.facing = 1
	hero.hitbox.scale.x = 1
	hero._attack_cd = 0.0
	hero._combo = 0
	dummy.hp = dummy._max_hp
	await _frames(3)


func _run() -> void:
	var game = root.get_node("Game")
	game.practice = "training_dummy"
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.8)
	var run = current_scene
	run.transition.instant = true
	await _settle(0.3)
	var hero = run.player
	hero.stats.crit_chance = 0.0
	var dummy = null
	for body in get_nodes_in_group("enemies"):
		dummy = body
	_check(dummy != null and dummy.enemy_id == "training_dummy", "the yard stands a straw man up")
	var list = run.get_node_or_null("UI/MoveList")
	_check(list != null, "and lists the moves")
	var swing: float = hero.stats.attack_damage

	# lunge
	await _reset(hero, dummy, 70.0)
	await _tap("move_left")
	await _tap("move_right")
	var from_x: float = hero.global_position.x
	await _tap("attack")
	await _frames(1)
	_check(hero.body.animation == "lunge", "back, forward, attack: the lunge")
	await _frames(12)
	var dealt: float = dummy._max_hp - dummy.hp
	_check(hero.global_position.x - from_x > 45.0, "it rushes forward (%.0f px)" % (hero.global_position.x - from_x))
	_check(dealt >= swing * 1.5, "and bites harder than a swing (%.1f vs %.1f)" % [dealt, swing])
	_check(list != null and list.is_done("lunge"), "ticked on the list")

	# sweep
	await _reset(hero, dummy)
	Input.action_press("move_down")
	await _frames(2)
	await _tap("attack")
	Input.action_release("move_down")
	await _frames(4)
	_check(hero.body.animation == "sweep", "down + attack: the sweep")
	_check(dummy.hp < dummy._max_hp, "it lands on the straw man")
	_check(list != null and list.is_done("sweep"), "ticked on the list")
	var cultist = run.room.spawn_enemy("cultist", hero.global_position + Vector2(30, -4), true)
	await _frames(6)
	cultist.global_position = hero.global_position + Vector2(26, -4)
	cultist.state = cultist.State.CHASE
	hero._attack_cd = 0.0
	Input.action_press("move_down")
	await _frames(2)
	await _tap("attack")
	Input.action_release("move_down")
	await _frames(4)
	_check(cultist.state == cultist.State.RECOVER, "and takes a walker off its feet (stagger)")
	cultist.take_damage(99999.0)

	# cleave
	await _reset(hero, dummy)
	Input.action_press("attack")
	await _settle(0.4 + hero.CHARGE_AFTER)
	_check(hero._charging and hero.body.animation == "charge", "attack held past the swing: the charge")
	await _settle(hero.CHARGE_FULL + 0.1)
	_check(hero._charge_ready, "and it glows when it is ready")
	dummy.hp = dummy._max_hp
	Input.action_release("attack")
	await _frames(5)
	dealt = dummy._max_hp - dummy.hp
	_check(hero.body.animation == "cleave", "let go: the cleave")
	_check(dealt >= swing * 2.2, "the hardest blow there is (%.1f)" % dealt)
	_check(list != null and list.is_done("cleave"), "ticked on the list")

	await _reset(hero, dummy)
	Input.action_press("attack")
	await _settle(0.25 + hero.CHARGE_AFTER + 0.1)
	var early: bool = hero._charging and not hero._charge_ready
	Input.action_release("attack")
	await _frames(4)
	_check(early and hero.body.animation != "cleave" and not hero._charging, "let go too early: nothing comes of it")

	# the list only lives in the yard
	run._to_menu()
	await _settle(0.8)
	game.practice = ""
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.8)
	_check(current_scene.get_node_or_null("UI/MoveList") == null, "a night has no move list")

	print("TECHNIQUES TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	await _settle(0.2)
	quit(0 if failures == 0 else 1)
