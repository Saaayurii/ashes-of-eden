extends SceneTree
## The chapter's forks (data/forks, scripts/run/route.gd):
##   - the way splits after the crone's swamp and after the knight's niche,
##     and both ways join again at the same room;
##   - the player picks by answering the question; unanswered, the first way;
##   - a night is 15 rooms whichever way, and the numbers shown have no gaps;
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
	var rooms: Array = route.rooms()
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
	_check(route.next_index(rooms, at.call("graveyard_tree")) == at.call("swamp_moon"), "elsewhere, the next room")
	_check(route.length(rooms) == rooms.size() - 2, "a night is %d rooms whichever way" % route.length(rooms))
	_check(route.step(rooms, at.call("swamp_red")) == route.step(rooms, at.call("swamp_crypt")), "both ways have the same number")
	_check(route.step(rooms, at.call("catacombs_threshold")) == route.step(rooms, at.call("swamp_red")) + 1, "and the number after is the next one: no gap")

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
