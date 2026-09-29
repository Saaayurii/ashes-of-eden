extends RefCounted
## Room-specific far painting: never redraw the foreground or its footholds.
const PATH := "res://assets/levels/depth/hell_gate_atmosphere_v2.png"
const HEAT := preload("res://assets/shaders/hell_depth.gdshader")

static func attach(room: Node2D) -> void:
	if room.scene_file_path.get_file().get_basename() != "hell_gate":
		return
	if room.has_meta("authored_hell_depth"):
		return
	var texture: Texture2D = load(PATH) if ResourceLoader.exists(PATH) else null
	if texture == null:
		var image := Image.load_from_file(PATH)
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	if texture == null:
		push_warning("[HellDepth] missing atmosphere plate; keeping original depth")
		return
	var uv_scale := Vector2(float(texture.get_width()) / room.width, float(texture.get_height()) / room.height)
	var materials: Dictionary = {}
	for polygon in room.get_node("DepthWindows").get_children():
		if not polygon is Polygon2D:
			continue
		var group: String = str(polygon.name).get_slice("Feather", 0)
		if not materials.has(group):
			var material := polygon.material as ShaderMaterial
			material.shader = HEAT
			material.set_shader_parameter("plate_width", float(room.width))
			material.set_shader_parameter("opacity", .70)
			material.set_shader_parameter("heat_px", .6)
			materials[group] = material
		polygon.material = materials[group]
		polygon.texture = texture
		var uv := PackedVector2Array()
		for point in polygon.polygon:
			uv.append(point * uv_scale)
		polygon.uv = uv
	room.set_meta("authored_hell_depth", true)
