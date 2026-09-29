extends SceneTree
## Interior art stays floor-anchored, separately composed and behind actors.
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("INTERIOR_FAIL ", message)

func _run() -> void:
	for key in ["church", "preacher_nave"]:
		var room = load("res://scenes/rooms/%s.tscn" % key).instantiate()
		root.add_child(room)
		current_scene = room
		await physics_frame
		var interior = room.get_node("Interior")
		_check(interior.has_node("AuthoredMasonry"), "%s missing authored wall" % key)
		_check(not interior.get_node("Wall_0_1").visible, "%s still draws broken-column wallpaper" % key)
		_check(room.get_node("DecorBack").scroll_scale == Vector2.ONE, "%s architecture drifts with camera" % key)
		for i in range(1, 5):
			var pillar: Sprite2D = interior.get_node("Pillar%d" % i)
			_check(pillar.texture.resource_path.ends_with("/pillar.png"), "%s inconsistent column %d" % [key, i])
			_check(absf(pillar.position.y + pillar.texture.get_height() * pillar.scale.y - 380) < .1, "%s column %d floats" % [key, i])
		var supports = interior.get_node("BalconySupports")
		_check(supports.get_child_count() == 4, "%s missing balcony posts" % key)
		for post in supports.get_children():
			_check(absf(post.position.y + post.texture.get_height() * post.scale.y - 380) < .1, "%s balcony post floats" % key)
		for jamb in interior.get_node("ExitFrame").get_children():
			_check(absf(jamb.position.y + jamb.texture.get_height() * jamb.scale.y - 380) < .1, "%s exit jamb floats" % key)
		if key == "preacher_nave":
			for prop in room.get_node("Props").get_children():
				_check(prop.position.distance_to(room.player_spawn.position + Vector2(0, 20)) >= 50, "offering overlaps arrival")
				_check(prop.position.distance_to(room.door.position + Vector2(0, 32)) >= 65, "offering overlaps exit")
			_check(room.intro_cutscene == "preacher_arrival", "preacher arrival removed")
		else:
			_check(room.has_node("Bell") and room.has_node("Shrine") and room.has_node("Props/Npc1"), "church story fixtures removed")
		var painting_name := "ChurchPainting" if key == "church" else "PreacherPainting"
		var painting = interior.get_node_or_null("AuthoredMasonry/" + painting_name)
		_check(painting != null and painting.texture.get_width() > 1200, "%s generated painting missing" % key)
		if painting != null:
			_check(painting.position == Vector2.ZERO and absf(painting.texture.get_width() * painting.scale.x - room.width) < .1, "%s painting does not fit room width" % key)
			_check(absf(painting.texture.get_height() * painting.scale.y - room.height) < .1, "%s painting does not fit room height" % key)
		for i in range(1, 5):
			_check(not interior.get_node("Pillar%d" % i).visible, "%s enlarged column overlaps painting" % key)
		current_scene = null
		room.queue_free()
		await physics_frame
	print("INTERIOR_LAYOUT_TEST %s" % ("PASSED" if failures == 0 else "FAILED"))
	quit(0 if failures == 0 else 1)
