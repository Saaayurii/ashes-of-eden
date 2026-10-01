extends SceneTree
## The reliquary (data/relics, scripts/meta/relics.gd):
##   - a relic is bought once, with Ash, and only when its "needs" is owned;
##   - every late gift has its "early" relic, made from the gift itself;
##   - bought relics are on the body when a night begins, the rosary deals the
##     gift cards again, an early gift is in the pool on the first night;
##   - a loaded save does not count them twice;
##   - the main menu opens the reliquary and lists them all.
## Puts the profile back as it found it.
##   godot --headless --path . -s scripts/tools/relics_test.gd

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
	var relics = load("res://scripts/meta/relics.gd")
	var profile = root.get_node("Profile")
	var game = root.get_node("Game")
	var saved: Dictionary = profile.data.duplicate(true)
	profile.data.relics = {}
	profile.data.nights = 0
	profile.data.ash = 1000

	var late := 0
	for gift in root.get_node("Data").abilities.values():
		if int(gift.get("unlock_nights", 0)) > 0:
			late += 1
	var early: Array = relics.all().filter(func(r: Dictionary) -> bool: return r.has("early"))
	_check(early.size() == late and late > 0, "every late gift has an early relic (%d)" % late)

	_check(not relics.can_buy("scarred_skin"), "old scars wait for tempered skin")
	_check(relics.buy("tempered_skin") and int(profile.data.ash) == 920, "a relic costs its Ash")
	_check(not relics.buy("tempered_skin"), "and is bought once")
	_check(relics.can_buy("scarred_skin"), "then old scars can be had")
	profile.data.ash = 10
	_check(not relics.can_buy("whetstone"), "not without the Ash for it")
	profile.data.ash = 1000
	for id in ["scarred_skin", "pilgrims_flask", "whetstone", "rosary", "early_blood_pact"]:
		relics.buy(id)

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
	var hero = run.player
	var base: Dictionary = hero.BASE_STATS
	_check(hero.stats.max_hp == base.max_hp + 20.0 and hero.hp == hero.stats.max_hp, "twenty more health, and full")
	_check(int(hero.heal_charges) == int(base.heal_charges) + 1, "one more flask")
	_check(hero.stats.attack_damage == base.attack_damage + 1.0, "a sharper sword")
	_check(game.rerolls == 1, "the rosary: one deal again tonight")
	_check(not run.gift_locked(root.get_node("Data").abilities["blood_pact"]), "an early gift is in the pool on the first night")
	_check(run.gift_locked(root.get_node("Data").abilities["executioner"]), "a late one not bought still waits")

	var options: Array[Dictionary] = run._roll_gifts()
	run.picker.pick(options, run._roll_gifts)
	await process_frame
	var button = run.picker.find_child("Reroll", true, false)
	_check(button != null and button.visible, "the gift cards offer a new deal")
	button.pressed.emit()
	await process_frame
	_check(game.rerolls == 0 and not button.visible and run.picker.cards.get_child_count() == 3,
		"a new hand, and no more deals tonight")
	run.picker.chosen.emit(options[0])
	await process_frame

	var saves = root.get_node("Saves")
	var before: Dictionary = hero.stats.duplicate()
	var snapshot: Dictionary = saves.capture(run.ROOMS[1], 0, 10.0, hero)
	saves.restore(snapshot, hero)
	_check(hero.stats.max_hp == before.max_hp and hero.stats.attack_damage == before.attack_damage
			and hero.stats.heal_charges == before.heal_charges, "a loaded save keeps the relics once, not twice")

	current_scene = null
	run.queue_free()
	await _settle(0.2)
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await _settle(0.8)
	var menu = current_scene
	var open = menu.find_child("OpenReliquary", true, false)
	_check(open != null, "the main menu has a reliquary")
	open.pressed.emit()
	await process_frame
	var book = menu.get_node("Reliquary")
	_check(book.visible and book._list.get_child_count() == relics.all().size(), "it lists every relic")
	var owned = book._list.find_child("Buy_whetstone", true, false)
	_check(owned != null and owned.disabled, "one owned cannot be bought again")
	book.close()

	profile.data = saved
	profile.save()
	current_scene = null
	menu.queue_free()
	await _settle(0.2)
	print("RELICS TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
