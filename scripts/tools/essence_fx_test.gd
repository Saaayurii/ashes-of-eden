extends SceneTree
## Verifies that enemy essence uses painted, transparent silhouettes rather
## than the generic 3x3 square. Optional first argument saves a preview PNG.


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
	for child in stage.get_children():
		if child is CPUParticles2D:
			emitters.append(child)
	assert(emitters.size() == 4, "two death effects need a fragment and a mote layer each")
	var light := emitters[0].texture
	var dark := emitters[2].texture
	assert(light.resource_path.ends_with("essence_light_v2.png"))
	assert(dark.resource_path.ends_with("essence_dark_v2.png"))
	for texture in [light, dark]:
		var image: Image = texture.get_image()
		assert(image.get_pixel(0, 0).a < 0.05, "the particle's corners must be transparent")
		assert(image.get_used_rect().size.x > 5, "the particle should have a painted shape")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		await create_timer(0.28).timeout
		var viewport_texture := root.get_viewport().get_texture()
		if viewport_texture != null:
			viewport_texture.get_image().save_png(args[0])
	print("ESSENCE_FX_OK")
	quit(0)
