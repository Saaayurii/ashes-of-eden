extends SceneTree
## Healing must show its flask; the intro must use the new grave-emergence strip.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var hero = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(hero)
	await process_frame
	var frames: SpriteFrames = hero.body.sprite_frames
	for action in ["heal", "wake"]:
		assert(frames.has_animation(action), "Missing %s animation" % action)
		assert(frames.get_frame_count(action) == 8, "%s needs eight frames" % action)
		for frame in 8:
			var texture := frames.get_frame_texture(action, frame)
			assert(texture != null and texture.get_size() == Vector2(128, 64),
				"%s frame %d has invalid art" % [action, frame])
	hero._start_heal()
	assert(hero.body.animation == "heal", "Healing does not play the flask animation")
	hero._animate(true)
	assert(hero.body.animation == "heal", "Idle replaced healing before it finished")
	print("PLAYER_ACTIONS_OK")
	hero.queue_free()
	await process_frame
	quit()
