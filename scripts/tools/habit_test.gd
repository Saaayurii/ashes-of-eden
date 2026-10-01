extends SceneTree
## The world notices (docs/CORE_LOOP.md), and the vial of wrath is greeted: nights that lean one way in a row
## become a habit the profile remembers (Profile.habit), and from the third
## Elian wakes saying so, the angel answers it, and the body carries a faint
## mark of it before the night has leaned anywhere.
##   - three clear nights on a path make a habit; two do not;
##   - a level night or another path starts the count over;
##   - the routers take the habit's line, and no line without one;
##   - the body is marked faintly by the habit, fully by the night.
## Puts the profile back as it found it (CLAUDE.md: tools share user://).
##   godot --headless --path . -s scripts/tools/habit_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _settle(seconds := 0.2) -> void:
	await create_timer(seconds, true, false, true).timeout


## The lines a caption dialogue reads out, walking its routers as the box does.
func _lines(dialogue_id: String) -> Array:
	var box = load("res://scripts/ui/dialogue_box.gd")
	var dialogue: Dictionary = root.get_node("Data").dialogues[dialogue_id]
	var out := []
	var node_id: String = dialogue.start
	while node_id != "":
		var node: Dictionary = dialogue.nodes[node_id]
		if node.has("branches"):
			node_id = node.get("next", "")
			for branch in node.branches:
				if box.branch_holds(branch):
					node_id = branch.next
					break
			continue
		out.append(node.text)
		node_id = node.get("next", "")
	return out


func _night(game, profile, lean: Dictionary) -> void:
	game.alignment = lean
	profile.record_run(3, 10, 300.0, 0, false)


func _run() -> void:
	var profile = root.get_node("Profile")
	var game = root.get_node("Game")
	var saved: Dictionary = profile.data.duplicate(true)
	var saved_alignment: Dictionary = game.alignment.duplicate()
	var grace := {"grace": 4, "temptation": 0, "will": 1}
	var temptation := {"grace": 0, "temptation": 5, "will": 1}
	var level := {"grace": 1, "temptation": 1, "will": 1}
	profile.data.habit = {"path": "", "nights": 0}

	_night(game, profile, grace)
	_night(game, profile, grace)
	_check(profile.habit() == "", "two nights of grace are not yet a habit")
	_night(game, profile, grace)
	_check(profile.habit() == "grace", "the third makes it one")
	_night(game, profile, level)
	_check(profile.habit() == "" and int(profile.data.habit.nights) == 0, "a level night starts the count over")
	for i in 3:
		_night(game, profile, temptation)
	_night(game, profile, grace)
	_check(profile.habit() == "" and profile.data.habit.path == "grace", "another path starts its own count")

	profile.data.habit = {"path": "", "nights": 0}
	_check(_lines("ch1_prologue_short") == ["DLG_CH1_PROLOGUE_1", "DLG_CH1_PROLOGUE_7"],
		"no habit: he wakes with the two lines he always had")
	for path in ["grace", "temptation", "will"]:
		profile.data.habit = {"path": path, "nights": 4}
		var woke := _lines("ch1_prologue_short")
		_check(woke.size() == 3 and woke[1] == "DLG_CH1_HABIT_ELIAN_" + path.to_upper(),
			"a habit of %s: Elian remembers it between the rope and the waking" % path)
		_check(_lines("ch1_intro").has("DLG_CH1_HABIT_ANGEL_" + path.to_upper()),
			"  and the angel answers it")

	# --- the vial of wrath is greeted too, ahead of the habit --------------------
	profile.data.habit = {"path": "will", "nights": 4}
	for tier_line in [[1, "DLG_CH1_VIAL_1"], [2, "DLG_CH1_VIAL_1"], [3, "DLG_CH1_VIAL_3"], [5, "DLG_CH1_VIAL_5"]]:
		game.vial = tier_line[0]
		var heard := _lines("ch1_intro")
		_check(heard.has(tier_line[1]) and not heard.has("DLG_CH1_HABIT_ANGEL_WILL"),
			"under vial %d the angel says %s instead" % [tier_line[0], tier_line[1]])
	game.vial = 0
	_check(_lines("ch1_intro").has("DLG_CH1_HABIT_ANGEL_WILL"), "no vial: the habit's line again")
	profile.data.habit = {"path": "", "nights": 0}

	# --- the body -------------------------------------------------------------
	var room = load("res://scenes/rooms/graveyard.tscn").instantiate()
	root.add_child(room)
	var player = load("res://scenes/player/player.tscn").instantiate()
	room.add_child(player)
	player.global_position = Vector2(300, 220)
	game.alignment = level.duplicate()
	profile.data.habit = {"path": "temptation", "nights": 3}
	await _settle(0.4)
	player._update_aura()
	var material = player.body.material
	_check(material is ShaderMaterial, "a habit binds the marks before the night leans")
	if material is ShaderMaterial:
		_check(absf(float(material.get_shader_parameter("strength")) - player.HABIT_MARK) < 0.01,
			"  faintly (%.2f)" % float(material.get_shader_parameter("strength")))
		_check(int(material.get_shader_parameter("mode")) == 1, "  with its own mark: veins for temptation")
	game.alignment = grace.duplicate()
	player._update_aura()
	_check(float(player.body.material.get_shader_parameter("strength")) > player.HABIT_MARK
			and int(player.body.material.get_shader_parameter("mode")) == 0,
		"the night's own lean takes over from the habit")
	profile.data.habit = {"path": "", "nights": 0}
	game.alignment = level.duplicate()
	player._update_aura()
	_check(float(player.body.material.get_shader_parameter("strength")) == 0.0, "no habit, no lean: no mark")
	room.queue_free()

	game.alignment = saved_alignment
	profile.data = saved
	profile.save()
	print("HABIT TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	await process_frame
	quit(0 if failures == 0 else 1)
