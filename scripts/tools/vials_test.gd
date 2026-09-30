extends SceneTree
## The vials of wrath (data/vials, scripts/run/vials.gd):
##   - each vial adds its rule to the ones below it;
##   - only a vial a dawn has opened can be chosen, and a dawn opens the next;
##   - the rules land: elites rise, a flask is gone, blows hurt more, an altar
##     gives half, the dead are tougher, the Ash is multiplied;
##   - the vial is kept in a save; the settings list only what is opened;
##   - winning under a vial counts for its deed.
## Puts the profile and the settings back as it found them.
##   godot --headless --path . -s scripts/tools/vials_test.gd

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
	var vials = load("res://scripts/run/vials.gd")
	var profile = root.get_node("Profile")
	var settings = root.get_node("Settings")
	var game = root.get_node("Game")
	var saved: Dictionary = profile.data.duplicate(true)
	var saved_vial: int = settings.vial

	var none: Dictionary = vials.rules(0)
	_check(none.flasks == 0 and none.enemy_hp == 1.0 and none.promote_chance == 0.0, "no vial, no rule")
	var second: Dictionary = vials.rules(2)
	_check(second.flasks == -1 and second.promote_chance == 0.25 and second.enemy_damage == 1.0,
		"the second holds the first's rule and its own")
	var fifth: Dictionary = vials.rules(5)
	_check(fifth.flasks == -1 and absf(fifth.enemy_damage - 1.2) < 0.001 and fifth.rest_heal == 0.5
			and absf(fifth.enemy_hp - 1.25) < 0.001 and fifth.promote_chance == 0.5,
		"the fifth holds all five")
	_check(vials.ash_multiplier(0) == 1.0 and vials.ash_multiplier(2) == 1.5, "each pays its own Ash")

	profile.data.vials_opened = 0
	settings.set_vial(3)
	_check(vials.for_new_night() == 0, "a vial not yet opened cannot be played")
	profile.data.vials_opened = 3
	_check(vials.for_new_night() == 3, "an opened one can")

	game.vial = 0
	var plain: float = game.enemy_damage_multiplier()
	game.vial = 3
	_check(absf(game.enemy_damage_multiplier() / plain - 1.2) < 0.001, "the third makes every blow a fifth harder")

	# --- in a night -----------------------------------------------------------
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.8)
	var run = current_scene
	run.transition.instant = true
	run._load_room(1)
	await _settle(0.4)
	run.cutscene.abort()
	game.cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	_check(game.vial == 3, "the night starts under the chosen vial")
	var hero = run.player
	_check(int(hero.heal_charges) == int(hero.BASE_STATS.heal_charges) - 1, "one flask fewer")

	game.vial = 5
	var risen := 0
	for i in 40:
		var body = run._spawn_enemy("possessed_villager", hero.global_position + Vector2(400, -40), false)
		if body.enemy_id == "elite_possessed":
			risen += 1
		body.queue_free()
	_check(risen > 8 and risen < 32, "about half the possessed rise as elites (%d of 40)" % risen)
	game.vial = 0
	risen = 0
	for i in 20:
		var body = run._spawn_enemy("possessed_villager", hero.global_position + Vector2(400, -40), false)
		if body.enemy_id == "elite_possessed":
			risen += 1
		body.queue_free()
	_check(risen == 0, "and none without a vial")

	game.vial = 4
	hero.hp = 10.0
	hero.rest()
	_check(absf(hero.hp - (10.0 + hero.stats.max_hp * 0.5)) < 0.01, "an altar gives back half the bar")
	game.vial = 0
	hero.hp = 10.0
	hero.rest()
	_check(hero.hp == hero.stats.max_hp, "and all of it without")

	game.vial = 3
	var snapshot: Dictionary = root.get_node("Saves").capture(run.ROOMS[1], 0, 10.0, hero)
	game.vial = 0
	root.get_node("Saves").restore(snapshot, hero)
	_check(game.vial == 3, "the vial comes back with a save")

	# --- a dawn ---------------------------------------------------------------
	profile.data.vials_opened = 2
	profile.data.deeds = {}
	profile.data.achievements = {}
	game.vial = 2
	profile.record_run(15, 50, 1500.0, 0, true)
	_check(int(profile.data.vials_opened) == 3, "a dawn under the second opens the third")
	_check(int(profile.data.deeds.get("wins_vial_2", 0)) == 1, "and is counted")
	game.vial = 1
	profile.record_run(15, 50, 1500.0, 0, true)
	_check(int(profile.data.vials_opened) == 3 and profile.data.achievements.has("vial_first"),
		"a dawn under the first closes nothing already open, and is a deed")
	game.vial = 0
	profile.record_run(3, 5, 300.0, 0, false)
	_check(int(profile.data.vials_opened) == 3, "a death opens nothing")

	# --- the settings -----------------------------------------------------------
	var menu = run.get_node("UI/PauseMenu/Settings")
	profile.data.vials_opened = 0
	menu._refresh()
	var row = menu.find_child("VialRow", true, false)
	_check(row != null and not row.visible, "no vial opened: the setting stays out of sight")
	profile.data.vials_opened = 3
	menu._refresh()
	_check(row.visible and menu._vial.item_count == 4, "three opened: none and three to choose from")

	settings.set_vial(saved_vial)
	profile.data = saved
	profile.save()
	current_scene = null
	run.queue_free()
	await _settle(0.2)
	print("VIALS TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
