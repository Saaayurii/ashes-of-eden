extends SceneTree
const ROOM_LAYERS := preload("res://scripts/rooms/room_layers.gd")
## Every painted room keeps its three planes apart (scripts/rooms/room_layers.gd):
## nothing but the far plane slides against the painting when the camera
## moves, the far plane only inside its openings, and no stock cutout is
## stamped over the picture.
##   godot --headless --path . -s scripts/tools/layers_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL ", message)


func _run() -> void:
	var rooms: Array = load("res://scripts/run/run.gd").get_script_constant_map()["ROOMS"]
	for path in rooms:
		var name: String = path.get_file().get_basename()
		var room = load(path).instantiate()
		root.add_child(room)
		current_scene = room
		await process_frame
		if room.get_node_or_null("Painting") == null:
			room.queue_free()
			await process_frame
			continue
		_check(ROOM_LAYERS.FAR_WINDOWS.has(name), "%s: no reviewed list of openings that look out" % name)
		for cutout in ["HorizonCutouts", "MiddleCutouts"]:
			_check(room.get_node_or_null(cutout) == null, "%s: stock %s over the painting" % [name, cutout])
		# every Parallax2D left in the room is either anchored to the world or
		# clipped to the sky
		for layer in room.find_children("*", "Parallax2D", true, false):
			var clipped: bool = layer.get_parent().name == "SkyClip"
			_check(clipped or layer.scroll_scale == Vector2.ONE,
				"%s: %s slides over the painting at %s" % [name, room.get_path_to(layer), layer.scroll_scale])
		var sky = room.get_node_or_null("SkyClip")
		if sky != null:
			_check(sky.clip_children == CanvasItem.CLIP_CHILDREN_ONLY and sky.polygon.size() >= 3,
				"%s: the clouds are not held inside the sky" % name)
		# openings: the camera far right, then only the ones that look out move
		var camera := Camera2D.new()
		camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
		room.add_child(camera)
		camera.make_current()
		camera.position = Vector2(room.width - 640.0, 0.0)
		await process_frame
		room._process(0.0)
		var far: Array = ROOM_LAYERS.FAR_WINDOWS.get(name, [])
		var windows = room.get_node_or_null("DepthWindows")
		var seen := {}
		for polygon in windows.get_children() if windows != null else []:
			var group: String = str(polygon.name).get_slice("Feather", 0)
			if seen.has(group):
				continue
			seen[group] = true
			var index := int(group.trim_prefix("Window"))
			var shift: float = polygon.material.get_shader_parameter("shift_px")
			if far.has(index):
				_check(shift > 0.0 and shift <= 16.0, "%s: opening %d looks out but does not move (%s)" % [name, index, shift])
			else:
				_check(shift == 0.0, "%s: opening %d is masonry and moves by %s" % [name, index, shift])
		if failures == 0:
			print("  ok   %s: far %s, the rest still" % [name, far])
		current_scene = null
		room.queue_free()
		await process_frame
	print("LAYERS TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
