extends SceneTree
## The scripted Preacher reveal must start in room 12 and release controls
## when skipped, just like the other two boss introductions.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	change_scene_to_file("res://scenes/run/run.tscn")
	await process_frame
	await process_frame
	var run = current_scene
	run.transition.instant = true
	run._load_room(11)
	var started := false
	for frame in 180:
		await process_frame
		if run.cutscene.playing == "preacher_arrival":
			started = true
			break
	if not started:
		printerr("PREACHER_ARRIVAL_FAIL: did not start")
		quit(1)
		return
	run.cutscene._skip()
	for frame in 180:
		await process_frame
		if run.cutscene.playing == "":
			break
	if run.cutscene.playing != "":
		printerr("PREACHER_ARRIVAL_FAIL: did not release after skip")
		quit(1)
		return
	print("PREACHER_ARRIVAL_OK")
	quit(0)
