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
		if key == "village_night":
			assert(room.get_node_or_null("CloudsFar") != null, "distant clouds behind gameplay")
			assert(room.get_node("CloudsFar").z_index == -28)
		count += 1
		room.queue_free()
		await process_frame
	assert(count == 19, "all 19 room scenes have authored depth")
	print("DEPTH_LAYERS_OK %d" % count)
	quit()
