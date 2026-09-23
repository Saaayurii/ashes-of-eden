extends SceneTree
## Headless regression for painted projectile styles and death-affinity rules.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	enemy.stats = {"tags": ["human", "cult"]}
	assert(enemy._soul_affinity() == "light")
	enemy.stats = {"tags": ["human", "possessed"]}
	assert(enemy._soul_affinity() == "dark")
	enemy.stats = {"tags": ["angel", "boss"]}
	assert(enemy._soul_affinity() == "light")
	enemy.stats = {"tags": ["undead", "fallen"]}
	assert(enemy._soul_affinity() == "dark")
	enemy.enemy_id = "wraith"
	assert(enemy._projectile_style() == "wraith")
	enemy.enemy_id = "cult_caller"
	enemy.stats = {"tags": ["human", "cult"]}
	assert(enemy._projectile_style() == "umbral")
	enemy.enemy_id = "zealot"
	enemy.stats = {"tags": ["human", "heaven"]}
	assert(enemy._projectile_style() == "sacred")
	for entry in [
		["zealot", "zealot"], ["preacher_acolyte", "acolyte"],
		["blind_preacher", "preacher"], ["cult_caller", "cult"],
		["knight_of_ash", "ash"], ["ophanim", "ophanim"], ["wraith", "wraith"],
	]:
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
			"res://data/enemies/%s.json" % entry[0]))
		var attacks: Array = raw.get("attacks", [raw.get("attack", {})])
		var ranged_found := false
		for attack in attacks:
			if attack.get("type") == "ranged":
				assert(attack.get("projectile_style") == entry[1])
				ranged_found = true
		assert(ranged_found)
		enemy.enemy_id = entry[0]
		enemy._attack = {"projectile_style": entry[1]}
		assert(enemy._projectile_style() == entry[1])
	enemy.free()
	for style in ["blade", "sacred", "umbral", "wraith", "zealot", "acolyte", "preacher", "cult", "ash", "ophanim"]:
		var projectile = load("res://scenes/fx/projectile.tscn").instantiate()
		projectile.visual_style = style
		projectile._set_art()
		assert(projectile.get_node("Art").texture != null)
		if projectile.FLIGHT_FPS.has(style):
			assert(projectile.get_node("Art").hframes == 4)
			assert(projectile.get_node("Art").texture.get_width() == 384)
			var sheet: Image = projectile.get_node("Art").texture.get_image()
			var first: PackedByteArray = sheet.get_region(Rect2i(0, 0, 96, 128)).get_data()
			for frame_id in range(1, 4):
				assert(first != sheet.get_region(Rect2i(frame_id * 96, 0, 96, 128)).get_data(),
					"%s has repeated sprite frames" % style)
			projectile._flight_clock = 1.0 / float(projectile.FLIGHT_FPS[style])
			projectile._animate_art()
			assert(projectile.get_node("Art").frame == 1)
			assert(projectile.get_node("Echo").frame == 0)
		else:
			assert(projectile.get_node("Art").hframes == 1)
			assert(projectile.get_node("Art").texture.get_width() == 96)
		projectile.free()
	var live = load("res://scenes/fx/projectile.tscn").instantiate()
	live.visual_style = "wraith"
	live.speed = 0.0
	root.add_child(live)
	await create_timer(0.22).timeout
	assert(live.get_node("Art").frame > 0)
	live.queue_free()
	await process_frame
	print("PASS: projectile art and enemy essence affinity")
	quit()
