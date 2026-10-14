extends SceneTree
## Flags that outlive their night (docs/CAMPAIGN.md §5, engine E1, Campaign):
## a game.json "flags_kept" flag set in a night is written into the profile
## under that night's id, a group remembers its last answer, the next night of
## another chapter starts with it and the same night does not, and the night of
## the day, the yard, an online night and a tool script neither write nor read.
## Puts the profile back the way it found it.
##   godot --headless --path . -s scripts/tools/kept_flags_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _run() -> void:
	var campaign = load("res://scripts/run/campaign.gd")
	var profile = root.get_node("Profile")
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	var net = root.get_node("Net")
	var saved_profile: Dictionary = profile.data.duplicate(true)
	var saved_list = data.game.get("flags_kept")
	var first_id := str(data.game.get("id", ""))

	# a list of our own, so the test does not lean on any chapter's data
	data.game["flags_kept"] = ["fact_learnt", ["answer_a", "answer_b", "answer_c"]]
	profile.data.kept = {}
	game.new_run()

	campaign.allow_in_tools = false
	game.night = ""
	game.set_flag("fact_learnt")
	_check(game.flags.has("fact_learnt") and profile.data.kept.is_empty(), "a tool script sets the flag but writes nothing to the profile")
	campaign.allow_in_tools = true

	game.set_flag("fact_learnt")
	_check(str(profile.data.kept.get("fact_learnt", "")) == first_id, "a kept fact is written under the first night's id (the game's: %s)" % first_id)
	game.set_flag("night_only")
	_check(not profile.data.kept.has("night_only"), "a flag of the night alone stays out of the profile")
	game.apply_effect({"set_flags": ["answer_a"]})
	_check(str(profile.data.kept.get("answer_a", "")) == first_id, "a choice's effect writes a kept answer too")
	game.night = "seir"
	game.apply_effect({"set_flags": ["answer_b"]})
	_check(not profile.data.kept.has("answer_a") and str(profile.data.kept.get("answer_b", "")) == "seir",
		"a group remembers only its last answer, under the night that gave it")

	# the next nights
	var flags := {}
	game.night = "marah"
	campaign.lay(flags)
	_check(flags.has("fact_learnt") and flags.has("answer_b") and not flags.has("answer_a") and not flags.has("night_only"),
		"another chapter's night starts with what was kept")
	flags = {}
	game.night = "seir"
	campaign.lay(flags)
	_check(flags.has("fact_learnt") and not flags.has("answer_b"), "the night that wrote an answer does not start with it")
	flags = {}
	game.night = ""
	campaign.lay(flags)
	_check(not flags.has("fact_learnt") and flags.has("answer_b"), "nor does the first night start with its own fact")
	flags["chosen_tonight"] = true
	game.night = "marah"
	campaign.relay(flags)
	_check(flags.has("fact_learnt") and flags.has("answer_b") and flags.has("chosen_tonight"),
		"switching the night at its start lays that night's (room= of another night)")

	# a skipped choice leaves the old answer alone: nothing is written without a flag
	game.night = "seir"
	game.new_run()
	_check(str(profile.data.kept.get("answer_b", "")) == "seir", "a night with the choice skipped keeps the old answer")

	# where nothing is remembered
	for case in [["daily", "the night of the day"], ["practice", "the practice yard"], ["online", "an online night"]]:
		match case[0]:
			"daily": game.daily = "2026-10-14"
			"practice": game.practice = "training_dummy"
			"online": net.active = true
		var before: Dictionary = profile.data.kept.duplicate()
		game.night = "marah"
		game.set_flag("answer_c")
		flags = {}
		campaign.lay(flags)
		_check(profile.data.kept == before and flags.is_empty(), "%s neither writes nor reads kept flags" % case[1])
		game.daily = ""
		game.practice = ""
		net.active = false

	# an old profile without "kept" loads, and a night starts with nothing kept
	var old: Dictionary = profile._defaults()
	old.erase("kept")
	old.erase("dawns")
	var merged: Dictionary = profile._defaults()
	merged.merge(old, true)
	_check(merged.get("kept") is Dictionary and (merged.kept as Dictionary).is_empty(), "an old profile reads an empty kept list")
	profile.data.erase("kept")
	flags = {}
	campaign.lay(flags)
	_check(flags.is_empty(), "a profile without kept flags lays nothing")

	# the game's own list names flags somebody writes
	data.game["flags_kept"] = saved_list
	var real_kept: Array = campaign.kept_list()
	_check(not real_kept.is_empty() and campaign.group_of("version_man") == ["version_man"]
		and campaign.group_of("voice_no").has("voice_yes"), "game.json keeps chapter I's facts and answers")

	campaign.allow_in_tools = false
	if saved_list == null:
		data.game.erase("flags_kept")
	profile.data = saved_profile
	profile.save()
	game.night = ""
	game.new_run()
	_check(profile.data == saved_profile, "the profile is put back as it was found")
	print("kept_flags_test: %s" % ("OK" if failures == 0 else "%d failure(s)" % failures))
	quit(1 if failures else 0)
