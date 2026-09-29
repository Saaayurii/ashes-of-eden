extends SceneTree
## Repeated scene removal during speech must not leave pause, controls, or bus listeners behind.


func _init() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	var data = root.get_node("Data")
	var bus = root.get_node("EventBus")
	var game = root.get_node("Game")
	var audio = root.get_node("Audio")
	var listeners: int = bus.enemy_died.get_connections().size()
	data.dialogues["qa_lifecycle"] = {"start": "line", "nodes": {
		"line": {"speaker": "", "text": "DLG_CH1_INTRO_1", "next": ""}}}
	for cycle in 4:
		change_scene_to_file("res://scenes/run/run.tscn")
		await _frames(4)
		var run = current_scene
		run.cutscene.abort()
		run.dialogue.skip()
		await _frames(5)
		var blocking := cycle % 2 == 0
		data.dialogues["qa_lifecycle"]["blocking"] = blocking
		run.dialogue.play("qa_lifecycle")
		await _frames(2)
		if paused != blocking or not run.dialogue.is_playing("qa_lifecycle"):
			printerr("RUN_LIFECYCLE_FAIL: dialogue did not start in expected mode")
			quit(1)
			return
		# Scene changes remove the outgoing scene before the replacement is ready.
		current_scene = null
		run.queue_free()
		await _frames(5)
		if paused or game.cutscene or audio._speech.playing:
			printerr("RUN_LIFECYCLE_FAIL: pause, cutscene lock or speech survived exit %d" % cycle)
			quit(1)
			return
		if bus.enemy_died.get_connections().size() != listeners:
			printerr("RUN_LIFECYCLE_FAIL: outgoing run retained event listeners")
			quit(1)
			return
	data.dialogues.erase("qa_lifecycle")
	# Give the audio mixer time to retire playbacks before shutting down the test.
	for voice in audio.get_children():
		if voice is AudioStreamPlayer:
			voice.stop()
	await create_timer(0.15, true, false, true).timeout
	print("RUN_LIFECYCLE_OK")
	quit()
