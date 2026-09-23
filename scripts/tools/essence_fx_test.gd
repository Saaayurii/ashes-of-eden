extends SceneTree
## Verifies two distinct four-frame soul dissolves, not a static square.
## Optional first argument saves a preview PNG.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var background := ColorRect.new()
	background.color = Color("#1b1923")
	background.size = Vector2(420, 240)
	stage.add_child(background)
	var fx = root.get_node("Fx")
	fx.essence_release(Vector2(130, 128), false, 12)
	fx.essence_release(Vector2(290, 128), true, 12)
	var emitters: Array[CPUParticles2D] = []
	var shards: Array[AnimatedSprite2D] = []
	for child in stage.get_children():
		if child is CPUParticles2D:
			emitters.append(child)
		elif child is AnimatedSprite2D:
			shards.append(child)
	assert(emitters.size() == 2, "soft motes remain a separate layer for each death")
	assert(shards.size() == 18, "each death should release nine painted shards")
	var sheets := ["res://assets/fx/essence_light_flight_v3.png",
		"res://assets/fx/essence_dark_flight_v3.png"]
	for sheet_path in sheets:
		var sheet: Texture2D = load(sheet_path)
		assert(sheet.get_width() == 128)
		var image: Image = sheet.get_image()
		assert(image.get_pixel(0, 0).a < 0.05, "sheet corners must be transparent")
		var first := image.get_region(Rect2i(0, 0, 32, 43)).get_data()
		for frame_index in range(1, 4):
			assert(first != image.get_region(Rect2i(frame_index * 32, 0, 32, 43)).get_data(),
				"dissolve must have distinct painted frames")
	for shard in shards:
		assert(shard.sprite_frames.get_frame_count("dissolve") == 4)
	var initial_frame := shards[0].frame
	await create_timer(0.35).timeout
	assert(shards[0].frame > initial_frame, "fragment animation must advance in the live scene")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var viewport_texture := root.get_viewport().get_texture()
		if viewport_texture != null:
			viewport_texture.get_image().save_png(args[0])
	await create_timer(1.1).timeout
	for child in stage.get_children():
		assert(not child is AnimatedSprite2D, "dissolved shards must clean themselves up")
	print("ESSENCE_FX_OK")
	quit(0)
