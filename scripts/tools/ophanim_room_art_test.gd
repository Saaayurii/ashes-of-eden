extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var room = load("res://scenes/rooms/church_ophanim.tscn").instantiate()
	root.add_child(room)
	await process_frame
	assert(room.has_meta("authored_sanctum"), "sanctum art failed to load")
	var backdrop: Sprite2D = room.get_node("Parallax/Backdrop")
	assert(backdrop.texture.resource_path.ends_with("ophanim_sanctum_v1.png"))
	assert(backdrop.position == Vector2.ZERO and not backdrop.centered)
	assert(absf(backdrop.texture.get_width() * backdrop.scale.x - room.width) < .1)
	assert(absf(backdrop.texture.get_height() * backdrop.scale.y - room.height) < .1)
	assert(room.get_node("Parallax").scroll_scale == Vector2.ONE, "wall drifts with camera")
	assert(not room.get_node("DecorBack").visible and not room.get_node("DecorFront").visible)
	assert(not room.get_node("HorizonCutouts").visible and not room.get_node("MiddleCutouts").visible)
	for child in room.get_node("DecorMid").get_children():
		if str(child.name).begins_with("fence_") or str(child.name).begins_with("graveyard_yard_"):
			assert(not child.visible, "outdoor ornament overlaps sanctuary")
	assert(room.intro_cutscene == "ophanim_arrival" and room.outro_cutscene == "ch1_finale")
	assert(room.get_node("Spawns/Spawn1").enemy_id == "ophanim")
	assert(room.has_node("Props/Npc1") and room.has_node("Shrine"))
	assert(room.get_node("Ledges").get_child_count() == 5, "combat ledges changed")
	assert(room.get_node("Geometry/Ground1Shape").position.y == 340, "floor moved")
	room.queue_free()
	await process_frame
	print("OPHANIM_ROOM_ART_OK")
	quit()
