extends Node2D
## The main menu's sky lives (scenes/ui/main_menu.tscn, under Layers, so in
## painting pixels): clouds drift over the painted ones (sky_drift.gdshader),
## shafts of light turn and breathe under the cross (god_rays.gdshader), now
## and then a far stroke of lightning lights the clouds and the painting
## (BackdropLife.react, the menu holds its picture like a room does), and
## crows cross the sky. Settings → Moving backdrops stops the clock the
## shaders run on; the light they change follows Settings.flash_scale(); the
## lightning rests with Settings.lighting off, like the painting's own life.

## The materials this sky drives (they read `clock`, `light`, and `flash`).
@export var clouds: CanvasItem
@export var rays: CanvasItem
## Seconds between lightning strokes, and how bright one is (life_flash).
const LIGHTNING_EVERY := Vector2(14.0, 28.0)
const LIGHTNING := 0.7
## Seconds between flocks; the first comes soon after the menu opens.
const CROWS_EVERY := Vector2(16.0, 30.0)
const FIRST_CROWS := 2.5
## Where crows fly, painting pixels, and how fast.
const CROW_BAND := Vector2(36.0, 120.0)
const CROW_SPEED := Vector2(16.0, 24.0)
const CROW_COLOR := Color(0.07, 0.06, 0.07, 0.95)
## A crow is five pixels wide: wings up, level, down (offsets from its middle).
const WINGS := [
	[Vector2i(-2, -1), Vector2i(2, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)],
	[Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1)],
	[Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(-2, 1), Vector2i(2, 1)],
]
const PAINTING_WIDTH := 640.0

var clock := 0.0
var _next_lightning := 0.0
var _strokes: Array[float] = []
var _next_crows := FIRST_CROWS
## {position, velocity, phase}
var _crows: Array[Dictionary] = []


func _ready() -> void:
	_next_lightning = randf_range(4.0, 9.0)


func _process(delta: float) -> void:
	if Settings.backdrop_motion:
		clock += delta
	var light := Settings.flash_scale()
	var flash := _lightning(delta)
	for item in [clouds, rays]:
		var material := (item as CanvasItem).material as ShaderMaterial if item != null else null
		if material != null:
			material.set_shader_parameter("clock", clock)
			material.set_shader_parameter("light", light)
	if clouds != null and clouds.material is ShaderMaterial:
		(clouds.material as ShaderMaterial).set_shader_parameter("flash", flash)
	BackdropLife.react(owner, {"flash": flash})
	_fly(delta)
	queue_redraw()


## The brightness of the lightning now: a stroke flickers twice and fades.
func _lightning(delta: float) -> float:
	_next_lightning -= delta
	if _next_lightning <= 0.0:
		_next_lightning = randf_range(LIGHTNING_EVERY.x, LIGHTNING_EVERY.y)
		if Settings.lighting:
			var now := Time.get_ticks_msec() / 1000.0
			_strokes = [now, now + randf_range(0.12, 0.2)]
			if randf() < 0.5:
				_strokes.append(now + randf_range(0.35, 0.5))
			get_tree().create_timer(randf_range(0.8, 2.0)).timeout.connect(func() -> void: Audio.play(&"thunder", -16.0))
	if _strokes.is_empty():
		return 0.0
	var at := Time.get_ticks_msec() / 1000.0
	var flash := 0.0
	for start in _strokes:
		if at >= start:
			flash = maxf(flash, exp(-(at - start) * 7.0))
	if at - _strokes.back() > 1.5:
		_strokes.clear()
	return flash * LIGHTNING


func _fly(delta: float) -> void:
	_next_crows -= delta
	if _next_crows <= 0.0:
		_next_crows = randf_range(CROWS_EVERY.x, CROWS_EVERY.y)
		_flock()
	for crow in _crows:
		crow.position += crow.velocity * delta
		crow.phase += delta
	_crows = _crows.filter(func(crow: Dictionary) -> bool: return crow.position.x > -20.0 and crow.position.x < PAINTING_WIDTH + 20.0)


## Two to five crows from one side, loosely together.
func _flock() -> void:
	var leftwards := randf() < 0.6
	var start := Vector2(PAINTING_WIDTH + 12.0 if leftwards else -12.0, randf_range(CROW_BAND.x, CROW_BAND.y))
	var speed := randf_range(CROW_SPEED.x, CROW_SPEED.y)
	for i in randi_range(2, 5):
		var offset := Vector2(i * randf_range(7.0, 14.0) * (1.0 if leftwards else -1.0), randf_range(-8.0, 8.0))
		_crows.append({
			"position": start + offset,
			"velocity": Vector2(-speed if leftwards else speed, randf_range(-1.5, 1.5)) * randf_range(0.9, 1.1),
			"phase": randf() * 10.0,
		})


func _draw() -> void:
	for crow in _crows:
		var phase: float = crow.phase
		# beats of the wings, then a glide on level wings
		var gliding := sin(phase * 0.9) < -0.4
		var wings: Array = WINGS[1] if gliding else WINGS[[0, 1, 2, 1][int(phase * 10.0) % 4]]
		var at := Vector2i((crow.position as Vector2 + Vector2(0.0, sin(phase * 2.0) * 1.5)).round())
		for pixel: Vector2i in wings:
			draw_rect(Rect2(Vector2(at + pixel), Vector2.ONE), CROW_COLOR)
