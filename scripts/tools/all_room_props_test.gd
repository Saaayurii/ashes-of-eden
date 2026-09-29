extends SceneTree
## Every room's props: physical footing, transparent padding and idle soles.
var failures := 0
var total := 0
var decorations := 0

func _init() -> void:
	call_deferred("_run")

func _bottom(texture: Texture2D, frame: int, frames: int) -> int:
	var img := texture.get_image()
	if img.is_compressed():
		img.decompress()
	var w := int(img.get_width() / frames)
	for y in range(img.get_height() - 1, -1, -1):
		for x in range(frame * w, (frame + 1) * w):
			if img.get_pixel(x, y).a >= 0.1:
				return y + 1
	return 0

func _run() -> void:
	var paths := DirAccess.get_files_at("res://scenes/rooms")
	for file in paths:
		if not file.ends_with(".tscn"):
			continue
		var room = load("res://scenes/rooms/" + file).instantiate()
		root.add_child(room)
		current_scene = room
		for i in 4:
			await physics_frame
		if file in ["catacombs_2.tscn", "catacombs_3.tscn", "crypt_skulls.tscn"]:
			if room.has_node("Shrine"):
				failures += 1
				print("LAYOUT_FAIL %s: redundant exit statue" % file)
			for piece in room.get_node("Terrain").get_children():
				if piece is Sprite2D and str(piece.name).begins_with("Platform"):
					if piece.texture != room.get_node("Painting").texture or not piece.region_enabled or piece.region_rect.size.y != 12:
						failures += 1
						print("LAYOUT_FAIL %s/%s: foreign platform art" % [file, piece.name])
		if file == "crypt_skulls.tscn":
			var distant_bridge := PhysicsRayQueryParameters2D.create(Vector2(760, 338), Vector2(760, 348), 17)
			if not room.get_world_2d().direct_space_state.intersect_ray(distant_bridge).is_empty():
				failures += 1
				print("LAYOUT_FAIL crypt_skulls: distant scenic bridge has gameplay collision")
		for layer in ["DecorMid", "DecorFront"]:
			var decor = room.get_node_or_null(layer)
			if decor == null:
				continue
			for item in decor.get_children():
				if not item is Sprite2D or item.texture == null:
					continue
				decorations += 1
				var bottom := _bottom(item.texture, 0, 1)
				var local_y: float = item.offset.y + bottom
				if item.centered:
					local_y -= item.texture.get_height() / 2.0
				var foot: Vector2 = item.to_global(Vector2(item.offset.x, local_y))
				var ray := PhysicsRayQueryParameters2D.create(foot + Vector2(0, -4), foot + Vector2(0, 8), 17)
				var ground: Dictionary = room.get_world_2d().direct_space_state.intersect_ray(ray)
				if ground.is_empty():
					failures += 1
					print("DECOR_REVIEW %s/%s/%s foot=%s" % [file, layer, item.name, foot])
		var holder = room.get_node_or_null("Props")
		if holder != null:
			for prop in holder.get_children():
				if not prop is Area2D or not prop.get("sprite") is Sprite2D:
					continue
				total += 1
				var problems: Array[String] = []
				var p: Vector2 = prop.global_position
				var query := PhysicsRayQueryParameters2D.create(p + Vector2(0, -2), p + Vector2(0, 8), 17)
				var hit: Dictionary = room.get_world_2d().direct_space_state.intersect_ray(query)
				if hit.is_empty() or absf(hit.position.y - p.y) > 2:
					var near := PhysicsRayQueryParameters2D.create(p + Vector2(0, -60), p + Vector2(0, 90), 17)
					var candidate: Dictionary = room.get_world_2d().direct_space_state.intersect_ray(near)
					problems.append("floor=" + (str(candidate.position.y) if not candidate.is_empty() else "none"))
				var sprite: Sprite2D = prop.sprite
				for f in mini(int(prop.stats.get("idle_frames", 1)), sprite.hframes):
					sprite.frame = f
					prop._idle_clock = 0.0
					prop._process(0.0)
					var local_foot := Vector2(0, sprite.offset.y + _bottom(sprite.texture, f, sprite.hframes))
					var foot: float = sprite.to_global(local_foot).y - p.y
					if absf(foot) > 2:
						problems.append("frame%d foot=%s" % [f, foot])
				var remains: float = prop._authored_sprite_offset.y + _bottom(sprite.texture, sprite.hframes - 1, sprite.hframes)
				if absf(remains) > 2:
					problems.append("remains foot=%s" % remains)
				if not problems.is_empty():
					failures += 1
					print("PROP_FAIL %s/%s %s at=%s: %s" % [file, prop.name, prop.prop_id, p, ", ".join(problems)])
		current_scene = null
		room.queue_free()
		await physics_frame
	print("ALL_ROOM_PROPS: %d props, %d grounded decorations, %d failures" % [total, decorations, failures])
	quit(0 if failures == 0 else 1)
