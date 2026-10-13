extends SceneTree
## A game is the engine's data with its pack laid over it (DataDoc, docs/GAME_PACKS.md):
##   godot --headless -s scripts/tools/data_roots_test.gd
## A pack's one-document file changes only the keys it names, its lists replace
## the engine's, its collection entries replace the engine's by id, and with
## "inherit" a collection it does not list comes from the pack alone.
## The pack is written under user://, never into the repository.
## Deliberately untyped w.r.t. game classes, like every -s tool script.

const PACK := "user://data_roots_test/data"

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failed = true


func _write(file: String, value) -> void:
	DirAccess.make_dir_recursive_absolute(PACK.path_join(file).get_base_dir())
	var out := FileAccess.open(PACK.path_join(file), FileAccess.WRITE)
	out.store_string(JSON.stringify(value))
	out.close()


func _run() -> void:
	var doc = load("res://scripts/data/data_doc.gd")
	var data = root.get_node("Data")
	_write("hero.json", {"feel": {"parry_window": 0.5}})
	_write("game.json", {"rooms": ["res://scenes/rooms/church.tscn"], "paths": {"grace": {"color": "#00ff00"}}})
	_write("enemies/cultist.json", {"id": "cultist", "name": "PACK_CULTIST", "hp": 1})
	_write("dialogues/only_mine.json", {"id": "only_mine", "nodes": {}})
	var roots: Array[String] = ["res://data", PACK]

	var hero: Dictionary = doc.doc("hero.json", roots)
	_check(is_equal_approx(float(hero.feel.parry_window), 0.5), "the pack's key wins")
	_check(hero.feel.has("slam_speed") and hero.has("stats"), "the keys it does not name stay the engine's")
	var game: Dictionary = doc.doc("game.json", roots)
	_check(game.rooms == ["res://scenes/rooms/church.tscn"], "a list is the pack's whole")
	_check(game.paths.grace.color == "#00ff00" and game.paths.grace.has("icon") and game.paths.has("will"),
		"a table merges key by key")
	_check(doc.doc("nothing_here.json", roots).is_empty() and not doc.exists("nothing_here.json", roots), "a file no root has is {}")
	_check(doc.relative("res://data/gore.json") == "gore.json", "an engine path names the same file in every root")

	var saved: Dictionary = data.game
	data.game = game
	var enemies: Dictionary = data._load_collection("enemies", roots)
	_check(enemies.cultist.hp == 1 and enemies.cultist._source.begins_with(PACK), "a pack's entry replaces the engine's by id")
	_check(enemies.size() > 5, "the engine's other enemies are still there")
	data.game = {"inherit": ["enemies"]}
	_check(data._load_collection("enemies", roots).size() == enemies.size(), "an inherited collection is the engine's and the pack's")
	var dialogues: Dictionary = data._load_collection("dialogues", roots)
	_check(dialogues.keys() == ["only_mine"], "a collection not inherited is the pack's alone (%d)" % dialogues.size())
	data.game = saved

	for file in ["hero.json", "game.json", "enemies/cultist.json", "dialogues/only_mine.json"]:
		DirAccess.remove_absolute(PACK.path_join(file))
	for dir in ["enemies", "dialogues", ""]:
		DirAccess.remove_absolute(PACK.path_join(dir))
	DirAccess.remove_absolute(PACK.get_base_dir())
	print("data_roots_test: %s" % ("FAILED" if _failed else "passed"))
	quit(1 if _failed else 0)
