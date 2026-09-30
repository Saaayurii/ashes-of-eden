extends RefCounted
## Authored interiors, not another layer of moving scenery over the floor.
const WALL := preload("res://assets/decor/wall_tiles.png")
const ARCH := preload("res://assets/decor/arch.png")
const PILLAR := preload("res://assets/decor/pillar.png")
const PAINTINGS := {
	"church": "res://assets/levels/church_interior_v1.png",
	"preacher_nave": "res://assets/levels/preacher_nave_interior_v1.png",
}
const BAYS := {
	"church": [180.0, 600.0, 1020.0],
	"preacher_nave": [240.0, 600.0, 960.0],
}

static func attach(room: Node2D) -> void:
	var key := room.scene_file_path.get_file().get_basename()
	if key == "church_ophanim":
		_attach_sanctum(room)
		return
	if not BAYS.has(key):
		return
	var interior := room.get_node("Interior") as Node2D
	if interior.has_node("AuthoredMasonry"):
		return
	for child in interior.get_children():
		if str(child.name).begins_with("Wall_"):
			child.visible = false
	var decor := room.get_node("DecorBack") as Parallax2D
	decor.scroll_scale = Vector2.ONE
	for child in decor.get_children():
		if str(child.name).begins_with("arch_"):
			child.visible = false
	var masonry := Node2D.new()
	masonry.name = "AuthoredMasonry"
	interior.add_child(masonry)
	interior.move_child(masonry, 1)
	var floor_y := 380.0
	var warm := key == "church"
	var has_painting := false
	var painting_texture: Texture2D
	if PAINTINGS.has(key):
		var path: String = PAINTINGS[key]
		var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
		if texture == null:
			var image := Image.load_from_file(path)
			if image != null and not image.is_empty():
				texture = ImageTexture.create_from_image(image)
		if texture != null:
			painting_texture = texture
			var painting := Sprite2D.new()
			painting.name = "ChurchPainting" if warm else "PreacherPainting"
			painting.texture = texture
			painting.centered = false
			painting.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			painting.scale = Vector2(float(room.width) / texture.get_width(), float(room.height) / texture.get_height())
			masonry.add_child(painting)
			has_painting = true
		else:
			push_warning("[Interior] %s painting missing; using masonry fallback" % key)
	# Use the unbroken brick portion of the existing wall sheet, not its cap
	# or the ruined column strips. Leave actual openings for the depth planes.
	for y in range(0, 0 if has_painting else 420, 24):
		for x in range(-15 if (y / 24) % 2 == 1 else 0, 1200, 30):
			var cell := Rect2(x, y, 30, 24)
			var opening := false
			for center in BAYS[key]:
				if cell.intersects(Rect2(center - 78, floor_y - 164, 156, 164)):
					opening = true
			if opening:
				continue
			var stone := Sprite2D.new()
			stone.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			stone.texture = WALL
			stone.centered = false
			stone.region_enabled = true
			stone.region_rect = Rect2(0, 8, 30, 24)
			stone.position = Vector2(x, y)
			stone.modulate = Color(.60, .56, .53) if warm else Color(.48, .47, .54)
			masonry.add_child(stone)
	var frame_centers: Array = [] if has_painting else BAYS[key]
	for center in frame_centers:
		var frame := Sprite2D.new()
		frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		frame.texture = ARCH
		frame.scale = Vector2.ONE * 3.0
		frame.position = Vector2(center, floor_y - ARCH.get_height() * 1.5)
		frame.modulate = Color(.82, .76, .67) if warm else Color(.64, .63, .72)
		masonry.add_child(frame)
	# All existing columns now share one material and a floor-anchored scale.
	# They remain scenic: never add obstacles to the combat lane.
	for child in interior.get_children():
		if not str(child.name).begins_with("Pillar") or not child is Sprite2D:
			continue
		var center: float = child.position.x + child.texture.get_width() * .5
		child.texture = PILLAR
		child.visible = not has_painting
		child.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		child.scale = Vector2.ONE * 2.5
		child.position = Vector2(center - PILLAR.get_width() * 1.25, floor_y - PILLAR.get_height() * 2.5)
		child.modulate = Color(.84, .78, .70) if warm else Color(.69, .68, .76)
	var supports := Node2D.new()
	supports.name = "BalconySupports"
	interior.add_child(supports)
	var ledges := room.get_node("Ledges")
	for collider in ledges.get_children():
		if not collider is CollisionShape2D or not collider.shape is RectangleShape2D:
			continue
		var size: Vector2 = collider.shape.size
		if size.x < 100:
			continue
		var top: float = collider.position.y - size.y * .5
		if key == "preacher_nave" and painting_texture != null:
			# Use actual nave masonry for a tapered wall corbel. The old
			# stretched freestanding posts made these wall-mounted balconies
			# look like floating exterior platforms over an indoor painting.
			var left: float = collider.position.x - size.x * .5
			var corbel := Polygon2D.new()
			corbel.name = "%sCorbel" % collider.name
			corbel.position = Vector2(left, top)
			corbel.texture = painting_texture
			corbel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			corbel.polygon = PackedVector2Array([
				Vector2(0, 10), Vector2(size.x, 10), Vector2(size.x, 17),
				Vector2(size.x - 24, 25), Vector2(size.x - 42, 35),
				Vector2(42, 35), Vector2(24, 25), Vector2(0, 17),
			])
			var source_x := 300.0 if collider.position.x < room.width * .5 else 1590.0
			var uv := PackedVector2Array()
			for point in corbel.polygon:
				uv.append(Vector2(source_x + point.x / size.x * 250.0,
					520.0 + (point.y - 10.0) / 25.0 * 65.0))
			corbel.uv = uv
			supports.add_child(corbel)
			continue
		for x in [collider.position.x - size.x * .5 + 22, collider.position.x + size.x * .5 - 22]:
			var post := Sprite2D.new()
			post.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			post.texture = PILLAR
			post.centered = false
			post.scale = Vector2(1.0, (floor_y - top - 12) / PILLAR.get_height())
			post.position = Vector2(x - PILLAR.get_width() * .5, top + 12)
			post.modulate = Color(.84, .78, .70) if warm else Color(.69, .68, .76)
			supports.add_child(post)
	# The existing animated gate stays interactive. Its stone jambs simply
	# connect it to the wall and floor instead of adding a second doorway.
	var exit_frame := Node2D.new()
	exit_frame.name = "ExitFrame"
	interior.add_child(exit_frame)
	for side in [-1.0, 1.0]:
		var jamb := Sprite2D.new()
		jamb.texture = PILLAR
		jamb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		jamb.centered = false
		jamb.scale = Vector2(.5, 60.0 / PILLAR.get_height())
		jamb.position = Vector2(room.door.position.x + side * 25 - PILLAR.get_width() * .25, floor_y - 60)
		jamb.modulate = Color(.84, .78, .70) if warm else Color(.69, .68, .76)
		exit_frame.add_child(jamb)


static func _attach_sanctum(room: Node2D) -> void:
	var path := "res://assets/levels/ophanim_sanctum_v1.png"
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if texture == null:
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	if texture == null:
		push_warning("[Interior] Ophanim painting missing; retaining original scenery")
		return
	var backdrop := room.get_node("Parallax/Backdrop") as Sprite2D
	backdrop.texture = texture
	backdrop.scale = Vector2(float(room.width) / texture.get_width(), float(room.height) / texture.get_height())
	backdrop.position = Vector2.ZERO
	backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	room.get_node("Parallax").scroll_scale = Vector2.ONE
	# Lights belonged to the old painted village, not this wall's glazing.
	for child in room.get_node("Parallax").get_children():
		if child is PointLight2D:
			child.visible = false
	room.set_meta("authored_sanctum", true)
	room.get_node("DecorBack").visible = false
	room.get_node("DecorFront").visible = false
	for child in room.get_node("DecorMid").get_children():
		if str(child.name).begins_with("fence_") or str(child.name).begins_with("graveyard_yard_"):
			child.visible = false
	var fog := room.get_node("FogFar/Fog") as ColorRect
	fog.material = fog.material.duplicate()
	fog.material.set_shader_parameter("density", .06)
