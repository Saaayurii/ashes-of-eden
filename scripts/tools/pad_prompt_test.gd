extends SceneTree
## Prompts name the button on the device in hand (Settings.key_name):
##   - a pad press switches every prompt to the pad's button names, a key
##     press switches them back, and the HUD follows at once;
##   - rebinding in Settings always names the key.
##   godot --headless --path . -s scripts/tools/pad_prompt_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _press(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	await process_frame


func _run() -> void:
	var settings = root.get_node("Settings")
	var hud = load("res://scenes/ui/hud.tscn").instantiate()
	root.add_child(hud)
	await process_frame
	var key: String = settings.key_name("attack")
	var pad_button := InputEventJoypadButton.new()
	pad_button.button_index = JOY_BUTTON_A
	pad_button.pressed = true
	await _press(pad_button)
	_check(settings.using_pad, "a pad press is noticed")
	_check(settings.key_name("attack") == "X" and settings.key_name("block") == "RB" and settings.key_name("jump") == "A",
		"prompts name the pad's buttons (attack %s, block %s)" % [settings.key_name("attack"), settings.key_name("block")])
	_check(settings.key_name("attack", false) == key, "rebinding still names the key (%s)" % key)
	var touch: bool = settings.touch_enabled()
	if not touch:
		_check(hud.attack_key.text == "X", "the HUD follows at once (%s)" % hud.attack_key.text)
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 0.1
	var keyboard := InputEventKey.new()
	keyboard.physical_keycode = KEY_J
	keyboard.pressed = true
	await _press(keyboard)
	_check(not settings.using_pad and settings.key_name("attack") == key, "a key press switches back (%s)" % settings.key_name("attack"))
	await _press(stick)
	_check(not settings.using_pad, "a resting stick's drift is not a switch")
	if not touch:
		_check(hud.attack_key.text == key, "  and the HUD with it")
	hud.queue_free()
	await process_frame
	print("PAD PROMPT TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
