extends SceneTree
## The blood altar (data/props/blood_altar, Run._on_blood_offered):
##   - it stands in the rooms the tables put it in, and opens only by hand;
##   - opened, it deals a hand of gifts under its price;
##   - a gift taken costs that share of the bar for the night, and counts;
##   - the hand turned down withdraws: nothing taken, nothing paid.
## Puts the profile back as it found it.
##   godot --headless --path . -s scripts/tools/blood_altar_test.gd

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


func _altar(run):
	for prop in run.room.find_children("*", "", true, false):
		if prop.get("prop_id") == "blood_altar":
			return prop
	return null


func _run() -> void:
	var game = root.get_node("Game")
	var profile = root.get_node("Profile")
	var saved: Dictionary = profile.data.duplicate(true)
	game.vial = 0
	game.omen = ""
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	var player = run.player
	for room_name in ["graveyard_tree", "crypt_skulls"]:
		run._load_room(run.ROOMS.find("res://scenes/rooms/%s.tscn" % room_name))
		await _settle(0.3)
		_check(_altar(run) != null, "%s has a blood altar" % room_name)
	run._load_room(run.ROOMS.find("res://scenes/rooms/graveyard_tree.tscn"))
	await _settle(0.4)
	run.cutscene.abort()
	game.cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false
	for node in get_nodes_in_group("enemies"):
		node.set_physics_process(false)
		node.set_process(false)
	var altar = _altar(run)
	if altar == null:
		_finish(saved)
		return
	_check(altar.is_in_group("interactable"), "it opens only by hand (a prompt over it)")

	# taken: the price is paid
	profile.data.deeds = {}
	var max_before: float = player.stats.max_hp
	var gifts_before: int = game.abilities.size()
	altar.open(player)
	for i in 20:
		if run.picker.visible:
			break
		await process_frame
	var title = run.picker.get_node("Center/VBox/Title")
	_check(run.picker.visible and title.text.contains("15"), "it deals a hand under its price (%s)" % title.text)
	run.picker.cards.get_child(0).pressed.emit()
	await process_frame
	await process_frame
	_check(game.abilities.size() == gifts_before + 1, "a gift taken is the body's")
	_check(is_equal_approx(player.stats.max_hp, max_before * 0.85), "  and costs a share of the bar (%.1f of %.1f)" % [player.stats.max_hp, max_before])
	_check(int(profile.data.deeds.get("blood_paid", 0)) == 1, "  counted")
	_check(title.text == "PICKER_TITLE" or not run.picker.visible, "the next hand has its own heading again")

	# turned down: nothing taken, nothing paid
	var fresh = load("res://scenes/props/prop.tscn").instantiate()
	fresh.prop_id = "blood_altar"
	run.room.add_child(fresh)
	fresh.global_position = player.global_position + Vector2(200, 0)
	await process_frame
	max_before = player.stats.max_hp
	gifts_before = game.abilities.size()
	fresh.open(player)
	for i in 20:
		if run.picker.visible:
			break
		await process_frame
	run.picker.find_child("Refuse", true, false).pressed.emit()
	await process_frame
	await process_frame
	_check(game.abilities.size() == gifts_before and is_equal_approx(player.stats.max_hp, max_before),
		"the hand turned down: nothing taken, nothing paid")
	_check(int(profile.data.deeds.get("blood_paid", 0)) == 1, "  and nothing counted")
	_check(fresh._spent, "  the altar is spent either way: one look at its cards")

	# the playtest log hears both, and the balance probe sums the trades
	var heard := []
	var bus = root.get_node("EventBus")
	var listen := func(paid: bool) -> void: heard.append(paid)
	bus.blood_settled.connect(listen)
	var third = load("res://scenes/props/prop.tscn").instantiate()
	third.prop_id = "blood_altar"
	run.room.add_child(third)
	await process_frame
	third.open(player)
	for i in 20:
		if run.picker.visible:
			break
		await process_frame
	run.picker.cards.get_child(0).pressed.emit()
	await process_frame
	bus.blood_settled.disconnect(listen)
	_check(heard == [true], "the altar's end is told to the playtest log (%s)" % [heard])
	var probe = load("res://scripts/tools/balance_probe.gd")
	DirAccess.make_dir_recursive_absolute("user://playtest_tools")
	var log_a := "user://playtest_tools/trade_a.jsonl"
	var log_b := "user://playtest_tools/trade_b.jsonl"
	var one := FileAccess.open(log_a, FileAccess.WRITE)
	one.store_string('{"e":"altar","paid":true}\n{"e":"chest","id":"elite_cache"}\n{"e":"chest","id":"elite_cache"}\n{"e":"run_end","won":true}\n')
	one = null
	var two := FileAccess.open(log_b, FileAccess.WRITE)
	two.store_string('{"e":"altar","paid":false}\n{"e":"refuse"}\n{"e":"chest","id":"chest_iron"}\n{"e":"run_end","won":false}\n')
	two = null
	var text := "\n".join(probe.trade_rows([log_a, log_b]))
	_check(text.contains("| altar paid | 1 | 1 | 1 |") and text.contains("| altar withdrawn | 1 | 1 | 0 |")
		and text.contains("| elite_cache | 2 | 1 | 1 |") and text.contains("| refuse | 1 | 1 | 0 |")
		and not text.contains("chest_iron"), "the probe sums the trades and how their nights ended:\n%s" % text)
	DirAccess.remove_absolute(log_a)
	DirAccess.remove_absolute(log_b)
	DirAccess.remove_absolute("user://playtest_tools")
	_finish(saved)


func _finish(saved: Dictionary) -> void:
	var profile = root.get_node("Profile")
	root.get_node("Game").new_run()
	profile.data = saved
	profile.save()
	await process_frame
	print("BLOOD ALTAR TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
