extends SceneTree
## The chapter map (scripts/ui/chapter_map.gd), from the pause menu:
##   - one column per room along the way, a fork's two ways in one column;
##   - the way walked, where we stand, the way not taken, the rooms ahead;
##   - places past the furthest any night has reached stay unnamed;
##   - rest points are marked;
##   - the way walked is kept in a save and comes back with it;
##   - the pause menu opens it and gets the focus back when it closes.
##   godot --headless --path . -s scripts/tools/map_test.gd

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


func _node(nodes: Array, name: String) -> Dictionary:
	for node in nodes:
		if str(node.path).get_file().get_basename() == name:
			return node
	return {}


func _run() -> void:
	var route = load("res://scripts/run/route.gd")
	var map_script = load("res://scripts/ui/chapter_map.gd")
	var rooms: Array = route.rooms()
	var at := func(name: String) -> String: return "res://scenes/rooms/%s.tscn" % name
	var walked := ["village_night", "graveyard_cross", "graveyard_arches", "graveyard_tree", "swamp_moon", "swamp_crypt"].map(at)

	var nodes: Array = map_script.layout(rooms, walked, at.call("swamp_crypt"), 15)
	var columns := {}
	for node in nodes:
		columns[int(node.step)] = true
	_check(columns.size() == route.length(rooms), "a column for every room along the way (%d)" % columns.size())
	var red := _node(nodes, "swamp_red")
	var crypt := _node(nodes, "swamp_crypt")
	_check(red.step == crypt.step and red.row != crypt.row, "a fork's two ways share a column, one above the other")
	_check(crypt.state == "here", "where we stand")
	_check(red.state == "passed", "the way not taken")
	_check(_node(nodes, "graveyard_arches").state == "walked", "the way walked")
	_check(_node(nodes, "catacombs_1").state == "ahead", "the rooms ahead, known from earlier nights")
	_check(_node(nodes, "graveyard_tree").rest and not _node(nodes, "graveyard_arches").rest, "a rest point is marked")
	_check(_node(nodes, "catacombs_2").state == "ahead" and _node(nodes, "catacombs_3").state == "ahead",
		"a fork not reached yet shows both ways")

	nodes = map_script.layout(rooms, walked, at.call("swamp_crypt"), 3)
	_check(_node(nodes, "catacombs_1").state == "ahead", "the room after this one is always shown")
	_check(_node(nodes, "hell_gate").state == "unknown", "past the furthest night, the way is unknown")

	# --- kept in a save, and opened from the pause menu -----------------------
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.8)
	var run = current_scene
	run.transition.instant = true
	run._load_room(rooms.find(at.call("graveyard_arches")))
	await _settle(0.4)
	run.cutscene.abort()
	root.get_node("Game").cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	var game = root.get_node("Game")
	_check(game.walked.has(at.call("graveyard_arches")), "entering a room adds it to the way walked")
	var saves = root.get_node("Saves")
	var snapshot: Dictionary = saves.capture(at.call("graveyard_arches"), 0, 10.0, run.player)
	var before: Array = game.walked.duplicate()
	game.walked.clear()
	saves.restore(snapshot, run.player)
	_check(game.walked == before, "the way walked comes back with a save")

	var pause = run.get_node("UI/PauseMenu")
	pause._open()
	var button = pause.get_node("%OpenMap")
	_check(button != null, "the pause menu has a map")
	button.pressed.emit()
	await process_frame
	_check(pause.chapter_map.visible and not pause.panel.visible, "it opens over the paused night")
	pause.chapter_map.close()
	await process_frame
	_check(pause.panel.visible and button.has_focus(), "and gives the menu back")
	pause._resume()

	current_scene = null
	run.queue_free()
	await _settle(0.2)
	print("MAP TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
