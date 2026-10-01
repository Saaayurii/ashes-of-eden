extends SceneTree
## The chronicle (Profile.data.history, the bestiary's last section):
##   - every finished night leaves a line: where it ended, how it leaned, what it carried;
##   - only the last Profile.HISTORY nights are kept;
##   - the bestiary lists the totals and those nights, newest first, and a
##     night's page names its gifts and resonances;
##   - a gift that no longer exists is left out, not shown as an id.
## Puts the profile back as it found it.
##   godot --headless --path . -s scripts/tools/chronicle_test.gd

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
	var profile = root.get_node("Profile")
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	var saved: Dictionary = profile.data.duplicate(true)
	profile.data.history = []
	profile.data.nights = 0

	game.new_run()
	game.alignment = {"grace": 5, "temptation": 0, "will": 1}
	game.abilities.append(data.abilities["mending_light"])
	game.abilities.append(data.abilities["blood_pact"])
	game.resonances.append("chorus")
	profile.record_run(7, 31, 754.0, 0, false)
	var line: Dictionary = profile.data.history.back()
	_check(int(line.night) == 1 and int(line.area) == 7 and not line.won, "a night leaves its line: where it ended")
	_check(line.path == "grace" and int(line.kills) == 31 and int(line.seconds) == 754, "  how it leaned, what it laid to rest, how long")
	_check(line.gifts == ["mending_light", "blood_pact"] and line.resonances == ["chorus"], "  what it carried")
	line.gifts.append("a_gift_that_was_removed")

	game.alignment = {"grace": 0, "temptation": 0, "will": 0}
	for i in 11:
		profile.record_run(3, 5, 200.0, 0, i == 10)
	_check(profile.data.history.size() == profile.HISTORY, "only the last %d nights are kept" % profile.HISTORY)
	_check(int(profile.data.history.back().night) == 12 and profile.data.history.back().won, "the newest last, a dawn remembered")
	_check(profile.data.history.back().path == "", "a level night leaned nowhere")

	var book = load("res://scenes/ui/bestiary.tscn").instantiate()
	root.add_child(book)
	book.open()
	await process_frame
	_check(book.list.get_node_or_null("chron_total") != null, "the bestiary has the chronicle")
	var newest = book.list.get_node_or_null("chron_%d" % (profile.HISTORY - 1))
	var oldest = book.list.get_node_or_null("chron_0")
	_check(newest != null and oldest != null and newest.get_index() < oldest.get_index(), "newest first")
	_check(newest.text.contains("12") and newest.text.contains(tr("CHRONICLE_DAWN")), "a night is named by its number and its end")
	book._show("chron:total")
	var shown := []
	for child in book.stats_box.get_children():
		shown.append(child.text)
	_check(shown.has("12"), "the totals count the nights")

	profile.data.history[0] = line
	book._show("chron:0")
	_check(book.lore_label.text.contains(tr(data.abilities["mending_light"].name))
			and book.lore_label.text.contains(tr(data.resonances["chorus"].name)), "a night's page names its gifts and resonances")
	_check(not book.lore_label.text.contains("a_gift_that_was_removed"), "a gift that is gone is left out")
	book.queue_free()

	game.new_run()
	profile.data = saved
	profile.save()
	await process_frame
	print("CHRONICLE TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
