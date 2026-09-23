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
		print("ROOM_LOAD_OK ", index + 1, " ", run.ROOMS[index])
	quit()
