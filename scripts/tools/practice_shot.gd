extends SceneTree
## Dev helper: the practice yard on screen — the straw man, the move list, a
## lunge and a charge. Needs a display:
##   xvfb-run -a godot --rendering-driver opengl3 --path . -s scripts/tools/practice_shot.gd -- out_dir

var _out := "/tmp"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	call_deferred("_run")


func _shot(name: String) -> void:
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])


func _run() -> void:
	root.get_node("Game").practice = "training_dummy"
	change_scene_to_file("res://scenes/run/run.tscn")
	await create_timer(1.6).timeout
	var hero = current_scene.player
	await _shot("yard")
	hero.global_position.x += 160
	for action in ["move_left", "move_right"]:
		Input.action_press(action)
		for i in 2:
			await physics_frame
		Input.action_release(action)
		await physics_frame
	Input.action_press("attack")
	await physics_frame
	Input.action_release("attack")
	for i in 5:
		await physics_frame
	await _shot("lunge")
	await create_timer(0.8).timeout
	Input.action_press("attack")
	await create_timer(1.3).timeout
	await _shot("charge")
	Input.action_release("attack")
	for i in 6:
		await physics_frame
	await _shot("cleave")
	quit()
