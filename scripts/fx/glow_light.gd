extends PointLight2D
class_name GlowLight
## A light with a life of its own: a candle flickers, a relic breathes, a
## flash dies out. Every light in the game goes through here so the
## "Lighting" setting can switch them all off at once (the Web build on a weak
## GPU). Radius is in world pixels; the texture is one shared radial gradient.

const TEXTURE := preload("res://assets/fx/light_radial.tres")

@export var radius := 64.0:
	set(value):
		radius = value
		texture_scale = radius * 2.0 / TEXTURE.width
## Random-walk brightness, 0 = steady. 0.25 reads as a candle.
@export var flicker := 0.0
## Slow sine pulse of the energy, 0 = none.
@export var breathe := 0.0
@export var flicker_speed := 9.0

var _base_energy := 1.0
var _target := 1.0
var _current := 1.0
var _phase := randf() * TAU


func _ready() -> void:
	texture = TEXTURE
	shadow_enabled = false
	add_to_group("lights")
	_base_energy = energy
	texture_scale = radius * 2.0 / TEXTURE.width
	_apply_setting()
	EventBus.lighting_changed.connect(_apply_setting)
	set_process(flicker > 0.0 or breathe > 0.0)


func _process(delta: float) -> void:
	if flicker > 0.0 and randf() < delta * flicker_speed:
		_target = 1.0 + randf_range(-flicker, flicker)
	_current = lerpf(_current, _target, minf(1.0, delta * 12.0))
	_phase += delta * 2.2
	energy = _base_energy * _current * (1.0 + breathe * sin(_phase))


## Sets the resting brightness (flicker and breathing play around it).
func set_base_energy(value: float) -> void:
	_base_energy = value
	energy = value


func _apply_setting() -> void:
	enabled = Settings.lighting
