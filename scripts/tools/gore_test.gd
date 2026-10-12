extends SceneTree
## Blood and torn limbs (data/gore.json, scripts/fx/gore.gd): a body's table is
## its material's with its own keys over them, a blow throws drops that land on
## the room's floor and leave marks, a death tears the body's own drawing into
## the pieces its table names, and Settings.gore turns it down or off.
## Untyped: -s scripts compile before autoloads.

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		_failed = true


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	await process_frame
	var gore = load("res://scripts/fx/gore.gd")
	var settings = root.get_node("Settings")
	var was: String = settings.gore

	# the game's own table
	_check(gore.spec("elian", "flesh").limbs == 0, "Elian bleeds but is never torn")
	_check(int(gore.spec("possessed_villager", "flesh").limbs) >= 2, "a possessed villager can be torn apart")
	_check(int(gore.spec("wraith", "spirit").limbs) == 0, "a spirit is never torn")
	_check(gore.spec("nobody", "no_such").blood == gore.spec("nobody", "flesh").blood, "an unknown material bleeds like flesh")

	# the cuts: as many pieces as asked, all inside the drawing, none overlapping in area beyond it
	var b := Rect2(10, 4, 20, 40)
	for limbs in [2, 3, 4, 5, 6]:
		var parts: Array = gore.cut(b, limbs)
		var area := 0.0
		var inside := true
		for part in parts:
			area += part.rect.get_area()
			inside = inside and b.grow(0.5).encloses(part.rect)
		_check(parts.size() == limbs and inside and area <= b.get_area() + 1.0, "%d limbs: %d pieces inside the drawing" % [limbs, parts.size()])

	# a room: a floor at y 100
	var room := Node2D.new()
	room.add_to_group("room")
	root.add_child(room)
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(800, 20)
	shape.shape = rect
	floor_body.add_child(shape)
	floor_body.position = Vector2(0, 110)
	room.add_child(floor_body)
	var body := Node2D.new()
	body.position = Vector2(0, 88)
	room.add_child(body)
	var sprite := AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var atlas := AtlasTexture.new()
	atlas.atlas = ImageTexture.create_from_image(image)
	atlas.region = Rect2(0, 0, 32, 32)
	frames.add_frame("default", atlas)
	sprite.sprite_frames = frames
	sprite.position = Vector2(0, -10)
	body.add_child(sprite)
	await _frames(2)

	settings.set_gore("full")
	gore.use({"flesh": {"drops": 10, "gush": 10, "limbs": 4, "chance": 1.0, "pool": 10, "bleed": 0.3}}, {})
	var thrown0: int = gore.thrown
	gore.hit(body, "t", "flesh", body.global_position + Vector2(0, -10), Vector2(1, -0.3), 1.0)
	_check(gore.thrown - thrown0 == 10, "a plain blow throws its drops (%d)" % (gore.thrown - thrown0))
	_check(body.get_node_or_null("Bleed") != null, "and leaves a wound that drips")
	var marked0: int = gore.marked
	await _frames(90)
	var layer = room.get_node_or_null("Gore")
	_check(layer != null, "the room got its blood layer")
	_check(gore.marked > marked0, "the drops landed on the floor and left marks (%d)" % (gore.marked - marked0))
	_check(layer != null and layer._drops.is_empty(), "no drop is still in the air a second and a half later")
	var on_floor := true
	if layer != null:
		for st in layer._stains:
			on_floor = on_floor and absf(st.p.y - 100.0) <= 1.0
	_check(on_floor, "every mark lies on the floor's lip")

	var torn0: int = gore.torn
	var torn: bool = gore.death(body, "t", "flesh", sprite, Vector2(1, -0.2))
	_check(torn and gore.torn - torn0 == 4, "a death tears the drawing into its four pieces")
	var pieces := get_nodes_in_group("gore_piece")
	await _frames(240)
	var resting := 0
	for piece in pieces:
		if is_instance_valid(piece) and piece._resting and piece.global_position.y < 101.0:
			resting += 1
	_check(resting == 4, "the pieces fell, bounced and came to rest on the floor (%d)" % resting)

	settings.set_gore("reduced")
	thrown0 = gore.thrown
	gore.hit(body, "t", "flesh", body.global_position, Vector2.RIGHT, 1.0)
	_check(gore.thrown - thrown0 == 5, "reduced: half the drops")
	_check(not gore.death(body, "t", "flesh", sprite, Vector2.RIGHT), "reduced: nobody is torn")
	settings.set_gore("off")
	thrown0 = gore.thrown
	gore.hit(body, "t", "flesh", body.global_position, Vector2.RIGHT, 1.0)
	_check(gore.thrown == thrown0 and not gore.death(body, "t", "flesh", sprite, Vector2.RIGHT), "off: no blood at all")

	settings.set_gore(was)
	_check(settings.gore == was, "the setting is put back as it was found")
	print("gore_test: " + ("FAILED" if _failed else "passed"))
	quit(1 if _failed else 0)
