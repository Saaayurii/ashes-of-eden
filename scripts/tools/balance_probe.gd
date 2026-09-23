extends SceneTree
## Measures the numbers docs/BALANCE.md says we must judge by, in the real
## engine rather than on paper:
##   godot --headless -s scripts/tools/balance_probe.gd
##
## 1. Duels. For every enemy id: an unbuffed hero stands next to it and swings
##    as fast as the combo allows, never rolling, never blocking. Measured:
##    time to kill (TTK), hits to kill, and how hard it hits back while he
##    face-tanks (HP lost per second). Bosses get an immortal hero, so the
##    number is the pure damage phase — the real fight is longer.
## 2. Census. Every room of the chapter: enemies, their total HP, essence,
##    and an estimate of the clear time from the measured TTKs.
## 3. The run as a whole: expected length, levels (gifts) reached, against the
##    targets (25–30 min, 10–14 upgrades, common TTK 2–3 s early).
##
## Writes docs/BALANCE_PROBE.md. Untyped on purpose: -s scripts compile before
## the autoloads exist.

const DUEL_LIMIT := 90.0
const BOSS_LIMIT := 240.0
## Walking the room and dodging between swings, relative to pure TTK. A guess
## until a real playtest replaces it; stated in the report.
const FIGHT_OVERHEAD := 1.8
const TRAVERSAL_SPEED := 110.0  # px/s: a hero who stops, looks, jumps

var _results := {}
var _lines: PackedStringArray = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	change_scene_to_file("res://scenes/run/run.tscn")
	await _wait(1.0)
	var run = current_scene
	# The room and the hero arrive behind the curtain a beat later.
	for i in 100:
		if run.get("player") != null and run.get("room") != null:
			break
		await _wait(0.1)
	if run.get("player") == null:
		printerr("no hero in the run scene")
		quit(1)
		return
	await _wait(2.0)
	run.get_node("UI/DialogueBox").skip()
	await _wait(0.5)
	_clear_room(run)
	var data = root.get_node("Data")
	# Kills earn essence, essence levels up, a level-up opens the gift picker and
	# pauses the game: the probe measures a hero *without* gifts, so no levels.
	var bus = root.get_node("EventBus")
	for connection in bus.level_up.get_connections():
		bus.level_up.disconnect(connection.callable)
	var ids: Array = data.enemies.keys()
	ids.sort()
	for id in ids:
		_results[id] = await _duel(run, id)
		var r: Dictionary = _results[id]
		print("  %-20s TTK %6.1fs  hits %3d  hurts %5.1f HP/s  %s" % [id, r.ttk, r.hits, r.dps_taken, "" if r.killed else "(NOT KILLED in limit)"])
	_census(run, data)
	var path := ProjectSettings.globalize_path("res://docs/BALANCE_PROBE.md")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	print("report: docs/BALANCE_PROBE.md")
	quit(0)


func _clear_room(run) -> void:
	for enemy in get_nodes_in_group("enemies"):
		enemy.queue_free()
	for prop in get_nodes_in_group("props"):
		prop.queue_free()


## One enemy, one hero, flat ground. Returns ttk, hits, dps_taken, killed.
func _duel(run, id: String) -> Dictionary:
	var hero = run.player
	hero.set("_dead", false)
	hero.set("controls_enabled", true)
	var boss: bool = root.get_node("Data").enemies[id].get("boss", false)
	hero.stats = hero.BASE_STATS.duplicate()
	hero.hp = 1000000.0 if boss else 100000.0
	hero.stats.max_hp = hero.hp
	var ground_y: float = hero.global_position.y
	var enemy = run.room.spawn_enemy(id, hero.global_position + Vector2(26, -2), true)
	await physics_frame
	await physics_frame
	var start_hp: float = hero.hp
	var t := 0.0
	var hits := 0
	var limit := BOSS_LIMIT if boss else DUEL_LIMIT
	var pressed := false
	var last_hp: float = enemy.hp
	paused = false
	root.get_node("Game").set("cutscene", false)
	while t < limit and is_instance_valid(enemy) and not enemy.is_dead():
		# Keep them face to face: an enemy that walks off or flies up is followed.
		if boss:
			# A boss is pinned in front of a hero standing on the floor: hanging him
			# in the air under a flying boss drops him out of the room (void fall).
			hero.global_position.y = ground_y
			enemy.global_position = hero.global_position + Vector2(24.0, -12.0)
			hero.facing = 1
		else:
			# Pinned too: a knocked-back or retreating body would otherwise leave the
			# swing's reach and the bot, which never chases, would measure its patience.
			hero.global_position.y = ground_y
			enemy.global_position = Vector2(hero.global_position.x + 24.0, enemy.global_position.y if enemy.stats.get("behaviour", "") == "flyer" else ground_y)
			if enemy.stats.get("behaviour", "") == "flyer":
				enemy.global_position.y = ground_y - 10.0
			hero.facing = 1
		# A boss's death slows time to a crawl for its theatre; physics ticks
		# (and this loop) would crawl with it.
		Engine.time_scale = 1.0
		pressed = not pressed
		if pressed:
			Input.action_press("attack")
		else:
			Input.action_release("attack")
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		if is_instance_valid(enemy) and enemy.hp < last_hp - 0.01:
			hits += 1
			last_hp = enemy.hp
	Input.action_release("attack")
	var killed: bool = not is_instance_valid(enemy) or enemy.is_dead()
	if is_instance_valid(enemy) and not killed:
		enemy.queue_free()
	await _wait(0.3)
	# Room bookkeeping: the probe's kills must not open or close anything.
	run.room.alive = maxi(0, run.room.alive)
	var taken: float = start_hp - hero.hp
	return {"ttk": t, "hits": hits, "dps_taken": taken / maxf(t, 0.01), "killed": killed, "boss": boss}


func _census(run, data) -> void:
	var rooms: Array = run.ROOMS
	var total_time := 0.0
	var total_essence := 0.0
	var room_rows: PackedStringArray = []
	for path in rooms:
		var scene = load(path).instantiate()
		var count := 0
		var hp := 0.0
		var essence := 0.0
		var fight := 0.0
		var bosses: PackedStringArray = []
		for spawn in scene.get_node("Spawns").get_children():
			var id: String = spawn.get("enemy_id")
			var spec: Dictionary = data.enemies.get(id, {})
			count += 1
			hp += float(spec.get("hp", 0))
			essence += float(spec.get("essence", 10))
			if _results.has(id):
				fight += _results[id].ttk
			if spec.get("boss", false):
				bosses.append(id)
		var width := float(scene.get("width"))
		var room_time := fight * FIGHT_OVERHEAD + width / TRAVERSAL_SPEED
		total_time += room_time
		total_essence += essence
		room_rows.append("| %s | %d | %d | %d | %.0f s | %s |" % [path.get_file().get_basename(), count, int(hp), int(essence), room_time, ", ".join(bosses)])
		scene.free()
	var levels := _levels(total_essence)
	var places := {}
	for path in rooms:
		places[data.chapter_for(path).get("id", path)] = true
	var doors := places.size()
	var gifts := levels + doors
	var common := ["possessed_villager", "cultist", "shade", "zealot", "wraith"]
	var common_ttk := 0.0
	var n := 0
	for id in common:
		if _results.has(id):
			common_ttk += _results[id].ttk
			n += 1
	common_ttk /= maxf(1.0, n)

	_lines.append("# Balance probe")
	_lines.append("")
	_lines.append("*Generated by `scripts/tools/balance_probe.gd` — measured in the engine, not estimated. Re-run after any change to `data/enemies` or `Player.BASE_STATS`.*")
	_lines.append("")
	_lines.append("## Verdict against docs/BALANCE.md")
	_lines.append("")
	_lines.append("| Target | Wanted | Measured | |")
	_lines.append("|---|---|---|---|")
	_lines.append("| Common enemy TTK, fresh hero | 2–3 s | %.1f s | %s |" % [common_ttk, _mark(common_ttk >= 1.5 and common_ttk <= 3.5)])
	_lines.append("| Upgrades per run (levels + place doors) | 10–14 | %d (%d levels + %d doors) | %s |" % [gifts, levels, doors, _mark(gifts >= 10 and gifts <= 14)])
	_lines.append("| Run length (estimate) | 25–30 min | %.0f min | %s |" % [total_time / 60.0, _mark(total_time >= 1500.0 and total_time <= 1800.0)])
	for boss_id in ["blind_preacher", "knight_of_ash", "ophanim"]:
		if _results.has(boss_id):
			var r: Dictionary = _results[boss_id]
			var mini: bool = boss_id != "ophanim"  # the preacher and the knight are mid-bosses
			var wanted := "1.5–2.5 min" if mini else "3–4 min"
			var real: float = r.ttk * 2.5  # dodging, phases: pure damage time × 2.5 (docs/BALANCE.md §6)
			var ok: bool = real >= 90.0 and real <= 150.0 if mini else real >= 180.0 and real <= 240.0
			_lines.append("| %s fight | %s | %.0f s damage phase → ~%.1f min | %s |" % [boss_id, wanted, r.ttk, real / 60.0, _mark(ok)])
	_lines.append("")
	_lines.append("## Duels (fresh hero, no gifts, standing and swinging)")
	_lines.append("")
	_lines.append("| Enemy | TTK | Hits | Damage taken while face-tanking |")
	_lines.append("|---|---|---|---|")
	var ids: Array = _results.keys()
	ids.sort()
	for id in ids:
		var r: Dictionary = _results[id]
		_lines.append("| %s%s | %.1f s%s | %d | %.1f HP/s |" % [id, " (boss)" if r.boss else "", r.ttk, "" if r.killed else " (limit)", r.hits, r.dps_taken])
	_lines.append("")
	_lines.append("## Rooms")
	_lines.append("")
	_lines.append("| Room | Enemies | Total HP | Essence | Est. time | Bosses |")
	_lines.append("|---|---|---|---|---|---|")
	_lines.append_array(room_rows)
	_lines.append("")
	_lines.append("Room time = Σ TTK × %.1f (walking, dodging, waiting for openings) + width / %d px/s. Both constants are guesses until a human playtest replaces them; the TTKs are real." % [FIGHT_OVERHEAD, int(TRAVERSAL_SPEED)])


## Levels reached from a pile of essence: 140 × 1.3^(level−1) each (Game.essence_needed).
func _levels(essence: float) -> int:
	var level := 1
	while essence >= 140.0 * pow(1.3, level - 1):
		essence -= 140.0 * pow(1.3, level - 1)
		level += 1
	return level - 1


func _mark(ok: bool) -> String:
	return "✅" if ok else "⚠️"


func _wait(seconds: float) -> void:
	Engine.time_scale = 1.0
	await create_timer(seconds, true, false, true).timeout
	await process_frame
