extends SceneTree
## Dev helper: every weapon in Elian's hands in the practice yard — its chain
## swung step by step, its guard and its lunge — saved as screenshots to look
## at the frames make_weapon_frames.py drew (docs/WEAPONS.md). Needs a display:
##   godot --path . -s scripts/tools/weapon_shot.gd -- out_dir

var _out := "/tmp"
var _hero: Node2D


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	call_deferred("_run")


func _shot(name: String) -> void:
	await process_frame
	RenderingServer.force_draw()  # a window without focus may not have drawn this frame
	var image: Image = root.get_viewport().get_texture().get_image()
	# the hero and the reach of his weapon, not the whole yard
	var zoom := Vector2(image.get_size()) / root.get_visible_rect().size  # the window over the game's own size
	var at: Vector2 = _hero.get_global_transform_with_canvas().origin * zoom
	var box := Rect2i(Vector2i(at) + Vector2i(-150, -190), Vector2i(380, 230)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	image.get_region(box).save_png("%s/%s.png" % [_out, name])


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _tap(action: String) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)


func _run() -> void:
	root.get_node("Game").practice = "training_dummy"
	change_scene_to_file("res://scenes/run/run.tscn")
	await process_frame
	await process_frame
	# a windowed Godot driven from a terminal never has focus, and the pause
	# menu opens on focus out (prologue_shot.gd): nothing here needs it
	for node in root.find_children("*", "", true, false):
		if node.get_script() != null and str(node.get_script().resource_path).ends_with("pause_menu.gd"):
			node.queue_free()
	root.get_node("Net").set_paused(false)
	await create_timer(1.6).timeout
	var hero = current_scene.player
	_hero = hero
	var data = root.get_node("Data")
	var ids: Array = data.weapons.keys()
	ids.sort()
	for id in ids:
		hero.equip(id)
		hero.global_position.x = 260.0
		hero.facing = 1
		await create_timer(0.6).timeout
		var steps: int = data.weapons[id].get("chain", []).size()
		for i in steps:
			await _tap("attack")
			await _frames(5)
			await _shot("%s_step%d" % [id, i])
			while hero._attack_cd > 0.0:
				await physics_frame
		await create_timer(0.5).timeout
		Input.action_press("block")
		await create_timer(0.4).timeout
		await _shot("%s_guard" % id)
		Input.action_release("block")
		await create_timer(0.5).timeout
	quit()
