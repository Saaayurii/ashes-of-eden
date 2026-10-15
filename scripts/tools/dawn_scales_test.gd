extends SceneTree
## The scales of dawns (docs/CHAPTER7.md §9, engine E2, Dawns): a dawn is
## written down as the path that led by 2, or "level"; the night of the day and
## the yard write nothing; a night with "seed": "dawns" (the Heavenly Hall)
## starts with +1 on a path for every other night that dawned leaning that way,
## nothing for a level one, and the flag that names how the pans hang; a loaded
## checkpoint does not weigh twice. Puts the profile back the way it found it.
##   godot --headless --path . -s scripts/tools/dawn_scales_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _lean(game, grace: int, temptation: int, will: int) -> void:
	game.alignment = {"grace": grace, "temptation": temptation, "will": will}


func _run() -> void:
	var campaign = load("res://scripts/run/campaign.gd")
	var dawns = load("res://scripts/run/dawns.gd")
	var profile = root.get_node("Profile")
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	var saves = root.get_node("Saves")
	var saved_profile: Dictionary = profile.data.duplicate(true)
	var first: String = campaign.night_key("")

	print("the night on the scales")
	var weighed := ""
	for night in data.nights():
		if dawns.seeds(str(night.get("id", ""))):
			weighed = str(night.get("id", ""))
	_check(weighed == "hall", "the Heavenly Hall is the night on the scales (%s)" % weighed)
	_check(not dawns.seeds("") and not dawns.seeds("seir"), "  and no other is")

	print("a dawn is written down")
	campaign.allow_in_tools = true
	profile.data.dawns = {}
	game.new_run()
	game.night = "seir"
	_lean(game, 4, 1, 2)
	_check(dawns.lean() == "grace", "grace ahead by 2: the lean is grace")
	campaign.record_dawn()
	_check(str(profile.data.dawns.get("seir", "")) == "grace", "  and seir's dawn is written as grace")
	game.night = ""
	_lean(game, 2, 3, 2)
	_check(dawns.lean() == "level", "ahead by 1: level")
	campaign.record_dawn()
	_check(str(profile.data.dawns.get(first, "")) == "level", "  the first night's dawn is written as level, under %s" % first)
	game.night = "marah"
	game.daily = "2026-10-14"
	_lean(game, 0, 5, 0)
	campaign.record_dawn()
	_check(not profile.data.dawns.has("marah"), "the night of the day writes no dawn")
	game.daily = ""
	game.practice = "training_dummy"
	campaign.record_dawn()
	_check(not profile.data.dawns.has("marah"), "nor does the yard")
	game.practice = ""

	print("the pans")
	var result: Dictionary = dawns.weigh({}, "hall")
	_check(result.flag == "weighed_none" and result.weight.values() == [0, 0, 0], "no dawns: nothing on the pans, weighed_none")
	result = dawns.weigh({first: "level", "seir": "level"}, "hall")
	_check(result.flag == "weighed_level" and result.weight.values() == [0, 0, 0], "only level dawns: nothing on the pans, weighed_level")
	result = dawns.weigh({first: "grace", "seir": "will", "marah": "will", "hall": "temptation"}, "hall")
	_check(result.weight.will == 2 and result.weight.grace == 1 and result.weight.temptation == 0,
		"+1 a path per night, the hall's own dawn not counted (%s)" % [result.weight])
	_check(result.flag == "weighed_will", "  the heaviest names the flag: weighed_will")
	result = dawns.weigh({first: "grace", "seir": "temptation", "marah": "level"}, "hall")
	_check(result.flag == "weighed_level", "a tie: weighed_level")
	var all := {first: "temptation"}
	for night in data.nights():
		all[campaign.night_key(str(night.get("id", "")))] = "temptation"
	result = dawns.weigh(all, "hall")
	_check(result.weight.temptation == all.size() - 1 and result.weight.temptation <= 6,
		"every other night leaning one way: +%d, no more than +6" % result.weight.temptation)

	print("a new night on the scales")
	profile.data.dawns = {first: "grace", "seir": "grace", "marah": "will"}
	game.new_run()
	game.night = "hall"
	var flag: String = dawns.seed_night()
	_check(flag == "weighed_grace" and game.flags.has("weighed_grace"), "seed_night lays the flag (%s)" % flag)
	_check(game.alignment.grace == 2 and game.alignment.will == 1 and game.alignment.temptation == 0,
		"  and the weight on the counters (%s)" % [game.alignment])
	game.night = "seir"
	game.new_run()
	_check(dawns.seed_night() == "" and game.alignment.grace == 0, "another night is not weighed")

	print("a checkpoint does not weigh twice")
	game.night = "hall"
	game.new_run()
	dawns.seed_night()
	var player = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(player)
	await process_frame
	var checkpoint: Dictionary = saves.capture("res://scenes/rooms/hall_outer_court.tscn", 0, 0.0, player)
	game.new_run()
	saves.restore(checkpoint, player)
	_check(game.alignment.grace == 2 and game.alignment.will == 1 and game.flags.has("weighed_grace"),
		"restored: the same weight and flag, not doubled (%s)" % [game.alignment])
	player.queue_free()

	print("a tool script remembers nothing")
	campaign.allow_in_tools = false
	game.night = "hall"
	game.new_run()
	_check(dawns.seed_night() == "weighed_none" and game.alignment.grace == 0, "without leave, the scales are empty")

	game.night = ""
	game.new_run()
	profile.data = saved_profile
	profile.save()
	_check(profile.data == saved_profile, "the profile is put back")
	print("dawn_scales_test: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
