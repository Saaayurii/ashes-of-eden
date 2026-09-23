extends Node
## Game feel: hit-stop and screen shake. Cheap, and the difference between
## "rectangles" and "rectangles that feel good to hit".

var _shake := 0.0


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
