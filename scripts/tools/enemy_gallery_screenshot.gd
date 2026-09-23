extends SceneTree
## Renders every enemy with its actual runtime sprite setup for visual QA.
##   godot -s scripts/tools/enemy_gallery_screenshot.gd -- /tmp/enemies.png

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var output := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "/tmp/enemies.png"
	var stage := Node2D.new()
	root.add_child(stage)
	var view_size := root.get_viewport().get_visible_rect().size
	var backdrop := ColorRect.new()
	backdrop.color = Color("#100d14")
	backdrop.size = view_size
	stage.add_child(backdrop)
	var ids: Array = root.get_node("Data").enemies.keys()
	var enemy_scene = load("res://scenes/enemies/enemy.tscn")
	ids.sort_custom(func(a, b): return int(root.get_node("Data").enemies[a].get("tier", 1)) < int(root.get_node("Data").enemies[b].get("tier", 1)))
	for index in ids.size():
		var enemy = enemy_scene.instantiate()
		enemy.enemy_id = ids[index]
		stage.add_child(enemy)
		var column := index % 4
		var row := floori(float(index) / 4.0)
		enemy.global_position = Vector2(view_size.x * (column + 0.5) / 4.0, view_size.y * (row + 0.42) / 3.0)
		enemy.z_index = 2
		enemy.set_physics_process(false)
		var preview_animation: String = ["attack", "attack_alt", "special"][index % 3]
		enemy.get_node("Sprite").play(preview_animation)
		var label := Label.new()
		label.text = "%s · %s" % [tr(root.get_node("Data").enemies[ids[index]].name), preview_animation]
		label.position = enemy.global_position + Vector2(-90, 48)
		label.size = Vector2(180, 24)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color("#ead690"))
		label.z_index = 3
		stage.add_child(label)
		var sprite_spec: Dictionary = root.get_node("Data").enemies[ids[index]].get("sprite", {})
		var active_path: String = str(sprite_spec.get("animations", {}).get(preview_animation, "<missing>"))
		print("gallery ", index, " ", ids[index], " at ", enemy.global_position,
			" visible=", enemy.visible, " source=", active_path)
	await process_frame
	await create_timer(0.8).timeout
	root.get_viewport().get_texture().get_image().save_png(output)
	print("ENEMY GALLERY SCREENSHOT: " + output)
	quit()
