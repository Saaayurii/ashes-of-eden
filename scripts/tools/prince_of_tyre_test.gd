extends SceneTree
## The Prince of Tyre (docs/CHAPTER4.md §6, data/enemies/prince_of_tyre.json):
##   - a boss, aware from the start, with a readable wind-up on every attack;
##   - at half health he raises his palm (a wind-up of his darkness_phase) and
##     puts the room out: every lamp, bought ones too, the painting's fires,
##     the room sinks to his "dark" and the lamps sell again at twice the price;
##   - he does it once; his own light, a body's, stays;
##   - his fall asks what to do with the light, and each answer sets its flag,
##     which the chapter's finale reads.
## In the counting house of Tyre, which has lamps to put out.
##   godot --headless --path . -s scripts/tools/prince_of_tyre_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _settle(seconds := 0.3) -> void:
	await create_timer(seconds, true, false, true).timeout


func _run() -> void:
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	var spec: Dictionary = data.enemies["prince_of_tyre"]
	_check(spec.get("boss", false), "the Prince is a boss")
	for attack in spec.attacks:
		_check(float(attack.get("windup", 0.0)) >= 0.9, "%s winds up for %.2f s" % [attack.name, float(attack.get("windup", 0.0))])
	var phase: Dictionary = spec.get("darkness_phase", {})
	_check(float(phase.get("windup", 0.0)) >= 1.0, "the douse is a wind-up too (%.1f s)" % float(phase.get("windup", 0.0)))
	_check(data.dialogues.has(str(phase.get("caption", ""))), "and says so (%s)" % phase.get("caption", ""))

	var had_night: String = game.night
	game.night = "tyre"
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	var player = run.player
	run._load_room(run.ROOMS.find("res://scenes/rooms/tyre_counting_house.tscn"))
	await _settle(0.4)
	run.cutscene.abort()
	game.cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false
	await _frames(4)
	var room = run.room
	for body in get_nodes_in_group("enemies"):
		body.queue_free()
	await _frames(2)
	var dark = room.get_node("Darkness")
	var lamps: Array = get_nodes_in_group("lamps")
	game.essence = 100.0
	var bought = lamps[0]
	bought.buy(player)
	_check(bought.lit, "a lamp bought before the fight")
	var fixed := 0
	for node in get_nodes_in_group("lights"):
		if room.is_ancestor_of(node) and not node.is_in_group("lamp_light") and not dark._carried(node):
			fixed += 1

	var prince = room.spawn_enemy("prince_of_tyre", player.global_position + Vector2(120, 0))
	await _frames(6)
	_check(not prince.is_unaware(), "he starts aware")
	prince.hp = prince._max_hp * 0.6
	await _settle(0.6)
	_check(not prince.get_meta("doused", false), "above half he has not put the room out")
	prince.hp = prince._max_hp * 0.49
	var raised := 0.0
	while not prince.get_meta("doused", false) and raised < 4.0:  # a blow under way ends first
		await physics_frame
		raised += 1.0 / 60.0
	_check(prince.get_meta("doused", false), "at half he raises his palm (%.1f s)" % raised)
	_check(not dark.doused, "the wind-up comes first: the room is still lit")
	_check(bought.lit, "and the lamp still burns over it")
	var waited := 0.0
	while not dark.doused and waited < 4.0:  # game time, in frames: a timer runs on the wall clock under --fixed-fps
		await physics_frame
		waited += 1.0 / 60.0
	_check(dark.doused, "then the room goes out (after %.1f s)" % waited)
	_check(waited >= float(phase.windup) - 0.15, "no sooner than the wind-up")
	_check(is_equal_approx(dark.dark, float(phase.dark)), "it sinks to %.2f" % dark.dark)
	var box = get_first_node_in_group("dialogue_box")
	_check(box != null and box._dialogue_id == str(phase.caption), "and the caption says so (%s)" % [box._dialogue_id if box else "no box"])
	_check(not bought.lit and not game.lamps_lit.has(bought.key()), "the bought lamp is out")
	var out := true
	for lamp in lamps:
		out = out and not lamp.lit
	_check(out, "every lamp is out")
	_check(bought.cost() == int(round(bought.price * float(phase.relight_price))),
		"a lamp sells again at %.0f× (%d)" % [float(phase.relight_price), bought.cost()])
	var left := 0
	for node in get_nodes_in_group("lights"):
		if room.is_ancestor_of(node) and not node.is_in_group("lamp_light") and not dark._carried(node):
			left += 1
	_check(left == 0, "the painting's fires went with them (%d of %d left)" % [left, fixed])
	var carried := false
	for child in prince.get_children():
		if child.is_in_group("lights"):
			carried = true
	_check(carried or not spec.has("light"), "his own light stays")

	dark.dark = 0.3
	prince.hp = prince._max_hp * 0.2
	await _settle(1.0)
	_check(is_equal_approx(dark.dark, 0.3), "he does it only once")
	prince.queue_free()
	await _frames(2)

	# --- the ray and the tithe come only in the second half
	var fresh = room.spawn_enemy("prince_of_tyre", player.global_position + Vector2(60, 0))
	await _frames(2)
	var late := []
	for i in fresh._attacks.size():
		if float(fresh._attacks[i].get("from_hp", 1.0)) < 1.0:
			late.append(i)
	_check(late.size() == 2, "two of his blows wait for the second half (%d)" % late.size())
	var picked := {}
	fresh.hp = fresh._max_hp * 0.9
	for n in 200:
		fresh._repeats = 0
		picked[fresh._choose_attack(Vector2(50, 0))] = true
	var early_late := false
	for i in late:
		early_late = early_late or picked.has(i)
	_check(not early_late, "above half: never the ray or the tithe (%s)" % [picked.keys()])
	picked = {}
	fresh.hp = fresh._max_hp * 0.4
	for n in 400:
		fresh._repeats = 0
		picked[fresh._choose_attack(Vector2(50, 0))] = true
	var all_late := true
	for i in late:
		all_late = all_late and picked.has(i)
	_check(all_late, "below half: both come (%s)" % [picked.keys()])
	fresh.queue_free()

	# --- his fall: the light, returned, shared or taken, read by the finale
	var fall: Dictionary = data.dialogues.get("ch4_prince_fall", {})
	var seen := {}
	for node in fall.get("nodes", {}).values():
		for choice in node.get("choices", []):
			for flag in choice.get("effect", {}).get("set_flags", []):
				seen[flag] = true
	for flag in ["light_returned", "light_shared", "light_taken"]:
		_check(seen.has(flag), "his fall can end in %s" % flag)
	var finale = FileAccess.get_file_as_string("res://data/cutscenes/ch4_finale.json")
	for flag in ["light_returned", "light_shared", "light_taken"]:
		_check(finale.find("\"%s\"" % flag) >= 0, "the finale answers %s" % flag)

	game.lamps_lit = {}
	game.night = had_night
	data.use_night(had_night)
	print("prince_of_tyre_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)
