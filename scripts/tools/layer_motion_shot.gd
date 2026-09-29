extends SceneTree
## Dev helper: what moves when the camera does. Each room is drawn whole
## twice with the tree paused (no weather, no flicker), the camera shifted by
## SHIFT pixels between the two; out_dir/<room>_a.png and _b.png, which a
## world-aligned diff turns into a map of every layer that slides against
## the painting. With `layers`, also out_dir/<room>_<layer>.png: the room
## with only that group of nodes visible (painting, depth, far, mid, decor,
## front). Needs a display (xvfb-run), not --headless:
##   xvfb-run -s "-screen 0 1920x1080x24" godot --path . -s scripts/tools/layer_motion_shot.gd -- out_dir [room|room] [layers]

const SHIFT := 200.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp"
	var only: Array = Array(args[1].split("|")) if args.size() > 1 and args[1] != "" else []
	var rooms: Array = load("res://scripts/run/run.gd").get_script_constant_map()["ROOMS"]
	for path in rooms:
		var name: String = path.get_file().get_basename()
		if not only.is_empty() and not only.has(name):
			continue
		var room = load(path).instantiate()
		root.add_child(room)
		current_scene = room
		var size := Vector2i(int(room.width), int(room.height))
		root.size = size + Vector2i(int(SHIFT), 0)
		root.content_scale_size = root.size
		var camera := Camera2D.new()
		camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
		camera.limit_right = 100000
		room.add_child(camera)
		camera.make_current()
		for frame in 20:
			await process_frame
		paused = true
		# weather and flicker hold still; the layers still follow the camera
		for node in room.find_children("*", "Parallax2D", true, false):
			node.process_mode = Node.PROCESS_MODE_ALWAYS
		await _pair(room, camera, "%s/%s" % [out, name])
		if args.has("layers"):
			# each moving group on its own: the others hidden
			var groups := {}
			for node in room.find_children("*", "Parallax2D", true, false):
				groups[str(node.name)] = [node]
			var windows = room.get_node_or_null("DepthWindows")
			if windows != null:
				groups["DepthWindows"] = [windows]
			var painting = room.get_node_or_null("Painting")
			for group in groups:
				var shown := {}
				for other in groups:
					for node in groups[other]:
						shown[node] = node.visible
						node.visible = other == group and node.visible
				await _pair(room, camera, "%s/%s__%s" % [out, name, group])
				for node in shown:
					node.visible = shown[node]
		print("MOTION ", name)
		paused = false
		current_scene = null
		room.queue_free()
		await process_frame
	quit()


func _pair(room, camera: Camera2D, stem: String) -> void:
	for step in 2:
		camera.position = Vector2(0.0 if step == 0 else SHIFT, 0.0)
		camera.force_update_scroll()
		for frame in 6:
			room._process(0.0)
			await process_frame
		root.get_texture().get_image().save_png("%s_%s.png" % [stem, "ab"[step]])
