extends SceneTree
## Regression: the fifth room's painting must remain visible even if its
## imported texture remap is missing. Run after the editor import pass.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var room = load("res://scenes/rooms/swamp_moon.tscn").instantiate()
	root.add_child(room)
	await process_frame
	var painting := room.get_node("Painting") as Sprite2D
	assert(painting.texture != null and painting.texture.get_width() == 1600,
		"Location 5 painting did not load")
	painting.texture = null
	room._ensure_painting()
	assert(painting.texture != null and painting.texture.get_width() == 1600,
		"Location 5 painting did not recover from its source PNG")
	var sample := painting.texture.get_image().get_pixel(400, 220)
	assert(sample.a > 0.95 and sample.v < 0.95,
		"Location 5 recovered painting is blank")
	print("PAINTING_TEST_OK")
	room.queue_free()
	await process_frame
	quit()
