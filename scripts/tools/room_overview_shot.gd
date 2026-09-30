extends SceneTree
## Dev helper: every room of the run drawn whole, one PNG each, at 1:1 — the
## painting, props, secrets and the door as the game draws them, nobody in
## the way. For reviewing where things stand. Needs a display (xvfb-run is
## enough), not --headless:
##   xvfb-run -s "-screen 0 1920x1080x24" godot --path . -s scripts/tools/room_overview_shot.gd -- out_dir [room|room]

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp"
	var only: Array = Array(args[1].split("|")) if args.size() > 1 else []
	var rooms: Array = load("res://scripts/run/run.gd").get_script_constant_map()["ROOMS"]
	for path in rooms:
		var name: String = path.get_file().get_basename()
		if not only.is_empty() and not only.has(name):
			continue
		var room = load(path).instantiate()
		root.add_child(room)
		current_scene = room
		var size := Vector2i(int(room.width), int(room.height))
		root.size = size
		root.content_scale_size = size
		var camera := Camera2D.new()
		camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
		room.add_child(camera)
		camera.make_current()
		for frame in 30:
			await process_frame
		var image := root.get_texture().get_image()
		var sample := image.get_pixel(10, 10)
		var painted := false
		for point in [Vector2i(size.x / 4, size.y / 4), Vector2i(size.x / 2, size.y / 2),
				Vector2i(size.x * 3 / 4, size.y * 3 / 4)]:
			if not image.get_pixelv(point).is_equal_approx(sample):
				painted = true
		if not painted:
			printerr("SHOT FAILED: %s produced a blank viewport" % name)
			quit(1)
			return
		image.save_png("%s/%s.png" % [out, name])
		print("SHOT ", name, " ", image.get_size())
		current_scene = null
		room.queue_free()
		# Wait for the old camera, canvas layers and textures to leave the
		# viewport. A single frame produced gray captures from the third room on.
		for frame in 5:
			await process_frame
	quit()
