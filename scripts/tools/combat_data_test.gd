extends SceneTree
## A game's combat is data (data/hero.json "moves" and "enemy_ai", docs/GAME_PACKS.md):
##   godot --headless -s scripts/tools/combat_data_test.gd
## A move turned off is gone (the slam is a plain fall, a backstab a plain blow)
## and back on the next apply; the enemy numbers reach the class, keep their
## types and come back as they were; one enemy's own "ai" wins over the game's.
## Exit code 1 on any failure.
## Deliberately untyped w.r.t. game classes, like every -s tool script.

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failed = true


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	var data = root.get_node("Data")
	var P = load("res://scripts/player/player.gd")
	var E = load("res://scripts/enemies/enemy.gd")
	var file = JSON.parse_string(FileAccess.get_file_as_string("res://data/hero.json"))
	var moves: Array = file.moves.keys()
	moves.sort()
	var known: Array = P.MOVE_KEYS.duplicate()
	known.sort()
	_check(moves == known, "hero.json names every move the hero has (%d)" % moves.size())
	var ai: Array = file.enemy_ai.keys()
	ai.sort()
	var ai_known: Array = E.AI_KEYS.duplicate()
	ai_known.sort()
	_check(ai == ai_known, "hero.json names every enemy AI number (%d)" % ai.size())
	# the game's numbers: the engine's file with a game pack's laid over it, when one is
	var game: Dictionary = data.hero.enemy_ai
	_check(_same(E.enemy_ai(), game), "after loading, Enemy holds the game's numbers")
	_check(_same(E._ai_defaults, file.enemy_ai), "the script's own numbers are the engine file's")

	# --- moves ---
	P.apply_hero({"moves": {"slam": false, "backstab": false, "made_up": false}})
	_check(not P.can_move("slam") and not P.can_move("backstab") and P.can_move("lunge"),
		"a move turned off is off, the rest stay on")
	var room = load("res://scenes/rooms/graveyard.tscn").instantiate()
	root.add_child(room)
	var player = load("res://scenes/player/player.tscn").instantiate()
	room.add_child(player)
	player.global_position = Vector2(300, 220)
	await _frames(40)
	var floor_y: float = player.global_position.y
	player.global_position = Vector2(300, floor_y - 100.0)
	await _frames(2)
	Input.action_press("move_down")
	await _frames(2)
	Input.action_release("move_down")
	await _frames(1)
	_check(not player._slamming, "with the slam off, down in the air is no slam")
	await _frames(60)

	var enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	enemy.enemy_id = "possessed_villager"
	room.add_child(enemy)
	await _frames(2)
	enemy.set_physics_process(false)
	var full: float = enemy.hp
	_check(enemy.is_unaware(), "the enemy starts unaware")
	enemy._apply_damage(10.0, enemy.global_position + Vector2(-20, 0), false, false, 0.0, 2.5)
	_check(is_equal_approx(full - enemy.hp, 10.0 * (1.0 - clampf(float(enemy.stats.get("armor", 0.0)), 0.0, 0.5))),
		"with the backstab off, a blow on a sleeper is a plain blow (%.1f)" % (full - enemy.hp))

	P.apply_hero(data.hero)
	_check(P.can_move("slam") and P.can_move("backstab"), "laying the file again gives every move back")

	# --- enemy AI ---
	P.apply_hero({"enemy_ai": {"crowd_step": 40, "attackers_per_side": 1.0, "sight_defaults": {"walker": [300, 80, 40]}, "nonsense": 1}})
	_check(E.CROWD_STEP is float and is_equal_approx(E.CROWD_STEP, 40.0), "a number reaches the class as the float it was declared")
	_check(E.ATTACKERS_PER_SIDE is int and E.ATTACKERS_PER_SIDE == 1, "a whole number stays an int")
	_check(is_equal_approx(float(E.SIGHT_DEFAULTS.walker[0]), 300.0), "a table is laid on whole")
	_check(is_equal_approx(enemy._ai("crowd_step"), 40.0), "a body without its own reads the game's")
	enemy.stats["ai"] = {"crowd_step": 5.0}
	_check(is_equal_approx(enemy._ai("crowd_step"), 5.0), "a body's own \"ai\" wins")
	_check(is_equal_approx(enemy._ai("flock_space"), E.FLOCK_SPACE), "and leaves the rest to the game")
	P.apply_hero({})
	_check(_same(E.enemy_ai(), file.enemy_ai), "a second apply starts from the defaults")
	P.apply_hero(data.hero)
	_check(_same(E.enemy_ai(), game), "laying the file again puts every number back")
	room.queue_free()
	print("combat_data_test: %s" % ("FAILED" if _failed else "passed"))
	quit(1 if _failed else 0)


func _same(a, b) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	if a is Array and b is Array:
		return a.size() == b.size() and range(a.size()).all(func(i): return _same(a[i], b[i]))
	if a is Dictionary and b is Dictionary:
		return a.size() == b.size() and a.keys().all(func(k): return b.has(k) and _same(a[k], b[k]))
	return a == b
