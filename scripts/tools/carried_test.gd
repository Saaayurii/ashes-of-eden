extends SceneTree
## Pause → Gifts (CarriedGifts): what our own body carries tonight.
##   - nothing taken: it says so;
##   - every gift taken, every resonance woken and every item found is a row,
##     in that order, with its name and its description;
##   - the pause menu opens it and Escape brings the menu back.
##   godot --headless --path . -s scripts/tools/carried_test.gd

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


func _texts(node: Node) -> Array[String]:
	var found: Array[String] = []
	for label in node.find_children("*", "Label", true, false):
		found.append(label.text)
	return found


func _run() -> void:
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	game.vial = 0
	game.omen = ""
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	run.cutscene.abort()
	game.cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false
	var player = run.player
	var pause = run.get_node("UI/PauseMenu")
	var carried = pause.carried
	var button = pause.get_node("%OpenCarried")
	_check(carried != null and button != null, "the pause menu has a Gifts page")

	game.abilities.clear()
	game.resonances.clear()
	game.items.clear()
	pause._open()
	button.pressed.emit()
	await process_frame
	_check(carried.visible and not pause.panel.visible, "it opens over the pause menu")
	_check(_texts(carried.list) == ["CARRIED_NONE"], "nothing taken: it says so")
	carried.close()
	_check(pause.panel.visible, "  and closes back to the menu")

	var ability_system = load("res://scripts/combat/ability_system.gd")
	ability_system.apply(player, data.abilities["briar_mantle"])
	ability_system.apply(player, data.abilities["blood_pact"])
	load("res://scripts/combat/item_system.gd").give(player, "censer_ember")
	var all: Array = carried.entries()
	var kinds: Array = all.map(func(e: Dictionary) -> String: return e.kind)
	_check(kinds == ["gift", "gift", "resonance", "item"], "gifts, then the resonance they woke, then the item (%s)" % [kinds])
	button.pressed.emit()
	await process_frame
	var shown := _texts(carried.list)
	var want := [TranslationServer.translate(data.abilities["briar_mantle"].name),
		TranslationServer.translate(data.abilities["briar_mantle"].description),
		TranslationServer.translate(data.items["censer_ember"].name)]
	var missing := want.filter(func(t: String) -> bool: return not shown.has(t))
	_check(carried.list.get_child_count() == 4 and missing.is_empty(), "every one is a row with its name and words (%s)" % [missing])
	_check(shown.any(func(t: String) -> bool: return t.begins_with("◆ ")), "  a resonance marked as one")
	# one gift away: Thorned Oath waits for its second gift while only the first is carried
	carried.close()
	var resonances = load("res://scripts/combat/resonances.gd")
	game.abilities.clear()
	game.resonances.clear()
	ability_system.apply(player, data.abilities["briar_mantle"])
	var near: Array = resonances.near(game.abilities)
	var oath: Array = near.filter(func(n: Dictionary) -> bool: return n.get("gift", "") == "blood_pact")
	_check(oath.size() == 1, "one gift short of a resonance is noticed (%s)" % [near])
	button.pressed.emit()
	await process_frame
	shown = _texts(carried.list)
	_check(shown.has("CARRIED_NEAR") and shown.any(func(t: String) -> bool:
		return t.contains(TranslationServer.translate(data.abilities["blood_pact"].name))), "  and the Gifts page names the gift that would wake it")
	ability_system.apply(player, data.abilities["blood_pact"])
	_check(not resonances.near(game.abilities).any(func(n: Dictionary) -> bool: return n.id == oath[0].id if not oath.is_empty() else false),
		"  woken, it is no longer one away")
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	Input.parse_input_event(escape)
	await process_frame
	await process_frame
	_check(not carried.visible and pause.panel.visible, "Escape brings the menu back")
	pause._resume()

	game.new_run()
	await process_frame
	print("CARRIED TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
