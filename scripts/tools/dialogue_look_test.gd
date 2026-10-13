extends SceneTree
## A dialogue's look (data/dialogue_looks.json, DialogueLook) reaches the box:
##   godot --headless --path . -s scripts/tools/dialogue_look_test.gd
## A dialogue with no look keeps the scene's layout; one with a look moves its
## panel, takes the style's colours and shows the speaker's portrait where it
## says; a line's own look is laid over the dialogue's ("portrait": false hides
## it); and the next plain dialogue gets everything back.

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _assert(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)
	else:
		print("ok  ", what)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	var data = root.get_node("Data")
	var box = load("res://scenes/ui/dialogue_box.tscn").instantiate()
	root.add_child(box)
	await _frames(2)
	var looks: Dictionary = load("res://scripts/ui/dialogue_look.gd").doc()
	_assert(looks.get("styles", {}).has("default") and looks.styles.has("ember"), "the styles are read from the file")
	var ember: Dictionary = looks.styles.ember
	var home: Vector2 = box.panel.position
	var home_size: Vector2 = box.panel.size
	data.dialogues["qa_plain"] = {"id": "qa_plain", "start": "a", "nodes": {
		"a": {"speaker": "NPC_MATTHEW", "text": "DLG_CONTINUE"}}}
	data.dialogues["qa_look"] = {"id": "qa_look", "start": "a",
		"look": {"style": "ember", "panel": [120, 40, 400, 96], "portrait": [20, 40, 80]},
		"nodes": {
			"a": {"speaker": "NPC_MATTHEW", "text": "DLG_CONTINUE", "next": "b"},
			"b": {"speaker": "SPEAKER_ELIAN", "text": "DLG_SKIP", "look": {"panel": [16, 200, 300, 120], "portrait": false}}}}

	box.play("qa_plain")
	await _frames(2)
	_assert(box.panel.position.is_equal_approx(home), "a plain dialogue keeps the scene's panel (%s)" % box.panel.position)
	_assert(not box._portrait.visible, "and shows no portrait")
	box._on_continue()
	await _frames(2)

	box.play("qa_look")
	await _frames(2)
	var screen: Vector2 = box.size
	var want: Rect2 = load("res://scripts/ui/dialogue_look.gd").on_screen([120, 40, 400, 96], screen)
	_assert(box.panel.position.is_equal_approx(want.position), "the look moves the panel (%s, want %s)" % [box.panel.position, want.position])
	_assert(absf(box.panel.size.x - want.size.x) < 1.0, "and sizes it (%s)" % box.panel.size)
	var panel_box := box.panel.get_theme_stylebox("panel") as StyleBoxFlat
	_assert(panel_box != null and panel_box.bg_color.is_equal_approx(Color.html(ember.bg)), "the style colours the panel")
	_assert(panel_box.border_width_left == int(ember.border_width), "and draws its border")
	_assert(box.speaker_label.get_theme_color("font_color").is_equal_approx(Color.html(ember.speaker)), "the speaker's name takes the style's colour")
	_assert(box._portrait.visible and box._portrait_image.texture != null, "Matthew's portrait is shown (his avatar in data/npcs)")
	var face: Rect2 = load("res://scripts/ui/dialogue_look.gd").on_screen([20, 40, 80], screen)
	_assert(box._portrait.position.is_equal_approx(face.position), "where the look puts it (%s)" % box._portrait.position)

	box._on_continue()
	await _frames(2)
	var line_spot: Rect2 = load("res://scripts/ui/dialogue_look.gd").on_screen([16, 200, 300, 120], screen)
	_assert(box.panel.position.is_equal_approx(line_spot.position), "a line's own look moves its panel")
	_assert(not box._portrait.visible, "\"portrait\": false hides the window for a line (Elian has no portrait anyway)")
	_assert(box.speaker_label.get_theme_color("font_color").is_equal_approx(Color.html(ember.speaker)), "the line keeps the dialogue's style")
	box._on_continue()
	await _frames(2)
	_assert(not box.is_open() and not box._portrait.visible, "the end of the talk hides the portrait")

	box.play("qa_plain")
	await _frames(2)
	_assert(box.panel.position.is_equal_approx(home) and box.panel.size.is_equal_approx(home_size), "the next plain dialogue gets the scene's panel back")
	_assert(not box.panel.has_theme_stylebox_override("panel"), "and the theme's own frame")
	box._on_continue()
	await _frames(2)

	data.dialogues["qa_caption"] = {"id": "qa_caption", "start": "a", "blocking": false,
		"look": {"style": "spectral", "caption": [200, 120, 240]},
		"nodes": {"a": {"speaker": "SPEAKER_ELIAN", "text": "DLG_CONTINUE"}}}
	box.play("qa_caption")
	await _frames(2)
	var at: Rect2 = load("res://scripts/ui/dialogue_look.gd").on_screen([200, 120, 240, 36], screen)
	_assert(box.caption.position.is_equal_approx(at.position) and absf(box.caption.size.x - at.size.x) < 1.0,
		"a caption goes where its look says (%s)" % box.caption.position)
	_assert(box.caption.get_theme_color("font_color").is_equal_approx(Color.html(looks.styles.spectral.caption)), "in the style's caption colour")
	box.skip()
	await _frames(3)
	box.announce("qa")
	await _frames(1)
	_assert(box.caption.get_theme_color("font_color").is_equal_approx(box._home_paint[box.caption][0]), "the game's own announcement keeps the scene's caption")
	box.skip()
	await _frames(3)

	data.dialogues.erase("qa_plain")
	data.dialogues.erase("qa_look")
	data.dialogues.erase("qa_caption")
	box.queue_free()
	await _frames(1)
	if failures:
		push_error("DIALOGUE_LOOK_FAILED: %d" % failures)
		quit(1)
	else:
		print("DIALOGUE_LOOK_OK")
		quit(0)
