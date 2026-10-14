extends SceneTree
## Wormwood's mechanics (docs/CHAPTER3.md §6, §9), all generic for any flying
## boss (chapter V reuses them):
##   - "mark_landing": an ember's landing glows before the ember lands, where it lands;
##   - "flood": at its share of health the named pool rises "rise" px over
##     "time" after "warn", once;
##   - "anchor" + "leash": it never wants further from its point than the leash,
##     and "hover_floor" keeps it over the floor or the water;
##   - a summon with "where": "liquid" rises out of the water with its side,
##     paying the attack's "essence";
##   - no soldier's quarry, and it hunts only the hero.
## Played in marah_bitter_wells, whose left basin stands in for the spring.
##   godot --headless --fixed-fps 60 --path . -s scripts/tools/wormwood_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


## A cleared room deals a hand of gifts, which pauses the tree.
func _frames(count: int) -> void:
	for i in count:
		paused = false
		await physics_frame


func _run() -> void:
	var game = root.get_node("Game")
	var profile = root.get_node("Profile")
	var saved_profile: Dictionary = profile.data.duplicate(true)
	var saved_flags: Dictionary = game.flags.duplicate()
	for flag in ["sided_host", "sided_legion", "sided_none", "truce_broken"]:
		game.flags.erase(flag)
	change_scene_to_file("res://scenes/run/run.tscn")
	await _frames(30)
	var run = current_scene
	run.transition.instant = true
	var data = root.get_node("Data")
	var index: int = data.all_rooms().find("res://scenes/rooms/marah_bitter_wells.tscn")
	_check(index >= 0, "marah_bitter_wells is a room of some night")
	data.use_night("marah")
	game.night = "marah"
	run._load_room(run.ROOMS.find("res://scenes/rooms/marah_bitter_wells.tscn"))
	await _frames(24)
	run.cutscene.abort()
	game.cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	var room = run.room
	for attempt in 8:
		for body in get_nodes_in_group("enemies"):
			if not body.is_dead():
				body.take_damage(99999.0)
		await _frames(6)
	var player = run.player
	player.stats["max_hp"] = 99999.0
	player.hp = 99999.0

	# the left basin is the spring here
	var pools: Array = get_nodes_in_group("liquids")
	_check(pools.size() >= 1, "the room has its bitter pools (%d)" % pools.size())
	pools.sort_custom(func(a, b) -> bool: return a.global_position.x < b.global_position.x)
	var spring = pools[0]
	spring.name = "Spring"
	# the anchor is the spring's centre in its own arena, which is bitter_wells' middle too
	var boss = room.spawn_enemy("wormwood", room.global_position + Vector2(800, 330), true)
	await _frames(4)
	_check(boss != null and boss.stats.get("boss", false), "Wormwood stands up as a boss")

	# --- the leash and the hover floor ------------------------------------------
	var anchor: Vector2 = room.global_position + Vector2(float(boss.stats.anchor[0]), float(boss.stats.anchor[1]))
	var leash := float(boss.stats.leash)
	var far: Vector2 = boss.global_position + boss._leashed(Vector2(2000, 0))
	_check(far.distance_to(anchor) <= leash + 0.5, "it never wants further than its leash (%.0f of %.0f)" % [far.distance_to(anchor), leash])
	var low: Vector2 = boss.global_position + boss._leashed(Vector2(0, 2000))
	var under: float = boss._ground_under(low.x)
	_check(low.y <= under - float(boss.stats.hover_floor) + 0.5, "nor lower than hover_floor over what is under it (%.0f over)" % (under - low.y))
	await _frames(240)
	_check(boss.global_position.distance_to(anchor) <= leash + 24.0, "after four seconds of hunting it is still over its spring (%.0f)" % boss.global_position.distance_to(anchor))

	# --- no soldier's quarry ---------------------------------------------------------
	var spear = room.spawn_enemy("host_spearman", room.global_position + Vector2(120, 440), true)
	await _frames(2)
	_check(not spear._hostile_to(boss) and not boss._hostile_to(spear), "no soldier touches the star, and it hunts only the hero")
	spear.queue_free()

	# --- mark_landing ------------------------------------------------------------------
	var ember: Dictionary = {}
	for attack in boss._attacks:
		if attack.has("mark_landing"):
			ember = attack.duplicate()
			break
	_check(not ember.is_empty(), "it has an attack that marks its landing")
	ember["damage"] = 0
	ember["volley"] = 1
	# the mark is Fx.ring's circle of radius 18 (a flash too, when lighting is on)
	var rings_before := {}
	for child in current_scene.get_children():
		rings_before[child.get_instance_id()] = true
	var shots_before := {}
	for child in boss.get_parent().get_children():
		shots_before[child.get_instance_id()] = true
	# its own hunting stands still meanwhile: one ember, ours, in the air
	boss.set_physics_process(false)
	await _frames(90)
	for child in boss.get_parent().get_children():
		shots_before[child.get_instance_id()] = true
	for child in current_scene.get_children():
		rings_before[child.get_instance_id()] = true
	boss.facing = 1
	boss._fire_round(ember, Vector2(220, 60))
	var shot: Node2D = null
	for child in boss.get_parent().get_children():
		if not shots_before.has(child.get_instance_id()) and child.get_script() == load("res://scripts/fx/projectile.gd"):
			shot = child
	_check(shot != null, "the ember flies")
	var last := Vector2.ZERO
	var marks: Array = []  # [frame, position]
	var landed := -1
	for frame in 360:
		await _frames(1)
		for child in current_scene.get_children():
			if rings_before.has(child.get_instance_id()):
				continue
			rings_before[child.get_instance_id()] = true
			if child is Line2D and child.points.size() == 41 and absf(child.points[0].x - 18.0) < 0.5:
				marks.append([frame, child.global_position])
		if shot != null and is_instance_valid(shot) and not shot.is_queued_for_deletion():
			last = shot.global_position
		elif landed < 0:
			landed = frame
			break
	var mark_at := Vector2.INF
	var mark_frame := -1
	for mark in marks:
		if mark_at == Vector2.INF or mark[1].distance_to(last) < mark_at.distance_to(last):
			mark_at = mark[1]
			mark_frame = mark[0]
	_check(landed > 0, "the ember comes down (frame %d)" % landed)
	_check(mark_at != Vector2.INF and mark_at.distance_to(last) <= 30.0, "the glow lies where it lands (%.0f px off: %s vs %s)" % [mark_at.distance_to(last) if mark_at != Vector2.INF else -1.0, mark_at, last])
	_check(mark_frame >= 0 and mark_frame < landed, "and before it lands (frame %d, landed %d)" % [mark_frame, landed])

	boss.set_physics_process(true)

	# --- the flood ---------------------------------------------------------------------
	var flood: Dictionary = boss.stats.flood
	var top_before: float = spring.global_position.y
	boss.hp = boss._max_hp * (float(flood.at_hp) + 0.02)
	boss.take_damage(boss._max_hp * 0.05, player)
	await _frames(int(float(flood.warn) * 60.0) - 12)
	_check(absf(spring.global_position.y - top_before) < 1.0, "the water waits through the warning")
	await _frames(int(float(flood.time) * 60.0) + 30)
	_check(absf((top_before - spring.global_position.y) - float(flood.rise)) < 1.5,
		"then rises %.0f px over %.1f s (%.1f)" % [float(flood.rise), float(flood.time), top_before - spring.global_position.y])
	boss.take_damage(1.0, player)
	await _frames(int((float(flood.warn) + float(flood.time)) * 60.0) + 30)
	_check(absf((top_before - spring.global_position.y) - float(flood.rise)) < 1.5, "once: a later blow raises it no further")

	# --- the risen come out of the water, with their side -------------------------------
	for attack in boss._attacks:
		if str(attack.get("where", "")) != "liquid":
			continue
		var id := str(attack.get("id", ""))
		var before := {}
		for body in get_nodes_in_group("enemies"):
			before[body.get_instance_id()] = true
		boss._call_up(attack)
		await _frames(3)
		var risen: Array = get_nodes_in_group("enemies").filter(func(b) -> bool: return not before.has(b.get_instance_id()) and b.enemy_id == id)
		_check(not risen.is_empty(), "%s rises" % id)
		for body in risen:
			var wet := false
			for pool in get_nodes_in_group("liquids"):
				if body.global_position.x >= pool.global_position.x and body.global_position.x <= pool.global_position.x + pool.size.x:
					wet = absf(body.global_position.y - pool.surface_y(body.global_position.x)) < 40.0 or wet
			_check(wet, "%s comes up out of the water" % id)
			_check(str(body.stats.get("faction", "")) == str(data.enemies[id].get("faction", "")), "%s keeps its side (%s)" % [id, body.stats.get("faction", "")])
			if attack.has("essence"):
				_check(is_equal_approx(float(body.stats.essence), float(attack.essence)), "%s pays what the summon says (%s)" % [id, attack.essence])
			body.queue_free()

	boss.queue_free()
	await _frames(2)
	data.use_night("")
	game.night = ""
	game.flags = saved_flags
	profile.data = saved_profile
	profile.save()
	_check(profile.data == saved_profile, "the profile is put back as it was found")
	print("wormwood_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)

