extends SceneTree
## The main menu in one language, for looking at rather than guessing about —
## mainly: does the font we ship actually have the glyphs this locale needs?
## Run windowed:
##   godot --path . -s scripts/tools/locale_shot.gd -- out.png zh_CN

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/locale.png"
	var locale: String = args[1] if args.size() > 1 else "zh_CN"
	await process_frame
	TranslationServer.set_locale(locale)
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await process_frame
	await create_timer(1.5).timeout
	root.get_viewport().get_texture().get_image().save_png(out)
	print("LOCALE SHOT: %s (%s)" % [out, TranslationServer.get_locale()])
	quit()
