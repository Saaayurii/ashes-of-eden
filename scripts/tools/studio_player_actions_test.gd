extends SceneTree
var failures := 0
func _init() -> void:
	call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("PLAYER_ACTION_FAIL: " + label)
func _run() -> void:
	var cls = load("res://scripts/player/player.gd")
	_check(cls.action_spec("cleave").multiplier == 3.0, "defaults preserve cleave strength")
	var arena := Node2D.new()
	root.add_child(arena)
	var hero = load("res://scenes/player/player.tscn").instantiate()
	arena.add_child(hero)
	hero.set_physics_process(false)
	cls.studio_actions.rising = {"animation_time":1.0,"hit_frame":1,"multiplier":2.5,"hitbox":[55,42],"offset":[20,-8],"recovery":1.7}
	hero._attack()
	hero.body.pause()
	_check(not hero.hitbox.monitoring, "paused initial frame cannot damage")
	_check(is_equal_approx(hero._attack_cd, hero.stats.attack_cooldown * 1.7), "custom recovery reaches combat")
	_check(hero.hitbox_collision.shape.size == Vector2(55,42), "custom hitbox reaches combat")
	await process_frame
	_check(not hero.hitbox.monitoring, "no timer fallback before selected frame")
	hero.body.frame = 1
	await process_frame
	_check(hero.hitbox.monitoring, "selected frame opens real damage area")
	await physics_frame
	await physics_frame
	await process_frame
	_check(not hero.hitbox.monitoring, "hit area closes after combat ticks")
	arena.queue_free()
	await process_frame
	print("STUDIO_PLAYER_ACTIONS_TEST " + ("PASSED" if failures == 0 else "FAILED"))
	quit(1 if failures else 0)
