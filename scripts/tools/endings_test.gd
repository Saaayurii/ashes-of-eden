extends SceneTree
## How the campaign ends (data/endings, scripts/run/endings.gd):
##   - the chooser reads the hidden counters and the flags: a clear lead picks
##     its path's ending, the fourth only a level night that heard all three
##     versions and read the book, and anything else falls back to man;
##   - Endings.seed lays a night each ending accepts, `--ending=` is parsed;
##   - the finale is the Heavenly Hall's gate and ends the campaign (E4); every
##     other night's dawn is "to be continued"; its scene closes on an epilogue
##     line for every answer the campaign keeps, and the cherub does not fall;
##   - the fourth wants the register read as well (chapter VII);
##   - each ending plays end to end in the run: its scene, the dawn, its line
##     on the night's end, a page in the book, a line in the chronicle, its deed.
##     The first plays through; the others are skipped like a player would.
## Puts the profile back as it found it.
##   godot --headless --path . -s scripts/tools/endings_test.gd

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


func _night(game, alignment: Dictionary, flags: Array) -> void:
	game.new_run()
	for path in alignment:
		game.alignment[path] = alignment[path]
	for flag in flags:
		game.flags[flag] = true


func _run() -> void:
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	var profile = root.get_node("Profile")
	var endings = load("res://scripts/run/endings.gd")
	var end_screen = load("res://scripts/ui/end_screen.gd")
	var achievements = load("res://scripts/meta/achievements.gd")
	var saved: Dictionary = profile.data.duplicate(true)
	var all_versions := ["version_heaven", "version_abyss", "version_man", "book_read", "register_read"]

	print("chooser")
	_check(endings.ids() == ["fourth", "heaven", "abyss", "man"], "endings are tried in order: %s" % [endings.ids()])
	for id in endings.ids():
		game.new_run()
		endings.seed(id)
		_check(endings.choose() == id, "a night seeded for %s ends in it (got %s)" % [id, endings.choose()])
	_night(game, {"grace": 4, "temptation": 1, "will": 1}, [])
	_check(endings.choose() == "heaven", "grace ahead by 3: heaven")
	_night(game, {"grace": 1, "temptation": 5, "will": 2}, [])
	_check(endings.choose() == "abyss", "temptation ahead by 3: abyss")
	_night(game, {"grace": 1, "temptation": 1, "will": 4}, [])
	_check(endings.choose() == "man", "will ahead by 3: man")
	_night(game, {"grace": 3, "temptation": 2, "will": 0}, [])
	_check(endings.choose() == "man", "a lead of 1 claims nothing: the fallback, man")
	_night(game, {"grace": 2, "temptation": 2, "will": 2}, all_versions)
	_check(endings.choose() == "fourth", "level, three versions heard and the book read: the fourth")
	_night(game, {"grace": 2, "temptation": 2, "will": 3}, all_versions)
	_check(endings.choose() == "fourth", "  a lead of 1 is still level")
	_night(game, {"grace": 2, "temptation": 2, "will": 2}, ["version_heaven", "version_abyss", "version_man", "book_read"])
	_check(endings.choose() == "man", "  three versions and the book, the register unread: not the fourth")
	_night(game, {"grace": 2, "temptation": 2, "will": 2}, ["version_heaven", "version_abyss", "version_man", "register_read"])
	_check(endings.choose() == "man", "  the versions without the book: not the fourth")
	_night(game, {"grace": 2, "temptation": 2, "will": 2}, ["version_heaven", "version_man", "book_read"])
	_check(endings.choose() == "man", "  two versions of three: not the fourth")
	_night(game, {"grace": 5, "temptation": 1, "will": 1}, all_versions)
	_check(endings.choose() == "heaven", "  everything heard but leaning hard: the lean wins")
	game.new_run()
	_check(endings.choose() == "man", "a fresh night, nothing leaned, nothing heard: man")

	print("finale")
	var finale: Dictionary = endings.finale()
	var gate := str(finale.get("room", ""))
	_check(gate != "" and data.cutscenes.has(str(finale.get("cutscene", ""))), "game.json names the finale room and its scene")
	_check(gate == "res://scenes/rooms/hall_eden_gate.tscn", "the finale is the gate of Eden (%s)" % gate)
	_check(data.night_of(gate) == "hall", "  in the Heavenly Hall's night")
	_check(finale.get("ends_campaign", false), "  and it ends the campaign")
	_check(endings.closes_campaign(gate), "  so its door leads to an ending, not the dawn")
	_check(not endings.closes_campaign("res://scenes/rooms/hell_gate.tscn"), "chapter I's gate leads to the dawn")
	_check(not endings.closes_campaign("res://scenes/rooms/church.tscn", "fourth"), "  and only from the finale's room")
	_check(endings.from_args(PackedStringArray(["room=3", "--ending=abyss"])) == "abyss", "--ending=abyss is read")
	_check(endings.from_args(PackedStringArray(["--ending=paradise"])) == "", "  an ending that does not exist is not")
	game.ending = ""
	game.new_run()
	_check(end_screen.ending_title("") == "", "no ending, no ending title")

	print("the epilogue")
	var steps: Array = data.cutscenes[str(finale.cutscene)].get("steps", [])
	var told := {}
	for step in steps:
		if str(step.get("do", "")) == "dialogue" and step.has("if"):
			told[str(step["if"])] = true
	# CAMPAIGN.md §7: a line for every answer of Lazarus, the watchman, Malchus,
	# Marah, Tyre's light, Tirzah, the pit, the four, the witnesses, Mara,
	# Matthew and Enoch
	for group in [["lazarus_helped", "lazarus_asked", "lazarus_passed"],
			["watchman_sent_down", "watchman_relieved", "watchman_dark"],
			["prisoner_cut", "malchus_asked", "malchus_hanged"], ["marah_sweetened", "marah_bitter"],
			["wormwood_drunk"], ["light_returned", "light_shared", "light_taken"], ["tirzah_herbs"],
			["pit_locked", "key_thrown", "key_kept"], ["angels_kept_bound", "angels_loosed", "angels_left_to_men"],
			["witnesses_covered", "witnesses_asked", "witnesses_robbed"], ["mara_saved"],
			["matthew_confessed", "matthew_judged", "matthew_released"],
			["enoch_wrote_names", "enoch_struck", "enoch_left"]]:
		var missing: Array = group.filter(func(flag): return not told.has(flag))
		_check(missing.is_empty(), "an epilogue line for each of %s%s" % [group, "" if missing.is_empty() else " — missing %s" % [missing]])
	var slain := false
	for step in steps:
		if str(step.get("who", "")) == "boss" and str(step.get("do", "")) in ["vanish", "anim"] and str(step.get("anim", "")) in ["", "death"]:
			slain = true
	_check(not slain, "the cherub lowers its sword: it does not die in the finale")

	print("pictures")
	var life = load("res://scripts/rooms/backdrop_life.gd")
	for id in endings.ids():
		var scene := str(endings.spec(id).get("cutscene", ""))
		for step in data.cutscenes[scene].get("steps", []):
			if str(step.get("do", "")) == "panel":
				var key := str(step.image).get_file().get_basename()
				_check(not life.rule(key).is_empty(), "%s: the picture %s has a rule" % [id, key])

	print("another night's dawn")
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	game.night = "seir"
	game.new_run()
	game.ending = ""
	current_scene.cutscene.abort()
	current_scene.run_end.show_result(true, 12, 30, 600.0)
	_check(game.ending == "" and current_scene.run_end.line.text.ends_with(TranslationServer.translate("RUN_TO_BE_CONTINUED")),
		"seir's dawn: no ending, the road goes on (%s)" % current_scene.run_end.line.text.get_slice("\n", 1))
	game.night = "hall"
	data.use_night("hall")

	print("each ending, end to end")
	for id in endings.ids():
		await _play(id, id == endings.ids()[0], game, profile, endings, end_screen, achievements)

	print("the book")
	paused = false
	unload_current_scene()
	await _settle(0.3)
	profile.data.bestiary.erase("ending:man")
	var book = load("res://scenes/ui/bestiary.tscn").instantiate()
	root.add_child(book)
	book.open()
	await process_frame
	var reached = book.list.get_node_or_null("ending_fourth")
	var unreached = book.list.get_node_or_null("ending_man")
	_check(reached != null and reached.text.contains(TranslationServer.translate("ENDING_FOURTH")),
		"the bestiary names an ending once reached")
	_check(unreached != null and not unreached.text.contains(TranslationServer.translate("ENDING_MAN")),
		"  and keeps the others a question")
	book._show("ending:fourth")
	_check(book.lore_label.text.contains(TranslationServer.translate("ENDING_FOURTH_DESC")), "  its page tells it")
	book._show("ending:man")
	_check(book.hint_label.text == TranslationServer.translate("ENDING_HINT"), "  an unreached one gives a hint")
	book.queue_free()

	game.night = ""
	data.use_night("")
	profile.data = saved
	profile.save()
	_check(profile.data == saved, "the profile is put back")
	print("endings_test: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


func _play(id: String, through: bool, game, profile, endings, end_screen, achievements) -> void:
	profile.data.bestiary.erase("ending:" + id)
	profile.data.achievements = profile.data.get("achievements", {})
	if profile.data.achievements is Dictionary:
		profile.data.achievements.erase("ending_" + id)
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	run.cutscene.abort()
	game.new_run()
	endings.seed(id)
	var gate: int = run.ROOMS.find(str(endings.finale().get("room", "")))
	await run._go_to_room(gate)
	await _settle(0.3)
	run.cutscene.abort()
	await _settle(0.2)
	for node in get_nodes_in_group("enemies"):
		node.set_physics_process(false)
		node.set_process(false)
	var scene := str(endings.spec(id).get("cutscene", ""))
	run._close_campaign(id)
	await _settle(0.2)
	_check(run.cutscene.playing == scene, "%s: its scene plays (%s)" % [id, run.cutscene.playing])
	var waited := 0.0
	if not through:
		run.cutscene._skip()
	while run.cutscene.playing != "" and waited < 60.0:
		await _settle(0.25)
		waited += 0.25
		if run.dialogue.visible and not through:
			run.dialogue.call("_on_skip")
	_check(run.cutscene.playing == "", "%s: the scene ends%s (%.1f s)" % [id, " on its own" if through else " when skipped", waited])
	waited = 0.0
	while not run.run_end.visible and waited < 10.0:
		await _settle(0.25)
		waited += 0.25
	_check(run.run_end.visible, "%s: the dawn comes up on it" % id)
	_check(game.ending == id, "%s: Game.ending is %s" % [id, game.ending])
	_check(run.run_end.title.text == end_screen.ending_title(id), "%s: the title names it (%s)" % [id, run.run_end.title.text])
	_check(run.run_end.line.text == str(endings.spec(id).get("line", "")), "%s: its own line under it" % id)
	var page: Dictionary = profile.data.bestiary.get("ending:" + id, {})
	_check(int(page.get("times", 0)) == 1 and page.get("met", false), "%s: a page in the book, reached once" % id)
	_check(profile.endings_seen().has(id), "%s: counted among the endings seen" % id)
	var last: Dictionary = profile.data.history.back() if not profile.data.history.is_empty() else {}
	_check(str(last.get("ending", "")) == id and last.get("won", false), "%s: the chronicle's line names it" % id)
	_check(achievements.done("ending_" + id), "%s: its deed is done" % id)
	root.get_node("Net").set_paused(false)
	paused = false
