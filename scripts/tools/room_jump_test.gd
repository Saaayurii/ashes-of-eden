extends SceneTree
## `room=` on the command line, which is how a room is reached while it is
## being worked on:
##
##     Godot --path . scenes/run/run.tscn -- room=hell_gate
##
## Worth a test because the failure is quiet: a name that does not match any
## room simply starts the night from the beginning, which looks like the
## argument being ignored rather than misspelled.

## Loaded rather than preloaded, and after a frame: run.gd names the
## autoloads, and a tool script's own compile happens before they exist.
var _failed := false


func _init() -> void:
	_go.call_deferred()


func _go() -> void:
	await process_frame
	var Run: GDScript = load("res://scripts/run/run.gd")
	var names: PackedStringArray = Run.room_names()
	_check(names.size() == int(Run.get_script_constant_map()["ROOMS"].size()), "every room has a name")
	_check(names[0] == "village_night", "the first is the village")
	_check(names[names.size() - 1] == "hell_gate", "the last is the gate")

	_check(Run.room_from_args(PackedStringArray([])) == -1,
		"no argument starts the night from the beginning")
	_check(Run.room_from_args(PackedStringArray(["something_else"])) == -1,
		"an unrelated argument is left alone")
	_check(Run.room_from_args(PackedStringArray(["room=hell_gate"])) == names.size() - 1,
		"a name finds its room")
	_check(Run.room_from_args(PackedStringArray(["room=village_night"])) == 0,
		"the first room by name")
	_check(Run.room_from_args(PackedStringArray(["room=7"])) == 7, "an index is taken as one")
	_check(Run.room_from_args(PackedStringArray(["room= church "])) == names.find("church"),
		"spaces around the name do not matter")
	# Out of range is clamped rather than refused: asking for room 99 means
	# "the last one" far more often than it means a typo worth stopping for.
	_check(Run.room_from_args(PackedStringArray(["room=99"])) == names.size() - 1,
		"past the end is the last room")
	_check(Run.asks_for_a_place(PackedStringArray(["--studio-preview", "practice=ash_archer"])),
		"a preview asked for an enemy skips the menu")
	_check(Run.asks_for_a_place(PackedStringArray(["--studio-preview", "room=hell_gate"])), "and one asked for a room")
	_check(not Run.asks_for_a_place(PackedStringArray(["--studio-preview"])), "a plain preview shows the menu")
	_check(not Run.asks_for_a_place(PackedStringArray(["practice=cultist"])), "and nothing without the preview flag")
	_check(Run.room_from_args(PackedStringArray(["room=-3"])) == 0, "before the start is the first")
	_check(Run.room_from_args(PackedStringArray(["room=nowhere"])) == -1,
		"a name that is not a room falls back to the beginning")

	print("ROOM JUMP TEST " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)


func _check(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failed = true
