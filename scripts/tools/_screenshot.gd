extends SceneTree
## Dev helper: loads the Run scene, walks the player to a few spots and saves
## screenshots. Run windowed (not --headless):
##   Godot --path . -s scripts/tools/_screenshot.gd -- out_dir room_index

var _out := "/tmp"
var _room := 0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_room = int(args[1])
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var run = load("res://scenes/run/run.tscn").instantiate()
	root.add_child(run)
	current_scene = run
	run.transition.instant = true
	await process_frame
	await process_frame
	if _room > 0:
		run._load_room(_room)
	await create_timer(0.6).timeout
	var player = run.player
	var room = run.room
	var spots := []
	for prop in get_nodes_in_group("props"):
		spots.append(prop.global_position + Vector2(-2, -20))
	var idx := 0
	for spot in spots:
		player.global_position = spot
		player.velocity = Vector2.ZERO
		await create_timer(0.35).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		img.save_png("%s/room%d_%02d.png" % [_out, _room, idx])
		idx += 1
	quit()
