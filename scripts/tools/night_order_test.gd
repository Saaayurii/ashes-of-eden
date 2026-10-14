extends SceneTree
## The order nights open in (docs/CAMPAIGN.md §6, engine E3, Campaign): each
## night's dawn is recorded with the path that led it, and a night "after"
## another waits for that night's dawn as well as its own number of dawns. The
## night of the day, the yard and an online night record no dawn.
## Puts the profile back the way it found it.
##   godot --headless --path . -s scripts/tools/night_order_test.gd

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
	var route = load("res://scripts/run/route.gd")
	var profile = root.get_node("Profile")
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	var net = root.get_node("Net")
	var saved_profile: Dictionary = profile.data.duplicate(true)
	var first_id := str(data.game.get("id", ""))
	campaign.allow_in_tools = true

	var marah := {"id": "marah", "after": "seir", "after_dawns": 2}
	var plain := {"id": "plain", "after_dawns": 2}
	profile.data.wins = 2
	profile.data.dawns = {}
	_check(not campaign.night_open(marah), "without Seir's dawn Marah stays shut, even with two dawns")
	_check(campaign.night_open(plain), "a night with no \"after\" opens by its dawns, as before")
	profile.data.dawns = {"seir": "will"}
	_check(campaign.night_open(marah), "after Seir's dawn Marah opens")
	profile.data.wins = 1
	_check(not campaign.night_open(marah) and not campaign.night_open(plain), "both conditions hold: not before its dawns")
	profile.data.wins = 2
	_check(campaign.night_open({"id": "x", "after": first_id, "after_dawns": 1}) == false, "after the first night: waits for its dawn")
	profile.data.dawns[first_id] = "level"
	_check(campaign.night_open({"id": "x", "after": first_id, "after_dawns": 1}), "the first night's dawn is kept under the game's id")
	var open_ids: Array = route.open_nights().map(func(n) -> String: return str(n.id))
	_check(open_ids.has(""), "the first night is always on the menu")
	for night in data.nights():
		_check(open_ids.has(str(night.id)) == campaign.night_open(night), "the menu offers %s exactly when it is open" % (night.id if night.id != "" else "the first night"))

	# the dawn is written with the night's lean
	profile.data.dawns = {}
	game.new_run()
	game.night = "seir"
	game.alignment = {"grace": 4, "temptation": 1, "will": 0}
	campaign.record_dawn()
	_check(str(profile.data.dawns.get("seir", "")) == "grace", "a dawn that leaned by 2 records the path")
	game.night = ""
	game.alignment = {"grace": 1, "temptation": 2, "will": 1}
	campaign.record_dawn()
	_check(str(profile.data.dawns.get(first_id, "")) == "level", "a level dawn records \"level\" (the first night under the game's id)")
	game.night = "seir"
	game.alignment = {"grace": 0, "temptation": 0, "will": 3}
	campaign.record_dawn()
	_check(str(profile.data.dawns.get("seir", "")) == "will", "a later dawn of the same night replaces the earlier")

	# a whole dawn through the profile writes it
	profile.data.dawns = {}
	data.use_night("seir")
	game.night = "seir"
	game.alignment = {"grace": 0, "temptation": 3, "will": 0}
	profile.record_run(10, 20, 600.0, 0, true)
	_check(str(profile.data.dawns.get("seir", "")) == "temptation", "Profile.record_run at dawn records it")
	profile.data.dawns = {}
	profile.record_run(3, 2, 100.0, 0, false)
	_check(profile.data.dawns.is_empty(), "a death records no dawn")

	for case in [["daily", "the night of the day"], ["practice", "the practice yard"], ["online", "an online night"]]:
		match case[0]:
			"daily": game.daily = "2026-10-14"
			"practice": game.practice = "training_dummy"
			"online": net.active = true
		campaign.record_dawn()
		_check(profile.data.dawns.is_empty(), "%s records no dawn" % case[1])
		game.daily = ""
		game.practice = ""
		net.active = false

	campaign.allow_in_tools = false
	campaign.record_dawn()
	_check(profile.data.dawns.is_empty(), "a tool script records no dawn")

	data.use_night("")
	game.night = ""
	game.new_run()
	profile.data = saved_profile
	profile.save()
	_check(profile.data == saved_profile, "the profile is put back as it was found")
	print("night_order_test: %s" % ("OK" if failures == 0 else "%d failure(s)" % failures))
	quit(1 if failures else 0)
