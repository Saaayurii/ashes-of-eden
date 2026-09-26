extends SceneTree
## Direct-load every room scene, independent of door/gift/story timing.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	change_scene_to_file("res://scenes/run/run.tscn")
	await process_frame
	await process_frame
	var run := current_scene
	for index in run.ROOMS.size():
		run._load_room(index)
		await process_frame
		assert(run.room != null and run.room_index == index, "Room %d failed to load" % (index + 1))
		var painting := run.room.get_node_or_null("Painting") as Sprite2D
		if painting != null:
			assert(painting.texture != null and painting.texture.get_width() >= run.room.width,
				"Room %d has no full-width painting" % (index + 1))
			assert(run.room.door.painted_arch and not run.room.door.gate.visible,
				"Room %d overlays a generic gate on its painted exit" % (index + 1))
			var windows: Node = run.room.get_node_or_null("DepthWindows")
			assert(windows != null and windows.get_child_count() >= 3,
				"Room %d has no authored depth masks" % (index + 1))
			for window in windows.get_children():
				assert(window is Polygon2D and window.texture != null,
					"Room %d has an empty depth mask" % (index + 1))
			if run.ROOMS[index].contains("graveyard_cross") or run.ROOMS[index].contains("swamp_red"):
				var silhouette := run.room.get_node_or_null("SeamSilhouette") as Sprite2D
				assert(silhouette != null and silhouette.texture != null,
					"Room %d lost its authored seam silhouette" % (index + 1))
		print("ROOM_LOAD_OK ", index + 1, " ", run.ROOMS[index])
	quit()
