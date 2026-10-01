extends SceneTree
## What laid him low (Player.slain_by, Game.slain_by):
##   - a blow names the enemy that struck it, a bolt the enemy that loosed it,
##     the lava and the drop name themselves, a forwarded hit carries its name;
##   - the night's end says so and gives the advice for it, the chronicle keeps it, the bestiary counts it
##     on that enemy's page;
##   - a revive forgets it, and a new night starts with nothing to blame.
## Puts the profile back as it found it (CLAUDE.md: tools share user://).
##   godot --headless --path . -s scripts/tools/slain_test.gd

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


func _lethal(player, source, info := {}) -> String:
	player.revive(player.global_position)
	player._hurt_grace_left = 0.0
	player._dash_left = 0.0
	player._blocking = false
	player._guard_left = 0
	player.stats.extra_lives = 0
	player._apply_damage(99999.0, source, info)
	return player.slain_by


func _run() -> void:
	var game = root.get_node("Game")
	var profile = root.get_node("Profile")
	var saved: Dictionary = profile.data.duplicate(true)
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	var player = run.player
	run._load_room(run.ROOMS.find("res://scenes/rooms/graveyard_tree.tscn"))
	await _settle(0.4)
	run.cutscene.abort()
	game.cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false
	var foe = null
	for node in get_nodes_in_group("enemies"):
		node.set_physics_process(false)
		node.set_process(false)
		foe = node
	await _frames(2)
	_check(foe != null, "there is someone to blame")

	var bolt = load("res://scenes/fx/projectile.tscn").instantiate()
	bolt.shooter_id = "zealot"
	_check(_lethal(player, bolt) == "zealot", "a bolt is blamed on whoever loosed it")
	bolt.free()
	_check(_lethal(player, null, {"killer": "wraith"}) == "wraith", "a forwarded hit carries its name")
	_check(_lethal(player, null) == "", "a blow from nowhere blames nobody")
	player.revive(player.global_position)
	player.burn(99999.0)
	_check(player.slain_by == "lava", "the lava names itself")
	player.revive(player.global_position)
	_check(player.slain_by == "", "a revive forgets it")

	# the last one, for the run to end on
	var felled_before := int(profile.data.bestiary.get(foe.enemy_id, {}).get("felled", 0))
	_check(_lethal(player, foe) == foe.enemy_id and game.slain_by == foe.enemy_id,
		"a blow is blamed on the enemy that struck it (%s)" % foe.enemy_id)
	game.ash_earned = 0
	profile.record_run(3, 4, 120.0, 0, false)
	_check(str(profile.data.history.back().get("slain_by", "")) == foe.enemy_id, "the chronicle keeps it")
	_check(int(profile.data.bestiary[foe.enemy_id].get("felled", 0)) == felled_before + 1,
		"  and the bestiary counts it on its page")
	var book = load("res://scenes/ui/bestiary.tscn").instantiate()
	root.add_child(book)
	book.open()
	await process_frame
	var advice: String = TranslationServer.translate(str(root.get_node("Data").enemies[foe.enemy_id].get("tip", "")))
	book._show(foe.enemy_id)
	var page: String = book.lore_label.text if int(profile.data.bestiary[foe.enemy_id].get("kills", 0)) > 0 \
		else book.hint_label.text
	_check(advice != "" and page.contains(advice), "the bestiary page gives the same advice")
	book.queue_free()
	var end_screen = null
	for node in run.find_children("*", "", true, false):
		if node.get_script() != null and str(node.get_script().resource_path).ends_with("end_screen.gd"):
			end_screen = node
			break
	_check(end_screen != null, "the run has an end screen")
	if end_screen != null:
		end_screen.show_result(false, 3, 4, 120.0)
		var named: String = TranslationServer.translate(str(root.get_node("Data").enemies[foe.enemy_id].name))
		_check(end_screen.stats.text.contains(named), "the night's end names it: %s" % end_screen.stats.text.get_slice("\n", 0))
		var tip: String = TranslationServer.translate(str(root.get_node("Data").enemies[foe.enemy_id].get("tip", "")))
		_check(tip != "" and end_screen.best.text.contains(tip), "  and says how to meet it next time")
		_check(end_screen.slain_tip("lava") == "TIP_LAVA" and end_screen.slain_tip("fall") == "TIP_FALL"
				and end_screen.slain_tip("") == "", "the lava and the drop have advice of their own")
		game.slain_by = ""
		end_screen.show_result(true, 3, 4, 120.0)
		_check(not end_screen.stats.text.contains(named), "a dawn blames nobody")

	game.new_run()
	_check(game.slain_by == "", "a new night starts with nothing to blame")
	profile.data = saved
	profile.save()
	await process_frame
	print("SLAIN TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
