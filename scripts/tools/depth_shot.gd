extends SceneTree
## Dev helper: a room seen through the game's own camera (640x360 at the
## hero's zoom) at a few points along it, so the far plates and the front
## plane can be looked at. Needs a display, not --headless:
##   godot --path . -s scripts/tools/depth_shot.gd -- out_dir res://scenes/rooms/<room>.tscn [y]

const XS := [0.15, 0.3, 0.45, 0.6, 0.75, 0.9]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var room = load(args[1]).instantiate()
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(640, 360)
	root.add_child(room)
	current_scene = room
	var camera := Camera2D.new()
	camera.zoom = Vector2(1.14, 1.14)
	room.add_child(camera)
	camera.make_current()
	var y: float = float(args[2]) if args.size() > 2 else room.height - 220.0
	for i in XS.size():
		camera.position = Vector2(room.width * XS[i], y)
		for frame in 12:
			await process_frame
		root.get_texture().get_image().save_png("%s/%s_%d.png" % [out, args[1].get_file().get_basename(), i])
	quit()
