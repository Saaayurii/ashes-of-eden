extends SceneTree
## The chapter's forks (data/forks, scripts/run/route.gd):
##   - the way splits after the crone's swamp and after the knight's niche,
##     and both ways join again at the same room;
##   - the player picks by answering the question; unanswered, the first way;
##   - a night skips one room per way not taken, and the numbers shown have no gaps;
##   - a door out of either way is a door out of the place: the gift is there;
##   - a save in a way the night took resumes on that way.
##   godot --headless --path . -s scripts/tools/fork_test.gd

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


func _path(name: String) -> String:
	return "res://scenes/rooms/%s.tscn" % name


## Rooms a night skips: one per way not taken, at the forks inside its rooms.
func _skipped(rooms: Array) -> int:
	var skipped := 0
	for fork in root.get_node("Data").forks.values():
		if rooms.has(str(fork.after)):
			skipped += fork.options.size() - 1
	return skipped


func _answer(run, choice_index: int) -> void:
	# wait for the question, then pick as a player would
	for i in 120:
		await process_frame
		if run.dialogue.visible:
			break
	await _settle(0.2)
	run.dialogue.answer_remote(choice_index)


func _run() -> void:
	var route = load("res://scripts/run/route.gd")
	var rooms: Array = route.rooms().duplicate()  # Data.rooms itself changes with the night
	var at := func(name: String) -> int: return rooms.find(_path(name))

	# the arithmetic
	_check(route.next_index(rooms, at.call("swamp_moon"), "red") == at.call("swamp_red"), "swamp: red is one way")
	_check(route.next_index(rooms, at.call("swamp_moon"), "crypt") == at.call("swamp_crypt"), "swamp: the crypt is the other")
	_check(route.next_index(rooms, at.call("swamp_moon")) == at.call("swamp_red"), "unanswered: the first way")
	_check(route.next_index(rooms, at.call("swamp_red")) == at.call("catacombs_threshold")
		and route.next_index(rooms, at.call("swamp_crypt")) == at.call("catacombs_threshold")
		and route.next_index(rooms, at.call("catacombs_threshold")) == at.call("catacombs_1"),
		"both pass the marsh causeway before the catacombs")
	_check(route.next_index(rooms, at.call("catacombs_2")) == at.call("crypt_threshold")
		and route.next_index(rooms, at.call("catacombs_3")) == at.call("crypt_threshold")
		and route.next_index(rooms, at.call("crypt_threshold")) == at.call("crypt_skulls"),
		"both galleries cross the same threshold before the skull crypt")
	_check(route.next_index(rooms, at.call("graveyard_tree")) == at.call("swamp_threshold")
		and route.next_index(rooms, at.call("swamp_threshold")) == at.call("swamp_moon"),
		"the cemetery leads through the marsh passage")
	_check(route.next_index(rooms, at.call("church")) == at.call("ashes_threshold")
		and route.next_index(rooms, at.call("ashes_threshold")) == at.call("crypt_lava"),
		"the church leads through the ash passage")
	_check(route.length(rooms) == rooms.size() - _skipped(rooms), "a night is %d rooms whichever way" % route.length(rooms))
	_check(route.step(rooms, at.call("swamp_red")) == route.step(rooms, at.call("swamp_crypt")), "both ways have the same number")
	_check(route.step(rooms, at.call("catacombs_threshold")) == route.step(rooms, at.call("swamp_red")) + 1, "and the number after is the next one: no gap")

	# a later night (game.json "nights") has its own forks, and the first night's
	# arithmetic does not see them, nor they its
	var data = root.get_node("Data")
	data.use_night("seir")
	var seir: Array = route.rooms()
	var on := func(name: String) -> int: return seir.find(_path(name))
	_check(not seir.has(_path("hell_gate")) and not rooms.has(_path("seir_road")), "the two nights share no room")
	_check(route.next_index(seir, on.call("seir_square"), "canal") == on.call("seir_canal")
		and route.next_index(seir, on.call("seir_roofs")) == on.call("seir_quay")
		and route.next_index(seir, on.call("seir_canal")) == on.call("seir_quay"),
		"Seir's square: the roofs or the canal, both to the quay")
	_check(route.length(seir) == seir.size() - _skipped(seir), "Seir's night is %d rooms whichever way" % route.length(seir))
	_check(route.step(seir, on.call("seir_quay")) == route.step(seir, on.call("seir_roofs")) + 1, "and counted from its own first room")
	data.use_night("")

	# the Run
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.6)
	var run = current_scene
	run.transition.instant = true
	run._load_room(at.call("swamp_moon"))
	await _settle(0.4)
	run.cutscene.abort()
	root.get_node("Game").cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	await _settle(0.2)
	_answer(run, 1)
	var picked: int = await run._next_room()
	_check(picked == at.call("swamp_crypt"), "asked at the door, the crypt picked")
	run._load_room(picked)
	await _settle(0.4)
	_check(run.room.scene_file_path == _path("swamp_crypt"), "and walked into")
	_check(run._door_grants_gift(), "its door leaves the swamp: the gift is there")
	var hud = run.get_node("UI/HUD")
	var shown: String = hud.wave_label.text
	_check(shown.contains(str(route.step(rooms, at.call("swamp_crypt")) + 1)), "the HUD counts the way walked (%s)" % shown)
	var saved: Dictionary = root.get_node("Saves").capture(_path("swamp_crypt"), 0, 0.0, run.player)
	_check(int(saved.room_number) == route.step(rooms, at.call("swamp_crypt")) + 1, "and so does a save")
	_check(route.next_index(rooms, root.get_node("Saves").room_index(saved.room)) == at.call("catacombs_threshold"),
		"a save on this way resumes on it")
	picked = await run._next_room()
	_check(picked == at.call("catacombs_threshold"), "out of the crypt: the causeway, no question")

	print("FORK TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	current_scene = null
	run.queue_free()
	await _settle(0.2)
	quit(0 if failures == 0 else 1)
