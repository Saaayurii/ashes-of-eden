extends SceneTree
## The pictures the README is made of. Loads the menu and a handful of rooms,
## lets each one settle so the enemies have closed in and the fog has drifted,
## and saves a few frames of every one. Run windowed — a viewport with no
## window renders nothing:
##   godot --path . -s scripts/tools/promo_screenshots.gd -- out_dir
##
## It shoots more than it needs on purpose: pick the good ones by eye and let
## the rest go. Deterministic it is not — the fog, the crowd and the fight are
## all moving, and that is what makes one frame better than the next.

## room index in run.gd ROOMS -> how long to let it run before shooting.
## A quiet room needs a moment; a boss needs long enough to have arrived.
const SHOTS := [
	{"room": 0, "name": "village", "settle": 1.2, "frames": 3, "gap": 0.9},
	{"room": 3, "name": "graveyard", "settle": 1.6, "frames": 3, "gap": 0.9},
	{"room": 5, "name": "swamp", "settle": 1.6, "frames": 3, "gap": 0.9},
	{"room": 9, "name": "catacombs", "settle": 1.6, "frames": 2, "gap": 0.9},
	{"room": 12, "name": "church", "settle": 1.4, "frames": 2, "gap": 0.9},
	{"room": 13, "name": "knight", "settle": 2.4, "frames": 3, "gap": 1.1},
	{"room": 14, "name": "ophanim", "settle": 2.4, "frames": 3, "gap": 1.1},
]

var _out := "/tmp"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	call_deferred("_run")


func _shoot(name: String) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name])
	print("SHOT: ", name)


func _run() -> void:
	await process_frame
	await process_frame

	# The menu, with its layered parallax already breathing.
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await process_frame
	await create_timer(1.5).timeout
	_shoot("menu")

	# change_scene_to_file only sets current_scene; adding the run beside it
	# would shoot every room through the menu still standing behind it.
	var menu := current_scene
	root.remove_child(menu)
	menu.queue_free()
	await process_frame

	var run = load("res://scenes/run/run.tscn").instantiate()
	root.add_child(run)
	current_scene = run
	run.transition.instant = true
	await process_frame
	await process_frame

	for shot in SHOTS:
		run._load_room(shot["room"])
		await create_timer(shot["settle"]).timeout
		for i in range(shot["frames"]):
			_shoot("%s_%d" % [shot["name"], i])
			await create_timer(shot["gap"]).timeout

	quit()
