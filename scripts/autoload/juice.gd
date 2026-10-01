extends Node
## Game feel: hit-stop and screen shake. Cheap, and the difference between
## "rectangles" and "rectangles that feel good to hit".

var _shake := 0.0


func _ready() -> void:
	# The body feels what the eyes see: our own blows taken, a clean parry,
	# a boss going down. Only our own body emits player_hurt.
	EventBus.player_hurt.connect(func(fraction: float) -> void: buzz(int(clampf(40.0 + fraction * 400.0, 40.0, 160.0)), clampf(0.4 + fraction * 2.0, 0.4, 1.0)))
	EventBus.player_parried.connect(func() -> void: buzz(25, 0.6))
	EventBus.boss_died.connect(func() -> void: buzz(350, 1.0))
	EventBus.player_died.connect(func() -> void: buzz(260, 1.0))


## Freezes time for a moment. Ignored if a hit-stop is already running.
func hit_stop(duration := 0.05, scale := 0.05) -> void:
	if Engine.time_scale < 1.0:
		return
	Engine.time_scale = scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


func shake(strength := 3.0) -> void:
	if not Settings.screen_shake:
		return
	_shake = maxf(_shake, strength)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	if _shake > 0.0:
		camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
		_shake = maxf(0.0, _shake - 14.0 * delta)
	elif camera.offset != Vector2.ZERO:
		camera.offset = Vector2.ZERO


## A short vibration (Settings.vibration): the phone or tablet itself, and
## every connected gamepad's motors — the light one carries a small blow, the
## heavy one comes in as it grows. Nothing on a desktop without a pad.
## [member last_buzz] keeps the last one asked for, for tests (headless
## has no motors to ask).
var last_buzz := {}


func buzz(milliseconds: int, strength := 1.0) -> void:
	if not Settings.vibration:
		return
	strength = clampf(strength, 0.1, 1.0)
	last_buzz = {"ms": milliseconds, "strength": strength}
	if OS.has_feature("mobile") or OS.has_feature("web_android"):
		Input.vibrate_handheld(milliseconds, strength)
	for device in Input.get_connected_joypads():
		Input.start_joy_vibration(device, strength, clampf(strength * 1.6 - 0.6, 0.0, 1.0), milliseconds / 1000.0)
