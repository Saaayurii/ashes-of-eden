extends SceneTree
## Elite affixes (data/affixes, Run.roll_affix, Enemy._apply_affix):
##   - an elite rises with one, a common enemy, a boss or anything in the yard with none;
##   - it changes the numbers it names (hp, damage, the rest between blows,
##     speed, armour), never the wind-ups;
##   - its name stands over the elite's head;
##   - an affix that no longer exists is no affix.
##   godot --headless --path . -s scripts/tools/affix_test.gd

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
	var data = root.get_node("Data")
	game.vial = 0
	game.omen = ""
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	var script = run.get_script()

	var rolled := {}
	for i in 200:
		rolled[script.roll_affix("elite_cultist")] = true
	_check(rolled.size() == data.affixes.size() and not rolled.has(""), "an elite rises with an affix, every one can come up (%s)" % [rolled.keys()])
	_check(script.roll_affix("cultist") == "" and script.roll_affix("ophanim") == "", "a common enemy and a boss rise with none")
	game.practice = "elite_cultist"
	_check(script.roll_affix("elite_cultist") == "", "  nor anything in the practice yard")
	game.practice = ""

	var plain = _make(run, "elite_cultist", "")
	var at := Vector2(-3000, -3000)
	await process_frame
	var base_hp: float = plain._max_hp
	var base_damage: float = float(plain._attacks[0].damage)
	var base_cooldown: float = float(plain._attacks[0].get("cooldown", 1.5))
	var base_windup: float = float(plain._attacks[0].get("windup", 0.0))
	var base_armor: float = float(plain.stats.get("armor", 0.0))
	var base_speed: float = float(plain.stats.get("speed", 50))
	_check(plain.get_node_or_null("Affix") == null, "no affix, no name over the head")

	var enduring = _make(run, "elite_cultist", "enduring")
	var brutal = _make(run, "elite_cultist", "brutal")
	var ironclad = _make(run, "elite_cultist", "ironclad")
	var swift = _make(run, "elite_cultist", "swift")
	var gone = _make(run, "elite_cultist", "an_affix_that_was_removed")
	await process_frame
	_check(is_equal_approx(enduring._max_hp, base_hp * 1.6) and is_equal_approx(float(enduring._attacks[0].damage), base_damage * 0.9),
		"Enduring: more life, a little less weight (%.0f of %.0f)" % [enduring._max_hp, base_hp])
	_check(is_equal_approx(float(brutal._attacks[0].damage), base_damage * 1.35)
		and is_equal_approx(float(brutal._attacks[0].cooldown), base_cooldown * 1.15), "Brutal: heavier blows, longer between them")
	_check(is_equal_approx(float(brutal._attacks[0].get("windup", 0.0)), base_windup), "  the wind-up is untouched")
	_check(is_equal_approx(float(ironclad.stats.armor), minf(0.5, base_armor + 0.2))
		and is_equal_approx(float(ironclad.stats.speed), base_speed * 0.85), "Ironclad: armour, and slower for it")
	_check(is_equal_approx(float(swift.stats.speed), base_speed * 1.35) and is_equal_approx(swift._max_hp, base_hp * 0.85), "Swift: faster, frailer")
	var label = brutal.get_node_or_null("Affix")
	_check(label != null and label.text == TranslationServer.translate("AFFIX_BRUTAL"), "its name stands over its head")
	_check(gone.affix == "" and gone.get_node_or_null("Affix") == null and is_equal_approx(gone._max_hp, base_hp), "an affix that no longer exists is no affix")

	# laid low, the affix goes onto its bestiary page
	var profile = root.get_node("Profile")
	var saved: Dictionary = profile.data.duplicate(true)
	profile.data.bestiary.erase("elite_cultist")
	brutal._die()
	swift._die()
	brutal._die()
	var page: Dictionary = profile.data.bestiary.get("elite_cultist", {})
	_check(page.get("affixes", []) == ["brutal", "swift"], "the bestiary keeps the affixes it was beaten in, once each (%s)" % [page.get("affixes", [])])
	page["kills"] = 2
	var book = load("res://scenes/ui/bestiary.tscn").instantiate()
	root.add_child(book)
	book.open()
	await process_frame
	book._show("elite_cultist")
	var shown: Array = book.stats_box.get_children().map(func(n: Node) -> String: return n.text if n is Label else "")
	_check(shown.any(func(t: String) -> bool: return t.contains("(2/%d)" % data.affixes.size())), "  and its page names them (%s)" % [shown])
	book.queue_free()
	# every affix beaten, on any elite: Every Face of the Chosen
	profile.data.achievements = {}
	var ids: Array = data.affixes.keys()
	for id in profile.data.bestiary:  # only what this test lays down counts
		if profile.data.bestiary[id] is Dictionary:
			profile.data.bestiary[id].erase("affixes")
	profile.data.bestiary["elite_cultist"]["affixes"] = ids.slice(0, 2)
	profile.check_achievements()
	_check(not profile.data.achievements.has("every_face"), "half the affixes beaten: not yet Every Face")
	profile.data.bestiary["elite_possessed"] = {"seen": true, "kills": 1, "affixes": ids.slice(2)}
	profile.check_achievements()
	_check(profile.data.achievements.has("every_face"), "every affix beaten, on any elite: Every Face of the Chosen")
	var end_screen = load("res://scripts/ui/end_screen.gd")
	var line: String = end_screen.deeds_line(["every_face", "no_such_deed"])
	_check(line.contains(TranslationServer.translate("DEED_EVERY_FACE")) and not line.contains("no_such"), "the night's end lists tonight's deeds: %s" % line)
	_check(game.deeds_tonight.has("every_face"), "  counted as tonight's")
	profile.data = saved
	profile.save()

	# the spawn data carries it, so a guest builds the same body
	var spawned = run._spawn_enemy("elite_cultist", at, false)
	await process_frame
	_check(data.affixes.has(spawned.affix), "a spawned elite carries its affix (%s)" % spawned.affix)
	for node in [plain, enduring, brutal, ironclad, swift, gone, spawned]:
		node.queue_free()
	game.new_run()
	await process_frame
	print("AFFIX TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)


func _make(run, id: String, affix: String):
	var enemy = run._make_enemy({"n": 9000 + randi() % 1000, "id": id, "pos": Vector2(-3000, -3000), "aware": false, "affix": affix})
	enemy.set_physics_process(false)
	run.entities.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy
