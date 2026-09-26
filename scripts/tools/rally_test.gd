extends SceneTree
## Counterattack recovery: capped, short-lived, and never a second potion.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var bus = root.get_node("EventBus")
	var hero = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(hero)
	await process_frame
	hero._apply_damage(20.0)
	assert(is_equal_approx(hero.hp, 80.0))
	assert(is_equal_approx(hero.recoverable_hp(), 7.0))
	hero._recover_from_strike(10.0)
	assert(is_equal_approx(hero.hp, 84.0))
	assert(is_equal_approx(hero.recoverable_hp(), 3.0))
	hero.heal(5.0)
	assert(is_equal_approx(hero.hp, 89.0))
	assert(is_zero_approx(hero.recoverable_hp()))
	hero._apply_damage(100.0)
	assert(hero.is_dead())
	assert(is_zero_approx(hero.recoverable_hp()))
	hero.revive(Vector2.ZERO)
	assert(is_zero_approx(hero.recoverable_hp()))
	hero._apply_damage(50.0)
	assert(is_equal_approx(hero.recoverable_hp(), 15.0))
	bus.room_started.emit(2)
	assert(is_zero_approx(hero.recoverable_hp()))
	hero._apply_damage(20.0)
	assert(is_equal_approx(hero.recoverable_hp(), 7.0))
	hero._tick_rally(hero.RALLY_TIME)
	assert(is_zero_approx(hero.recoverable_hp()))
	print("RALLY_OK")
	hero.queue_free()
	await process_frame
	quit()
