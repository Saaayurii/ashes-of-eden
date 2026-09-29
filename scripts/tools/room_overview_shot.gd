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
		image.save_png("%s/%s.png" % [out, name])
		print("SHOT ", name, " ", image.get_size())
		current_scene = null
		room.queue_free()
		await process_frame
	quit()
