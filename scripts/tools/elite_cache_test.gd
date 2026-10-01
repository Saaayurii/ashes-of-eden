extends SceneTree
## An elite's fall leaves a cache (Enemy._leave_cache, data/props/elite_cache):
##   - on the floor under the body, once;
##   - walking into it pays a common item and essence;
##   - a common enemy leaves none, nor a boss, nor anything in the yard;
##   - an elite laid low counts for Hunter of the Chosen.
## Puts the profile back as it found it.
##   godot --headless --path . -s scripts/tools/elite_cache_test.gd

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


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _caches(room) -> Array:
	return room.find_children("EliteCache*", "", true, false)


var _saved := {}


func _run() -> void:
	var game = root.get_node("Game")
	_saved = root.get_node("Profile").data.duplicate(true)
	root.get_node("Profile").data.deeds = {}
	game.vial = 0
	game.omen = ""
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
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
	var player = run.player
	for i in 240:
		if player.is_on_floor():
			break
		await physics_frame
	var floor_y: float = player.global_position.y + 15.0  # the body's origin sits 15 px above its feet
	var stand: Vector2 = player.global_position

	# a common one leaves nothing
	var common = run._spawn_enemy("cultist", player.global_position + Vector2(120, -30), false)
	await process_frame
	common.set_physics_process(false)
	common._die()
	await _frames(3)
	_check(_caches(run.room).is_empty(), "a common enemy leaves no cache")

	# an elite does, on the floor under it
	var elite = run._spawn_enemy("elite_cultist", player.global_position + Vector2(0, -30), false)
	await process_frame
	elite.set_physics_process(false)
	var at: Vector2 = elite.global_position
	player.global_position = stand + Vector2(160, -10)  # not standing on it when it lands
	await _frames(3)
	elite._die()
	await _frames(3)
	var caches := _caches(run.room)
	_check(caches.size() == 1, "an elite's fall leaves one cache (%d)" % caches.size())
	if caches.is_empty():
		_finish()
		return
	var cache = caches[0]
	_check(absf(cache.global_position.x - at.x) < 1.0 and absf(cache.global_position.y - floor_y) < 4.0,
		"  on the floor under the body (%s, floor %.0f)" % [cache.global_position, floor_y])
	elite._die()
	await _frames(3)
	_check(_caches(run.room).size() == 1, "  once")

	var items_before: int = game.items.size()
	var essence_before: float = game.essence + game.level * 1000.0
	_check(not player.is_dead(), "  (the body still stands)")
	player.global_position = stand
	await _frames(20)
	_check(game.items.size() == items_before + 1, "walking into it pays a common item (%s)" % [game.items])
	_check(game.essence + game.level * 1000.0 > essence_before, "  and some essence")
	if game.items.size() > items_before:
		_check(str(root.get_node("Data").items[game.items.back()].get("rarity", "")) == "common", "  a common one")

	_check(int(root.get_node("Profile").data.deeds.get("elites", 0)) == 1, "an elite laid low is counted for a deed")

	# nor in the yard
	game.practice = "elite_cultist"
	var yard = run._spawn_enemy("elite_cultist", player.global_position + Vector2(-120, -30), false)
	await process_frame
	yard.set_physics_process(false)
	var before := _caches(run.room).size()
	yard._die()
	await _frames(3)
	game.practice = ""
	_check(_caches(run.room).size() == before, "nothing in the practice yard")
	_finish()


func _finish() -> void:
	root.get_node("Game").new_run()
	var profile = root.get_node("Profile")
	profile.data = _saved
	profile.save()
	await process_frame
	print("ELITE CACHE TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
