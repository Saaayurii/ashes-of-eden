extends SceneTree
## Accessibility (Settings.text_size / flashes):
##   - a larger text size grows the story text, the hints and the toasts;
##   - reduced flashes dim a flash of light, the white of a blow and the red
##     at the screen's edge, and full puts them back;
##   - the settings menu offers both, and they are saved;
##   - vibration (phones and gamepads) follows a blow's weight and its switch.
## Puts the settings back as it found them, through their setters.
##   godot --headless --path . -s scripts/tools/accessibility_test.gd

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


func _run() -> void:
	var settings = root.get_node("Settings")
	var was_size: String = settings.text_size
	var was_flashes: String = settings.flashes

	settings.set_text_size("normal")
	var normal: float = settings.text_scale()
	settings.set_text_size("largest")
	_check(absf(settings.text_scale() / normal - 1.5) < 0.001, "the largest text is half again as big")
	var hints = load("res://scripts/ui/move_hints.gd").new()
	root.add_child(hints)
	var toast = load("res://scripts/ui/deed_toast.gd").new()
	root.add_child(toast)
	await process_frame
	_check(hints.get_theme_font_size("font_size") >= int(9 * 1.5), "the move hints grow with it")
	_check(toast.get_theme_font_size("font_size") >= int(10 * 1.5), "and the toasts")
	hints.queue_free()
	toast.queue_free()
	var box = load("res://scenes/ui/dialogue_box.tscn").instantiate()
	root.add_child(box)
	await process_frame
	var caption_size: int = box.caption.get_theme_font_size("font_size")
	box.queue_free()
	settings.set_text_size("normal")
	box = load("res://scenes/ui/dialogue_box.tscn").instantiate()
	root.add_child(box)
	await process_frame
	_check(caption_size > box.caption.get_theme_font_size("font_size"), "and the captions")
	box.queue_free()

	# --- flashes -------------------------------------------------------------
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.8)
	var run = current_scene
	var fx = root.get_node("Fx")
	var energy := func() -> float:
		fx.flash(Vector2(100, 100), Color.WHITE, 60.0, 0.5, 1.0)
		var last = run.get_child(run.get_child_count() - 1)
		return float(last.get("energy")) if last.get("energy") != null else -1.0
	settings.set_flashes("full")
	var full: float = energy.call()
	settings.set_flashes("reduced")
	var reduced: float = energy.call()
	_check(full > 0.0 and reduced > 0.0 and reduced < full * 0.5, "a flash of light is dimmed (%.2f → %.2f)" % [full, reduced])
	var enemy = run._spawn_enemy("possessed_villager", Vector2(600, 100), true)
	await _settle(0.2)
	enemy.take_damage(1.0)
	_check(enemy.visual.modulate.r < 2.0, "the white of a blow is dimmed (%.2f)" % enemy.visual.modulate.r)
	var screen = run.get_node("UI").find_child("ScreenFx", true, false)
	if screen == null:
		for child in run.get_node("UI").get_children():
			if child.get_script() != null and str(child.get_script().resource_path).ends_with("screen_fx.gd"):
				screen = child
	_check(screen != null, "the screen's own effects are there")
	if screen != null:
		screen._hit = 0.0
		root.get_node("EventBus").player_hurt.emit(0.5)
		await process_frame
		await process_frame
		var dim: float = screen._material.get_shader_parameter("strength")
		settings.set_flashes("full")
		screen._hit = 0.0
		root.get_node("EventBus").player_hurt.emit(0.5)
		await process_frame
		await process_frame
		var bright: float = screen._material.get_shader_parameter("strength")
		_check(dim > 0.0 and dim < bright, "the red at the edge is dimmed (%.2f < %.2f)" % [dim, bright])

	var menu = run.get_node("UI/PauseMenu/Settings")
	menu._refresh()
	_check(menu.find_child("TextSizeRow", true, false) != null and menu.find_child("FlashesRow", true, false) != null,
		"the settings offer both")
	var cfg := ConfigFile.new()
	settings.set_flashes("reduced")
	cfg.load("user://settings.cfg")
	_check(cfg.get_value("access", "flashes", "") == "reduced", "and keep them")

	# vibration: a blow taken buzzes the phone and the pads, the switch stops it
	var juice = root.get_node("Juice")
	var was_vibration: bool = settings.vibration
	settings.set_vibration(true)
	juice.last_buzz = {}
	root.get_node("EventBus").player_hurt.emit(0.25)
	_check(int(juice.last_buzz.get("ms", 0)) > 0, "a blow taken buzzes (%s)" % juice.last_buzz)
	var small: float = float(juice.last_buzz.get("strength", 0.0))
	juice.last_buzz = {}
	root.get_node("EventBus").player_hurt.emit(0.05)
	_check(float(juice.last_buzz.get("strength", 1.0)) < small, "  a smaller one, softer")
	settings.set_vibration(false)
	juice.last_buzz = {}
	root.get_node("EventBus").player_hurt.emit(0.25)
	_check(juice.last_buzz.is_empty(), "  and the switch in Settings stops it")
	settings.set_vibration(was_vibration)

	# damage numbers: off means the figure is not drawn at all
	var was_numbers: bool = settings.damage_numbers
	var labels := func() -> int:
		return current_scene.get_children().filter(func(n: Node) -> bool: return n is Label).size() if current_scene else 0
	settings.set_damage_numbers(true)
	var before: int = labels.call()
	fx.damage_number(Vector2(100, 100), 12.0)
	_check(labels.call() == before + 1, "a damage number is drawn")
	settings.set_damage_numbers(false)
	before = labels.call()
	fx.damage_number(Vector2(100, 100), 12.0)
	_check(labels.call() == before, "  and not with Damage numbers off")
	settings.set_damage_numbers(was_numbers)

	settings.set_text_size(was_size)
	settings.set_flashes(was_flashes)
	current_scene = null
	run.queue_free()
	await _settle(0.2)
	print("ACCESSIBILITY TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
