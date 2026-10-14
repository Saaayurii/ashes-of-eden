extends SceneTree
## Blood and torn limbs (data/gore.json, scripts/fx/gore.gd): a body's table is
## its material's with its own keys over them, a blow throws drops that land on
## the room's floor and leave marks, a death tears the body's own drawing into
## pieces its table names, and Settings.gore turns it down or off. Blood keeps
## to what it lands on: a mark stops at its ledge's edge and drips off it, a
## streak runs no further than its wall, a ledge's underside drips, a heavy drop
## splashes, drops thrown into the depth stick to the painting but never to an
## opening in it, and the marks soak in through a multiply pass. In water a
## drop clouds, on lava it hisses off; reduced blood throws no mist or splash.
## Untyped: -s scripts compile before autoloads.

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		_failed = true


func _box(room: Node2D, at: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	body.position = at
	room.add_child(body)
	return body


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
	# every way to tear, ragged: inside the drawing, the right pieces, the right ones left standing
	var ways := {"head": [6, ["head", "body"]], "half": [6, ["upper", "lower"]],
		"limb": [6, ["arm", "body", "legs"]], "all": [6, ["head", "arm_l", "torso", "arm_r", "leg_l", "leg_r"]]}
	for way in ways:
		var ok := true
		for n in 20:
			var parts: Array = gore.cut(b, ways[way][0], way, gore.RAGGED)
			var names := parts.map(func(p): return str(p.name).trim_suffix("_l").trim_suffix("_r") if way == "limb" and str(p.name).begins_with("arm") else str(p.name))
			ok = ok and names == ways[way][1]
			for part in parts:
				ok = ok and b.grow(0.5).encloses(part.rect) and part.rect.size.x >= 1.0 and part.rect.size.y >= 1.0
				ok = ok and part.stands == (way != "all" and str(part.name) in ["body", "lower", "legs"])
		_check(ok, "torn %s: %s, inside the drawing, what is left stands" % [way, ways[way][1]])
	_check(gore.cut(b, 4, "limb").map(func(p): return p.name) == ["head", "body"], "a body without arms loses its head instead")
	var shapes := {}
	for n in 12:
		shapes[str(gore.cut(b, 6, "all", gore.RAGGED).map(func(p): return p.rect))] = true
	_check(shapes.size() > 6, "ragged cuts: no two deaths cut alike (%d of 12)" % shapes.size())
	var picked := {}
	for n in 400:
		var w: String = gore.pick_cut({"all": 1, "head": 1, "half": 0}, 6)
		picked[w] = picked.get(w, 0) + 1
	_check(picked.size() == 2 and picked.get("all", 0) > 120 and picked.get("head", 0) > 120, "the ways are picked by their weights: %s" % picked)
	_check(gore.pick_cut({"limb": 1}, 4) == "head" and gore.pick_cut({}, 6) == "all", "no arms: the head; no weights: to pieces")

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
	# a ledge floating at 46..54 from x 280 to 320, a wall standing from y 40 to 80 at x 495, the sky's opening up high
	_box(room, Vector2(300, 50), Vector2(40, 8))
	_box(room, Vector2(500, 60), Vector2(10, 40))
	var lava = load("res://scripts/rooms/hazard.gd").new()
	lava.size = Vector2(100, 20)
	lava.position = Vector2(-200, 90)
	room.add_child(lava)
	var windows := Node2D.new()
	windows.name = "DepthWindows"
	room.add_child(windows)
	var corners := [Vector2(-200, -300), Vector2(200, -300), Vector2(200, -100), Vector2(-200, -100)]
	for i in corners.size():
		var triangle := Polygon2D.new()
		triangle.name = "Window1Feather%d" % (i + 1)
		triangle.polygon = PackedVector2Array([Vector2.ZERO, corners[i], corners[(i + 1) % corners.size()]])
		windows.add_child(triangle)
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
	gore.use({"flesh": {"drops": 10, "gush": 10, "limbs": 4, "chance": 1.0, "pool": 10, "bleed": 0.3, "shade": 0.3,
		"cuts": {"all": 1}}}, {})
	var thrown0: int = gore.thrown
	gore.hit(body, "t", "flesh", body.global_position + Vector2(0, -10), Vector2(1, -0.3), 1.0)
	_check(gore.thrown - thrown0 >= 7 and gore.thrown - thrown0 <= 13, "a plain blow throws about its drops (%d)" % (gore.thrown - thrown0))
	var tints := {}
	for d in room.get_node("Gore")._drops:
		tints[d[2].to_html()] = true
	_check(tints.size() > 3, "every drop its own shade of the blood (%d shades)" % tints.size())
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
			if st.face == 0:
				on_floor = on_floor and st.p.y <= 100.0 and st.p.y >= 97.0
	_check(on_floor, "every mark on a floor lies across the floor's top face (y 97..100)")

	# where blood lands, it keeps to
	if layer != null:
		layer._stains.clear()
		var how := {"stain": 1.0, "life": 30.0, "soak": 0.6, "splash": 6.0, "run": 30.0, "drip": 1.0, "back": 0.0, "cloud": 10.0}
		for i in 12:  # on the ledge, close to its right edge
			layer.drop(Vector2(randf_range(316, 319.5), 30), Vector2(0, 40), Color.RED, how, gore.SPLASHED)
		await _frames(16)
		var on_ledge: Array = layer._stains.filter(func(st): return st.face == 0 and st.p.y <= 46.0 and st.p.y >= 43.0)
		_check(not on_ledge.is_empty() and on_ledge.all(func(st): return st.lo == 280.0 and st.hi == 320.0),
			"a mark on a ledge knows the ledge's edges (%d marks)" % on_ledge.size())
		_check(not layer._drips.is_empty(), "what hangs over the edge gathers to drip off it")
		await _frames(240)
		_check(layer._stains.any(func(st): return st.face == 0 and st.p.y <= 100.0 and st.p.y >= 97.0 and st.p.x >= 319.0),
			"and drips down to the floor below the edge")

		layer._stains.clear()
		layer._drips.clear()
		for i in 8:  # into the wall's side
			layer.drop(Vector2(470, randf_range(44, 76)), Vector2(400, 0), Color.RED, how, gore.SPLASHED)
		await _frames(20)
		var streaks: Array = layer._stains.filter(func(st): return st.face == 1)
		_check(streaks.size() >= 6 and streaks.all(func(st): return st.p.y + st.w <= 80.5 and st.hi == 80.0),
			"a streak runs down the wall, never past its foot (%d)" % streaks.size())
		_check(streaks.any(func(st): return st.w > st.spot + 3.0), "some streaks run a long way")

		layer._stains.clear()
		layer.drop(Vector2(300, 80), Vector2(0, -400), Color.RED, how, gore.SPLASHED)
		await _frames(10)
		_check(layer._stains.any(func(st): return st.face == 2 and absf(st.p.y - 54.0) <= 1.0), "a drop thrown up marks the ledge's underside")
		_check(not layer._drips.is_empty(), "and the underside drips")
		layer._drips.clear()

		var thrown1: int = gore.thrown
		layer.drop(Vector2(100, 40), Vector2(0, 300), Color.RED, how)
		await _frames(20)
		_check(gore.thrown - thrown1 >= 2, "a heavy drop splashes into droplets (%d)" % (gore.thrown - thrown1 - 1))

		layer._stains.clear()
		for i in 10:  # into the depth: in the sky's opening, by the wall, out in the open where the painting is far
			layer.drop(Vector2(randf_range(-150, 150), -250), Vector2.ZERO, Color.RED, how, gore.BACK)
			layer.drop(Vector2(randf_range(512, 524), 50), Vector2.ZERO, Color.RED, how, gore.BACK)
			layer.drop(Vector2(randf_range(180, 240), 20), Vector2.ZERO, Color.RED, how, gore.BACK)
		await _frames(60)
		var behind: Array = layer._stains.filter(func(st): return st.face == 3)
		_check(behind.size() >= 8 and behind.all(func(st): return st.p.x >= 505.0 and st.p.x <= 530.0),
			"drops into the depth stick to the painted wall by something solid, never in the sky or out in the open (%d)" % behind.size())
		_check(layer._stains.any(func(st): return st.face == 0 and st.p.x >= 170.0 and st.p.x <= 250.0), "and what found nothing to stick to fell to the floor")
		_check((layer.get_node("Soak").material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_MUL
			and behind.all(func(st): return is_equal_approx(st.soak, 0.6)), "the marks soak into the painting: a multiply pass")
		layer._stains.clear()

		# water clouds, lava hisses
		layer._in_liquid(Vector2.ZERO)
		layer._water.append(Rect2(-350, 80, 100, 40))
		var hissed0: int = gore.hissed
		layer._stains.clear()
		for i in 6:
			layer.drop(Vector2(randf_range(-330, -270), 60), Vector2(0, 80), Color.RED, how, gore.SPLASHED)
			layer.drop(Vector2(randf_range(-180, -120), 60), Vector2(0, 80), Color.RED, {"stain": 1.0, "life": 30.0, "hiss": 1.0}, gore.SPLASHED)
			await _frames(6)
		await _frames(30)
		var clouds: Array = layer._stains.filter(func(st): return st.face == 4)
		_check(clouds.size() >= 4 and clouds.all(func(st): return st.p.x >= -350 and st.p.x <= -250 and st.soak == 0.0),
			"blood in water spreads as a faint cloud that soaks into nothing (%d)" % clouds.size())
		_check(not layer._stains.any(func(st): return st.p.x >= -202 and st.p.x <= -98) and gore.hissed > hissed0,
			"blood on lava leaves no mark and goes up as steam (%d)" % (gore.hissed - hissed0))
		layer._stains.clear()

	var torn0: int = gore.torn
	var torn: bool = gore.death(body, "t", "flesh", sprite, Vector2(1, -0.2))
	_check(torn and gore.torn - torn0 == 4, "a death tears the drawing into its four pieces")
	var pieces := get_nodes_in_group("gore_piece")
	await _frames(240)
	var resting := 0
	for piece in pieces:
		if is_instance_valid(piece) and piece.is_resting() and piece.global_position.y < 101.0:
			resting += 1
	_check(resting == 4, "the pieces fell, bounced and came to rest on the floor (%d)" % resting)

	for piece in get_nodes_in_group("gore_piece"):
		piece.free()

	# the head off: the head flies, the body stands a beat, its neck jets, then it falls over the way the blow went
	gore.use({"flesh": {"limbs": 6, "chance": 1.0, "gush": 0, "pool": 0, "spurt": 1.0, "cuts": {"head": 1}}}, {})
	_check(gore.death(body, "t", "flesh", sprite, Vector2(1, -0.2)), "beheaded")
	var standing = null
	for piece in get_nodes_in_group("gore_piece"):
		if piece.name.begins_with("Piece_body"):
			standing = piece
	_check(standing != null and standing._hold > 0.0, "what is left of the body stands")
	var still_at: Vector2 = standing.global_position if standing else Vector2.ZERO
	thrown0 = gore.thrown
	await _frames(5)
	_check(standing != null and standing.global_position == still_at and absf(standing.rotation) < 0.01, "a beat on its feet")
	await _frames(25)
	_check(gore.thrown - thrown0 >= 2, "the neck jets (%d drops)" % (gore.thrown - thrown0))
	await _frames(120)
	_check(standing != null and standing.is_resting() and is_equal_approx(absf(standing.rotation), absf(standing._target))
		and standing.rotation > 1.2, "then it topples the way the blow went and lies on its side (%.2f rad)" % (standing.rotation if standing else 0.0))
	_check(standing != null and standing.global_position.y + standing._reach().y <= 101.0, "lying on the floor, not in it")
	for piece in get_nodes_in_group("gore_piece"):
		piece.free()

	# the blow decides the way: an uppercut throws it up, a sweep low and flat, a slam scatters pieces both ways
	var blood_layer = gore.of(body)
	gore.use({"flesh": {"drops": 20, "gush": 0, "pool": 0, "bleed": 0, "mist": 0, "limbs": 4, "chance": 1.0, "fling": 150,
		"cuts": {"all": 1}}}, {}, {"attack": {"aim": -7}, "rising": {"aim": -70, "spread": 0.3, "height": 6},
		"sweep": {"aim": 20, "spread": 0.3, "height": -7}, "slam": {"scatter": 1.0, "lift": 1.0, "cuts": {"half": 1}}})
	_check(gore.move_spec("nonsense").aim == -7.0 and gore.move_spec("").aim == -7.0 and gore.move_spec("rising").spread == 0.3,
		"an unnamed blow bleeds like a plain swing")
	var how := {}
	for move in ["rising", "attack", "sweep"]:
		var vy := 0.0
		var y := 0.0
		var n := 0
		for i in 8:
			blood_layer._drops.clear()
			gore.hit(body, "t", "flesh", body.global_position + Vector2(0, -10), Vector2(1, -0.3), 1.0, move)
			for d in blood_layer._drops:
				vy += d[1].y / maxf(d[1].length(), 1.0)
				y += d[0].y
				n += 1
		how[move] = [vy / maxf(n, 1), y / maxf(n, 1)]
	blood_layer._drops.clear()
	_check(how.rising[0] < -0.75 and how.rising[0] < how.attack[0] and how.attack[0] < how.sweep[0],
		"an uppercut throws the blood up, a sweep low (rise %.2f / swing %.2f / sweep %.2f)" % [how.rising[0], how.attack[0], how.sweep[0]])
	_check(how.rising[1] < how.attack[1] - 4.0 and how.sweep[1] > how.attack[1] + 4.0,
		"and the wound opens where the blade went in (y %.0f / %.0f / %.0f)" % [how.rising[1], how.attack[1], how.sweep[1]])
	gore.death(body, "t", "flesh", sprite, Vector2(1, -0.2), false, "slam")
	var flung := get_nodes_in_group("gore_piece").filter(func(p): return p._hold <= 0.0)
	_check(gore.torn > 0 and flung.size() >= 1 and flung.all(func(p): return p.velocity.x < 0.0 and p.velocity.y < 0.0),
		"a slam cuts the way it says and flings the pieces back over it, upward (%d)" % flung.size())
	for piece in get_nodes_in_group("gore_piece"):
		piece.free()
	gore.use({"flesh": {"limbs": 6, "chance": 1.0, "gush": 0, "pool": 0, "spurt": 1.0, "cuts": {"head": 1}}}, {})

	settings.set_gore("reduced")
	thrown0 = gore.thrown
	gore.hit(body, "t", "flesh", body.global_position, Vector2.RIGHT, 1.0)
	_check(gore.thrown - thrown0 >= 2 and gore.thrown - thrown0 <= 7, "reduced: half the drops (%d)" % (gore.thrown - thrown0))
	_check(not gore.death(body, "t", "flesh", sprite, Vector2.RIGHT), "reduced: nobody is torn")
	thrown0 = gore.thrown
	var layer2 = room.get_node("Gore")
	layer2.spray(Vector2(0, 50), Vector2.RIGHT, 5, {"blood": "#ff0000", "shade": 0.0, "spray": 100.0, "drops": 5, "mist": 20,
		"stain": 1.0, "stain_life": 5.0}, 30.0)
	_check(gore.thrown - thrown0 == 5, "reduced: no mist (%d specks)" % (gore.thrown - thrown0 - 5))
	settings.set_gore("off")
	thrown0 = gore.thrown
	gore.hit(body, "t", "flesh", body.global_position, Vector2.RIGHT, 1.0)
	_check(gore.thrown == thrown0 and not gore.death(body, "t", "flesh", sprite, Vector2.RIGHT), "off: no blood at all")

	# the painting's water, in the world: swamp_red has three pools
	var swamp = load("res://scenes/rooms/swamp_red.tscn").instantiate()
	root.add_child(swamp)
	await process_frame
	var pools: Array = load("res://scripts/rooms/backdrop_life.gd").zones_in_world(swamp, "water")
	var bounds := Rect2(0, 0, float(swamp.get("width")), float(swamp.get("height"))).grow(2.0)
	_check(pools.size() == 3 and pools.all(func(r): return bounds.encloses(r) and r.get_area() > 1000.0),
		"a room's water zones land in its world (%s)" % [pools])
	swamp.queue_free()

	settings.set_gore(was)
	_check(settings.gore == was, "the setting is put back as it was found")
	print("gore_test: " + ("FAILED" if _failed else "passed"))
	quit(1 if _failed else 0)
