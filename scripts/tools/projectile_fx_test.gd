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
		["zealot", "zealot"], ["preacher_acolyte", "halo"],
		["blind_preacher", "preacher"], ["cult_caller", "hex"],
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
	var styles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/projectiles.json")).styles
	for style in ["blade", "sacred", "umbral", "wraith", "zealot", "acolyte", "preacher", "cult", "ash", "ophanim"]:
		assert(styles.has(style), "%s left data/projectiles.json" % style)
	for style in styles:
		var projectile = load("res://scenes/fx/projectile.tscn").instantiate()
		projectile.visual_style = style
		projectile._set_art()
		var art: Sprite2D = projectile.get_node("Art")
		assert(art.texture != null, "%s has no sheet" % style)
		var frames := int(styles[style].get("frames", 1))
		assert(art.hframes == frames)
		if frames > 1:
			var w: int = art.texture.get_width() / frames
			var h: int = art.texture.get_height()
			var sheet: Image = art.texture.get_image()
			var first: PackedByteArray = sheet.get_region(Rect2i(0, 0, w, h)).get_data()
			for frame_id in range(1, frames):
				assert(first != sheet.get_region(Rect2i(frame_id * w, 0, w, h)).get_data(),
					"%s has repeated sprite frames" % style)
			projectile._flight_clock = 1.0 / float(styles[style].get("fps", 10.0))
			projectile._animate_art()
			assert(art.frame == 1)
			assert(projectile.get_node("Echo").frame == 0)
		projectile.free()
	# an attack's own size sits on top of the style's
	var big = load("res://scenes/fx/projectile.tscn").instantiate()
	big.visual_style = "cult"
	big.size = 2.0
	big._set_art()
	assert(absf(big.get_node("Art").scale.x - 2.0 * float(styles.cult.get("scale", 0.62))) < 0.001)
	big.free()
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
