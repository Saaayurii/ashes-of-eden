extends SceneTree
const ROOM_LAYERS := preload("res://scripts/rooms/room_layers.gd")
## Every painted room keeps its three planes apart (scripts/rooms/room_layers.gd):
## nothing but the far plane slides against the painting when the camera
## moves, the far plane only inside its openings, and no stock cutout is
## stamped over the picture. The rooms the studio composed (scenes/rooms/
## composed) too: every opening they keep looks out, each sky holds clouds,
## and the plane in front of the hero (Front) sits over the bodies, under
## the blows, and takes no light.
##   godot --headless --path . -s scripts/tools/layers_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL ", message)


func _run() -> void:
	var rooms: Array = (root.get_node("Data").rooms as Array).duplicate()
	if DirAccess.dir_exists_absolute("res://scenes/rooms/composed"):
		for file in ResourceLoader.list_directory("res://scenes/rooms/composed"):
			if file.ends_with(".tscn"):
				rooms.append("res://scenes/rooms/composed/" + file)
	for path in rooms:
		var composed: bool = path.contains("/composed/")
		var name: String = ("composed/" if composed else "") + path.get_file().get_basename()
		var room = load(path).instantiate()
		root.add_child(room)
		current_scene = room
		await process_frame
		if room.get_node_or_null("Painting") == null:
			room.queue_free()
			await process_frame
			continue
		_check(composed or ROOM_LAYERS.FAR_WINDOWS.has(name), "%s: no reviewed list of openings that look out" % name)
		var front = room.get_node_or_null("Front")
		if front != null:
			_check(front.z_index > 2 and front.z_index < 4, "%s: the front plane is not between the weather and the blows (z %d)" % [name, front.z_index])
			for piece in front.get_children():
				_check(piece.light_mask == 0, "%s: %s takes the room's light" % [name, piece.name])
			_check(front.depths.size() == front.get_child_count(), "%s: a front piece has no depth" % name)
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
			_check(sky.polygons.size() == (room.sky_windows.size() if room.sky_windows.size() > 1 else 0),
				"%s: %d skies, %d clipped" % [name, room.sky_windows.size(), sky.polygons.size()])
		# openings: the camera far right, then only the ones that look out move
		var camera := Camera2D.new()
		camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
		room.add_child(camera)
		camera.make_current()
		camera.position = Vector2(room.width - 640.0, 0.0)
		await process_frame
		room._process(0.0)
		var far: Array = ROOM_LAYERS.FAR_WINDOWS.get(name, [])
		if composed:
			far = range(1, room.window_depths.size() + 1)
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
