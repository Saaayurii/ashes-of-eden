extends SceneTree
## The three alignment marks side by side, for looking at rather than guessing
## about. Run windowed (a shader needs a renderer):
##   godot --path . -s scripts/tools/alignment_marks_shot.gd -- out_dir
##
## Writes one frame per path plus a level one, all from the same pose, so the
## difference in the pictures is the difference the shader makes.

const PATHS := ["", "grace", "temptation", "will"]

var _out := "/tmp"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var room = load("res://scenes/rooms/graveyard.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	var player = load("res://scenes/player/player.tscn").instantiate()
	room.add_child(player)
	player.global_position = Vector2(300, 220)
	await create_timer(1.0).timeout
	player.controls_enabled = false
	player.play_scripted("idle")
	if player.camera != null:
		player.camera.zoom = Vector2(4.0, 4.0)

	for path in PATHS:
		player._mark_body(path, 1.0 if path != "" else 0.0)
		await create_timer(0.6).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		img.save_png("%s/marks_%s.png" % [_out, path if path != "" else "none"])
		print("MARK SHOT: ", path if path != "" else "none")
	quit()
