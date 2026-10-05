extends SceneTree
## The practice yard's drills (PracticeDrills, docs/PRACTICE.md):
##   - spar is the foe the yard was opened for, the straw man from the menu;
##   - guard puts a foe that swings in place of the straw man, and a block and
##     a parry are counted;
##   - volley puts a foe that shoots;
##   - parries in a row are counted until a wound, the best run kept;
##   - stalk puts an unaware foe with its back to the hero, a backstab is
##     counted, and once it knows him it is put back unaware;
##   - only one foe ever stands, and the drill comes round to spar again.
##   godot --headless --path . -s scripts/tools/practice_drills_test.gd

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
	game.practice = "training_dummy"
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.8)
	var run = current_scene
	run.transition.instant = true
	await _settle(0.3)
	var drills = run.drills
	var hero = run.player
	_check(drills != null and drills.drill == "spar", "the yard opens on spar")
	_check(_foes().size() == 1 and _foes()[0].enemy_id == "training_dummy", "against the straw man")
	var moves = run.get_node("UI/MoveList")
	_check(moves._drill.text.contains(root.get_node("Settings").key_name("interact")), "the list names the key that changes it")

	# guard
	drills.next()
	await _settle(0.2)
	var foes := _foes()
	_check(drills.drill == "guard" and foes.size() == 1 and foes[0].enemy_id == drills.GUARD_FOE and foes[0].aware,
		"guard: the straw man gives way to a foe that swings, already fighting")
	_check(run.room.alive == 1, "the room counts one foe, not two")
	var foe = foes[0]
	hero.global_position = foe.global_position + Vector2(-30, 0)
	hero.facing = 1
	hero._blocking = true
	hero._parry_left = 0.0
	hero._hurt_grace_left = 0.0
	var hp_before: float = hero.hp
	hero.take_damage(10.0, foe)
	_check(drills.tally.blocked == 1, "a blow on the guard is counted as blocked")
	hero._parry_left = 0.2
	hero.take_damage(10.0, foe)
	_check(drills.tally.parried == 1 and drills.tally.blocked == 1, "a blow met as it lands is counted as parried")
	_check(hero.hp > hp_before - 10.0, "and neither went through whole")
	hero._parry_left = 0.2
	hero.take_damage(10.0, foe)
	_check(drills.tally.streak == 2 and drills.tally.best == 2, "two parries in a row make a run of two")
	hero._blocking = false
	hero._hurt_grace_left = 0.0
	hero.take_damage(1.0, foe)
	_check(drills.tally.streak == 0 and drills.tally.best == 2, "a wound ends the run, the best is kept")
	await _settle(0.1)
	_check(moves._tally.visible and moves._tally.text.contains("2"), "the tally is on the list")

	# volley
	drills.next()
	await _settle(0.2)
	foes = _foes()
	_check(drills.drill == "volley" and foes.size() == 1 and foes[0].enemy_id == drills.VOLLEY_FOE and foes[0].aware,
		"volley: a foe that shoots, already fighting")

	# stalk
	hero.global_position = run.room.player_spawn.global_position
	drills.next()
	await _settle(0.2)
	foes = _foes()
	_check(drills.drill == "stalk" and foes.size() == 1 and foes[0].is_unaware(), "stalk: one foe, unaware")
	foe = foes[0]
	var away: float = signf(foe.global_position.x - hero.global_position.x)
	_check(foe.facing == int(away), "with its back to the hero")
	_check(absf(foe.global_position.x - hero.global_position.x) > 300.0, "set down far from him")
	hero.global_position = foe.global_position - Vector2(away * 24.0, 8.0)
	foe._apply_damage(1.0, hero.global_position, true, false, 0.0, 2.0)  # what a sword on its back sends
	_check(drills.tally.backstab == 1, "a blow on its back is counted as a backstab")
	_check(not foe.is_unaware(), "and now it knows him")
	await _settle(drills.STALK_RESET + 0.4)
	foes = _foes()
	_check(foes.size() == 1 and foes[0] != foe and foes[0].is_unaware(), "a little later it is put back, unaware again")
	_check(run.room.alive == 1, "still one in the room's count")

	# a death in a drill: the run's respawn stands up the drill's foe, once
	foes[0].take_damage(99999.0)
	await _settle(run.PRACTICE_RESPAWN + 0.4)
	foes = _foes()
	_check(foes.size() == 1 and foes[0].is_unaware(), "downed, it stands up again for the same drill")

	drills.next()
	await _settle(0.2)
	_check(drills.drill == "spar" and _foes().size() == 1 and _foes()[0].enemy_id == "training_dummy", "and round to spar")

	game.practice = ""
	print("practice drills: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(failures)
