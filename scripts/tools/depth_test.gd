extends SceneTree
## The plane in front of the hero (scripts/rooms/front_layer.gd, docs/DEPTH.md):
## a piece stands where it was placed while the camera looks at it, runs ahead
## of the camera by its depth elsewhere, lets a body behind it be seen, and
## holds still when Settings → Moving backdrops is off.
##   godot --headless --path . -s scripts/tools/depth_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL ", message)


func _run() -> void:
	# loaded, not preloaded: it names the Settings autoload, which a -s script compiles before
	var FRONT_LAYER = load("res://scripts/rooms/front_layer.gd")
	_check(FRONT_LAYER.at(Vector2(500, 300), Vector2(500, 300), 1.4) == Vector2(500, 300), "a piece is not where it was placed at its focus")
	_check(FRONT_LAYER.at(Vector2(500, 300), Vector2(600, 300), 1.5).is_equal_approx(Vector2(450, 300)), "a piece does not run ahead of the camera")

	var world := Node2D.new()
	root.add_child(world)
	var layer = FRONT_LAYER.new()
	layer.depths = PackedFloat32Array([1.5])
	var piece := Sprite2D.new()
	var image := Image.create(100, 60, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	piece.texture = ImageTexture.create_from_image(image)
	piece.position = Vector2(500, 300)
	layer.add_child(piece)
	world.add_child(layer)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	camera.position = Vector2(700, 300)
	var body := Node2D.new()
	body.add_to_group("player")
	body.position = Vector2(-1000, 0)
	world.add_child(body)
	var settings = root.get_node("Settings")
	var moving: bool = settings.backdrop_motion
	settings.backdrop_motion = true   # the field, not the setter: nothing is saved
	await process_frame
	await process_frame
	_check(piece.position.is_equal_approx(Vector2(400, 300)), "camera 200 right: the piece should be at 400, is at %s" % piece.position)
	# a body behind it: the piece thins out, and comes back when it leaves
	body.position = piece.position + Vector2(0, 20)
	for i in 30:
		await process_frame
	_check(piece.modulate.a < 0.5, "a body behind the piece is hidden (alpha %s)" % piece.modulate.a)
	body.position = Vector2(-1000, 0)
	for i in 60:
		await process_frame
	_check(piece.modulate.a > 0.95, "the piece does not come back (alpha %s)" % piece.modulate.a)
	settings.backdrop_motion = false
	await process_frame
	_check(piece.position.is_equal_approx(Vector2(500, 300)), "with moving backdrops off the piece still moves: %s" % piece.position)
	settings.backdrop_motion = moving
	_check(settings.backdrop_motion == moving, "the setting is not put back")
	world.queue_free()
	print("DEPTH TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
