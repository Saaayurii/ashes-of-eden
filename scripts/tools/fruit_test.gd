extends SceneTree
## The garden's fruit and the locust's sting (docs/CHAPTER5.md §2, scripts/rooms/fruit.gd,
## scripts/player/torment.gd), in a real room of the night of Engedi:
##   - a sting stops every heal, keeps the longer of two, never past the cap;
##   - a fruit is not eaten by walking into it, only on interact;
##   - eaten, it lifts the sting first and then heals its share;
##   - it counts in the night's surfeit and sets fruit_eaten, once;
##   - it is gone for the night: the room built again lays it no more;
##   - a fruit that waits for the story (requires_flag) is hidden and cannot be eaten;
##   - the surfeit thickens the clouds still to come (Swarm.size_for) and is saved;
##   - the Seal on the Brow keeps the sting off.
##   godot --headless --path . -s scripts/tools/fruit_test.gd

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


func _fruits(room: Node) -> Array:
	var out: Array = []
	for node in room.find_children("*", "Prop", true, false):
		if str(node.stats.get("kind", "")) == "fruit" and not node.is_queued_for_deletion():
			out.append(node)
	return out


func _run() -> void:
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	var swarm = load("res://scripts/enemies/swarm.gd")
	var torment = load("res://scripts/player/torment.gd")
	var flags_were: Dictionary = game.flags.duplicate(true)
	var night_was: String = game.night
	game.night = "engedi"  # the Run takes its night from here (Data.use_night)
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	var player = run.player
	var spring: int = run.ROOMS.find("res://scenes/rooms/engedi_spring.tscn")
	_check(spring >= 0, "the spring is a room of the night of Engedi")
	game.flags.erase("tirzah_fed")
	game.surfeit = 0
	run._load_room(spring)
	await _settle(0.4)
	run.cutscene.abort()
	game.cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false
	await _frames(4)
	var room = run.room

	# the sting
	player.hp = player.stats.max_hp * 0.4
	player.torment = 0.0
	player.apply_torment(3.0)
	_check(player.torment >= 3.0, "a sting takes hold (%.1f s)" % player.torment)
	player.apply_torment(1.0)
	_check(player.torment >= 2.9, "a shorter one keeps the longer (%.1f s)" % player.torment)
	player.apply_torment(99.0)
	_check(player.torment <= torment.CAP + 0.01, "never past the cap (%.1f s)" % player.torment)
	var hp: float = player.hp
	player.heal(50.0)
	_check(is_equal_approx(player.hp, hp), "a stung body heals with nothing")

	# a fruit on the floor
	var fruits := _fruits(room)
	var free: Array = fruits.filter(func(f): return not f.stats.has("requires_flag"))
	var waiting: Array = fruits.filter(func(f): return f.stats.has("requires_flag"))
	_check(free.size() >= 2, "the spring has its fruit (%d)" % free.size())
	_check(waiting.size() == 1 and not waiting[0].visible, "Tirzah's pomegranate waits unseen until she is fed")
	var fruit = free[0]
	player.global_position = fruit.global_position + Vector2(0, -2)
	await _frames(20)
	_check(fruit.visible and not game.flags.has("fruit_eaten"), "walking into a fruit does not eat it")
	var share := float(fruit.stats.get("heal", 0.25))
	hp = player.hp
	fruit.open(player)
	await _frames(4)
	_check(player.torment <= 0.0, "eaten, it lifts the sting")
	_check(player.hp - hp >= player.stats.max_hp * share - 0.5,
		"and heals its share (%.1f of %.1f)" % [player.hp - hp, player.stats.max_hp * share])
	_check(game.surfeit == maxi(1, int(fruit.stats.get("surfeit", 1))), "the night's surfeit counts it (%d)" % game.surfeit)
	_check(game.flags.get("fruit_eaten", false), "and the night knows a fruit was eaten")
	_check(not fruit.visible, "it is gone from the branch")
	var surfeit: int = game.surfeit
	fruit.open(player)
	await _frames(2)
	_check(game.surfeit == surfeit, "a fruit is eaten once")

	waiting[0].open(player)
	await _frames(2)
	_check(game.surfeit == surfeit, "a fruit the story has not laid cannot be eaten")

	# the room built again: the eaten fruit stays eaten, the others are still there
	run._load_room(spring)
	await _settle(0.4)
	run.cutscene.abort()
	game.cutscene = false
	await _frames(4)
	var again := _fruits(run.room).filter(func(f): return not f.stats.has("requires_flag"))
	_check(again.size() == free.size() - 1, "the eaten fruit does not grow back tonight (%d -> %d)" % [free.size(), again.size()])

	# the surfeit thickens the clouds, and is carried by a save
	game.surfeit = 0
	var thin: int = swarm.size_for("locust")
	game.surfeit = 4
	var thick: int = swarm.size_for("locust")
	_check(thick > thin, "the surfeit thickens a cloud (%d -> %d)" % [thin, thick])
	game.surfeit = 999
	_check(swarm.size_for("locust") == int(swarm.spec("locust").max), "never past its max")
	game.surfeit = 3
	var saves = root.get_node("Saves")
	var state: Dictionary = saves.capture(run.room.scene_file_path, 0, 0.0, player)
	_check(int(state.game_state.get("surfeit", -1)) == 3, "a save carries the surfeit")

	# the Seal on the Brow
	player.torment = 0.0
	player.stats["torment_immune"] = 1.0
	player.apply_torment(5.0)
	_check(player.torment <= 0.0, "the Seal on the Brow keeps the sting off")
	player.stats["torment_immune"] = 0.0

	game.surfeit = 0
	game.flags = flags_were
	game.night = night_was
	data.use_night(night_was)
	print("fruit_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)
