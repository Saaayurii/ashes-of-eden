extends SceneTree
## The scripted Preacher reveal must start in the nave and release controls
## when skipped, just like the other two boss introductions.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	change_scene_to_file("res://scenes/run/run.tscn")
	await process_frame
	await process_frame
	var run = current_scene
	run.transition.instant = true
	# by name: threshold rooms between places keep moving the index
	run._load_room(run.ROOMS.find("res://scenes/rooms/preacher_nave.tscn"))
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
	current_scene = null
	run.queue_free()
	await process_frame
	await process_frame
	# Active mixer playbacks otherwise outlive an immediate headless quit.
	for voice in root.get_node("Audio").get_children():
		if voice is AudioStreamPlayer:
			voice.stop()
	await create_timer(0.15, true, false, true).timeout
	quit(0)
