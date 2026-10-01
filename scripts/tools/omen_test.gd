extends SceneTree
## The omens (data/omens, scripts/run/omens.gd, docs/OMENS.md):
##   - the first nights are plain; after them most nights draw one, every omen
##     can come up, the same seed draws the same one;
##   - none in the practice yard; the night of the day draws the day's own;
##   - an omen's rules stack on the vial's, and only tonight's count;
##   - essence, Ash, flasks, the altars and the promotions obey it;
##   - a save keeps it, a removed one loads as a plain night.
## Puts the profile back as it found it.
##   godot --headless --path . -s scripts/tools/omen_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _settle(seconds := 0.3) -> void:
	await create_timer(seconds, true, false, true).timeout


func _run() -> void:
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	var profile = root.get_node("Profile")
	var saves = root.get_node("Saves")
	var omens = load("res://scripts/run/omens.gd")
	var vials = load("res://scripts/run/vials.gd")
	var daily = load("res://scripts/run/daily.gd")
	var saved: Dictionary = profile.data.duplicate(true)

	# --- the draw ----------------------------------------------------------------
	var drawn := {}
	var with_one := 0
	for seed in 2000:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var id: String = omens.roll(rng)
		if id != "":
			with_one += 1
			drawn[id] = true
	var share := with_one / 2000.0
	_check(absf(share - omens.CHANCE) < 0.05, "about %d%% of nights draw an omen (%.2f)" % [int(omens.CHANCE * 100), share])
	_check(drawn.size() == data.omens.size(), "every omen can come up (%d of %d)" % [drawn.size(), data.omens.size()])
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 77
	b.seed = 77
	_check(omens.roll(a) == omens.roll(b), "the same seed draws the same omen")

	game.new_run()
	profile.data.nights = omens.FROM_NIGHT - 1
	var plain := true
	for i in 50:
		plain = plain and omens.for_new_night(true) == ""
	_check(plain, "the first %d nights are plain" % omens.FROM_NIGHT)
	profile.data.nights = omens.FROM_NIGHT
	var some := false
	for i in 50:
		some = some or omens.for_new_night(true) != ""
	_check(some, "  and after them omens come")
	game.practice = "cultist"
	var none := true
	for i in 50:
		none = none and omens.for_new_night(true) == ""
	_check(none, "none in the practice yard")
	game.practice = ""
	game.daily = "2026-10-01"
	var first: String = omens.for_new_night(true)
	var same := true
	for i in 10:
		same = same and omens.for_new_night(true) == first
	profile.data.nights = 0
	_check(same and omens.for_new_night(true) == first, "the night of the day draws the day's own, whatever the profile")
	game.daily = ""

	# --- the rules ---------------------------------------------------------------
	game.vial = 0
	game.omen = "blood_moon"
	_check(is_equal_approx(float(vials.rule("enemy_damage")), 1.15) and is_equal_approx(float(vials.rule("essence")), 1.3),
		"Blood Moon: harder blows, more essence")
	game.vial = 3
	_check(is_equal_approx(float(vials.rule("enemy_damage")), 1.2 * 1.15), "  on top of the vial's own")
	_check(is_equal_approx(float(vials.rules(3).enemy_damage), 1.2), "  a vial asked about by its tier is the vial alone")
	game.vial = 0
	game.essence = 0.0
	game.essence_bonus = 0.0
	game.add_essence(10.0)
	_check(is_equal_approx(game.essence, 13.0), "the dead give more essence (%.1f of 10)" % game.essence)
	game.omen = "heavy_earth"
	_check(is_equal_approx(vials.ash_multiplier(), 1.3) and is_equal_approx(float(vials.rule("enemy_hp")), 1.2),
		"Heavy Earth: tougher dead, more Ash")
	game.vial = 1
	_check(is_equal_approx(vials.ash_multiplier(), 1.25 * 1.3), "  multiplied with the vial's Ash")
	game.vial = 0
	game.omen = "procession"
	_check(float(vials.rule("promote_chance")) > 0.0 and vials.rule("promote").has("cultist"),
		"The Procession raises elites without a vial")
	game.omen = ""
	_check(is_equal_approx(vials.ash_multiplier(), 1.0) and float(vials.rule("promote_chance")) == 0.0,
		"a plain night is a plain night")

	# --- on the body and in the room ------------------------------------------------
	game.omen = "thin_veil"
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	_check(game.omen == "", "a tool script's run draws no omen of its own")
	game.omen = "thin_veil"
	var body = load("res://scenes/player/player.tscn").instantiate()
	var base_flasks := int(body.BASE_STATS.heal_charges)
	run.add_child(body)
	await process_frame
	_check(body.heal_charges == base_flasks + 1, "Thin Veil: one more flask (%d)" % body.heal_charges)
	body.queue_free()
	game.omen = "dry_altars"
	var player = run.player
	player.hp = 1.0
	player.rest()
	_check(is_equal_approx(player.hp, 1.0 + player.stats.max_hp * 0.5), "Dry Altars: an altar gives back half")
	game.omen = "procession"
	run._load_room(run.ROOMS.find("res://scenes/rooms/graveyard_tree.tscn"))
	await _settle(0.4)
	var risen := 0
	for i in 60:
		var spawned = run._spawn_enemy("cultist", Vector2(-4000, -4000))
		if spawned != null:
			if spawned.enemy_id == "elite_cultist":
				risen += 1
			spawned.queue_free()
	_check(risen > 0 and risen < 30, "  and some cultists rise as Zealot Brothers (%d of 60)" % risen)

	var checkpoint: Dictionary = saves.capture(run.ROOMS[run.room_index], 0, 0.0, player)
	_check(str(checkpoint.game_state.get("omen", "")) == "procession", "a save keeps the omen")
	game.omen = ""
	saves.restore(checkpoint, player)
	_check(game.omen == "procession", "  and loading puts it back")
	checkpoint.game_state.omen = "an_omen_that_was_removed"
	saves.restore(checkpoint, player)
	_check(game.omen == "", "  a removed omen loads as a plain night")

	game.omen = ""
	game.vial = 0
	profile.data = saved
	profile.save()
	await process_frame
	print("OMEN TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
