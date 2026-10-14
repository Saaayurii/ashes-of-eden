extends SceneTree
## A room of waiters left alone (Room.quiet_outro, docs/CHAPTER2.md §8):
##   - Seir's gate, street and square name a scene for it, and it exists;
##   - walked through with nobody woken, the door plays it before the way on;
##   - a waiter struck (or laid low) silences it, and a rest that stands the
##     dead up again does not make the room forget it.
##   godot --headless --path . -s scripts/tools/quiet_outro_test.gd

const ROOMS := ["seir_gate", "seir_street", "seir_square"]

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _settle(seconds := 0.3) -> void:
	await create_timer(seconds, true, false, true).timeout


func _open(run, name: String):
	var game = root.get_node("Game")
	run._load_room(run.ROOMS.find("res://scenes/rooms/%s.tscn" % name))
	await _settle(0.4)
	run.cutscene.abort()
	await _frames(2)
	game.cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false
	await _frames(4)
	return run.room


## Walk through the door (the run's own way, Room.exited) and say which scene
## the door played, if any, before the run moved on.
func _leave(run) -> String:
	var heard := ""
	run.room.exited.emit()
	for i in 120:
		await process_frame
		if run.cutscene.playing != "":
			heard = run.cutscene.playing
			break
		if not run._advancing:
			break
	run.cutscene.abort()
	for i in 240:  # the door's gift, if this door gives one: refused
		await process_frame
		if not run._advancing:
			break
		if run.picker.visible:
			run.picker.chosen.emit({})
	return heard


func _run() -> void:
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	var had_flag: bool = game.flags.has("waiter_struck")
	game.night = "seir"
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true

	for name in ROOMS:
		var room = await _open(run, name)
		_check(room.quiet_outro != "" and data.cutscenes.has(room.quiet_outro),
			"%s names a scene for leaving it waiting (%s)" % [name, room.quiet_outro])
		_check(not room.woke_waiter(), "%s: nobody woken on arrival" % name)

	# left alone: the door says its piece
	var room = await _open(run, "seir_gate")
	var index: int = run.room_index
	var heard := await _leave(run)
	_check(heard == "seir_gate_left_waiting", "the gate left waiting plays its scene (%s)" % heard)
	_check(run.room_index != index, "and the way on opens after it")

	# one struck: nothing is said
	room = await _open(run, "seir_gate")
	var waiter = null
	for pair in room._from_markers:
		if not room.holds_door(pair[0].enemy_id):
			waiter = pair[1]
			break
	_check(waiter != null, "the gate has a waiter to strike")
	if waiter != null:
		waiter.take_damage(1.0, run.player)
		await _frames(4)
	_check(room.woke_waiter(), "a waiter struck is a waiter woken")
	heard = await _leave(run)
	_check(heard == "", "the gate left woken says nothing (%s)" % heard)

	# one laid low, then a rest raises it unaware: still remembered
	room = await _open(run, "seir_street")
	for pair in room._from_markers:
		if not room.holds_door(pair[0].enemy_id):
			pair[1].take_damage(99999.0)
			break
	await _frames(6)
	room.respawn_commons()
	await _frames(4)
	var all_waiting := true
	for pair in room._from_markers:
		if not room.holds_door(pair[0].enemy_id) and is_instance_valid(pair[1]) and not pair[1].is_unaware():
			all_waiting = false
	_check(all_waiting, "after a rest every waiter stands waiting again")
	_check(room.woke_waiter(), "and the room still knows one was woken")

	if had_flag:
		game.flags["waiter_struck"] = true
	else:
		game.flags.erase("waiter_struck")
	game.night = ""
	data.use_night("")
	print("quiet_outro_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)
