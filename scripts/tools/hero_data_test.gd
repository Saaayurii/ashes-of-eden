extends SceneTree
## How the hero handles is data (data/hero.json, Player.apply_hero, docs/GAME_PACKS.md):
##   godot --headless -s scripts/tools/hero_data_test.gd
## The file names every key the script has and the class holds its values, a
## value laid on reaches the class and a fresh body, an unknown key is skipped,
## and laying the file again puts every value back. Exit code 1 on any failure.
## Deliberately untyped w.r.t. game classes, like every -s tool script.

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failed = true


func _same(a, b) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	if a is Array and b is Array:
		return a.size() == b.size() and range(a.size()).all(func(i): return _same(a[i], b[i]))
	if a is Dictionary and b is Dictionary:
		return a.size() == b.size() and a.keys().all(func(k): return b.has(k) and _same(a[k], b[k]))
	return a == b


func _keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys


func _run() -> void:
	var data = root.get_node("Data")
	var P = load("res://scripts/player/player.gd")
	var file = JSON.parse_string(FileAccess.get_file_as_string("res://data/hero.json"))
	_check(file is Dictionary and data.hero.has("feel") and data.hero.has("stats"), "Data loads hero.json")
	var defaults: Dictionary = P._hero_defaults
	# the file is the truth and the studio rewrites it; the script's numbers are only the fallback
	# for a game whose file leaves a key out, so the keys must match, the values need not
	_check(_keys(defaults.feel) == _keys(file.feel), "the file names every feel key the script has (%d)" % file.feel.size())
	_check(_keys(defaults.stats) == _keys(file.stats), "the file names every BASE_STATS key (%d)" % file.stats.size())
	_check(_same(P.hero_feel(), file.feel), "after loading, the class holds the file's feel")
	_check(file.feel.size() == P.FEEL_KEYS.size(), "every FEEL_KEYS name is in the file")
	_check(P.BASE_STATS.max_jumps is int, "a whole-number stat stays an int after loading")

	P.apply_hero({"stats": {"max_hp": 150.0, "nonsense": 3}, "feel": {"parry_window": 0.5, "combo_window": 2, "made_up": 1}})
	_check(is_equal_approx(P.PARRY_WINDOW, 0.5), "feel reaches the class (PARRY_WINDOW 0.5)")
	_check(P.COMBO_WINDOW is float and is_equal_approx(P.COMBO_WINDOW, 2.0), "an int from JSON lands as the float the script declared")
	_check(is_equal_approx(P.BASE_STATS.max_hp, 150.0) and not P.BASE_STATS.has("nonsense"), "stats reach BASE_STATS, unknown keys skipped")
	var hero = load("res://scenes/player/player.tscn").instantiate()
	_check(is_equal_approx(float(hero.stats.max_hp), 150.0), "a fresh body is built from the new stats")
	hero.free()
	P.apply_hero({})
	_check(is_equal_approx(P.PARRY_WINDOW, float(defaults.feel.parry_window)) and is_equal_approx(P.BASE_STATS.max_hp, float(defaults.stats.max_hp)),
		"a second apply starts from the defaults, not from the last one")
	P.apply_hero(data.hero)
	_check(_same(P.hero_feel(), file.feel), "laying the file again puts every value back")
	print("hero_data_test: %s" % ("FAILED" if _failed else "passed"))
	quit(1 if _failed else 0)
