extends SceneTree
## Physical soles, authored crypt floors, props and stationary parallax masks.

var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FIRST_ROOMS_FAIL: " + message)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func _drawn_bottom(texture: Texture2D) -> int:
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	for y in range(image.get_height() - 1, -1, -1):
		for x in image.get_width():
			if image.get_pixel(x, y).a >= 0.1:
				return y + 1
	return 0

func _run() -> void:
	var floor_probes := {
		"village_night": [[1450, 655], [1390, 560], [1500, 520], [1220, 625]],
		"graveyard_cross": [[70, 655], [1340, 388], [1300, 220]],
		"graveyard_arches": [[150, 220], [660, 350], [610, 552], [1120, 594], [1540, 387]],
		"graveyard_tree": [[110, 289], [510, 312], [660, 419], [920, 635], [1500, 241]],
		"swamp_moon": [[410, 264], [760, 338], [860, 415], [1295, 413], [1468, 478], [1520, 554], [1550, 413]],
		"swamp_red": [[120, 347], [410, 499], [800, 405], [1260, 425], [1568, 370], [1568, 310], [1480, 255]],
		"swamp_crypt": [[150, 319], [340, 375], [720, 256], [790, 451], [1315, 560], [1407, 603], [1450, 485], [1130, 655]],
		"catacombs_1": [[150, 157], [580, 260], [860, 403], [1470, 191], [760, 556], [1570, 610]],
	}
	for key in floor_probes:
		var room = load("res://scenes/rooms/%s.tscn" % key).instantiate()
		root.add_child(room)
		current_scene = room
		var hero = load("res://scenes/player/player.tscn").instantiate()
		room.add_child(hero)
		hero.controls_enabled = false
		hero.camera.enabled = false
		var camera := Camera2D.new()
		room.add_child(camera)
		camera.position = Vector2(400, 360)
		camera.make_current()
		await _frames(4)
		hero._mantle_left = 1.0
		hero._mantle_end = Vector2(-500, -500)
		hero._drop_left = 1.0
		hero.collision_mask &= ~16
		hero.place_in_room(Vector2(40, 170))
		_check(hero._mantle_left == 0 and hero._drop_left == 0 and hero.collision_mask & 16,
			"%s room entry retained a climb or drop-through" % key)
		_check(hero._safe_position == Vector2(40, 170), "%s retained the previous room's hazard return" % key)
		for animation in ["idle", "rest", "walk", "run"]:
			var texture: Texture2D = hero.body.sprite_frames.get_frame_texture(animation, 0)
			var sole: float = hero.body.position.y + hero.body.offset.y - texture.get_height() * 0.5 + _drawn_bottom(texture)
			_check(absf(sole - 15.0) <= 2.0, "%s %s drawing floats above physical soles (%s)" % [key, animation, sole])
		_check(room.get_node_or_null("Shrine") == null, "%s duplicated its painted exit statue" % key)
		for prop in room.get_node("Props").get_children():
			if not prop is Area2D:
				continue
			var query := PhysicsRayQueryParameters2D.create(prop.global_position + Vector2(0, -2),
				prop.global_position + Vector2(0, 8), 17)
			var hit: Dictionary = room.get_world_2d().direct_space_state.intersect_ray(query)
			_check(not hit.is_empty() and absf(hit.position.y - prop.global_position.y) <= 1.0,
				"%s/%s has no matching floor" % [key, prop.name])
			var texture: Texture2D = prop.sprite.texture
			var image := texture.get_image()
			var cell := ImageTexture.create_from_image(image.get_region(Rect2i(0, 0, int(image.get_width() / prop.sprite.hframes), image.get_height())))
			var drawn: float = prop.sprite.offset.y + _drawn_bottom(cell)
			_check(absf(drawn) <= 2, "%s/%s has transparent padding under its drawing (%s)" % [key, prop.name, drawn])
		var probes: Array = floor_probes[key]
		for probe in probes:
			hero.position = Vector2(probe[0], probe[1] - 15.0)
			hero.velocity = Vector2.ZERO
			await _frames(12)
			_check(hero.is_on_floor() and absf(hero.position.y + 15.0 - float(probe[1])) <= 1.0,
				"%s floor %s does not match physical feet: %s" % [key, probe, hero.position])
		if key == "graveyard_cross":
			for direction in [1, -1]:
				hero.position = Vector2(1125, 530) if direction > 0 else Vector2(1330, 373)
				hero.velocity = Vector2.ZERO
				hero.controls_enabled = true
				await _frames(4)
				var action := "move_right" if direction > 0 else "move_left"
				Input.action_press(action)
				for frame in 240:
					await physics_frame
					if (direction > 0 and hero.position.x >= 1320) or (direction < 0 and hero.position.x <= 1130):
						break
				Input.action_release(action)
				_check((hero.position.x >= 1320 and hero.position.y < 380) if direction > 0 else (hero.position.x <= 1130 and hero.position.y > 500),
					"graveyard staircase landing blocks direction %d at %s" % [direction, hero.position])
				hero.controls_enabled = false
		if key == "swamp_crypt":
			for direction in [1, -1]:
				hero.place_in_room(Vector2(1295, 545) if direction > 0 else Vector2(1410, 588))
				hero.controls_enabled = true
				await _frames(12)
				var action := "move_right" if direction > 0 else "move_left"
				Input.action_press(action)
				for frame in 160:
					await physics_frame
					if (direction > 0 and hero.position.x >= 1400) or (direction < 0 and hero.position.x <= 1300):
						break
				Input.action_release(action)
				_check((hero.position.x >= 1400 and absf(hero.position.y - 588) < 3) if direction > 0 else
					(hero.position.x <= 1300 and absf(hero.position.y - 545) < 3),
					"crypt stair landing blocks direction %d at %s" % [direction, hero.position])
				hero.controls_enabled = false
		# Masks and gameplay must remain world-anchored while their sampled plate
		# has bounded, fractional camera travel, rather than following the camera.
		var polygon = room.get_node("DepthWindows").get_child(0)
		var anchor: Vector2 = polygon.global_position
		var shape_anchor: Vector2 = room.get_node("Ledges/Ledge1Shape").global_position
		camera.position.x += 400
		await _frames(4)
		_check(polygon.global_position == anchor and room.get_node("Ledges/Ledge1Shape").global_position == shape_anchor,
			"%s moved masks or colliders with the camera" % key)
		var shift: float = polygon.material.get_shader_parameter("shift_px")
		_check(shift > 0 and shift <= 16, "%s far plate has no bounded parallax" % key)
		_check(room.get_node("HorizonCutouts").scroll_scale.x < room.get_node("MiddleCutouts").scroll_scale.x,
			"%s scenic planes have no depth separation" % key)
		current_scene = null
		room.queue_free()
		await _frames(3)
	for voice in root.get_node("Audio").get_children():
		if voice is AudioStreamPlayer:
			voice.stop()
	await create_timer(0.15, true, false, true).timeout
	print("FIRST_ROOMS_GEOMETRY_%s" % ("OK" if failures == 0 else "FAILED"))
	quit(0 if failures == 0 else 1)
