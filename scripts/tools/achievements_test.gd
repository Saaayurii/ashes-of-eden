extends SceneTree
## Deeds (data/achievements, scripts/meta/achievements.gd):
##   - each kind of condition is read from the profile and done when it holds;
##   - a deed is done once and pays its Ash once;
##   - the counters count parries, backstabs, ripostes, clean rooms, rests,
##     and a dawn by the path the night leaned to and by the difficulty;
##   - nothing counts in the practice yard;
##   - a deed done is announced, and the bestiary lists every deed.
## Puts the profile back as it found it (CLAUDE.md: tools share user://).
##   godot --headless --path . -s scripts/tools/achievements_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _run() -> void:
	var deeds = load("res://scripts/meta/achievements.gd")
	var profile = root.get_node("Profile")
	var game = root.get_node("Game")
	var settings = root.get_node("Settings")
	var bus = root.get_node("EventBus")
	var saved: Dictionary = profile.data.duplicate(true)
	var saved_difficulty: String = settings.difficulty
	var heard := []
	bus.achievement_unlocked.connect(func(id: String) -> void: heard.append(id))

	for key in ["nights", "wins", "total_kills", "ash"]:
		profile.data[key] = 0
	for key in ["bestiary", "moves_done", "deeds", "achievements"]:
		profile.data[key] = {}
	game.practice = ""
	_check(profile.check_achievements().is_empty(), "a fresh profile has done nothing")

	profile.record_run(3, 5, 60.0, 0, false)
	_check(deeds.done("first_night") and heard.has("first_night"), "a night lived through: the first deed, announced")
	_check(int(profile.data.ash) == int(deeds.spec("first_night").ash), "its Ash is paid")
	var ash: int = profile.data.ash
	profile.check_achievements()
	_check(int(profile.data.ash) == ash and heard.count("first_night") == 1, "and paid once")
	_check(not deeds.done("dawn"), "a death is no dawn")

	game.alignment = {"grace": 5, "temptation": 1, "will": 0}
	settings.difficulty = "judgment"
	profile.record_run(15, 60, 1500.0, 0, true)
	_check(deeds.done("dawn") and deeds.done("path_grace"), "a dawn, leaning to grace")
	_check(not deeds.done("path_will") and not deeds.done("path_temptation"), "and not the other paths")
	_check(deeds.done("judgment"), "a dawn on Judgment")
	settings.difficulty = saved_difficulty

	_check(deeds.progress("parries") == [0, 50], "progress reads the counter")
	for i in 50:
		bus.player_parried.emit()
	_check(deeds.done("parries"), "fifty parries counted from the body's own signal")
	for i in 25:
		bus.technique_performed.emit("backstab")
	_check(deeds.done("backstabs") and not deeds.done("ripostes"), "backstabs counted, ripostes apart")

	game.practice = "training_dummy"
	for i in 5:
		bus.player_rested.emit("res://scenes/rooms/church.tscn")
	bus.enemy_died.emit(&"ophanim", Vector2.ZERO)
	_check(not deeds.done("rested") and not deeds.done("ophanim"), "nothing counts in the practice yard")
	game.practice = ""
	for i in 5:
		bus.player_rested.emit("res://scenes/rooms/church.tscn")
	_check(deeds.done("rested"), "five rests at an altar")
	bus.enemy_died.emit(&"ophanim", Vector2.ZERO)
	_check(deeds.done("ophanim"), "the Ophanim put down")

	for id in root.get_node("Data").techniques:
		profile.data.moves_done[id] = true
	profile.check_achievements()
	_check(deeds.done("every_move"), "every move the sword knows")
	_check(not deeds.done("bestiary") and deeds.progress("bestiary")[0] == 1, "the book: one kind known of all")

	var toast = load("res://scripts/ui/deed_toast.gd").new()
	root.add_child(toast)
	toast.announce("dawn")
	_check(toast.text.contains(tr(deeds.spec("dawn").name)), "the toast names the deed")
	toast.queue_free()

	var book = load("res://scenes/ui/bestiary.tscn").instantiate()
	root.add_child(book)
	book.open()
	var listed = book.list.get_node_or_null("deed_dawn")
	_check(listed != null and listed.text.contains(tr(deeds.spec("dawn").name)), "the bestiary lists the deeds by name")
	var locked = book.list.get_node_or_null("deed_unscathed")
	_check(locked != null and locked.text.contains(tr(deeds.spec("unscathed").name)), "an undone deed shows its name too: a goal, not a secret")
	book._show("deed:unscathed")
	var shown := []
	for child in book.stats_box.get_children():
		shown.append(child.text)
	_check(shown.has("0 / 30"), "its page says how far along")
	book.queue_free()

	profile.data = saved
	profile.save()
	print("ACHIEVEMENTS TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	await process_frame
	quit(0 if failures == 0 else 1)
