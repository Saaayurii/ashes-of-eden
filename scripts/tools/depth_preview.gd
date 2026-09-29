extends SceneTree

## Render one room at a chosen camera position for visual QA.
## godot --path . -s scripts/tools/depth_preview.gd -- graveyard_arches 800 360 /tmp/depth.png

func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		push_error("room x y output.png required")
		quit(1)
		return
	var room_scene := load("res://scenes/rooms/%s.tscn" % args[0]) as PackedScene
	if room_scene == null:
		quit(1)
		return
	var room := room_scene.instantiate()
	root.add_child(room)
	var camera := Camera2D.new()
	camera.position = Vector2(float(args[1]), float(args[2]))
	if args.size() >= 5:
		camera.zoom = Vector2.ONE * maxf(0.1, float(args[4]))
	root.add_child(camera)
	camera.make_current()
	await process_frame
	await process_frame
	await create_timer(0.35).timeout
	var image := root.get_texture().get_image()
	var status := image.save_png(args[3])
	print("DEPTH_PREVIEW ", args[0], " ", args[3], " ", image.get_size(), " status=", status)
	quit(0 if status == OK else 1)
