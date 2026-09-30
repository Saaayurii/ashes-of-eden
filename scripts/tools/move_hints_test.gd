extends SceneTree
## The special moves taught in the night (scripts/ui/move_hints.gd):
##   - each moment is recognised: a flyer overhead, a wind-up at arm's reach,
##     armour in reach, two in a row ahead;
##   - a hint comes once per profile, and never for a move already done;
##   - doing a move records it in the profile, in the yard too;
##   - a night lost with moves unknown points at the practice yard.
## Puts the profile back as it found it (CLAUDE.md: tools share user://).
##   godot --headless --path . -s scripts/tools/move_hints_test.gd

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
	var profile = root.get_node("Profile")
	var saved: Dictionary = profile.data.duplicate(true)
	profile.data.moves_done = {}
	profile.data.hints_shown = {}
	var hints_script = load("res://scripts/ui/move_hints.gd")

	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.8)
	var run = current_scene
	run.transition.instant = true
	run._load_room(run.ROOMS.find("res://scenes/rooms/graveyard_tree.tscn"))
	await _settle(0.4)
	run.cutscene.abort()
	root.get_node("Game").cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	for body in get_nodes_in_group("enemies"):
		body.queue_free()
	await _settle(0.2)
	var hero = run.player
	hero.facing = 1
	_check(run.get_node_or_null("UI/MoveHints") != null, "a night watches for the moments")

	var raven = run.room.spawn_enemy("raven", hero.global_position + Vector2(10, -50), true)
	await physics_frame
	raven.set_physics_process(false)
	raven.global_position = hero.global_position + Vector2(10, -50)
	_check(hints_script.moment(hero, [raven]) == "rising", "a flyer overhead: rising")

	var guard = run.room.spawn_enemy("fallen_guard", hero.global_position + Vector2(40, 0), true)
	await physics_frame
	guard.set_physics_process(false)
	guard.global_position = hero.global_position + Vector2(40, 0)
	guard.state = guard.State.CHASE
	_check(hints_script.moment(hero, [guard]) == "cleave", "armour in reach: cleave")
	guard.state = guard.State.WINDUP
	_check(hints_script.moment(hero, [guard]) == "sweep", "a wind-up at arm's reach: sweep first")

	var a = run.room.spawn_enemy("cultist", hero.global_position + Vector2(70, 0), true)
	var b = run.room.spawn_enemy("cultist", hero.global_position + Vector2(120, 0), true)
	await physics_frame
	for body in [a, b]:
		body.set_physics_process(false)
	a.global_position = hero.global_position + Vector2(70, 0)
	b.global_position = hero.global_position + Vector2(120, 0)
	_check(hints_script.moment(hero, [a, b]) == "lunge", "two in a row ahead: lunge")
	_check(hints_script.moment(hero, [a]) == "", "one alone: nothing to teach")

	var watcher = run.get_node("UI/MoveHints")
	watcher.show_hint("lunge")
	_check(profile.data.hints_shown.has("lunge") and watcher.text != "", "a hint is shown and remembered")
	_check(hints_script.moment(hero, [a, b]) == "", "and not given twice")
	root.get_node("EventBus").technique_performed.emit("rising")
	_check(profile.data.moves_done.has("rising"), "doing a move records it")
	_check(hints_script.moment(hero, [raven]) == "", "a move already done is not hinted")

	var run_end = run.get_node("UI/RunEnd")
	run_end.show_result(false, 3, 10, 120.0)
	_check(run_end.best.text.contains(tr("RUN_PRACTICE_TIP")), "a night lost with moves unknown points at the yard")
	for id in ["lunge", "cleave", "sweep"]:
		profile.data.moves_done[id] = true
	run_end.show_result(false, 3, 10, 120.0)
	_check(not run_end.best.text.contains(tr("RUN_PRACTICE_TIP")), "and says nothing once they are known")
	run_end.visible = false

	profile.data = saved
	profile.save()
	print("MOVE HINTS TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	current_scene = null
	run.queue_free()
	await _settle(0.2)
	quit(0 if failures == 0 else 1)
