extends SceneTree
## Render a chapter threshold without playing a full run:
## Godot --path . -s scripts/tools/chapter_card_shot.gd -- output.png swamp_moon

func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var output := args[0] if args.size() > 0 else "/tmp/chapter_card.png"
	var room_name := args[1] if args.size() > 1 else "swamp_moon"
	await process_frame
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var curtain: CanvasLayer = root.get_node("Curtain")
	var chapter: Dictionary = root.get_node("Data").chapter_for("res://scenes/rooms/%s.tscn" % room_name)
	root.get_node("Settings").transitions = "normal"
	Engine.time_scale = 1.0
	paused = false
	curtain.instant = false
	await curtain.cover(chapter, true, true)
	curtain.reveal(chapter, true)
	await create_timer(1.2, true, false, true).timeout
	# A tool-driven reveal can leave its async tween suspended; render the held
	# card state explicitly so this remains a reliable visual QA screenshot.
	curtain._kill()
	for label in [curtain.get_node("%Chapter"), curtain.get_node("%Title"), curtain.get_node("%Epigraph")]:
		label.modulate.a = 1.0
	curtain.get_node("%Rule").scale.x = 1.0
	await process_frame
	var picture: Image = root.get_viewport().get_texture().get_image()
	var code := picture.save_png(output)
	print("CHAPTER_CARD_SHOT %s %s" % [output, error_string(code)])
	quit(0 if code == OK else 1)
