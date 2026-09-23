extends Node2D
## Fire/lantern glow: random-walk brightness and a little breathing in scale.
## Attach to an additive Sprite2D with a radial gradient texture.

@export var base_alpha := 0.55
@export var variation := 0.25
@export var speed := 9.0

var _target := 1.0
var _current := 1.0
var _base_scale := Vector2.ONE


func _ready() -> void:
	_base_scale = scale


func _process(delta: float) -> void:
	if randf() < delta * speed:
		_target = 1.0 + randf_range(-variation, variation)
	_current = lerpf(_current, _target, minf(1.0, delta * 12.0))
	modulate.a = base_alpha * _current
	scale = _base_scale * (0.92 + 0.08 * _current)
