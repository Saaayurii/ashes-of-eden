extends Node
class_name DepthLayers
## Two quiet scenic planes behind gameplay. Positions are authored per room,
## not inferred from camera position or scattered randomly at runtime. Existing
## decor art is reused as distant silhouettes; the lower edge dissolves into
## the painted mist so no object pretends to stand on an unsupported platform.

const SHADE := preload("res://assets/shaders/distant_scenery.gdshader")
const ART := {
	"tree": "res://assets/decor/tree_1.png",
	"dead_tree": "res://assets/decor/tree_4.png",
	"crypt": "res://assets/decor/crypt_1.png",
	"grave": "res://assets/decor/graveyard/crypt_1.png",
	"angel": "res://assets/decor/graveyard/angel_1.png",
	"arch": "res://assets/decor/arch.png",
	"pillar": "res://assets/decor/pillar.png",
	"monument": "res://assets/decor/monument_1.png",
}
## [art, horizontal fraction, vertical fraction, scale]. Far = sparse horizon;
## middle = a few landmarks. Every room scene has its own composition.
const LAYOUTS := {
	"village_night": {"far": [["tree", .14, .53, 1.8], ["crypt", .72, .49, 1.5]], "mid": [["dead_tree", .43, .68, 1.6], ["grave", .87, .64, 1.5]]},
	"graveyard_cross": {"far": [["crypt", .23, .47, 1.7], ["tree", .76, .50, 1.7]], "mid": [["angel", .52, .67, 1.6], ["dead_tree", .91, .70, 1.5]]},
	"graveyard_arches": {"far": [["arch", .17, .49, 2.1], ["crypt", .83, .50, 1.5]], "mid": [["dead_tree", .41, .66, 1.5], ["monument", .72, .67, 2.0]]},
	"graveyard_tree": {"far": [["crypt", .25, .49, 1.6], ["arch", .75, .47, 1.8]], "mid": [["tree", .56, .69, 1.45], ["angel", .89, .66, 1.5]]},
	"swamp_moon": {"far": [["tree", .19, .54, 1.9], ["dead_tree", .76, .51, 1.8]], "mid": [["dead_tree", .46, .73, 1.55], ["tree", .88, .71, 1.4]]},
	"swamp_red": {"far": [["dead_tree", .27, .51, 2.0], ["tree", .81, .53, 1.6]], "mid": [["tree", .52, .74, 1.5], ["dead_tree", .92, .72, 1.35]]},
	"swamp_crypt": {"far": [["crypt", .20, .51, 1.65], ["dead_tree", .76, .53, 1.8]], "mid": [["grave", .46, .72, 1.7], ["tree", .87, .71, 1.45]]},
	"catacombs_threshold": {"far": [], "mid": []}, # Its own painting and sky window, never stock cutouts.
	"catacombs_1": {"far": [["arch", .20, .48, 2.2], ["pillar", .77, .48, 2.3]], "mid": [["crypt", .45, .70, 1.4], ["pillar", .91, .73, 1.8]]},
	"catacombs_2": {"far": [["pillar", .16, .47, 2.4], ["arch", .74, .49, 2.0]], "mid": [["pillar", .48, .72, 1.8], ["grave", .87, .71, 1.6]]},
	"catacombs_3": {"far": [["crypt", .21, .50, 1.6], ["arch", .80, .47, 2.1]], "mid": [["pillar", .51, .70, 1.9], ["monument", .91, .73, 2.1]]},
	"crypt_threshold": {"far": [], "mid": []}, # Its own painting and sky window, never stock cutouts.
	"crypt_skulls": {"far": [["arch", .22, .48, 2.0], ["crypt", .77, .50, 1.6]], "mid": [["grave", .47, .72, 1.7], ["pillar", .90, .70, 1.8]]},
	"preacher_nave": {"far": [["arch", .18, .63, 1.6], ["arch", .81, .63, 1.6]], "mid": [["pillar", .37, .80, 1.45], ["pillar", .64, .80, 1.45]]},
	"church": {"far": [["arch", .22, .62, 1.7], ["arch", .79, .62, 1.7]], "mid": [["angel", .42, .81, 1.2], ["pillar", .67, .81, 1.5]]},
	"crypt_lava": {"far": [["pillar", .16, .48, 2.5], ["arch", .80, .49, 2.1]], "mid": [["crypt", .49, .73, 1.5], ["pillar", .91, .71, 1.8]]},
	"hell_gate": {"far": [["arch", .23, .47, 2.2], ["pillar", .81, .47, 2.5]], "mid": [["pillar", .51, .73, 2.0], ["monument", .90, .71, 2.1]]},
	"graveyard": {"far": [["crypt", .17, .55, 1.6], ["tree", .78, .54, 1.7]], "mid": [["angel", .48, .78, 1.5], ["dead_tree", .90, .75, 1.45]]},
	"dead_bridge": {"far": [["arch", .22, .52, 2.0], ["dead_tree", .79, .56, 1.7]], "mid": [["pillar", .47, .76, 1.8], ["monument", .90, .78, 1.9]]},
	"fallen_knight": {"far": [["crypt", .19, .51, 1.7], ["arch", .80, .52, 1.9]], "mid": [["angel", .49, .76, 1.6], ["pillar", .91, .75, 1.8]]},
	"church_ophanim": {"far": [["arch", .20, .53, 2.1], ["arch", .80, .53, 2.1]], "mid": [["pillar", .42, .77, 1.8], ["pillar", .62, .77, 1.8]]},
}
const PALETTES := {
	"village": Color("8f9db7"), "graveyard": Color("8392ae"),
	"swamp": Color("788e85"), "catacombs": Color("85859a"),
	"crypt": Color("897e91"), "preacher": Color("a395a5"),
	"church": Color("a6a0aa"), "hell": Color("aa7777"),
	"bridge": Color("8793a6"), "knight": Color("97868f"),
}


static func attach(room: Node2D) -> void:
	var key := room.scene_file_path.get_file().get_basename()
	var layout: Dictionary = LAYOUTS.get(key, {})
	if layout.is_empty():
		return
	var parent: Node2D = room.get_node_or_null("Interior") as Node2D
	var base: CanvasItem = room.get_node_or_null("Painting") as CanvasItem
	if base == null:
		base = room.get_node_or_null("Parallax") as CanvasItem
	if parent == null and base == null:
		return
	if parent == null and room.get_node_or_null("Painting") != null:
		# A painted room is its own composition: stock trees and crypts
		# stamped over it as translucent silhouettes, sliding at another speed,
		# read as stickers on the picture. Its depth is RoomLayers' far plane.
		base.z_index = -30
		var painted_windows := room.get_node_or_null("DepthWindows") as CanvasItem
		if painted_windows != null:
			painted_windows.z_index = -29
		var painted_fog := room.get_node_or_null("FogFar") as CanvasItem
		if painted_fog != null:
			painted_fog.z_index = -27
		var painted_decor := room.get_node_or_null("DecorBack") as CanvasItem
		if painted_decor != null:
			painted_decor.z_index = -25
		return
	if parent == null:
		base.z_index = -30
		var windows := room.get_node_or_null("DepthWindows") as CanvasItem
		if windows != null:
			windows.z_index = -29
		var fog := room.get_node_or_null("FogFar") as CanvasItem
		if fog != null:
			fog.z_index = -27
		parent = room
	var palette := Color("8392ae")
	for family in PALETTES:
		if key.contains(family):
			palette = PALETTES[family]
			break
	var width := float(room.get("width"))
	var height := float(room.get("height"))
	if parent != room:
		_add_interior_light(parent, width, height, key)
	_make_plane(parent, "HorizonCutouts", layout.get("far", []), width, height, .91, -28 if parent == room else 0, palette, .20)
	_make_plane(parent, "MiddleCutouts", layout.get("mid", []), width, height, .97, -26 if parent == room else 0, palette, .29)
	if room.has_meta("authored_sanctum") or room.has_meta("authored_hell_depth"):
		# Do not stamp unrelated translucent columns over room-specific art.
		parent.get_node("HorizonCutouts").visible = false
		parent.get_node("MiddleCutouts").visible = false
	var decor := room.get_node_or_null("DecorBack") as CanvasItem
	if decor != null and parent == room:
		decor.z_index = -25


static func _make_plane(parent: Node2D, plane_name: String, items: Array, width: float, height: float,
		scroll: float, z: int, palette: Color, opacity: float) -> void:
	var plane := Parallax2D.new()
	plane.name = plane_name
	plane.scroll_scale = Vector2(scroll, 1.0)
	plane.z_index = z
	parent.add_child(plane)
	if parent.get_node_or_null("Backing") != null:
		# Interior walls share z=0. A plane appended after their hundreds of
		# tiles paints over the stone like a sticker; keep it just behind them.
		parent.move_child(plane, 1 if plane_name == "HorizonCutouts" else 2)
	for i in items.size():
		var item: Array = items[i]
		var path: String = ART.get(str(item[0]), "")
		var texture := load(path) as Texture2D
		if texture == null:
			continue
		var sprite := Sprite2D.new()
		sprite.name = "Cutout%d" % i
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.position = Vector2(roundf(width * float(item[1])), roundf(height * float(item[2])))
		sprite.offset.y = -texture.get_height() * .5
		sprite.scale = Vector2.ONE * float(item[3])
		sprite.modulate = Color(palette.r, palette.g, palette.b, opacity)
		var material := ShaderMaterial.new()
		material.shader = SHADE
		sprite.material = material
		plane.add_child(sprite)


static func _add_interior_light(interior: Node2D, width: float, height: float, key: String) -> void:
	var shafts := Node2D.new()
	shafts.name = "WindowLight"
	interior.add_child(shafts)
	# The shaft illuminates the wall, while the large foreground pillars mask
	# it. The silhouettes themselves remain behind the wall's open masonry.
	var front_pillar := interior.get_node_or_null("Pillar1")
	if front_pillar != null:
		interior.move_child(shafts, front_pillar.get_index())
	var warm := key.contains("church")
	var tint := Color(0.95, 0.78, 0.52) if warm else Color(0.65, 0.72, 0.91)
	for fraction in [.24, .73]:
		var x := roundf(width * fraction)
		var beam := Polygon2D.new()
		beam.polygon = PackedVector2Array([
			Vector2(x - 12.0, 68.0), Vector2(x + 12.0, 68.0),
			Vector2(x + 88.0, height - 30.0), Vector2(x - 88.0, height - 30.0)])
		beam.vertex_colors = PackedColorArray([
			Color(tint.r, tint.g, tint.b, .11), Color(tint.r, tint.g, tint.b, .11),
			Color(tint.r, tint.g, tint.b, 0.0), Color(tint.r, tint.g, tint.b, 0.0)])
		shafts.add_child(beam)
