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
## Walking to a seal and breaking it (45 HP, ~4 swings) — a guess, stated.
const SEAL_TIME := 4.0
const FREE_TIME := 20.0

var _results := {}
## Common enemies free to move (docs/ENEMY_AI.md: they pace, queue, give
## ground): what a hero who stands and swings really takes from them.
var _free := {}
## The moves' damage per second on the straw man (docs/TECHNIQUES.md).
var _moves := {}
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
	# the straw man and the Ophanim's seals are not fights of their own
	# Before the duels (a boss's death plays the chapter's end, which stops
	# play), and in the practice yard: a flat floor to walk on, nothing counts.
	var game = root.get_node("Game")
	game.practice = "training_dummy"
	run._load_room(run.PRACTICE_INDEX)
	await _wait(1.0)
	_clear_room(run)
	await _wait(0.3)
	for id in ["possessed_villager", "cultist", "fallen_guard", "shade", "raven"]:
		_free[id] = await _free_duel(run, id)
		print("  free %-15s hurts %5.1f HP/s" % [id, _free[id]])
	_moves = await _move_rates(run)
	game.practice = ""
	if OS.get_cmdline_user_args().has("quick"):
		quit(0)
		return
	run._load_room(0)
	await _wait(1.0)
	_clear_room(run)
	var ids: Array = []
	for id in data.enemies:
		if data.enemies[id].get("bestiary", true) and data.enemies[id].get("behaviour", "walker") != "seal":
			ids.append(id)
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
		if enemy.get("_sealed"):
			# Warded: nothing reaches it until its seals break. A player walks to
			# each and breaks it; the probe breaks one per seal-TTK plus a walk.
			var seals: Array = []
			for e in get_nodes_in_group("enemies"):
				if e.stats.get("behaviour", "") == "seal" and not e.is_dead():
					seals.append(e)
			if not seals.is_empty():
				Input.action_release("attack")
				await _wait(SEAL_TIME)
				t += SEAL_TIME
				seals[0].take_damage(99999.0)
				continue
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


## One common enemy, left to move as it likes, against a hero who stands and
## swings for FREE_TIME: the damage it deals when it paces and gives ground.
func _free_duel(run, id: String) -> float:
	var hero = run.player
	hero.set("_dead", false)
	hero.set("controls_enabled", true)
	paused = false
	root.get_node("Game").set("cutscene", false)
	hero.stats = hero.BASE_STATS.duplicate()
	hero.stats.max_hp = 1000000.0
	hero.hp = hero.stats.max_hp
	var anchor: Vector2 = run.room.player_spawn.global_position + Vector2(200, 0)
	hero.global_position = anchor
	await _wait(0.3)
	anchor = hero.global_position
	var enemy = run.room.spawn_enemy(id, anchor + Vector2(90, -2), true)
	# endless, but at full health: a fraction over 1 would close every phase-gated attack
	enemy.set("_max_hp", 1000000.0)
	enemy.set("hp", 1000000.0)
	var t := 0.0
	var pressed := false
	while t < FREE_TIME and is_instance_valid(enemy):
		hero.global_position = anchor
		hero.facing = 1 if enemy.global_position.x >= anchor.x else -1
		pressed = not pressed
		if pressed:
			Input.action_press("attack")
		else:
			Input.action_release("attack")
		Engine.time_scale = 1.0
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	Input.action_release("attack")
	if OS.get_cmdline_user_args().has("debug"):
		print("    debug: paused=%s cutscene=%s controls=%s dead=%s hero=%s enemy=%s state=%s hp=%s/%s anim=%s" % [paused,
			root.get_node("Game").cutscene, hero.controls_enabled, hero.is_dead(), hero.global_position,
			enemy.global_position if is_instance_valid(enemy) else "-", enemy.state if is_instance_valid(enemy) else "-",
			hero.hp, hero.stats.max_hp, hero.body.animation])
		if is_instance_valid(enemy):
			print("    enemy: cd=%.2f rank=%d pace=%.0f disengage=%.2f target=%s aware=%s" % [enemy._attack_cd, enemy._crowd_rank, enemy._pace_goal, enemy._disengage_left, enemy._target, enemy.aware])
	var taken: float = hero.stats.max_hp - hero.hp
	if is_instance_valid(enemy):
		enemy.queue_free()
	await _wait(0.3)
	run.room.alive = maxi(0, run.room.alive)
	return taken / FREE_TIME


## Damage per second of each way of fighting on the straw man, 10 s each: the
## chain, the lunge over and over, the cleave charged and let go, the sweep.
func _move_rates(run) -> Dictionary:
	var hero = run.player
	hero.set("_dead", false)
	hero.set("controls_enabled", true)
	paused = false
	root.get_node("Game").set("cutscene", false)
	hero.stats = hero.BASE_STATS.duplicate()
	hero.stats.crit_chance = 0.0
	var anchor: Vector2 = run.room.player_spawn.global_position + Vector2(200, 0)
	hero.global_position = anchor
	await _wait(0.3)
	anchor = hero.global_position
	var dummy = run.room.spawn_enemy("training_dummy", anchor + Vector2(30, -2), true)
	dummy.stats.hp = 1000000.0
	dummy.set("_max_hp", 1000000.0)
	var out := {}
	var post: Vector2 = anchor + Vector2(30, 0)
	for way in ["chain", "lunge", "cleave", "sweep"]:
		dummy.hp = 1000000.0
		var dealt := 0.0
		var t := 0.0
		while t < 10.0:
			# the straw man stays on its post, and every blow is banked before it
			# can fill up again (it does after two quiet seconds)
			dealt += 1000000.0 - dummy.hp
			dummy.hp = 1000000.0
			dummy.global_position = Vector2(post.x, dummy.global_position.y)
			hero.global_position = anchor if way != "lunge" else hero.global_position
			hero.facing = 1
			match way:
				"chain":
					Input.action_press("attack")
					await physics_frame
					Input.action_release("attack")
					await physics_frame
					t += 2.0 / Engine.physics_ticks_per_second
				"sweep":
					Input.action_press("move_down")
					Input.action_press("attack")
					await physics_frame
					Input.action_release("attack")
					await physics_frame
					Input.action_release("move_down")
					t += 2.0 / Engine.physics_ticks_per_second
				"lunge":
					hero.global_position = anchor + Vector2(-40, 0)
					for action in ["move_left", "move_right", "attack"]:
						Input.action_press(action)
						await physics_frame
						Input.action_release(action)
						await physics_frame
					await _wait(0.45)
					t += 6.0 / Engine.physics_ticks_per_second + 0.45
				"cleave":
					Input.action_press("attack")
					await _wait(hero.CHARGE_AFTER + hero.CHARGE_FULL + 0.3)
					Input.action_release("attack")
					await _wait(0.5)
					t += hero.CHARGE_AFTER + hero.CHARGE_FULL + 0.8
		dealt += 1000000.0 - dummy.hp
		out[way] = dealt / t
		if OS.get_cmdline_user_args().has("debug"):
			print("    move debug: dummy=%s hero=%s hp=%s anim=%s" % [dummy.global_position, hero.global_position, dummy.hp, hero.body.animation])
		print("  move %-8s %5.1f dmg/s" % [way, out[way]])
		await _wait(0.6)
	Input.action_release("attack")
	dummy.queue_free()
	await _wait(0.3)
	run.room.alive = maxi(0, run.room.alive)
	return out


func _census(run, data) -> void:
	var rooms: Array = run.ROOMS
	var total_time := 0.0
	var total_essence := 0.0
	var room_rows: PackedStringArray = []
	var route = load("res://scripts/run/route.gd")
	for path in rooms:
		# a fork's ways share one slot of the night: each counts for its share
		var fork: Dictionary = route.fork_holding(path)
		var share: float = 1.0 / fork.options.size() if not fork.is_empty() else 1.0
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
		total_time += room_time * share
		total_essence += essence * share
		room_rows.append("| %s%s | %d | %d | %d | %.0f s | %s |" % [path.get_file().get_basename(), " (one way of a fork)" if share < 1.0 else "", count, int(hp), int(essence), room_time, ", ".join(bosses)])
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
	_append_playtests(total_time)
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
	_lines.append("## Common enemies free to move")
	_lines.append("")
	_lines.append("The duels above pin the enemy in front of the sword. Here it paces, queues and gives ground as it does in play (docs/ENEMY_AI.md) against a hero who stands and swings for %d s." % int(FREE_TIME))
	_lines.append("")
	_lines.append("| Enemy | Pinned | Free |")
	_lines.append("|---|---|---|")
	for id in _free:
		_lines.append("| %s | %.1f HP/s | %.1f HP/s |" % [id, _results.get(id, {}).get("dps_taken", 0.0), _free[id]])
	_lines.append("")
	_lines.append("## The moves on the straw man")
	_lines.append("")
	_lines.append("Damage per second over 10 s of doing only that (docs/TECHNIQUES.md): a move should be worth choosing, never worth spamming.")
	_lines.append("")
	_lines.append("| Way | Damage/s | vs the chain |")
	_lines.append("|---|---|---|")
	for way in _moves:
		_lines.append("| %s | %.1f | ×%.2f |" % [way, _moves[way], _moves[way] / maxf(0.01, _moves.get("chain", 1.0))])
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


## Real hands: every run recorded by the Playtest autoload (user://playtest/*.jsonl).
## The estimate above guesses walking and dodging; these do not.
func _append_playtests(estimate: float) -> void:
	var dir := DirAccess.open("user://playtest")
	var files: Array = []
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".jsonl"):
				files.append("user://playtest/" + f)
	_lines.append("")
	_lines.append("## Playtests (%d recorded runs)" % files.size())
	_lines.append("")
	if files.is_empty():
		_lines.append("No recorded runs yet. Play the chapter (any build, solo): every run is written to `user://playtest/` and summarised here on the next probe.")
		return
	var room_times := {}
	var room_damage := {}
	var deaths := {}
	var bosses := {}
	var finished: Array = []
	var moves := {}  # special move -> times used (docs/TECHNIQUES.md)
	for path in files:
		for line in FileAccess.get_file_as_string(path).split("\n", false):
			var e = JSON.parse_string(line)
			if not e is Dictionary:
				continue
			match str(e.get("e", "")):
				"room_clear":
					room_times.get_or_add(e.room, []).append(float(e.seconds))
					room_damage.get_or_add(e.room, []).append(float(e.damage))
				"death":
					deaths[e.room] = int(deaths.get(e.room, 0)) + 1
				"boss":
					bosses.get_or_add(e.room, []).append(float(e.seconds))
				"run_end":
					if bool(e.get("won", false)):
						finished.append(float(e.seconds))
				"move":
					moves[str(e.get("id", ""))] = int(moves.get(str(e.get("id", "")), 0)) + 1
	if not finished.is_empty():
		_lines.append("Finished runs: %d, median %.0f min (estimate above: %.0f min)." % [finished.size(), _median(finished) / 60.0, estimate / 60.0])
	else:
		_lines.append("No run reached the end yet (estimate above: %.0f min)." % (estimate / 60.0))
	_lines.append("")
	_lines.append("| Room | Clears | Median time | Median damage (bar) | Deaths | Boss fight |")
	_lines.append("|---|---|---|---|---|---|")
	var names: Array = room_times.keys()
	for r in deaths.keys() + bosses.keys():
		if not names.has(r):
			names.append(r)
	for r in names:
		var times: Array = room_times.get(r, [])
		var hurt: Array = room_damage.get(r, [])
		var boss: Array = bosses.get(r, [])
		_lines.append("| %s | %d | %s | %s | %d | %s |" % [r, times.size(),
			"%.0f s" % _median(times) if not times.is_empty() else "—",
			"%.0f %%" % (_median(hurt) * 100.0) if not hurt.is_empty() else "—",
			int(deaths.get(r, 0)),
			"%.1f min" % (_median(boss) / 60.0) if not boss.is_empty() else "—"])
	_append_moves(moves, files.size())


## After the rooms: which moves real hands used, so a move nobody finds shows.
func _append_moves(moves: Dictionary, runs: int) -> void:
	_lines.append("")
	_lines.append("| Move | Times used | Per run |")
	_lines.append("|---|---|---|")
	for id in ["lunge", "cleave", "sweep", "rising", "dash_strike", "slam", "wall_jump", "riposte", "backstab"]:
		var n := int(moves.get(id, 0))
		_lines.append("| %s | %d | %.1f |" % [id, n, float(n) / maxf(1.0, runs)])


func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])
