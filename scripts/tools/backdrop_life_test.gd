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
	# the pictures that are not rooms: cutscene panels and passage cards
	var shown := TextureRect.new()
	root.add_child(shown)
	var pictures: Array = []
	for each in DirAccess.get_files_at("res://assets/cutscenes") + DirAccess.get_files_at("res://assets/ui/transitions"):
		if each.ends_with(".png"):
			pictures.append(each.get_basename())
	_check(pictures.size() >= 6, "only %d scene and passage pictures found" % pictures.size())
	for key in pictures:
		var picture: Dictionary = life.rule(key)
		_check(not picture.is_empty(), "%s: no rule — the picture stands still" % key)
		var file := "res://assets/cutscenes/%s.png" % key
		if not ResourceLoader.exists(file):
			file = "res://assets/ui/transitions/%s.png" % key
		var texture: Texture2D = load(file)
		_check(life.picture_key(texture) == key, "%s: its texture is keyed as %s" % [key, life.picture_key(texture)])
		for zone in picture.get("zones", []):
			var r: Array = zone.rect
			_check(Rect2(Vector2.ZERO, texture.get_size()).encloses(Rect2(r[0], r[1], r[2], r[3])),
				"%s: %s zone %s is not on the %s picture" % [key, zone.kind, r, texture.get_size()])
		shown.texture = texture
		var set: Array = life.attach_picture(shown, key)
		_check(set.size() == 1 and shown.material == set[0] and int(set[0].get_shader_parameter("life_count")) == picture.zones.size(),
			"%s: the panel did not come to life" % key)
	# one panel showing picture after picture keeps one material and one watcher
	_check(shown.get_children().filter(func(n) -> bool: return n.name.begins_with("BackdropLifeSettings")).size() == 1,
		"a panel shown twice grew a second settings watcher")
	life.attach_picture(shown, "no_such_picture")
	_check(shown.material == null, "a picture with no rule kept the last one's life")
	shown.free()
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
	life.react(yard, {"origin": backdrop.global_position + Vector2(100, 50) * backdrop.global_scale, "direction": Vector2.RIGHT, "energy": 0.8, "exhale": 0.5})
	var wind: Vector4 = backdrop.material.get_shader_parameter("life_wind")
	_check(Vector2(wind.x, wind.y).distance_to(Vector2(100, 50)) < 0.5 and is_equal_approx(wind.z, 0.8) and is_equal_approx(wind.w, 1.0),
		"practice_yard: the gust reached the painting as %s" % wind)
	_check(is_equal_approx(float(backdrop.material.get_shader_parameter("life_exhale")), 0.5), "practice_yard: the cleared room's swell did not arrive")
	# lightning, a wounded heart and its quickened clock reach the shader too
	life.react(yard, {"flash": 0.4, "flash_tint": Color.RED, "dread": 0.75, "beat": 12.5, "rage": 0.3})
	_check(is_equal_approx(float(backdrop.material.get_shader_parameter("life_flash")), 0.4)
		and backdrop.material.get_shader_parameter("life_flash_tint") == Vector3(1, 0, 0)
		and is_equal_approx(float(backdrop.material.get_shader_parameter("life_dread")), 0.75)
		and is_equal_approx(float(backdrop.material.get_shader_parameter("life_beat_clock")), 12.5)
		and is_equal_approx(float(backdrop.material.get_shader_parameter("life_rage")), 0.3),
		"practice_yard: a flash, the heartbeat or a fight's heat did not reach the painting")
	# a calm mood puts every answer back to rest
	life.react(yard, {})
	_check(float(backdrop.material.get_shader_parameter("life_rage")) == 0.0
		and float(backdrop.material.get_shader_parameter("life_beat_clock")) < 0.0,
		"practice_yard: a calm room keeps the last fight's heat")
	# the flames lean with the hero from the aura's threshold
	_check(life.lean_of("grace", 1).w == 0.0 and life.lean_of("nobody", 9).w == 0.0, "the flames lean before the hero does")
	var red: Vector4 = life.lean_of("temptation", life.LEAN_FULL)
	_check(red.w == 1.0 and red.x > red.z, "temptation does not redden the flames (%s)" % red)
	_check(life.lean_of("will", 2).w > 0.0 and life.lean_of("will", 2).w < life.lean_of("will", 4).w, "the flames do not lean further as he does")
	life.react(yard, {"path": "grace", "lead": 4})
	_check((backdrop.material.get_shader_parameter("life_lean") as Vector4).w > 0.0, "practice_yard: the lean did not reach the flames")
	# rage: none before the first blow, all of it as the boss falls
	_check(life.rage_of(1.0) == 0.0 and life.rage_of(0.0) == 0.0 and is_equal_approx(life.rage_of(0.25), 0.75),
		"a boss fight's heat does not follow the boss's health")
	# dread: nothing while he is whole, all of it at death's door
	_check(life.dread_of(1.0) == 0.0 and life.dread_of(life.DREAD_FROM) == 0.0, "dread before the body is wounded enough")
	_check(life.dread_of(life.DREAD_FULL) == 1.0 and life.dread_of(0.01) == 1.0, "no full dread at death's door")
	var half: float = life.dread_of((life.DREAD_FROM + life.DREAD_FULL) * 0.5)
	_check(half > 0.4 and half < 0.6, "dread does not grow evenly (%s halfway)" % half)
	yard.queue_free()
	await process_frame
	# the settings reach a room's painting and its openings at once; the
	# player's own settings are put back the way they were changed
	var settings = root.get_node("/root/Settings")
	var was_motion: bool = settings.backdrop_motion
	var was_flashes: String = settings.flashes
	var was_lighting: bool = settings.lighting
	var night = load("res://scenes/rooms/village_night.tscn").instantiate()
	root.add_child(night)
	await process_frame
	var night_materials: Array = night.get_meta(&"backdrop_life").materials
	_check(night_materials.size() > 1, "village_night: its openings do not share the painting's life")
	settings.set_backdrop_motion(false)
	settings.set_flashes("reduced")
	for each in night_materials:
		_check(float(each.get_shader_parameter("life_motion")) == 0.0, "village_night: the picture still moves with Moving backdrops off")
		_check(is_equal_approx(float(each.get_shader_parameter("life_light")), 0.35), "village_night: its light ignores reduced flashes")
	settings.set_backdrop_motion(true)
	settings.set_flashes("full")
	for each in night_materials:
		_check(float(each.get_shader_parameter("life_motion")) == 1.0 and float(each.get_shader_parameter("life_light")) == 1.0,
			"village_night: the picture does not come back to life")
	# the weak-GPU switch rests the picture and gives its life back after
	var zones_lit: int = night_materials[0].get_shader_parameter("life_count")
	settings.set_lighting(false)
	for each in night_materials:
		_check(int(each.get_shader_parameter("life_count")) == 0 and float(each.get_shader_parameter("life_flame")) == 0.0,
			"village_night: the picture still lives with the lighting off")
	settings.set_lighting(true)
	_check(int(night_materials[0].get_shader_parameter("life_count")) == zones_lit and zones_lit > 0,
		"village_night: the life did not come back with the lighting")
	settings.set_backdrop_motion(was_motion)
	settings.set_flashes(was_flashes)
	settings.set_lighting(was_lighting)
	_check(settings.backdrop_motion == was_motion and settings.flashes == was_flashes and settings.lighting == was_lighting,
		"the player's settings were not put back")
	night.queue_free()
	await process_frame
	# a room hears a boss weaken and a scene flash, through its Ambience
	var lava = load("res://scenes/rooms/crypt_lava.tscn").instantiate()
	root.add_child(lava)
	await process_frame
	var bus = root.get_node("/root/EventBus")
	bus.boss_hp_changed.emit("BOSS", 25.0, 100.0)
	bus.backdrop_flash.emit(0.8, 0.5, Color(1, 0.2, 0.1))
	for i in 3:
		await process_frame
	var heat = life.painting_of(lava).material
	_check(float(heat.get_shader_parameter("life_rage")) > 0.0, "crypt_lava: the room did not heat as the boss weakened")
	var lit: float = heat.get_shader_parameter("life_flash")
	_check(lit > 0.5 and heat.get_shader_parameter("life_flash_tint").x > 0.9, "crypt_lava: a scene's red flash did not reach the painting (%s)" % lit)
	bus.boss_died.emit()
	await create_timer(2.0).timeout
	_check(float(heat.get_shader_parameter("life_rage")) < float(heat.get_shader_parameter("life_exhale")),
		"crypt_lava: the place did not let go when the boss fell")
	_check(float(heat.get_shader_parameter("life_flash")) == 0.0, "crypt_lava: a scene's flash never faded")
	lava.queue_free()
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
	# the frame meter's line, as a phone's log will show it
	var meter = load("res://scripts/autoload/frame_meter.gd")
	var frames := PackedFloat32Array()
	for i in 100:
		frames.append(50.0 if i < 10 else 16.0)
	var said: String = meter.line(frames, "hell_gate", "x")
	_check(said.begins_with("[FrameMeter] hell_gate:") and said.contains("10/100 over 33 ms") and said.contains("50.0 ms p95"),
		"the frame meter says: %s" % said)
	print("backdrop_life_test: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
