extends SceneTree
## Dev helper: how blood looks on the real paintings, blow by blow. In each room
## a body is felled beside the hero by each of the hero's moves (data/gore.json
## `moves`), every one torn; out_dir/<room>_<move>_<enemy>.png is a strip of
## crops round the body (time running right), and out_dir/<room>.png the
## whole view at the end, every mark the room's blows left lying on its
## painting — soaked in, on the ledges, the walls, the wall behind, in the water.
## Needs a display:
##   godot --path . -s scripts/tools/gore_shot.gd -- out_dir [room|room] [move|move] [enemy|enemy]

const ROOMS := ["village_night", "graveyard_tree", "swamp_red", "catacombs_2", "crypt_lava", "church"]
const MOVES := ["attack3", "rising", "thrust", "cleave", "sweep", "slam", "lunge", "nova"]
const ENEMIES := ["possessed_villager", "cultist", "fallen_guard"]
const TIMES := [0.06, 0.3, 0.8, 2.5]
const CROP := Vector2i(400, 240)

var _out := "/tmp"


func _init() -> void:
	call_deferred("_run")


func _arg(args: Array, i: int, fallback: Array) -> Array:
	return Array(args[i].split("|")) if args.size() > i and args[i] != "" else fallback


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp"
	var rooms := _arg(args, 1, ROOMS)
	var moves := _arg(args, 2, MOVES)
	var enemies := _arg(args, 3, ENEMIES)
	# every death tears, so each move's way shows
	var gore = load("res://scripts/fx/gore.gd")
	gore.move_spec("")
	for table in gore._materials.values():
		if int(table.get("limbs", 0)) >= 2:
			table.chance = 1.0
	root.get_node("Settings").gore = "full"
	change_scene_to_file("res://scenes/run/run.tscn")
	await create_timer(0.6).timeout
	var run = current_scene
	# a windowed Godot driven from a terminal never has focus, and the pause menu opens on
	# losing it (prologue_shot.gd): nothing here needs it
	for node in root.find_children("*", "", true, false):
		if node.get_script() != null and str(node.get_script().resource_path).ends_with("pause_menu.gd"):
			node.queue_free()
	root.get_node("EventBus").essence_changed.connect(func(_e, _n, _l): root.get_node("Game").essence = 0.0)
	root.get_node("Game").essence_bonus = -1.0
	for name in rooms:
		run._load_room(run.ROOMS.find("res://scenes/rooms/%s.tscn" % name))
		await create_timer(0.8).timeout
		run.cutscene.abort()
		root.get_node("Game").cutscene = false
		if run.dialogue.visible:
			run.dialogue.call("_on_skip")
		paused = false
		for body in get_nodes_in_group("enemies"):
			body.queue_free()
		var player = run.player
		player.stats.max_hp = 99999.0
		player.hp = 99999.0
		var i := 0
		for move in moves:
			var id: String = enemies[i % enemies.size()]
			i += 1
			await _kill(run, player, id, move, "%s_%s_%s" % [name, move, id])
		await create_timer(0.5).timeout
		RenderingServer.force_draw(false)
		root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	quit()


func _kill(run, player, id: String, move: String, label: String) -> void:
	# in front of the hero, who comes in at the room's left door facing in
	var foe = run.room.spawn_enemy(id, player.global_position + Vector2(46.0, -8), true)
	await create_timer(0.5).timeout
	if not is_instance_valid(foe):
		return
	foe.set_physics_process(false)
	player.set_physics_process(false)
	var at: Vector2 = foe.global_position + Vector2(0, -16)
	var frames := []
	var clock := 0.0
	foe.take_damage(99999.0, player, {"move": move})
	print("GORE_SHOT %s: %s hp %s torn %s" % [label, "alive" if is_instance_valid(foe) and not foe.get("_dead") else "dead",
		foe.get("hp") if is_instance_valid(foe) else "-", get_nodes_in_group("gore_piece").size()])
	for t in TIMES:
		await create_timer(t - clock).timeout
		clock = t
		frames.append(_grab(at))
	var sheet := Image.create(CROP.x * frames.size(), CROP.y, false, Image.FORMAT_RGBA8)
	for k in frames.size():
		sheet.blit_rect(frames[k], Rect2i(Vector2i.ZERO, CROP), Vector2i(CROP.x * k, 0))
	sheet.save_png("%s/%s.png" % [_out, label])
	player.set_physics_process(true)


func _grab(at: Vector2) -> Image:
	RenderingServer.force_draw(false)  # a window another covers stops drawing by itself
	var shot: Image = root.get_viewport().get_texture().get_image()
	var xform: Transform2D = root.get_viewport().get_canvas_transform()
	var scale := shot.get_width() / float(root.get_viewport().get_visible_rect().size.x)
	var centre := Vector2i((xform * at) * scale)
	var rect := Rect2i(centre - CROP / 2, CROP).intersection(Rect2i(Vector2i.ZERO, shot.get_size()))
	var crop := Image.create(CROP.x, CROP.y, false, Image.FORMAT_RGBA8)
	crop.fill(Color.BLACK)
	crop.blit_rect(shot, rect, Vector2i(rect.position - (centre - CROP / 2)))
	return crop
