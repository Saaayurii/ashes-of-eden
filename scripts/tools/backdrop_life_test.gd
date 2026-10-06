extends SceneTree
## Every room's backdrop lives (scripts/rooms/backdrop_life.gd): each room of
## the chapter has a rule in data/backdrops.json, its painting carries the
## life shader with all of the rule's zones, every zone lies on the picture,
## the depth windows run the same life (so a waterfall does not stop at the
## frame of an opening), and a room without a rule is left alone.
##   godot --headless --path . -s scripts/tools/backdrop_life_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL ", message)


func _run() -> void:
	var life = load("res://scripts/rooms/backdrop_life.gd")
	var shader: Shader = load("res://assets/shaders/backdrop_life.gdshader")
	# ROOMS read as text: the test should not depend on all of run.gd compiling
	var run := FileAccess.get_file_as_string("res://scripts/run/run.gd")
	var listed := run.substr(run.find("const ROOMS := ["))
	listed = listed.substr(0, listed.find("]"))
	var rooms: Array = []
	for found in RegEx.create_from_string("res://scenes/rooms/\\w+\\.tscn").search_all(listed):
		rooms.append(found.get_string())
	_check(rooms.size() > 10, "run.gd lists %d rooms — does it compile?" % rooms.size())
	for path in rooms:
		var name: String = path.get_file().get_basename()
		var found: Dictionary = life.rule(name)
		_check(not found.is_empty(), "%s: no rule in data/backdrops.json" % name)
		var room = load(path).instantiate()
		root.add_child(room)
		await process_frame
		var painting = life.painting_of(room)
		_check(painting != null, "%s: no painting to bring to life" % name)
		if painting == null or found.is_empty():
			room.queue_free()
			await process_frame
			continue
		var material := painting.material as ShaderMaterial
		_check(material != null and material.shader == shader, "%s: the painting has no life shader" % name)
		_check(found.zones.size() <= life.MAX_ZONES, "%s: %d zones, the shader holds %d" % [name, found.zones.size(), life.MAX_ZONES])
		if material != null:
			_check(int(material.get_shader_parameter("life_count")) == found.zones.size(),
				"%s: %s of %d zones reached the shader" % [name, material.get_shader_parameter("life_count"), found.zones.size()])
			_check(is_equal_approx(float(material.get_shader_parameter("life_light")), root.get_node("/root/Settings").flash_scale()),
				"%s: the light ignores Settings.flashes" % name)
		var size: Vector2 = painting.texture.get_size()
		for zone in found.zones:
			_check(life.KINDS.has(str(zone.get("kind", ""))), "%s: unknown kind %s" % [name, zone.get("kind")])
			var r: Array = zone.rect
			var rect := Rect2(r[0], r[1], r[2], r[3])
			_check(rect.size.x > 0 and rect.size.y > 0 and Rect2(Vector2.ZERO, size).encloses(rect),
				"%s: %s zone %s is not on the %s picture" % [name, zone.kind, rect, size])
		var windows = room.get_node_or_null("DepthWindows")
		for polygon in windows.get_children() if windows != null else []:
			var window_material := (polygon as CanvasItem).material as ShaderMaterial
			if window_material == null:
				continue
			_check(int(window_material.get_shader_parameter("life_count")) == found.zones.size(),
				"%s: %s does not share the painting's life" % [name, polygon.name])
		room.queue_free()
		await process_frame
	# a room the table does not name keeps its picture as it was
	var plain_room = load("res://scenes/rooms/dead_bridge.tscn").instantiate()
	root.add_child(plain_room)
	await process_frame
	var plain = life.painting_of(plain_room)
	_check(plain == null or plain.material == null, "dead_bridge: given life it has no rule for")
	plain_room.queue_free()
	await process_frame
	# the yard and the main menu are pictures too
	var yard = load("res://scenes/rooms/practice_yard.tscn").instantiate()
	root.add_child(yard)
	await process_frame
	var backdrop = life.painting_of(yard)
	_check(backdrop != null and backdrop.material is ShaderMaterial, "practice_yard: its backdrop stands still")
	# a gust near the hero reaches the painting, in the painting's pixels
	life.react(yard, backdrop.global_position + Vector2(100, 50) * backdrop.global_scale, Vector2.RIGHT, 0.8, 0.5)
	var wind: Vector4 = backdrop.material.get_shader_parameter("life_wind")
	_check(Vector2(wind.x, wind.y).distance_to(Vector2(100, 50)) < 0.5 and is_equal_approx(wind.z, 0.8) and is_equal_approx(wind.w, 1.0),
		"practice_yard: the gust reached the painting as %s" % wind)
	_check(is_equal_approx(float(backdrop.material.get_shader_parameter("life_exhale")), 0.5), "practice_yard: the cleared room's swell did not arrive")
	# lightning, a wounded heart and its quickened clock reach the shader too
	life.react(yard, Vector2.ZERO, Vector2.RIGHT, 0.0, 0.0, 0.4, 0.75, 12.5)
	_check(is_equal_approx(float(backdrop.material.get_shader_parameter("life_flash")), 0.4)
		and is_equal_approx(float(backdrop.material.get_shader_parameter("life_dread")), 0.75)
		and is_equal_approx(float(backdrop.material.get_shader_parameter("life_beat_clock")), 12.5),
		"practice_yard: lightning or the heartbeat did not reach the painting")
	# dread: nothing while he is whole, all of it at death's door
	_check(life.dread_of(1.0) == 0.0 and life.dread_of(life.DREAD_FROM) == 0.0, "dread before the body is wounded enough")
	_check(life.dread_of(life.DREAD_FULL) == 1.0 and life.dread_of(0.01) == 1.0, "no full dread at death's door")
	var half: float = life.dread_of((life.DREAD_FROM + life.DREAD_FULL) * 0.5)
	_check(half > 0.4 and half < 0.6, "dread does not grow evenly (%s halfway)" % half)
	yard.queue_free()
	await process_frame
	var arena = load("res://scenes/pvp/arena.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	var dusk = arena.get_node("Parallax/Backdrop")
	_check(dusk.material is ShaderMaterial and int(dusk.material.get_shader_parameter("life_count")) > 0, "arena: Babylon stands still")
	arena.queue_free()
	await process_frame
	var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var sky = menu.get_node("Layers/Background")
	_check(sky.material is ShaderMaterial and int(sky.material.get_shader_parameter("life_count")) > 0, "main_menu: the village stands still")
	menu.queue_free()
	await process_frame
	print("backdrop_life_test: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
