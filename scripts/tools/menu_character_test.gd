extends SceneTree
## Every selectable menu figure must have visible, animated frames.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile = root.get_node("Profile")
	var original_selection: Variant = profile.data.get("menu_character", "elian")
	profile.data["menu_character"] = "mara"
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await process_frame
	await process_frame
	var menu := current_scene
	assert(menu._characters[menu._character] == "mara", "Saved menu selection was not restored")
	assert(menu.figure.sprite_frames.get_frame_count("idle") > 1, "Saved character started invisible")
	var expected := ["elian", "knight", "mara", "matthew", "nun", "severin", "villager"]
	assert(menu._characters.size() == expected.size(), "Wrong menu character count")
	for id in expected:
		assert(menu._characters.has(id), "Missing menu character %s" % id)
		menu._character = menu._characters.find(id)
		menu._show_character()
		var figure: AnimatedSprite2D = menu.figure
		assert(figure.visible and figure.sprite_frames != null, "%s is invisible" % id)
		assert(figure.sprite_frames.has_animation("idle"), "%s has no idle animation" % id)
		assert(figure.sprite_frames.get_frame_count("idle") > 1, "%s idle has no motion" % id)
		assert(figure.sprite_frames.get_frame_texture("idle", 0) != null, "%s idle texture is missing" % id)
		assert(figure.scale == Vector2.ONE * menu.FIGURE_SCALE, "%s has inconsistent scale" % id)
		if id != "elian":
			assert(figure.sprite_frames.has_animation("walk"), "%s has no walk animation" % id)
			assert(figure.sprite_frames.get_frame_count("walk") > 1, "%s walk has no motion" % id)
		print("MENU_CHARACTER_OK ", id)
	profile.data["menu_character"] = original_selection
	quit()
