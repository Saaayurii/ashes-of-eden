extends SceneTree
## The night's numbers (Game.dealt / heaviest / taken / parries):
##   - a blow on one of the dead counts as dealt, after its armour; the
##     heaviest is kept;
##   - a blow on our body counts as taken; a parry counts;
##   - none of it in the practice yard;
##   - a save keeps them, the chronicle line and its page show them.
## Puts the profile back as it found it.
##   godot --headless --path . -s scripts/tools/numbers_test.gd

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
	var game = root.get_node("Game")
	var profile = root.get_node("Profile")
	var saves = root.get_node("Saves")
	var bus = root.get_node("EventBus")
	var saved: Dictionary = profile.data.duplicate(true)
	game.vial = 0
	game.omen = ""
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	run.cutscene.abort()
	game.cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false
	var player = run.player
	game.new_run()

	var foe = run._spawn_enemy("cultist", player.global_position + Vector2(400, -20), false)
	await process_frame
	foe.set_physics_process(false)
	var armor := float(foe.stats.get("armor", 0.0))
	foe.aware = true  # no backstab: the plain blow is what is measured
	foe.take_damage(10.0, player)
	foe.take_damage(4.0, player)
	_check(is_equal_approx(game.dealt, 14.0 * (1.0 - armor)), "blows on the dead count as dealt, after armour (%.1f)" % game.dealt)
	_check(is_equal_approx(game.heaviest, 10.0 * (1.0 - armor)), "  the heaviest is kept (%.1f)" % game.heaviest)
	player.take_damage(7.0, foe)
	_check(game.taken > 0.0 and game.taken <= 7.0, "a blow on our body counts as taken (%.1f)" % game.taken)
	bus.player_parried.emit()
	_check(game.parries == 1, "a parry counts")
	game.practice = "cultist"
	var before: float = game.dealt
	foe.take_damage(10.0, player)
	bus.player_parried.emit()
	game.practice = ""
	_check(game.dealt == before and game.parries == 1, "none of it in the practice yard")

	var checkpoint: Dictionary = saves.capture(run.ROOMS[run.room_index], 0, 0.0, player)
	var dealt: float = game.dealt
	game.new_run()
	_check(game.dealt == 0.0 and game.parries == 0, "a new night starts at nothing")
	saves.restore(checkpoint, player)
	_check(is_equal_approx(game.dealt, dealt) and game.parries == 1, "a save keeps them")

	profile.record_run(3, 4, 120.0, 0, false)
	var line: Dictionary = profile.data.history.back()
	_check(int(line.get("dealt", -1)) == roundi(dealt) and int(line.get("parries", -1)) == 1, "the chronicle line keeps them (%s)" % line)
	var book = load("res://scenes/ui/bestiary.tscn").instantiate()
	root.add_child(book)
	book.open()
	await process_frame
	book._show("chron:%d" % (profile.data.history.size() - 1))
	var texts: Array = book.stats_box.get_children().map(func(n: Node) -> String: return n.text if n is Label else "")
	_check(texts.has("CHRONICLE_DEALT") and texts.has(str(roundi(dealt))), "  and its page shows them")
	book.queue_free()

	foe.queue_free()
	game.new_run()
	profile.data = saved
	profile.save()
	await process_frame
	print("NUMBERS TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
