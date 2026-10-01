extends SceneTree
## A boss's best fight (Enemy.fight_time, Profile.record_boss_time):
##   - the clock starts at the first blow that lands, not before;
##   - a cutscene does not count;
##   - its fall keeps the time on its bestiary page, only if it is the best;
##   - nothing counts in the practice yard;
##   - the page shows it as m:ss.t.
## Puts the profile back as it found it.
##   godot --headless --path . -s scripts/tools/boss_time_test.gd

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


func _boss(run, at: Vector2):
	var boss = run._spawn_enemy("knight_of_ash", at, false)
	await process_frame
	boss.set_physics_process(false)
	boss.set_process(false)
	return boss


func _run() -> void:
	var game = root.get_node("Game")
	var profile = root.get_node("Profile")
	var saved: Dictionary = profile.data.duplicate(true)
	var bestiary = load("res://scripts/ui/bestiary.gd")
	game.vial = 0
	game.omen = ""

	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	run.cutscene.abort()
	game.cutscene = false
	paused = false
	var at: Vector2 = run.player.global_position + Vector2(300, -40)
	profile.data.bestiary.erase("knight_of_ash")

	var boss = await _boss(run, at)
	boss._time_fight(5.0)
	_check(boss.fight_time < 0.0, "the clock waits for the first blow")
	boss.hp -= 1.0
	boss._time_fight(0.5)
	boss._time_fight(40.0)
	game.cutscene = true
	boss._time_fight(30.0)
	game.cutscene = false
	_check(is_equal_approx(boss.fight_time, 40.0), "  then runs, a cutscene not counted (%.1f)" % boss.fight_time)
	boss._die()
	var entry: Dictionary = profile.data.bestiary.get("knight_of_ash", {})
	_check(is_equal_approx(float(entry.get("best_time", 0.0)), 40.0), "its fall keeps the time (%s)" % entry)

	_check(not profile.record_boss_time("knight_of_ash", 55.0)
		and is_equal_approx(float(profile.data.bestiary.knight_of_ash.best_time), 40.0), "a slower fight leaves the best alone")
	_check(profile.record_boss_time("knight_of_ash", 31.25)
		and is_equal_approx(float(profile.data.bestiary.knight_of_ash.best_time), 31.3), "a faster one replaces it")
	game.practice = "knight_of_ash"
	_check(not profile.record_boss_time("knight_of_ash", 5.0), "the practice yard counts nothing")
	game.practice = ""

	_check(bestiary.fight_clock(31.3) == "0:31.3" and bestiary.fight_clock(125.0) == "2:05.0", "m:ss.t (%s, %s)"
		% [bestiary.fight_clock(31.3), bestiary.fight_clock(125.0)])
	profile.data.bestiary.knight_of_ash["kills"] = 1
	var book = load("res://scenes/ui/bestiary.tscn").instantiate()
	root.add_child(book)
	book.open()
	await process_frame
	book._show("knight_of_ash")
	var shown := false
	for label in book.stats_box.get_children():
		shown = shown or (label is Label and label.text == "0:31.3")
	_check(shown, "the page shows the best fight")
	book.queue_free()

	game.new_run()
	profile.data = saved
	profile.save()
	await process_frame
	print("BOSS TIME TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
