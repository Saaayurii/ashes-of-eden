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
	var rooms: Array = route.rooms().duplicate()  # Data.rooms itself changes with the night
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
	_check(_node(nodes, "catacombs_threshold").state == "ahead", "the room after this one is always shown")
	_check(_node(nodes, "hell_gate").state == "unknown", "past the furthest night, the way is unknown")
	nodes = map_script.layout(rooms, walked, at.call("swamp_crypt"), 15, at.call("catacombs_2"))
	_check(_node(nodes, "catacombs_2").fell and not _node(nodes, "catacombs_1").fell,
		"the room where last night's body lies is marked")

	_check(_node(nodes, "seir_road").is_empty(), "the first night's map ends at its own last room")

	# a later night (game.json "nights") maps its own way, from its own first room
	root.get_node("Data").use_night("seir")
	var seir: Array = route.rooms()
	nodes = map_script.layout(seir, [at.call("seir_road")], at.call("seir_road"), 0)
	columns = {}
	for node in nodes:
		columns[int(node.step)] = true
	_check(columns.size() == route.length(seir) and _node(nodes, "hell_gate").is_empty(),
		"Seir's map is Seir's rooms alone (%d columns)" % columns.size())
	_check(_node(nodes, "seir_road").step == 0 and _node(nodes, "seir_road").state == "here", "and starts at its road")
	_check(_node(nodes, "seir_gate").state == "ahead" and _node(nodes, "seir_square").state == "unknown",
		"its own furthest room, not the first night's, hides what is past it")

	# every night of the campaign: a column per step, every room once and in a
	# place, a fork's ways side by side, somewhere to rest on the way
	for night in root.get_node("Data").nights():
		var id := str(night.id)
		root.get_node("Data").use_night(id)
		var way: Array = route.rooms()
		nodes = map_script.layout(way, [], str(way[0]), 99)
		columns = {}
		var unplaced: Array = []
		var rests := 0
		for node in nodes:
			columns[int(node.step)] = true
			if str(node.place) == "":
				unplaced.append(str(node.path).get_file().get_basename())
			if node.rest:
				rests += 1
		var label := id if id != "" else "first"
		_check(nodes.size() == way.size() and columns.size() == route.length(way), "%s: %d rooms in %d columns" % [label, nodes.size(), columns.size()])
		_check(unplaced.is_empty(), "%s: every room is in a place %s" % [label, unplaced])
		_check(rests > 0, "%s: a rest point on the way (%d)" % [label, rests])
		var forked := nodes.filter(func(n) -> bool: return n.row != 0.0)
		_check(forked.all(func(n) -> bool: return forked.any(func(m) -> bool: return m.step == n.step and m.row == -n.row)),
			"%s: each fork's ways share a column (%d rooms on forks)" % [label, forked.size()])
	root.get_node("Data").use_night("")

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

	# --- which chapter a night starts in: asked on Play only after a dawn -----
	var profile = root.get_node("Profile")
	var wins_were = profile.data.get("wins", 0)
	profile.data.wins = 0  # in memory only: nothing here saves the profile
	_check(route.open_nights().size() == 1, "before any dawn only the first night is open")
	var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await _settle(0.2)
	profile.data.wins = 1
	var open: Array = route.open_nights()
	_check(open.size() == 2 and str(open[1].id) == "seir", "a dawn opens Seir's night")
	menu._open_night_pick(open)
	await process_frame
	var pick = menu.get_node("NightPick")
	var buttons: Array = pick.find_children("Night_*", "Button", true, false)
	_check(pick.visible and buttons.size() == 2, "Play asks which chapter (%d)" % buttons.size())
	_check(buttons[1].text != "" and buttons[1].text != buttons[0].text, "each by its chapter's name (%s)" % buttons[1].text)
	menu._close_night_pick()
	_check(not pick.visible, "and Back leaves the question")
	profile.data.wins = wins_were
	menu.queue_free()
	await _settle(0.2)
	print("MAP TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
