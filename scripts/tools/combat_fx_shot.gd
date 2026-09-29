extends SceneTree
## Dev helper: what a death and a bolt look like, frame by frame. Kills one of
## each enemy beside the hero and lets a ranged one fire, then saves a contact
## sheet per enemy (crops of the viewport around the body, time running right).
## Needs a display:
##   xvfb-run -a godot --rendering-driver opengl3 --path . -s scripts/tools/combat_fx_shot.gd -- out_dir [enemy_id…]

const TIMES := [0.0, 0.08, 0.18, 0.32, 0.5, 0.75, 1.05]
const CROP := Vector2i(160, 120)

var _out := "/tmp"
var _only: Array = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_only = args.slice(1)
	call_deferred("_run")


func _run() -> void:
	change_scene_to_file("res://scenes/run/run.tscn")
	await create_timer(0.6).timeout
	var run = current_scene
	run.transition.instant = true
	run._load_room(run.ROOMS.find("res://scenes/rooms/graveyard_tree.tscn"))
	await create_timer(0.6).timeout
	run.cutscene.abort()
	root.get_node("Game").cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false
	for body in get_nodes_in_group("enemies"):
		body.queue_free()
	var player = run.player
	player.global_position = Vector2(300, 380)
	player.stats.max_hp = 99999.0
	player.hp = 99999.0
	# no gift cards over the shots: every kill's essence is taken back
	root.get_node("EventBus").essence_changed.connect(func(_e, _n, _l): root.get_node("Game").essence = 0.0)
	root.get_node("Game").essence_bonus = -1.0
	var data = root.get_node("Data")
	var ids: Array = _only if not _only.is_empty() else data.enemies.keys()
	for id in ids:
		if id == "ophanim_seal":
			continue
		await _death(run, player, id)
		await _bolt(run, player, id)
	quit()


func _grab(at: Vector2) -> Image:
	var shot: Image = root.get_viewport().get_texture().get_image()
	var xform: Transform2D = root.get_viewport().get_canvas_transform()
	var screen := xform * at
	var scale := shot.get_width() / float(root.get_viewport().get_visible_rect().size.x)
	var centre := Vector2i(screen * scale)
	var rect := Rect2i(centre - CROP / 2, CROP).intersection(Rect2i(Vector2i.ZERO, shot.get_size()))
	var crop := Image.create(CROP.x, CROP.y, false, Image.FORMAT_RGBA8)
	crop.fill(Color.BLACK)
	crop.blit_rect(shot, rect, Vector2i.ZERO)
	return crop


func _sheet(frames: Array, name: String) -> void:
	var sheet := Image.create(CROP.x * frames.size(), CROP.y, false, Image.FORMAT_RGBA8)
	for i in frames.size():
		sheet.blit_rect(frames[i], Rect2i(Vector2i.ZERO, CROP), Vector2i(CROP.x * i, 0))
	sheet.save_png("%s/%s.png" % [_out, name])


func _death(run, player, id: String) -> void:
	var foe = run.room.spawn_enemy(id, player.global_position + Vector2(50, -6), true)
	await create_timer(0.5).timeout
	if not is_instance_valid(foe):
		return
	foe.set_physics_process(false)
	var at: Vector2 = foe.global_position + Vector2(0, -10)
	var frames := []
	var clock := 0.0
	foe.take_damage(99999.0)
	for t in TIMES:
		await create_timer(t - clock).timeout
		clock = t
		frames.append(_grab(at))
	_sheet(frames, "death_" + id)
	await create_timer(1.0).timeout


func _bolt(run, player, id: String) -> void:
	var data = root.get_node("Data")
	var spec: Dictionary = data.enemies[id]
	var ranged := -1
	var attacks: Array = spec.get("attacks", []) + ([spec.attack] if spec.has("attack") else [])
	for i in attacks.size():
		if attacks[i].get("type") == "ranged":
			ranged = i
	if ranged < 0:
		return
	var foe = run.room.spawn_enemy(id, player.global_position + Vector2(140, -6), true)
	await create_timer(0.4).timeout
	foe.set_physics_process(false)
	foe._attack = foe._attacks[ranged]
	foe._strike(player.global_position - foe.global_position)
	var frames := []
	for i in 6:
		await create_timer(0.09).timeout
		var bolt: Node2D = null
		for node in run.room.get_children():
			if node is Area2D and node.get("visual_style") != null:
				bolt = node
		frames.append(_grab(bolt.global_position if bolt != null else foe.global_position))
	_sheet(frames, "bolt_" + id)
	foe.take_damage(99999.0)
	await create_timer(1.2).timeout
