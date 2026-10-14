extends SceneTree
## How the campaign ends (data/endings, scripts/run/endings.gd):
##   - the chooser reads the hidden counters and the flags: a clear lead picks
##     its path's ending, the fourth only a level night that heard all three
##     versions and read the book, and anything else falls back to man;
##   - Endings.seed lays a night each ending accepts, `--ending=` is parsed;
##   - the finale ends the campaign only when game.json says so, or when forced;
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
	var all_versions := ["version_heaven", "version_abyss", "version_man", "book_read"]

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
	_night(game, {"grace": 2, "temptation": 2, "will": 2}, ["version_heaven", "version_abyss", "version_man"])
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
	_check(not finale.get("ends_campaign", true), "chapter I does not end the campaign yet (to be continued)")
	_check(not endings.closes_campaign(gate), "  so its door leads to the dawn, not an ending")
	_check(endings.closes_campaign(gate, "fourth"), "  unless an ending is asked for")
	_check(not endings.closes_campaign("res://scenes/rooms/church.tscn", "fourth"), "  and only from the finale's room")
	_check(endings.from_args(PackedStringArray(["room=3", "--ending=abyss"])) == "abyss", "--ending=abyss is read")
	_check(endings.from_args(PackedStringArray(["--ending=paradise"])) == "", "  an ending that does not exist is not")
	game.ending = ""
	game.new_run()
	_check(end_screen.ending_title("") == "", "no ending, no ending title")

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
