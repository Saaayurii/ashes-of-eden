extends SceneTree
## A room change cancels a scene; a player's skip still applies its ending.


func _init() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	var data = root.get_node("Data")
	var player = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(player)
	var box = load("res://scenes/ui/dialogue_box.tscn").instantiate()
	root.add_child(box)
	var scene = load("res://scripts/ui/cutscene.gd").new()
	root.add_child(scene)
	var finished_count := [0]
	scene.finished.connect(func(_id: String) -> void: finished_count[0] += 1)
	data.cutscenes["qa_owned_caption"] = {"steps": [
		{"do": "hold"}, {"do": "dialogue", "id": "ch1_prologue_short"},
		{"do": "face", "dir": -1}, {"do": "release"}]}
	data.cutscenes["qa_wait"] = {"steps": [
		{"do": "hold"}, {"do": "panel", "image": "res://assets/cutscenes/elian_gallows_approach.png"},
		{"do": "wait", "time": 10.0},
		{"do": "face", "dir": -1}, {"do": "release"}]}
	data.cutscenes["qa_panel_clear"] = {"steps": [
		{"do": "panel", "image": "res://assets/cutscenes/elian_gallows_drop.png"},
		{"do": "panel_clear"}]}
	scene.play("qa_panel_clear")
	await _frames(3)
	assert(scene.playing == "" and not scene._panel.visible,
		"completed scene left its picture on screen")
	scene.play("qa_owned_caption")
	for i in 20:
		await process_frame
		if box.is_playing("ch1_prologue_short"):
			break
	assert(box.is_playing("ch1_prologue_short"), "test never reached the scene's caption")
	scene.abort()
	await _frames(5)
	assert(scene.playing == "" and not box.is_open(), "abort left a scene or caption hanging")
	assert(player.facing == 1, "aborted scene applied its future actions to the room")
	assert(player.controls_enabled and not root.get_node("Game").cutscene)
	assert(finished_count[0] == 1, "an aborted scene was reported as completed")

	scene.play("qa_wait")
	box.play("ch1_prologue_short")  # not a dialogue step owned by this scene
	await _frames(2)
	scene.abort()
	await _frames(5)
	assert(scene.playing == "" and box.is_open(), "abort cancelled an unrelated conversation")
	assert(not scene._panel.visible, "abort left the prologue picture on screen")
	box.skip()
	await _frames(3)
	scene.play("qa_wait")
	await _frames(2)
	scene._skip()
	await _frames(5)
	assert(scene.playing == "" and player.facing == -1, "player skip lost the scene's ending")
	assert(not scene._panel.visible, "skip left the prologue picture on screen")
	assert(finished_count[0] == 2)
	scene.play("qa_wait")
	await _frames(2)
	assert(not player.controls_enabled and root.get_node("Game").cutscene)
	root.remove_child(scene)
	assert(player.controls_enabled and not root.get_node("Game").cutscene,
		"removing an awaiting scene left persistent controls locked")
	await _frames(3)
	assert(finished_count[0] == 2, "removed scene was reported as completed")
	data.cutscenes.erase("qa_owned_caption")
	data.cutscenes.erase("qa_wait")
	data.cutscenes.erase("qa_panel_clear")
	print("CUTSCENE_ABORT_OK")
	player.queue_free()
	box.queue_free()
	scene.free()
	await _frames(2)
	quit()
