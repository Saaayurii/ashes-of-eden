extends SceneTree
## Dev helper: what the backdrop life costs the GPU. A room's painting is
## drawn LAYERS times over a 1920x1080 window with vsync off, so the frame is
## bound by filling pixels, plain and then with its life — still, and moving —
## and the frame times are compared. The ratio is what carries over to a
## weaker GPU: a phone or a browser fills the same pixels with the same shader.
## Needs a display:
##   godot --path . -s scripts/tools/backdrop_life_bench.gd -- [room]

const LAYERS := 24
const FRAMES := 240


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var key: String = args[0] if args.size() > 0 else "hell_gate"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	var life = load("res://scripts/rooms/backdrop_life.gd")
	var room = load("res://scenes/rooms/%s.tscn" % key).instantiate()
	var texture: Texture2D = room.get_node("Painting").texture
	room.free()
	var holder := Node2D.new()
	root.add_child(holder)
	var sprites: Array[Sprite2D] = []
	for i in LAYERS:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.scale = Vector2(1920.0, 1080.0) / texture.get_size()
		holder.add_child(sprite)
		sprites.append(sprite)
	var material: ShaderMaterial = life.attach_sprite(sprites[0], key)[0]
	var plain := await _measure()
	# any custom shader at all, for the floor under the life's own cost
	var trivial := ShaderMaterial.new()
	trivial.shader = Shader.new()
	trivial.shader.code = "shader_type canvas_item;\nvoid fragment() { COLOR = texture(TEXTURE, UV) * COLOR; }\n"
	for sprite in sprites:
		sprite.material = trivial
	var custom := await _measure()
	print("BENCH   a trivial custom shader: %.2f ms/frame" % custom)
	for sprite in sprites:
		sprite.material = material
	material.set_shader_parameter("life_motion", 0.0)
	var still := await _measure()
	material.set_shader_parameter("life_motion", 1.0)
	var moving := await _measure()
	var zones = material.get_shader_parameter("life_count")
	var flame = material.get_shader_parameter("life_flame")
	material.set_shader_parameter("life_count", 0)
	var no_zones := await _measure()
	material.set_shader_parameter("life_flame", 0.0)
	var bare := await _measure()
	material.set_shader_parameter("life_count", zones)
	var no_flame := await _measure()
	material.set_shader_parameter("life_flame", flame)
	print("BENCH   no zones (flames only) %.2f, no flames (zones only) %.2f, neither %.2f" % [no_zones, no_flame, bare])
	print("BENCH %s (%d zones), %d layers at 1920x1080:" % [key, life.rule(key).zones.size(), LAYERS])
	print("BENCH   plain   %.2f ms/frame" % plain)
	print("BENCH   still   %.2f ms/frame  (x%.2f)" % [still, still / plain])
	print("BENCH   moving  %.2f ms/frame  (x%.2f)" % [moving, moving / plain])
	print("BENCH   one full-screen layer of life costs %.3f ms more than a plain one" % ((moving - plain) / LAYERS))
	quit()


## Mean frame time over FRAMES frames, after a few to settle.
func _measure() -> float:
	for i in 30:
		await process_frame
	var start := Time.get_ticks_usec()
	for i in FRAMES:
		await process_frame
	return (Time.get_ticks_usec() - start) / 1000.0 / FRAMES
