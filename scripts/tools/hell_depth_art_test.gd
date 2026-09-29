extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var room = load("res://scenes/rooms/hell_gate.tscn").instantiate()
	var masks: Dictionary = {}
	for polygon in room.get_node("DepthWindows").get_children():
		masks[polygon.name] = [polygon.polygon, polygon.vertex_colors]
	var colliders: Dictionary = {}
	for holder in ["Geometry", "Ledges"]:
		for collider in room.get_node(holder).get_children():
			var local_path: String = holder + "/" + str(collider.name)
			var geometry = collider.polygon if collider is CollisionPolygon2D else collider.shape.size
			colliders[local_path] = [collider.position, geometry]
	root.add_child(room)
	await process_frame
	assert(room.has_meta("authored_hell_depth"))
	assert(room.get_node("Painting").texture.resource_path.ends_with("hell_gate_wide.png"), "foreground replaced")
	for polygon in room.get_node("DepthWindows").get_children():
		assert(polygon.polygon == masks[polygon.name][0] and polygon.vertex_colors == masks[polygon.name][1], "window edge changed")
		assert(polygon.texture.resource_path.ends_with("hell_gate_atmosphere_v2.png"))
		assert(polygon.material.shader.resource_path.ends_with("hell_depth.gdshader"))
		for i in polygon.polygon.size():
			var expected: Vector2 = polygon.polygon[i] / Vector2(room.width, room.height)
			var sampled: Vector2 = polygon.uv[i] / polygon.texture.get_size()
			assert(sampled.distance_to(expected) < .00001, "plate resolution changes sampling")
	for holder in ["Geometry", "Ledges"]:
		for collider in room.get_node(holder).get_children():
			var local_path: String = holder + "/" + str(collider.name)
			var geometry = collider.polygon if collider is CollisionPolygon2D else collider.shape.size
			assert([collider.position, geometry] == colliders[local_path], "collision changed")
	var camera := Camera2D.new()
	root.add_child(camera)
	camera.make_current()
	camera.position = Vector2(320, 360)
	await process_frame
	await process_frame
	for material in room._depth_window_materials.values():
		assert(is_zero_approx(material.get_shader_parameter("shift_px")))
	camera.position = Vector2(780, 360)
	await process_frame
	await process_frame
	var shifts: Array = []
	for material in room._depth_window_materials.values():
		var shift: float = material.get_shader_parameter("shift_px")
		assert(shift > 0 and shift <= 16, "camera travel detaches far plate")
		shifts.append(shift)
	assert(not is_equal_approx(shifts[0], shifts[1]), "different openings lost their depth factors")
	assert(not room.get_node("HorizonCutouts").visible and not room.get_node("MiddleCutouts").visible)
	assert(room.intro_cutscene == "ophanim_arrival" and room.outro_cutscene == "ch1_finale")
	room.queue_free()
	camera.queue_free()
	await process_frame
	print("HELL_DEPTH_ART_OK")
	quit()
