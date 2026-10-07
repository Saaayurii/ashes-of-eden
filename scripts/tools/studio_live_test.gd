extends SceneTree
## The studio's sandbox (StudioLive, `--studio-live`): what the studio posts —
## strips as base64 PNG, a cell, the enemy it fights like — becomes the foe in
## the practice yard, built through the same Enemy._setup_sprite as a file:
##   - only `--studio-live` asks for it;
##   - a post makes a creature on its base, with her strips and none of the base's;
##   - the yard's foe is swapped for it, and swapped again on the next post;
##   - a strip that is not whole cells is left out, a post without idle is refused.
##   godot --headless --path . -s scripts/tools/studio_live_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _settle(seconds := 0.3) -> void:
	await create_timer(seconds, true, false, true).timeout


func _foes() -> Array:
	return get_nodes_in_group("enemies").filter(func(e) -> bool: return not e.is_dead())


## A strip of `frames` cells, each a different colour, as the studio sends it.
func _strip(cell: Vector2i, frames: int) -> String:
	var picture := Image.create(cell.x * frames, cell.y, false, Image.FORMAT_RGBA8)
	for i in frames:
		picture.fill_rect(Rect2i(i * cell.x + 8, 4, cell.x - 16, cell.y - 5), Color.from_hsv(i / float(frames), 0.6, 0.7))
	return "data:image/png;base64," + Marshalls.raw_to_base64(picture.save_png_to_buffer())


func _run() -> void:
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	var live_script = load("res://scripts/run/studio_live.gd")
	_check(live_script.requested(PackedStringArray(["--studio-live"])), "--studio-live asks for the sandbox")
	_check(not live_script.requested(PackedStringArray(["--studio-preview", "practice=cultist"])), "nothing else does")

	game.practice = live_script.WAITING_FOR
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.8)
	var run = current_scene
	run.transition.instant = true
	run._start_studio_live()
	await _settle(0.4)
	_check(run.room_index == run.PRACTICE_INDEX, "the sandbox is the practice yard")
	_check(_foes().size() == 1 and _foes()[0].enemy_id == "training_dummy", "with the straw man until the studio posts")

	var cell := Vector2i(32, 40)
	var spec: Dictionary = run.studio_live.apply({
		"type": "ashes-live", "name": "Лучница", "extends": "cultist", "cell": [cell.x, cell.y], "fps": 7,
		"strips": {"idle": _strip(cell, 2), "walk": _strip(cell, 3), "attack": _strip(Vector2i(30, 40), 4)},
	})
	_check(not spec.is_empty() and data.enemies.has(live_script.ID), "a post becomes a creature in Data")
	_check(spec.get("hp") == data.enemies.cultist.get("hp") and spec.get("behaviour") == data.enemies.cultist.get("behaviour") and spec.get("attacks") == data.enemies.cultist.get("attacks"), "that fights like the one it extends")
	_check(spec.get("name") == "Лучница", "under the name she gave it")
	_check(spec.sprite.animations.keys().size() == 2 and not spec.sprite.animations.has("attack"),
		"a strip that is not whole cells is left out, the base's strips are not borrowed")
	await _settle(0.4)
	var foes := _foes()
	_check(foes.size() == 1 and foes[0].enemy_id == live_script.ID, "the yard's foe is hers now")
	if foes.size() == 1:
		var frames: SpriteFrames = foes[0].sprite.sprite_frames
		_check(frames.get_frame_count("idle") == 2 and frames.get_frame_count("walk") == 3, "its frames are her strips")
		_check(frames.get_frame_texture("idle", 0).get_size() == Vector2(cell), "cut at her cell")

	run.studio_live.apply({"type": "ashes-live", "extends": "cultist", "cell": [cell.x, cell.y], "strips": {"idle": _strip(cell, 4)}})
	await _settle(0.4)
	foes = _foes()
	_check(foes.size() == 1 and foes[0].sprite.sprite_frames.get_frame_count("idle") == 4, "the next post swaps it again")
	_check(run.studio_live.apply({"type": "ashes-live", "cell": [32, 40], "strips": {"walk": _strip(cell, 2)}}).is_empty(),
		"a post without an idle strip is refused")
	_check(live_script.build_spec({"extends": "ophanim", "cell": [32, 40], "strips": {"idle": _strip(cell, 1)}}).get("hp") == data.enemies.cultist.get("hp"),
		"a boss is no base: it falls back to the cultist")

	game.practice = ""
	print("studio_live_test: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)
