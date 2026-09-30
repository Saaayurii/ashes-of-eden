extends SceneTree
## Resonances (data/resonances): what gifts do together.
##   - a path's count wakes its resonance on the gift that reaches it, not before;
##   - a resonance applies once, however many gifts follow;
##   - a pair across paths wakes when both are taken, in either order;
##   - the effects land on the body's stats, under the caps;
##   - a card says what it would complete; the toast says what woke;
##   - a restored night knows its resonances without applying them again.
##   godot --headless --path . -s scripts/tools/resonance_test.gd

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
	var data = root.get_node("Data")
	var game = root.get_node("Game")
	var abilities = load("res://scripts/combat/ability_system.gd")
	var resonances = load("res://scripts/combat/resonances.gd")
	var woke := []
	root.get_node("EventBus").resonance_awakened.connect(func(id: String) -> void: woke.append(id))

	var room = load("res://scenes/rooms/graveyard.tscn").instantiate()
	root.add_child(room)
	var player = load("res://scenes/player/player.tscn").instantiate()
	room.add_child(player)
	player.global_position = Vector2(300, 220)
	await _settle()
	game.new_run()
	var gift = func(id: String) -> void: abilities.apply(player, data.abilities[id])

	gift.call("mending_light")
	gift.call("tempered_mail")
	_check(game.resonances.is_empty() and float(player.stats.parry_stun) == 0.0, "two gifts of grace wake nothing")
	_check(resonances.completes(data.abilities["litany_of_rest"], game.abilities).has("chorus"),
		"the third grace card says it completes the Chorus")
	var card = load("res://scripts/ui/ability_picker.gd").new()
	var button = card._make_card(data.abilities["litany_of_rest"])
	_check(button.text.contains(tr(resonances.spec("chorus").name)), "  and the card shows it")
	button.free()
	card.free()
	gift.call("litany_of_rest")
	_check(game.resonances == ["chorus"] and woke == ["chorus"], "the third wakes the Chorus, once")
	_check(absf(float(player.stats.parry_stun) - 0.5) < 0.001, "  a parry now stops everyone near")
	gift.call("sanctuary")
	_check(absf(float(player.stats.parry_stun) - 0.5) < 0.001 and woke.size() == 1, "a fourth gift does not apply it again")
	gift.call("vigil_unbroken")
	_check(game.resonances.has("radiant_host") and float(player.stats.clean_clear_charge) == 1.0
			and float(player.stats.heal_burst) == 25.0, "the fifth wakes the Radiant Host")

	gift.call("severing_arc")
	_check(not game.resonances.has("last_rites"), "one half of a pair is nothing")
	var execute_before: float = player.stats.execute
	gift.call("executioner")
	_check(game.resonances.has("last_rites"), "the other half, from another path, wakes Last Rites")
	_check(absf(float(player.stats.execute) - (execute_before + 0.6 + 0.3)) < 0.001,
		"  the gift's execute and the rite's on top (%.2f)" % float(player.stats.execute))
	_check(float(player.stats.execute) <= 1.2, "  under the cap")

	var restored: Array = resonances.active(game.abilities)
	restored.sort()
	var kept: Array = game.resonances.duplicate()
	kept.sort()
	_check(restored == kept, "a restored night reads the same resonances off its gifts")

	var toast = load("res://scripts/ui/deed_toast.gd").new()
	root.add_child(toast)
	root.get_node("EventBus").resonance_awakened.emit("bulwark")
	_check(toast.text.contains(tr(resonances.spec("bulwark").name)), "the toast says which one woke")
	toast.queue_free()

	room.queue_free()
	game.new_run()
	print("RESONANCE TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	await process_frame
	quit(0 if failures == 0 else 1)
