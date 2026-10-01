extends SceneTree
## The cursed chest (data/props/chest_cursed.json, Prop "curse", Player.take_curse):
##   - walking into it opens nothing; standing at it offers it, `interact` opens it;
##   - it pays a rare item, its essence and a nudge to temptation, and lays the curse;
##   - while cursed a wound lands twice as hard;
##   - each enemy that falls takes one off, and at none the curse lifts and is counted
##     (the deed "cursed");
##   - a save keeps what is owed, a death pays it.
## Puts the profile back as it found it (CLAUDE.md: tools share user://).
##   godot --headless --path . -s scripts/tools/curse_test.gd

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


func _quiet(run) -> void:
	run.cutscene.abort()
	root.get_node("Game").cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false


## The wound a 10-point blow leaves, with nothing in the way.
func _wound(player) -> float:
	player.hp = player.stats.max_hp
	player._hurt_grace_left = 0.0
	player._dash_left = 0.0
	player._blocking = false
	player._guard_left = 0
	var before: float = player.hp
	player._apply_damage(10.0)
	return before - player.hp


func _run() -> void:
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	var profile = root.get_node("Profile")
	var saves = root.get_node("Saves")
	var saved: Dictionary = profile.data.duplicate(true)
	profile.data.deeds = {}
	profile.data.achievements = {}
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	var player = run.player
	run._load_room(run.ROOMS.find("res://scenes/rooms/graveyard_tree.tscn"))
	await _settle(0.4)
	_quiet(run)
	# nobody to fight here: the deaths below are the test's own
	for node in get_nodes_in_group("enemies"):
		node.set_physics_process(false)
		node.set_process(false)
	await _frames(4)

	_check(int(data.props.chest_cursed.get("curse", 0)) > 0 and data.props.chest_cursed.get("item") == "rare",
		"the cursed chest asks a price and holds a rare item")
	var chest = load("res://scenes/props/prop.tscn").instantiate()
	chest.prop_id = "chest_cursed"
	chest.position = player.position
	player.get_parent().add_child(chest)
	await _frames(6)
	_check(not chest._spent, "walking into it opens nothing")
	_check(chest._local_taker() == player and chest.is_in_group("interactable"),
		"standing at it, it offers itself (the touch pad's talk button shows)")
	chest._offer()
	_check(chest._prompt.visible and chest._prompt.text.contains(str(int(data.props.chest_cursed.curse))),
		"  and says how many must fall")

	var clean := _wound(player)
	var items_before: int = game.items.size()
	var temptation_before: int = int(game.alignment.temptation)
	var owed: int = int(data.props.chest_cursed.curse)
	chest.open(player)
	await _frames(2)
	_check(chest._spent and not chest.is_in_group("interactable"), "interact opens it, once")
	_check(player.curse == owed, "the opener carries the curse (%d)" % player.curse)
	_check(game.items.size() == items_before + 1, "  and the item it held")
	_check(int(game.alignment.temptation) == temptation_before + 1, "  and leans a little to temptation")
	var cursed := _wound(player)
	_check(absf(cursed - clean * player.CURSE_DAMAGE) < 0.01,
		"a wound lands twice as hard (%.1f, not %.1f)" % [cursed, clean])

	var checkpoint: Dictionary = saves.capture(run.ROOMS[run.room_index], 0, 0.0, player)
	_check(int(checkpoint.player.get("curse", -1)) == owed, "a save keeps what is owed")

	for i in owed - 1:
		root.get_node("EventBus").enemy_died.emit(&"cultist", Vector2.ZERO)
	_check(player.curse == 1, "each enemy that falls takes one off")
	root.get_node("EventBus").enemy_died.emit(&"cultist", Vector2.ZERO)
	await _frames(2)
	_check(player.curse == 0, "the last one lifts it")
	_check(int(profile.data.deeds.get("curses_lifted", 0)) == 1 and profile.data.achievements.has("cursed"),
		"  counted, and the deed is done")
	_check(absf(_wound(player) - clean) < 0.01, "a wound is a wound again")

	saves.restore(checkpoint, player)
	_check(player.curse == owed, "loading the room puts the curse back on")
	player.revive(player.global_position)
	_check(player.curse == 0, "a death pays it")
	chest.queue_free()

	profile.data = saved
	profile.save()
	await process_frame
	print("CURSE TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
