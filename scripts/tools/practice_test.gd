extends SceneTree
## The practice yard (docs/PRACTICE.md), from the Run's side:
##   - Game.practice opens the yard, not the chapter, and nothing is saved;
##   - the foe stands there already fighting and stands up again when downed;
##   - nothing counts: no essence, no Ash, no bestiary, no profile;
##   - the hero cannot lose, he gets up at the gate;
##   - the straw man takes any blow and never falls;
##   - the pause menu's way out clears the practice.
##   godot --headless --path . -s scripts/tools/practice_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _settle(seconds := 0.3) -> void:
	await create_timer(seconds, true, false, true).timeout


func _foes() -> Array:
	return get_nodes_in_group("enemies").filter(func(e) -> bool: return not e.is_dead())


func _run() -> void:
	var game = root.get_node("Game")
	var profile = root.get_node("Profile")
	var saves = root.get_node("Saves")
	var before_book: Dictionary = profile.data.bestiary.duplicate(true)

	game.practice = "cultist"
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.8)
	var run = current_scene
	run.transition.instant = true
	await _settle(0.3)
	_check(run.room != null and run.room.scene_file_path.ends_with("practice_yard.tscn"), "the yard opens, not the chapter")
	_check(run.room_index == run.PRACTICE_INDEX, "as the practice room")
	_check(run.checkpoint.is_empty(), "and nothing is saved")
	var foes := _foes()
	_check(foes.size() == 1 and foes[0].enemy_id == "cultist" and foes[0].aware, "one cultist, already fighting")
	_check(not run.room.door.visible, "the yard's door is no way out")

	var essence: float = game.essence
	var ash: int = game.ash_earned
	foes[0].take_damage(99999.0)
	await _settle(0.2)
	_check(game.essence == essence and game.ash_earned == ash, "a practice kill pays nothing")
	_check(profile.data.bestiary == before_book, "and writes nothing in the book")
	await _settle(run.PRACTICE_RESPAWN + 0.4)
	_check(_foes().size() == 1, "it stands up again")

	var hero = run.player
	_check(hero.global_position.distance_to(run.room.player_spawn.global_position) < 40.0,
		"the hero starts the yard at its gate, on screen (%s, gate %s)" % [hero.global_position, run.room.player_spawn.global_position])
	hero.global_position.x += 200.0
	hero._hurt_grace_left = 0.0
	hero.take_damage(99999.0)
	await _settle(1.4)
	_check(not hero.is_dead() and hero.hp == hero.stats.max_hp, "the hero cannot lose: up again, whole")
	_check(not run._finished, "and the night does not end")
	_check(abs(hero.global_position.x - run.room.player_spawn.global_position.x) < 4.0, "at the gate")
	_check(game.enemy_hp_multiplier() == root.get_node("Settings").difficulty_hp(), "the clock hardens nobody in practice")

	# the straw man
	for body in _foes():
		body.queue_free()
	await _settle(0.1)
	var dummy = run.room.spawn_enemy("training_dummy", run.room.player_spawn.global_position + Vector2(60, 0), true)
	await _settle(0.2)
	dummy.take_damage(5000.0)
	await _settle(0.1)
	_check(not dummy.is_dead() and dummy.hp >= 1.0, "the straw man takes any blow and stands")
	await _settle(2.3)
	_check(dummy.hp == dummy._max_hp, "and is whole again when left alone")
	_check(not root.get_node("Data").enemies.training_dummy.get("bestiary", true), "and is not in the bestiary")

	run._to_menu()
	_check(game.practice == "", "leaving clears the practice")
	print("PRACTICE TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	await _settle(0.3)
	quit(0 if failures == 0 else 1)
