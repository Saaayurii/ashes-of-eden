extends Sprite2D
class_name RoomFixture
## Scenery that answers the room it stands in. One strip, one reaction when the
## last enemy dies: the shrine lights up ([member lights]), the arena barrier
## stops humming and fades ([member falls]).

@export var fps := 8.0
## Play the strip as an idle loop until the room is cleared (the barrier hums).
@export var loop := false
## Play the strip once, from dark to lit, and keep the last frame.
@export var lights := false
## Fade out instead: the thing was holding the player in.
@export var falls := false
## The candles at its base; the whole thing glows once it has lit up.
@export var light_color := Color(1.0, 0.85, 0.55)

var _time := 0.0
var _done := false
var _light: GlowLight


func _ready() -> void:
	frame = 0
	set_process(loop)
	if lights:
		_light = Fx.light(self, Vector2(0, -22), light_color, 70.0, 0.25, 0.25)
	var node := get_parent()
	while node != null and not (node is Room):
		node = node.get_parent()
	if node is Room:
		(node as Room).cleared.connect(_on_cleared)


func _process(delta: float) -> void:
	_time += delta
	frame = int(_time * fps) % maxi(1, hframes)


func _on_cleared() -> void:
	if _done:
		return
	_done = true
	if falls:
		set_process(false)
		Fx.puff(global_position + Vector2(0, -20), 1.2, Color(0.6, 0.75, 1.0))
		create_tween().tween_property(self, "modulate:a", 0.0, 0.7)
		return
	if not lights:
		return
	if _light != null:
		create_tween().tween_method(_light.set_base_energy, 0.25, 1.0, hframes / fps)
		Fx.sparkle(global_position + Vector2(0, -8), light_color, 20, 16.0)
	for index in range(1, hframes):
		await get_tree().create_timer(1.0 / fps).timeout
		if not is_inside_tree():
			return
		frame = index
