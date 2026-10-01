extends SceneTree
## The night of the day (scripts/run/daily.gd):
##   - a day has one seed and one vial, the same for every player;
##   - the gift cards are dealt from the seed: the same deal for the same day;
##   - no relics, every gift in the pool, no autosave;
##   - a dawn in it opens no vial; the day's best is kept by its own rule;
##   - the main menu offers it beside Play; the end screen says how it stands.
## Puts the profile back as it found it.
##   godot --headless --path . -s scripts/tools/daily_test.gd

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


func _run() -> void:
	var daily = load("res://scripts/run/daily.gd")
	var profile = root.get_node("Profile")
	var game = root.get_node("Game")
	var saved: Dictionary = profile.data.duplicate(true)
	var day := "2026-10-01"

	_check(RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$").search(daily.today()) != null, "today is a date, YYYY-MM-DD")
	_check(daily.seed_of(day) == daily.seed_of(day) and daily.seed_of(day) != daily.seed_of("2026-10-02"), "a day has its own seed")
	_check(daily.VIALS.has(daily.vial_of(day)), "and one of the lower vials")

	profile.data.daily = {}
	_check(daily.record(day, 5, 600.0, false), "the first try is the day's best")
	_check(not daily.record(day, 4, 300.0, false), "a shorter way is not")
	_check(daily.record(day, 5, 500.0, false), "as far, sooner is")
	_check(daily.record(day, 5, 900.0, true), "as far, a dawn beats a death")
	_check(daily.record(day, 9, 900.0, false), "further is better")
	_check(int(daily.best(day).tries) == 5 and daily.best("2026-09-30").is_empty(), "every try counted, the day's alone")

	# the streak: days in a row, a second try changes nothing, a gap starts again
	profile.data.daily_streak = {}
	profile.data.deeds = {}
	profile.data.achievements = {}
	_check(daily.day_before("2026-03-01") == "2026-02-28" and daily.day_before("2026-01-01") == "2025-12-31",
		"the day before crosses months and years")
	for d in ["2026-04-01", "2026-04-01", "2026-04-02", "2026-04-03"]:
		daily.record(d, 3, 300.0, false)
	_check(int(daily.streak().days) == 3, "three days in a row, two tries on one (%s)" % daily.streak())
	_check(daily.streak_days("2026-04-04") == 3 and daily.streak_days("2026-04-05") == 0, "  it holds through the next day, a missed one ends it")
	daily.record("2026-04-06", 3, 300.0, false)
	_check(int(daily.streak().days) == 1 and int(daily.streak().best) == 3, "a gap starts again at one, the best kept")
	for i in 7:
		daily.record("2026-05-%02d" % (i + 1), 3, 300.0, false)
	_check(profile.data.achievements.has("daily_week"), "seven days in a row are A Week of Nights")

	profile.data.relics = {"whetstone": true}
	profile.data.nights = 0
	profile.data.vials_opened = 0
	game.daily = day
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.8)
	var run = current_scene
	run.transition.instant = true
	run._load_room(1)
	await _settle(0.4)
	run.cutscene.abort()
	game.cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	_check(game.vial == daily.vial_of(day), "the night pours the day's vial, opened or not")
	_check(run.player.stats.attack_damage == run.player.BASE_STATS.attack_damage, "no relics: everyone starts the same")
	_check(not run.gift_locked(root.get_node("Data").abilities["executioner"]), "every gift is in the pool")
	_check(run.checkpoint.is_empty(), "no autosave to try a room twice")
	run._gift_rng.seed = daily.seed_of(day)
	var first: Array = run._roll_gifts().map(func(a: Dictionary) -> String: return a.id)
	run._gift_rng.seed = daily.seed_of(day)
	var again: Array = run._roll_gifts().map(func(a: Dictionary) -> String: return a.id)
	_check(first == again and first.size() == 3, "the same deal for the same day: %s" % ", ".join(first))
	_check(not run.get_node("UI/PauseMenu").find_child("SaveRow", true, false).visible, "the pause menu offers no save")

	profile.record_run(15, 40, 1400.0, 0, true)
	_check(int(profile.data.vials_opened) == 0, "a dawn in it opens no vial")
	var end = run.get_node("UI/RunEnd")
	game.daily_best = true
	end.show_result(true, 15, 40, 1400.0)
	_check(end.best.text.contains(tr("DAILY_NEW_BEST")), "the end screen says it is the day's best")
	end.visible = false

	current_scene = null
	run.queue_free()
	await _settle(0.2)
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await _settle(0.8)
	var menu = current_scene
	_check(game.daily == "", "the main menu ends the night of the day")
	var button = menu.find_child("PlayDaily", true, false)
	_check(button != null and button.get_parent().name == "PlayRow", "and offers it beside Play")

	profile.data = saved
	profile.save()
	current_scene = null
	menu.queue_free()
	await _settle(0.2)
	print("DAILY TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
