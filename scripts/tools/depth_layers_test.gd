extends SceneTree
## Every room scene gets both scenic planes with valid art.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var depth = load("res://scripts/rooms/depth_layers.gd")
	var count := 0
	for key in depth.LAYOUTS:
		var room = load("res://scenes/rooms/%s.tscn" % key).instantiate()
		root.add_child(room)
		await process_frame
		var parent = room.get_node_or_null("Interior")
		if parent == null:
			parent = room
		for name in ["HorizonCutouts", "MiddleCutouts"]:
			var plane = parent.get_node_or_null(name)
			assert(plane != null, "%s missing %s" % [key, name])
			assert(plane.get_child_count() == 2, "%s has incomplete %s" % [key, name])
			for sprite in plane.get_children():
				assert(sprite.texture != null, "%s has missing cutout art" % key)
				assert(sprite.position.x >= 0.0 and sprite.position.x <= room.width)
				assert(sprite.position.y >= 0.0 and sprite.position.y <= room.height)
		if parent != room:
			assert(parent.get_node("Backing").get_index() == 0)
			assert(parent.get_node("HorizonCutouts").get_index() == 1)
			assert(parent.get_node("MiddleCutouts").get_index() == 2)
			assert(parent.get_node("MiddleCutouts").get_index() < parent.get_node("Wall_0_1").get_index(),
				"%s paints scenic cutouts over its masonry" % key)
			assert(parent.get_node("WindowLight").get_index() > parent.get_node("Wall_0_1").get_index())
			assert(parent.get_node("WindowLight").get_index() < parent.get_node("Pillar1").get_index(),
				"%s paints light over its foreground pillars" % key)
		if key == "village_night":
			assert(room.get_node_or_null("CloudsFar") != null, "distant clouds behind gameplay")
			assert(room.get_node("CloudsFar").z_index == -28)
		var windows = room.get_node_or_null("DepthWindows")
		if windows != null:
			var group_materials: Dictionary = {}
			for polygon in windows.get_children():
				var group: String = polygon.name.get_slice("Feather", 0)
				assert(polygon.material is ShaderMaterial, "%s has an unmasked opening" % key)
				if group_materials.has(group):
					assert(polygon.material == group_materials[group], "%s has a torn opening" % key)
				else:
					for other in group_materials.values():
						assert(polygon.material != other, "%s shares material across openings" % key)
					group_materials[group] = polygon.material
			assert(group_materials.size() >= 3, "%s needs separate authored openings" % key)
		count += 1
		room.queue_free()
		await process_frame
	assert(count == 19, "all 19 room scenes have authored depth")
	print("DEPTH_LAYERS_OK %d" % count)
	quit()
