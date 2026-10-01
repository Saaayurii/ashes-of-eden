extends SceneTree
## Turning a hand of gifts down (AbilityPicker's Refuse, Run._refuse_gift):
##   - the picker always offers it, under the cards;
##   - pressing it takes no gift, closes the picker and unpauses the night;
##   - the body gets a breath instead: Player.REFUSE_HEAL of the bar and one
##     flask, never past full;
##   - the profile counts it, and ten of them are a deed (The Ascetic).
## Puts the profile back as it found it.
##   godot --headless --path . -s scripts/tools/refuse_test.gd

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


func _quiet(run) -> void:
	run.cutscene.abort()
	root.get_node("Game").cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false


## Opens one hand on [param run] and waits until the picker shows it.
func _open_hand(run) -> void:
	run._pending_gifts += 1
	run._offer_gifts()
	for i in 20:
		if run.picker.visible:
			return
		await process_frame


func _run() -> void:
	var game = root.get_node("Game")
	var profile = root.get_node("Profile")
	var saved: Dictionary = profile.data.duplicate(true)
	game.vial = 0
	game.omen = ""

	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	_quiet(run)
	var player = run.player
	for node in get_nodes_in_group("enemies"):
		node.set_physics_process(false)
		node.set_process(false)

	profile.data.deeds = {}
	profile.data.achievements = {}
	var refused := [0]
	var heard := func() -> void: refused[0] += 1
	root.get_node("EventBus").gift_refused.connect(heard)

	# a wounded body, two flasks down
	var full: int = int(player.stats.heal_charges)
	player.hp = player.stats.max_hp * 0.3
	player.heal_charges = full - 2
	var gifts_before: int = game.abilities.size()
	await _open_hand(run)
	var refuse = run.picker.find_child("Refuse", true, false)
	_check(run.picker.visible and refuse != null and refuse.visible, "the picker offers to refuse the hand")
	_check(refuse != null and refuse.text == TranslationServer.translate("PICKER_REFUSE"), "  and says so")
	var cards = run.picker.cards
	_check(refuse != null and refuse.get_index() > cards.get_index(), "  under the cards")
	_check(paused, "the night waits while the hand is shown")
	if refuse != null:
		refuse.pressed.emit()
	await process_frame
	await process_frame
	_check(not run.picker.visible and not paused, "refusing closes the picker and the night goes on")
	_check(game.abilities.size() == gifts_before, "  no gift is taken")
	_check(is_equal_approx(player.hp, player.stats.max_hp * (0.3 + player.REFUSE_HEAL)),
		"  a share of the bar comes back (%.1f of %.1f)" % [player.hp, player.stats.max_hp])
	_check(player.heal_charges == full - 1, "  and one flask fills (%d of %d)" % [player.heal_charges, full])
	_check(refused[0] == 1 and int(profile.data.deeds.get("refusals", 0)) == 1, "  and the profile counts it")

	# whole already: nothing goes past full
	player.hp = player.stats.max_hp
	player.heal_charges = full
	await _open_hand(run)
	run.picker.find_child("Refuse", true, false).pressed.emit()
	await process_frame
	_check(is_equal_approx(player.hp, player.stats.max_hp) and player.heal_charges == full, "a whole body stays whole, not past it")

	# a gift still works as before, and the button goes away with the cards
	await _open_hand(run)
	var first = cards.get_child(0)
	first.pressed.emit()
	await process_frame
	_check(game.abilities.size() == gifts_before + 1 and not refuse.visible, "a card still gives its gift")

	# ten refusals are a deed
	_check(not profile.data.achievements.has("ascetic"), "two refusals are no deed yet")
	for i in 8:
		await _open_hand(run)
		run.picker.find_child("Refuse", true, false).pressed.emit()
		await process_frame
	_check(profile.data.achievements.has("ascetic"), "ten refused hands are The Ascetic")

	# nothing counts in the practice yard
	game.practice = "training_dummy"
	await _open_hand(run)
	run.picker.find_child("Refuse", true, false).pressed.emit()
	await process_frame
	game.practice = ""
	_check(int(profile.data.deeds.get("refusals", 0)) == 10, "  and the yard counts none")

	root.get_node("EventBus").gift_refused.disconnect(heard)
	game.new_run()
	profile.data = saved
	profile.save()
	await process_frame
	print("REFUSE TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
