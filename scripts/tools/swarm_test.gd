extends SceneTree
## The locusts' cloud (docs/CHAPTER5.md §9, scripts/enemies/swarm.gd), in a real
## room of the night of Engedi:
##   - one marker lets out a cloud of Swarm.size_for bodies, one key between them;
##   - every one of them holds the door;
##   - the night's surfeit makes the next cloud thicker;
##   - one sees him, the whole cloud wakes;
##   - awake, it hangs above him and never dives with more than dive_slots at once;
##   - each dive has its wind-up (never an unreadable instant hit);
##   - a summoned locust joins the cloud nearest it.
##   godot --headless --fixed-fps 60 --path . -s scripts/tools/swarm_test.gd

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


func _cloud() -> Array:
	return get_nodes_in_group("enemies").filter(
		func(e): return e.enemy_id == "locust" and not e.is_dead() and e.has_meta(&"swarm_cloud"))


func _enter(run, index: int) -> void:
	run._load_room(index)
	await _settle(0.4)
	run.cutscene.abort()
	root.get_node("Game").cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false
	await _frames(4)


func _run() -> void:
	var game = root.get_node("Game")
	var swarm = load("res://scripts/enemies/swarm.gd")
	var states = load("res://scripts/enemies/enemy.gd").State
	var flags_were: Dictionary = game.flags.duplicate(true)
	var night_was: String = game.night
	game.night = "engedi"
	game.surfeit = 0
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	var player = run.player
	var road: int = run.ROOMS.find("res://scenes/rooms/engedi_smoke_road.tscn")
	await _enter(run, road)

	var cloud := _cloud()
	_check(cloud.size() == swarm.size_for("locust"), "one marker, a cloud of %d" % cloud.size())
	var keys := {}
	for body in cloud:
		keys[body.get_meta(&"swarm_cloud")] = true
	_check(keys.size() == 1, "one key between them")
	_check(run.room.alive >= cloud.size(), "every one of them holds the door (%d alive)" % run.room.alive)
	_check(cloud.all(func(e): return e.is_unaware()), "the cloud starts unaware")

	var attack: Dictionary = root.get_node("Data").enemies["locust"].attacks[0]
	_check(float(attack.get("windup", 0.0)) >= 0.4, "a dive has its wind-up (%.2f s)" % float(attack.get("windup", 0.0)))

	# one sees him: all of them know
	player.hp = player.stats.max_hp
	player.global_position = cloud[0].global_position + Vector2(-140, 120)
	cloud[0]._notice(player)
	await _frames(4)
	_check(cloud.all(func(e): return e.state != states.PATROL), "one sees him, the whole cloud wakes (its \"!\" beat at once)")

	# awake: above him, never more than dive_slots diving at once
	var slots := int(swarm.spec("locust").dive_slots)
	var most := 0
	var above := 0
	var samples := 0
	var godmode: float = player.stats.max_hp
	for i in 360:
		await physics_frame
		player.hp = godmode  # the test watches the cloud, not the hero's death
		player.torment = 0.0
		var busy := 0
		var alive := _cloud()
		for e in alive:
			if e.state == states.WINDUP or e.state == states.STRIKE:
				busy += 1
		most = maxi(most, busy)
		if i % 30 == 29 and not alive.is_empty():
			samples += 1
			var mid: Vector2 = swarm.centre(alive)
			if mid.y < player.global_position.y - 10.0:
				above += 1
	_check(most <= slots, "never more than %d dive at once (most seen %d)" % [slots, most])
	_check(most >= 1, "and it does dive")
	_check(above * 2 >= samples, "the cloud hangs above him (%d of %d looks)" % [above, samples])

	# a summoned locust joins the nearest cloud
	var near: Vector2 = swarm.centre(_cloud())
	var newcomer = run.room.spawn_enemy("locust", near + Vector2(20, 0), true)
	await _frames(2)
	_check(swarm.cloud(newcomer) == str(_cloud()[0].get_meta(&"swarm_cloud")), "a summoned locust joins the cloud nearest it")

	# the surfeit thickens the next one
	game.surfeit = 6
	await _enter(run, road)
	var thick := _cloud().size()
	_check(thick == swarm.size_for("locust") and thick > swarm.size_for("locust", 0.0),
		"after six fruit the cloud is thicker (%d -> %d)" % [int(swarm.spec("locust").base), thick])

	game.surfeit = 0
	game.flags = flags_were
	game.night = night_was
	root.get_node("Data").use_night(night_was)
	print("swarm_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)
