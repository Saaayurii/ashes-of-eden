extends SceneTree
## Dev helper: what a painted tree does when it is struck (scripts/rooms/foliage.gd).
## Each room with trees is drawn whole (particles, weather and ambience hidden);
## every crown takes a swing from the left at once. out_dir/<room>_struck.png
## is the room SHOT seconds after the blow (the crowns leaning, the leaves
## and ravens in the air; <room>_perched.png is just before it, the ravens
## still on their branches), <room>_bend.png lights up every pixel the blow moved over a dimmed
## copy, outlining the crowns, and <room>_leaves.png is the room LATER seconds
## on, the leaves come down onto the floors. Needs a display.
##   godot --path . -s scripts/tools/foliage_shot.gd -- out_dir [room|room]

const SHOT := 0.22
const LATER := 6.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp"
	var only: Array = Array(args[1].split("|")) if args.size() > 1 and args[1] != "" else []
	var bus = root.get_node("/root/EventBus")
	for path in load("res://scripts/data/data_doc.gd").doc("game.json").get("rooms", []):
		var name: String = str(path).get_file().get_basename()
		if not only.is_empty() and not only.has(name):
			continue
		var room = load(path).instantiate()
		root.add_child(room)
		var foliage = room.get_node_or_null("Foliage")
		if foliage == null:
			room.queue_free()
			await process_frame
			continue
		root.size = Vector2i(int(room.width), int(room.height))
		root.content_scale_size = root.size
		current_scene = room
		var camera := Camera2D.new()
		camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
		room.add_child(camera)
		camera.make_current()
		for node in room.find_children("*", "CPUParticles2D", true, false):
			(node as CanvasItem).visible = false
		for each in ["Ambience", "Weather", "FogFar", "SkyClip", "DecorFront"]:
			var node = room.get_node_or_null(each)
			if node is CanvasItem:
				node.visible = false
		for frame in 12:
			await process_frame
		var before := root.get_texture().get_image()
		before.save_png("%s/%s_perched.png" % [out, name])
		for crown in foliage.trees:
			bus.world_impulse.emit(crown.rect.get_center(), Vector2(1, -0.15), 0.85, &"attack")
		await create_timer(SHOT).timeout
		var struck := root.get_texture().get_image()
		struck.save_png("%s/%s_struck.png" % [out, name])
		_diff(before, struck, foliage).save_png("%s/%s_bend.png" % [out, name])
		await create_timer(LATER).timeout
		root.get_texture().get_image().save_png("%s/%s_leaves.png" % [out, name])
		print("%s: %d crowns, %d leaves, %d ravens" % [name, foliage.trees.size(), foliage.leaves.size(), foliage.birds.size()])
		room.queue_free()
		await process_frame
	quit()


func _diff(a: Image, b: Image, foliage) -> Image:
	var out := Image.create(a.get_width(), a.get_height(), false, Image.FORMAT_RGB8)
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := clampf((absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) * 6.0, 0.0, 1.0)
			var base := ca.get_luminance() * 0.35
			out.set_pixel(x, y, Color(base + d, base + d * 0.8, base))
	for crown in foliage.trees:
		var rect: Rect2 = crown.rect.intersection(Rect2(0, 0, out.get_width() - 1, out.get_height() - 1))
		for x in range(int(rect.position.x), int(rect.end.x)):
			out.set_pixel(x, int(rect.position.y), Color(0.2, 0.8, 1.0))
			out.set_pixel(x, int(rect.end.y), Color(0.2, 0.8, 1.0))
		for y in range(int(rect.position.y), int(rect.end.y)):
			out.set_pixel(int(rect.position.x), y, Color(0.2, 0.8, 1.0))
			out.set_pixel(int(rect.end.x), y, Color(0.2, 0.8, 1.0))
	return out
