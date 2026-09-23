extends Control
## The room at a glance, top right of the HUD. Drawn from the live scene,
## nothing is replicated for it: a client has the same room, the same bodies
## and the enemies' replicated `aware`.
##
## Layers, back to front:
##   the room's own painting, dimmed (painted rooms are their picture), or a
##   mood gradient for the older rooms → the geometry with a drop shadow and a
##   lit top edge (one-way ledges thinner and paler, ramps as polygons) → fog
##   of war over what our body has not been near yet → the camera's view as
##   corner brackets → shrine, chests, door, NPCs → sleeping enemies with a
##   faint sight cone (plan the backstab from here), hunters pulsing red, the
##   boss as a gold diamond → players as chevrons pointing where they face →
##   an ornate frame in the same stone-and-gold as the HUD bars.

const BOX_COLOR := Color(0.04, 0.035, 0.05, 0.86)
const PAINT_TINT := Color(0.52, 0.5, 0.58, 0.9)
const PAINT_SHADE := Color(0.02, 0.02, 0.04, 0.2)
const SKY_TOP := Color(0.1, 0.1, 0.17, 0.92)
const SKY_BOTTOM := Color(0.04, 0.03, 0.05, 0.92)
const SOLID_FILL := Color(0.36, 0.32, 0.36, 0.97)
const SOLID_EDGE := Color(0.82, 0.76, 0.66, 1.0)
const LEDGE_FILL := Color(0.58, 0.54, 0.5, 0.9)
const LEDGE_EDGE := Color(0.95, 0.9, 0.78, 1.0)
const SHADOW := Color(0, 0, 0, 0.55)
const FOG := Color(0.02, 0.02, 0.035, 0.6)
const VIEW_COLOR := Color(1, 0.96, 0.85, 0.55)
const DOOR_OPEN := Color(1.0, 0.82, 0.42)
const DOOR_SHUT := Color(0.5, 0.46, 0.5)
const SHRINE := Color(0.62, 0.9, 1.0)
const CHEST := Color(0.95, 0.72, 0.3)
const HUNTER := Color(1.0, 0.28, 0.25)
const SLEEPER := Color(0.7, 0.64, 0.7)
const CONE := Color(0.95, 0.9, 0.6, 0.07)
const BOSS := Color(1.0, 0.8, 0.35)
const NPC := Color(0.55, 0.9, 0.95)
const FRAME_DARK := Color(0.08, 0.06, 0.06, 1.0)
const FRAME_STONE := Color(0.42, 0.37, 0.33, 1.0)
const FRAME_LIGHT := Color(0.86, 0.77, 0.6, 1.0)
const FRAME_GOLD := Color(0.84, 0.66, 0.34, 1.0)
## Fog of war: one cell per this many room pixels, revealed within REVEAL of our body.
const FOG_CELL := 16.0
const REVEAL := 150.0
## Inside the frame, the map keeps this margin.
const INSET := 5.0

var _room: Room
var _solids: Array[Rect2] = []
var _ledges: Array[Rect2] = []
var _ramps: Array[PackedVector2Array] = []
var _painting: Sprite2D
var _shrine: Node2D
var _fog_image: Image
var _fog_texture: ImageTexture
var _fog_size := Vector2i.ZERO


func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # the painting and the fog, scaled down, want it soft
	EventBus.room_started.connect(func(_index: int) -> void: _room = null)


func _process(_delta: float) -> void:
	if _room == null or not is_instance_valid(_room) or _room.is_queued_for_deletion():
		var found := _find_room()
		if found != _room:
			_room = found
			_rebuild()
	if _room != null:
		_reveal()
	queue_redraw()


## The one room in the tree that is not on its way out.
func _find_room() -> Room:
	for node in get_tree().get_nodes_in_group("room"):
		var room := node as Room
		if room != null and not room.is_queued_for_deletion() and room.is_node_ready():
			return room
	return null


## Everything static about the room, read once per room.
func _rebuild() -> void:
	_solids.clear()
	_ledges.clear()
	_ramps.clear()
	_painting = null
	_shrine = null
	_fog_image = null
	_fog_texture = null
	if _room == null:
		return
	for holder_name in ["Geometry", "Ledges"]:
		var holder := _room.get_node_or_null(holder_name)
		if holder == null:
			continue
		for child in holder.get_children():
			if child is CollisionShape2D and (child as CollisionShape2D).shape is RectangleShape2D:
				var size: Vector2 = ((child as CollisionShape2D).shape as RectangleShape2D).size
				var rect := Rect2((child as Node2D).position - size / 2.0, size)
				if rect.end.x <= 0.0 or rect.position.x >= _room.width or rect.end.y <= 0.0:
					continue  # the invisible side walls
				(_ledges if holder_name == "Ledges" else _solids).append(rect)
			elif child is CollisionPolygon2D:
				var poly := child as CollisionPolygon2D
				var points := PackedVector2Array()
				for p in poly.polygon:
					points.append(poly.position + p)
				_ramps.append(points)
	_painting = _room.get_node_or_null("Painting") as Sprite2D
	_shrine = _room.get_node_or_null("Shrine") as Node2D
	_fog_size = Vector2i(ceili(_room.width / FOG_CELL), ceili(_room.height / FOG_CELL))
	_fog_image = Image.create(maxi(1, _fog_size.x), maxi(1, _fog_size.y), false, Image.FORMAT_RGBA8)
	_fog_image.fill(FOG)
	_fog_texture = ImageTexture.create_from_image(_fog_image)


## Clears the fog around our own body. Cheap: a handful of cells per frame at most.
func _reveal() -> void:
	if _fog_image == null:
		return
	var me := _own_body()
	if me == null:
		return
	var local := me.global_position - _room.global_position
	var centre := Vector2i(floori(local.x / FOG_CELL), floori(local.y / FOG_CELL))
	var radius := ceili(REVEAL / FOG_CELL)
	var changed := false
	for y in range(maxi(0, centre.y - radius), mini(_fog_size.y, centre.y + radius + 1)):
		for x in range(maxi(0, centre.x - radius), mini(_fog_size.x, centre.x + radius + 1)):
			var distance := Vector2(x - centre.x, y - centre.y).length() * FOG_CELL
			if distance > REVEAL:
				continue
			# Soft edge: the last third of the radius only thins the fog.
			var alpha := FOG.a * clampf((distance - REVEAL * 0.66) / (REVEAL * 0.34), 0.0, 1.0)
			var current := _fog_image.get_pixel(x, y)
			if alpha < current.a - 0.01:
				_fog_image.set_pixel(x, y, Color(FOG, alpha))
				changed = true
	if changed:
		_fog_texture.update(_fog_image)


func _own_body() -> Player:
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as Player
		if body != null and body.is_multiplayer_authority():
			return body
	return null


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size)
	draw_rect(box, BOX_COLOR)
	if _room == null:
		_draw_frame(box)
		return
	var inner := box.grow(-INSET)
	# The room keeps its proportions inside the box, centred.
	var room_size := Vector2(_room.width, _room.height)
	var scale := minf(inner.size.x / room_size.x, inner.size.y / room_size.y)
	var origin := inner.position + (inner.size - room_size * scale) / 2.0
	var map_rect := Rect2(origin, room_size * scale)
	var room_origin: Vector2 = _room.global_position
	var t := Time.get_ticks_msec() / 1000.0

	_draw_backdrop(map_rect, origin, scale)
	_draw_geometry(origin, scale)
	if _fog_texture != null:
		draw_texture_rect(_fog_texture, map_rect, false)
		_draw_outline(origin, scale)
	_draw_view(map_rect, origin, scale, room_origin)
	_draw_landmarks(origin, scale, room_origin, t)
	_draw_enemies(origin, scale, room_origin, t)
	_draw_players(origin, scale, room_origin, t)
	_draw_frame(box)


# ----------------------------------------------------------------- layers ---

func _draw_backdrop(map_rect: Rect2, origin: Vector2, scale: float) -> void:
	if _painting != null and _painting.texture != null:
		var local := _painting.get_rect()
		var world := Rect2(_painting.position + local.position * _painting.scale, local.size * _painting.scale)
		draw_texture_rect(_painting.texture, Rect2(origin + world.position * scale, world.size * scale), false, PAINT_TINT)
		draw_rect(map_rect, PAINT_SHADE)
		return
	# Older rooms: a sky that darkens towards the ground, in eight bands.
	for i in 8:
		var band := Rect2(map_rect.position + Vector2(0, map_rect.size.y * i / 8.0), Vector2(map_rect.size.x, map_rect.size.y / 8.0 + 1.0))
		draw_rect(band, SKY_TOP.lerp(SKY_BOTTOM, i / 7.0))


func _draw_geometry(origin: Vector2, scale: float) -> void:
	for points in _ramps:
		var mapped := PackedVector2Array()
		for p in points:
			mapped.append(origin + p * scale)
		var shadow := PackedVector2Array()
		for p in mapped:
			shadow.append(p + Vector2(1, 1))
		if mapped.size() >= 3:
			draw_colored_polygon(shadow, SHADOW)
			draw_colored_polygon(mapped, SOLID_FILL)
	for rect in _solids:
		_draw_slab(rect, origin, scale, SOLID_FILL, SOLID_EDGE, 1.0)
	for rect in _ledges:
		_draw_slab(rect, origin, scale, LEDGE_FILL, LEDGE_EDGE, 0.0)


## A block with a drop shadow and a lit top edge: the one thing that makes a
## flat map read as stone you can stand on.
func _draw_slab(rect: Rect2, origin: Vector2, scale: float, fill: Color, edge: Color, min_height: float) -> void:
	var top_left := origin + rect.position * scale
	var extent := (rect.size * scale).max(Vector2(1.0, maxf(1.0, min_height)))
	var mapped := Rect2(top_left, extent)
	draw_rect(Rect2(mapped.position + Vector2(1, 1), mapped.size), SHADOW)
	draw_rect(mapped, fill)
	draw_line(mapped.position, mapped.position + Vector2(mapped.size.x, 0), edge, 1.0)


## Over the fog: just the top edges, faint, so the shape of the room is never a
## mystery — the fog hides what is there, not where you can stand.
func _draw_outline(origin: Vector2, scale: float) -> void:
	for rect in _solids + _ledges:
		var a := origin + rect.position * scale
		draw_line(a, a + Vector2(maxf(1.0, rect.size.x * scale), 0), Color(SOLID_EDGE, 0.28), 1.0)


func _draw_view(map_rect: Rect2, origin: Vector2, scale: float, room_origin: Vector2) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	var view := get_viewport_rect().size / camera.zoom
	var top_left := camera.get_screen_center_position() - view / 2.0 - room_origin
	var rect := Rect2(origin + top_left * scale, view * scale).intersection(map_rect)
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return
	draw_rect(rect, Color(1, 1, 1, 0.05))
	# Corner brackets instead of a box: the view is a frame, not a wall.
	var arm := minf(4.0, minf(rect.size.x, rect.size.y) / 3.0)
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var sx := 1.0 if corner.x <= rect.get_center().x else -1.0
		var sy := 1.0 if corner.y <= rect.get_center().y else -1.0
		draw_line(corner, corner + Vector2(arm * sx, 0), VIEW_COLOR, 1.0)
		draw_line(corner, corner + Vector2(0, arm * sy), VIEW_COLOR, 1.0)


func _draw_landmarks(origin: Vector2, scale: float, room_origin: Vector2, t: float) -> void:
	if _shrine != null and is_instance_valid(_shrine):
		var at := origin + (_shrine.global_position - room_origin) * scale + Vector2(0, -2)
		_glow(at, 4.0, SHRINE, 0.18 + 0.08 * sin(t * 2.0))
		_diamond(at, 2.0, SHRINE)
	for node in get_tree().get_nodes_in_group("props"):
		var prop := node as Node2D
		if prop == null or not (prop.get("stats") is Dictionary) or prop.stats.get("kind", "") != "chest" or bool(prop.get("_spent")):
			continue
		var at := origin + (prop.global_position - room_origin) * scale + Vector2(0, -1.5)
		draw_rect(Rect2(at - Vector2(2, 1.5), Vector2(4, 3)), CHEST)
		draw_line(at + Vector2(-2, -0.5), at + Vector2(2, -0.5), CHEST.darkened(0.45), 1.0)
	if _room.door != null:
		var at := origin + (_room.door.global_position - room_origin) * scale
		var open: bool = _room.door.open
		if open:
			_glow(at, 6.0, DOOR_OPEN, 0.25 + 0.15 * sin(t * 4.0))
		_arch(at, DOOR_OPEN if open else DOOR_SHUT, open)
	for node in get_tree().get_nodes_in_group("npc"):
		var npc := node as Node2D
		if npc == null:
			continue
		var spoken := bool(npc.get("_spoken"))
		var at := origin + (npc.global_position - room_origin) * scale + Vector2(0, -2)
		if not spoken:
			_glow(at, 3.5, NPC, 0.2 + 0.1 * sin(t * 3.0))
		draw_circle(at, 1.3, NPC if not spoken else NPC.darkened(0.45))


func _draw_enemies(origin: Vector2, scale: float, room_origin: Vector2, t: float) -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead():
			continue
		var at := origin + (enemy.global_position - room_origin) * scale + Vector2(0, -1.5)
		var boss: bool = enemy.stats.get("boss", false)
		if boss:
			_glow(at, 7.0, BOSS, 0.3 + 0.15 * sin(t * 3.0))
			_diamond(at, 3.0, BOSS)
			draw_circle(at, 1.0, HUNTER)
			continue
		if enemy.aware:
			var pulse := 0.5 + 0.5 * sin(t * 6.0 + enemy.get_instance_id() % 7)
			_glow(at, 3.5 + pulse, HUNTER, 0.25 + 0.2 * pulse)
			draw_circle(at, 1.6, HUNTER)
		else:
			_sight_cone(at, enemy, scale)
			draw_circle(at, 1.3, SLEEPER)
			draw_line(at, at + Vector2(enemy.facing * 3.0, 0.0), SLEEPER, 1.0)


## Where a sleeping enemy is looking — the cone it would spot you in.
func _sight_cone(at: Vector2, enemy: Enemy, scale: float) -> void:
	var sight: Dictionary = enemy.stats.get("sight", {})
	var flying: bool = enemy.stats.get("behaviour", "walker") in ["flyer", "boss_ophanim"]
	var defaults: Array = Enemy.SIGHT_DEFAULTS["flyer" if flying else "walker"]
	var reach := float(sight.get("range", defaults[0])) * scale * 0.7
	var half_height := float(sight.get("height", defaults[1])) * scale * 0.5
	var tip := at + Vector2(enemy.facing * reach, 0.0)
	draw_colored_polygon(PackedVector2Array([at, tip + Vector2(0, -half_height), tip + Vector2(0, half_height)]), CONE)


func _draw_players(origin: Vector2, scale: float, room_origin: Vector2, t: float) -> void:
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as Player
		if body == null:
			continue
		var at := origin + (body.global_position - room_origin) * scale + Vector2(0, -2)
		var tint: Color = Player.SLOT_TINTS[body.slot % Player.SLOT_TINTS.size()]
		var mine := body.is_multiplayer_authority()
		if mine:
			_glow(at, 5.0 + sin(t * 2.5), Color(1, 1, 1), 0.22)
		# A chevron pointing the way the body faces.
		var f := float(body.facing)
		var chevron := PackedVector2Array([at + Vector2(3.0 * f, 0), at + Vector2(-2.0 * f, -2.5), at + Vector2(-0.8 * f, 0), at + Vector2(-2.0 * f, 2.5)])
		draw_colored_polygon(chevron, tint if mine else tint.darkened(0.3))
		draw_polyline(chevron + PackedVector2Array([chevron[0]]), Color(0, 0, 0, 0.7), 1.0)


func _draw_frame(box: Rect2) -> void:
	# Inner shadow so the map sits *in* the frame.
	for i in 3:
		var a := 0.35 - i * 0.1
		draw_rect(box.grow(-2.0 - i), Color(0, 0, 0, a), false, 1.0)
	# Stone bevel: dark outer line, stone body, light top-left, dark bottom-right.
	draw_rect(box, FRAME_DARK, false, 1.0)
	var r := box.grow(-1.0)
	draw_rect(r, FRAME_STONE, false, 1.0)
	draw_line(r.position, Vector2(r.end.x, r.position.y), FRAME_LIGHT, 1.0)
	draw_line(r.position, Vector2(r.position.x, r.end.y), FRAME_LIGHT.darkened(0.2), 1.0)
	draw_line(Vector2(r.position.x, r.end.y - 1.0), r.end - Vector2(0, 1.0), FRAME_DARK.lightened(0.1), 1.0)
	draw_line(Vector2(r.end.x - 1.0, r.position.y), r.end - Vector2(1.0, 0), FRAME_DARK.lightened(0.1), 1.0)
	draw_rect(box.grow(-2.0), FRAME_DARK, false, 1.0)
	# Gold studs at the corners, the same diamond as the HUD bars' left cap.
	for corner in [box.position + Vector2(2, 2), Vector2(box.end.x - 3, box.position.y + 2), box.end - Vector2(3, 3), Vector2(box.position.x + 2, box.end.y - 3)]:
		_diamond(corner, 2.5, FRAME_DARK)
		_diamond(corner, 1.6, FRAME_GOLD)
	# A small gold cartouche centred on the top edge.
	var mid := Vector2(box.get_center().x, box.position.y + 1.5)
	draw_rect(Rect2(mid - Vector2(8, 1), Vector2(16, 2)), FRAME_GOLD)
	_diamond(mid, 2.2, FRAME_GOLD)


# ---------------------------------------------------------------- shapes ---

func _diamond(at: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius, 0), at + Vector2(0, radius), at + Vector2(-radius, 0)]), color)


## A soft halo: three rings fading out, cheap enough to draw every frame.
func _glow(at: Vector2, radius: float, color: Color, strength: float) -> void:
	for i in 3:
		draw_circle(at, radius * (1.0 - i * 0.28), Color(color, strength * (0.35 + i * 0.3)))


## A door: an arch, filled when it opens.
func _arch(at: Vector2, color: Color, open: bool) -> void:
	var w := 2.5
	var h := 5.0
	var base := at + Vector2(0, 2)
	var points := PackedVector2Array([base + Vector2(-w, 0), base + Vector2(-w, -h + w), base + Vector2(-w * 0.7, -h + 0.7), base + Vector2(0, -h), base + Vector2(w * 0.7, -h + 0.7), base + Vector2(w, -h + w), base + Vector2(w, 0)])
	if open:
		draw_colored_polygon(points, color)
	else:
		draw_polyline(points, color, 1.0)
		draw_line(base + Vector2(-w, -h * 0.45), base + Vector2(w, -h * 0.45), color, 1.0)
