extends SceneTree
## The two control schemes, headless:
##   godot --headless --path . -s scripts/tools/controls_test.gd
## Keyboard alone keeps the project's map; keyboard + mouse lays MOUSE_LAYOUT
## over it (a click strikes, the other guards) and leaves the pad alone; a key
## or a mouse button can be bound, a clash swaps instead of leaving a hole,
## each scheme keeps its own rebinds; the hero turns to the cursor; the menu
## does all of it. Whatever the player had is put back, on disk too.

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var settings = root.get_node("Settings")
	var was_scheme: String = settings.control_scheme
	var was_aim: bool = settings.mouse_aim
	var was_keys: Dictionary = settings.keys.duplicate()
	var was_mouse_keys: Dictionary = settings.mouse_keys.duplicate()
	settings.keys.clear()
	settings.mouse_keys.clear()
	settings.set_mouse_aim(true)

	settings.set_control_scheme("keyboard")
	_assert(settings.primary("attack") == KEY_J and settings.primary("block") == KEY_L, "keyboard: J strikes, L guards")
	_assert(settings.key_name("attack", false) == "J", "keyboard: the prompt says J (%s)" % settings.key_name("attack", false))
	_assert(not settings.mouse_aims(), "keyboard: no turning to the cursor")

	settings.set_control_scheme("mouse")
	_assert(settings.primary("attack") == -MOUSE_BUTTON_LEFT, "mouse: left click strikes")
	_assert(settings.primary("block") == -MOUSE_BUTTON_RIGHT, "mouse: right click guards")
	_assert(settings.primary("dash") == KEY_SHIFT and settings.primary("skill") == KEY_Q and settings.primary("heal") == KEY_R,
		"mouse: Shift rolls, Q casts, R heals")
	_assert(settings.primary("move_left") == KEY_A and settings.primary("jump") == KEY_SPACE, "mouse: A walks, Space jumps")
	_assert(settings.key_name("attack", false) == TranslationServer.translate("MOUSE_LEFT"), "mouse: the prompt names the click")
	_assert(_has_pad("attack") and _has_pad("block") and _has_pad("jump"), "mouse: the pad's buttons are untouched")
	_assert(not _has_key("attack", KEY_J), "mouse: J no longer swings")
	_assert(settings.mouse_aims(), "mouse: the hero turns to the cursor")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	Input.flush_buffered_events()  # headless has no display loop to flush it
	_assert(Input.is_action_pressed("attack"), "mouse: a real left click is an attack")
	click = click.duplicate()
	click.pressed = false
	Input.parse_input_event(click)
	Input.flush_buffered_events()

	settings.bind("heal", -MOUSE_BUTTON_XBUTTON1)
	_assert(settings.primary("heal") == -MOUSE_BUTTON_XBUTTON1, "rebind: a side button heals")
	_assert(settings.key_name("heal", false) == TranslationServer.translate("MOUSE_BACK"), "rebind: and is named")
	settings.bind("dash", KEY_Q)
	_assert(settings.primary("dash") == KEY_Q and settings.primary("skill") == KEY_SHIFT, "rebind: a clash swaps the two keys")
	var before: int = settings.primary("jump")
	settings.bind("jump", -MOUSE_BUTTON_WHEEL_UP)
	_assert(settings.primary("jump") == before, "rebind: the wheel is refused")
	_assert(settings.binding_of(_key(KEY_K)) == KEY_K and settings.binding_of(click) == -MOUSE_BUTTON_LEFT, "binding_of: a key and a click")

	settings.set_control_scheme("keyboard")
	_assert(settings.primary("attack") == KEY_J and settings.primary("dash") != KEY_Q, "each scheme keeps its own rebinds")
	settings.set_control_scheme("mouse")
	_assert(settings.primary("dash") == KEY_Q, "and the mouse's come back with it")
	settings.reset_keys()
	_assert(settings.primary("dash") == KEY_SHIFT and settings.primary("heal") == KEY_R, "reset: back to the layout")

	# the hero
	var room = load("res://scenes/rooms/church.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	var player = load("res://scenes/player/player.tscn").instantiate()
	room.add_child(player)
	await create_timer(0.3).timeout
	player.global_position = Vector2(300, 360)
	player.facing = 1
	player._aim_at(250.0)
	_assert(player.facing == -1 and player.body.flip_h, "aim: a cursor on the left turns him left")
	player._aim_at(298.0)
	_assert(player.facing == -1, "aim: not for a cursor right on top of him")
	player._dash_left = 0.2
	player._aim_at(400.0)
	_assert(player.facing == -1, "aim: not in the middle of a roll")
	player._dash_left = 0.0
	player._aim_at(400.0)
	_assert(player.facing == 1 and player.hitbox.scale.x > 0.0, "aim: and back right, the blade with him")
	room.queue_free()

	# the menu
	var menu = load("res://scenes/ui/settings_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu.open()
	var scheme_row = menu.find_child("SchemeRow", true, false)
	_assert(scheme_row != null, "menu: a control scheme row")
	_assert(menu.find_child("MouseAimRow", true, false).visible, "menu: the cursor switch shows with the mouse scheme")
	menu._scheme.select(0)
	menu._scheme.item_selected.emit(0)
	_assert(settings.control_scheme == "keyboard" and not menu.find_child("MouseAimRow", true, false).visible,
		"menu: picks the keyboard, hides the cursor switch")
	menu._scheme.item_selected.emit(1)
	menu._start_rebind("attack")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	menu._input(right)
	_assert(settings.primary("attack") == -MOUSE_BUTTON_RIGHT and settings.primary("block") == -MOUSE_BUTTON_LEFT,
		"menu: a right click binds the swing, the guard takes the left")
	_assert(menu.bindings.get_node("attack").text == TranslationServer.translate("MOUSE_RIGHT"), "menu: the button shows it")
	menu._start_rebind("jump")
	var wheel := right.duplicate()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	menu._input(wheel)
	_assert(menu._rebinding == "jump", "menu: the wheel does not end the wait")
	menu._input(_key(KEY_ESCAPE))
	_assert(menu._rebinding == "" and settings.primary("jump") == KEY_SPACE, "menu: Escape gives up")
	menu.queue_free()

	# put the player's own back, through the setters that save
	settings.keys = was_keys
	settings.mouse_keys = was_mouse_keys
	settings.set_mouse_aim(was_aim)
	settings.set_control_scheme(was_scheme)
	var cfg := ConfigFile.new()
	cfg.load(settings.PATH)
	_assert(str(cfg.get_value("controls", "scheme", "keyboard")) == was_scheme and bool(cfg.get_value("controls", "mouse_aim", true)) == was_aim,
		"the player's settings are back on disk")
	print("CONTROLS TEST PASSED" if failures == 0 else "CONTROLS TEST FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)


func _key(code: int) -> InputEventKey:
	var key := InputEventKey.new()
	key.physical_keycode = code
	key.pressed = true
	return key


func _has_pad(action: String) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return true
	return false


func _has_key(action: String, code: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == code:
			return true
	return false


func _assert(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		failures += 1
