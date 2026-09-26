extends SceneTree
## Eyes on the prologue: starts a run the way the menu does and shoots the
## opening every second, so the monologue over the black screen, the fade and
## the wake-up can be looked at rather than assumed. Run windowed:
##   godot --path . -s scripts/tools/prologue_shot.gd -- out_dir [count]

var _out := "/tmp"
var _count := 14


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_count = int(args[1])
	call_deferred("_run")


func _run() -> void:
	await process_frame
	change_scene_to_file("res://scenes/run/run.tscn")
	await process_frame
	await process_frame
	# A windowed Godot driven from a terminal never has focus, and the pause
	# menu opens on NOTIFICATION_APPLICATION_FOCUS_OUT — every frame would be
	# a picture of the pause screen. Nothing here needs it.
	for node in root.find_children("*", "", true, false):
		if node.get_script() != null and str(node.get_script().resource_path).ends_with("pause_menu.gd"):
			node.queue_free()
	await process_frame
	for i in range(_count):
		await create_timer(1.0).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		img.save_png("%s/prologue_%02d.png" % [_out, i])
		print("SHOT: prologue_%02d" % i)
	quit()
