extends SceneTree
## A cutscene plays as cinema, headless, on the Preacher's arrival:
##   godot --headless --path . -s scripts/tools/cinema_test.gd
## The HUD steps out while the scene holds the controls, the boss is named by
## a title card, a line from the cast turns the camera to whoever says it,
## one press only arms the skip and the second one skips, and afterwards the
## HUD, the controls and the room's own camera are all given back.

var failures := 0
var _speakers: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	change_scene_to_file("res://scenes/run/run.tscn")
	await process_frame
	await process_frame
	var run = current_scene
	run.transition.instant = true
	var scene = run.cutscene
	var hud: CanvasItem = run.get_node("UI/HUD")
	run._load_room(run.ROOMS.find("res://scenes/rooms/preacher_nave.tscn"))
	if not await _until(func() -> bool: return scene.playing == "preacher_arrival", 6.0):
		_assert(false, "the Preacher's arrival starts")
		_finish(run)
		return
	run.dialogue.line_shown.connect(func(speaker: String) -> void: _speakers.append(speaker))
	await create_timer(0.6).timeout
	_assert(scene.cinema() and hud.modulate.a < 0.05, "the HUD steps out while the scene holds (%.2f)" % hud.modulate.a)

	var preacher_name := TranslationServer.translate("ENEMY_BLIND_PREACHER")
	_assert(await _until(func() -> bool: return scene._title.visible and scene._title_name.text == preacher_name, 4.0),
		"the boss is named by a title card")
	_assert(scene._title_sub.text == TranslationServer.translate("BOSS_EPITHET_BLIND_PREACHER"), "with its epithet")

	var player = run.player
	_assert(await _until(func() -> bool: return _speakers.has("SPEAKER_ELIAN"), 40.0), "Elian speaks in the scene")
	await create_timer(0.9).timeout
	var cam = scene._camera
	_assert(cam != null and absf(cam.global_position.x - player.global_position.x) < 40.0,
		"his line turns the camera to him (camera %.0f, Elian %.0f)" % [cam.global_position.x if cam else -1.0, player.global_position.x])

	var jump := InputEventAction.new()
	jump.action = "jump"
	jump.pressed = true
	scene._input(jump)
	_assert(scene.skip_armed() and not scene.skipping() and scene.playing != "", "one press only arms the skip")
	scene._input(jump)
	_assert(scene.skipping(), "the second press skips")
	_assert(await _until(func() -> bool: return scene.playing == "", 5.0), "the scene ends after the skip")
	await create_timer(0.6).timeout
	_assert(not scene.cinema() and hud.modulate.a > 0.95, "the HUD comes back (%.2f)" % hud.modulate.a)
	_assert(player.controls_enabled and not root.get_node("Game").cutscene, "the controls come back")
	_assert(player.camera.is_current(), "the room's own camera is current again")
	_assert(not scene._title.visible and scene._flash.color.a <= 0.01, "no title or flash is left on screen")
	_finish(run)


func _until(check: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if check.call():
			return true
		await process_frame
	return check.call()


func _finish(run) -> void:
	print("CINEMA TEST PASSED" if failures == 0 else "CINEMA TEST FAILED (%d)" % failures)
	current_scene = null
	run.queue_free()
	await process_frame
	for voice in root.get_node("Audio").get_children():
		if voice is AudioStreamPlayer:
			voice.stop()
	await create_timer(0.15, true, false, true).timeout
	quit(1 if failures > 0 else 0)


func _assert(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		failures += 1
