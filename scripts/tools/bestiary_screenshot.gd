extends SceneTree
## Visual regression helper for the expanded bestiary.
##   godot -s scripts/tools/bestiary_screenshot.gd -- /tmp/bestiary.png [page]
## A page id (an enemy, "npc:…", "note:…", "deed:…") opens that page instead.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var output := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "/tmp/bestiary.png"
	var profile = root.get_node("Profile")
	var data = root.get_node("Data")
	for id in data.enemies:
		profile.data.bestiary[id] = {"seen": true, "kills": 1}
	for id in data.npcs:
		profile.data.bestiary["npc:" + id] = {"seen": true, "met": true, "kills": 0}
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await process_frame
	await process_frame
	var book = current_scene.get_node("Bestiary")
	book.open()
	if OS.get_cmdline_user_args().size() > 1:
		var page: String = OS.get_cmdline_user_args()[1]
		if page.begins_with("deed:"):
			profile.data.achievements["first_night"] = 1790000000
			profile.data.achievements["dawn"] = 1790000000
			book.open()
		var button = book.list.get_node_or_null(page.replace(":", "_"))
		if button:
			button.grab_focus()
	await create_timer(0.5).timeout
	root.get_viewport().get_texture().get_image().save_png(output)
	print("BESTIARY SCREENSHOT: " + output)
	quit()
