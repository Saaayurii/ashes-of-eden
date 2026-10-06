extends SceneTree
## Dev helper: what lives on a backdrop (scripts/rooms/backdrop_life.gd).
## Each room is drawn whole with the particles, weather and ambience hidden,
## at two moments GAP seconds apart; out_dir/<room>_life.png is the first
## frame, out_dir/<room>_diff.png lights up every pixel that changed — the
## flames, the falls, the swaying banners — over a dimmed copy of the room,
## and the zones from data/backdrops.json are outlined on it. With `gust`, the
## frames are one apart and between them a full gust and a cleared-room swell
## arrive from the middle of the room, so the diff shows only what answers. Needs a display:
## `wound` does the same with the hero at death's door (the veins' beat),
## `flash` with a lightning stroke, `rage` with a boss nearly down, `lean`
## with the hero deep in temptation. Beyond the chapter's rooms: main_menu,
## practice_yard, arena.
##   godot --path . -s scripts/tools/backdrop_life_shot.gd -- out_dir [room|room] [gust|wound|flash|rage|lean]

## Pictures that are not rooms of the chapter: scene, its picture, its size.
const EXTRA := {
	"main_menu": ["res://scenes/ui/main_menu.tscn", "Layers/Background", Vector2i(640, 340)],
	"practice_yard": ["res://scenes/rooms/practice_yard.tscn", "Parallax/Backdrop", Vector2i(704, 396)],
	"arena": ["res://scenes/pvp/arena.tscn", "Parallax/Backdrop", Vector2i(640, 360)],
}

const GAP := 0.45


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp"
	var only: Array = Array(args[1].split("|")) if args.size() > 1 and args[1] != "" else []
	var run := FileAccess.get_file_as_string("res://scripts/run/run.gd")
	var listed := run.substr(run.find("const ROOMS := ["))
	listed = listed.substr(0, listed.find("]"))
	var rooms: Array = []
	for found in RegEx.create_from_string("res://scenes/rooms/\\w+\\.tscn").search_all(listed):
		rooms.append(found.get_string())
	for key in EXTRA:
		if only.has(key):
			rooms.append(EXTRA[key][0])
	var mode := ""
	for each in ["gust", "wound", "flash", "rage", "lean"]:
		if args.has(each):
			mode = each
	var life = load("res://scripts/rooms/backdrop_life.gd")
	for path in rooms:
		var name: String = path.get_file().get_basename()
		if not only.is_empty() and not only.has(name):
			continue
		var room = load(path).instantiate()
		root.add_child(room)
		current_scene = room
		root.size = EXTRA[name][2] if EXTRA.has(name) else Vector2i(int(room.width), int(room.height))
		if EXTRA.has(name):
			# a picture without a room: hold its materials the way a room does
			var picture = room.get_node(EXTRA[name][1])
			room.set_meta(&"backdrop_life", {"painting": picture, "materials": [picture.material]})
			# nothing but the picture: menus, fog, the hero by the fire, the pause
			for node in room.find_children("*", "CanvasLayer", true, false):
				node.visible = false
			var keep: Node = picture
			while keep != room:
				for sibling in keep.get_parent().get_children():
					if sibling != keep and sibling is CanvasItem:
						sibling.visible = false
				keep = keep.get_parent()
		root.content_scale_size = root.size
		var camera := Camera2D.new()
		camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
		room.add_child(camera)
		camera.make_current()
		for frame in 10:
			await process_frame
		_still(room)
		paused = false
		await process_frame
		await process_frame
		var gust: bool = mode != ""
		if gust:
			# one frame apart, so all that changes is the answer to the gust
			var ambience = room.get_node_or_null("Ambience")
			if ambience != null:
				ambience.free()
			life.react(room, {"beat": 0.1})
			await process_frame
			await process_frame
		var a := root.get_texture().get_image()
		if gust:
			match mode:
				"gust":
					life.react(room, {"origin": Vector2(root.size) * 0.5, "energy": 1.0, "exhale": 1.0})
				"wound":
					life.react(room, {"dread": 1.0, "beat": 0.1})
				"flash":
					life.react(room, {"flash": 0.55})
				"lean":
					life.react(room, {"path": "temptation", "lead": 6})
				"rage":
					life.react(room, {"rage": 1.0, "beat": 0.1})
			await process_frame
			await process_frame
		else:
			await create_timer(GAP).timeout
		var b := root.get_texture().get_image()
		a.save_png("%s/%s_life.png" % [out, name])
		_diff(a, b, room, life, name).save_png("%s/%s_diff.png" % [out, name])
		print("%s: written" % name)
		room.queue_free()
		await process_frame
	quit()


## Everything that moves on its own but is not the backdrop.
func _still(room: Node) -> void:
	for node in room.find_children("*", "CPUParticles2D", true, false):
		(node as CanvasItem).visible = false
	for name in ["Ambience", "Weather", "FogFar", "SkyClip", "Props", "DecorFront"]:
		var node = room.get_node_or_null(name)
		if node is CanvasItem:
			node.visible = false
	for node in room.find_children("*", "Light2D", true, false):
		node.enabled = false


func _diff(a: Image, b: Image, room: Node, life, name: String) -> Image:
	var out := Image.create(a.get_width(), a.get_height(), false, Image.FORMAT_RGB8)
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := clampf((absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) * 12.0, 0.0, 1.0)
			var base := ca.get_luminance() * 0.35
			out.set_pixel(x, y, Color(base + d, base + d * 0.8, base))
	var painting = room.get_meta(&"backdrop_life").painting if room.has_meta(&"backdrop_life") else null
	var found: Dictionary = life.rule(name)
	if painting == null or found.is_empty():
		return out
	var xf: Transform2D = painting.get_global_transform()
	for zone in found.zones:
		var r: Array = zone.rect
		var p0: Vector2 = xf * Vector2(r[0], r[1])
		var p1: Vector2 = xf * Vector2(r[0] + r[2], r[1] + r[3])
		var rect := Rect2(p0, p1 - p0).intersection(Rect2(0, 0, out.get_width() - 1, out.get_height() - 1))
		var c := Color(0.2, 0.8, 1.0)
		for x in range(int(rect.position.x), int(rect.end.x)):
			out.set_pixel(x, int(rect.position.y), c)
			out.set_pixel(x, int(rect.end.y), c)
		for y in range(int(rect.position.y), int(rect.end.y)):
			out.set_pixel(int(rect.position.x), y, c)
			out.set_pixel(int(rect.end.x), y, c)
	return out

