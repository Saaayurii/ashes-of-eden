extends Node2D
class_name LiquidSurface
## The living top of a pool (Hazard): a row of springs every COLUMN px that a
## body, a blade or a bolt pushes down, the push spreading to the neighbours and
## dying away, over a slow resting swell. Draws the body under it with
## liquid.gdshader and a 1-px rim of foam on top. Cosmetic and local on every
## peer: each one sees the same bodies move through it.
## The studio's «Жидкости» preview ports this: change one, change the other.

const SHADER := preload("res://assets/shaders/liquid.gdshader")
const COLUMN := 4.0
## Spread passes per physics frame: more = waves run further, faster.
const PASSES := 3
## No spring goes further than this from rest, whatever lands in it.
const MAX_OFFSET := 9.0

var size := Vector2(100, 30)
var spec: Dictionary = {}
var painted := false
var _heights := PackedFloat32Array()
var _speeds := PackedFloat32Array()
var _time := 0.0
var _rim := Color.WHITE
var _material: ShaderMaterial
## The foam rim draws itself as a child: the pool's shader must not tint it.
var _rim_line: Node2D
var _rim_points := PackedVector2Array()
## How much is still moving, 0..1, for the shader's glints and for Hazard.
var energy := 0.0


func setup(pool_size: Vector2, kind_spec: Dictionary, is_painted: bool) -> void:
	size = pool_size
	spec = kind_spec
	painted = is_painted
	var columns := int(ceil(size.x / COLUMN)) + 1
	_heights.resize(columns)
	_speeds.resize(columns)
	_heights.fill(0.0)
	_speeds.fill(0.0)
	var colors: Dictionary = spec.get("colors", {})
	_rim = Color(str(colors.get("foam", "#ffffff")))
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("surface_color", Color(str(colors.get("surface", "#a9d2ec"))))
	_material.set_shader_parameter("body_color", Color(str(colors.get("body", "#20425e"))))
	_material.set_shader_parameter("deep_color", Color(str(colors.get("deep", "#0a1826"))))
	_material.set_shader_parameter("glow_color", Color(str(colors.get("glow", colors.get("surface", "#ffffff")))))
	_material.set_shader_parameter("pool", size)
	_material.set_shader_parameter("opacity", float(spec.get("painted_opacity" if painted else "opacity", 0.6)))
	_material.set_shader_parameter("flow", float(spec.get("flow", 0.0)))
	_material.set_shader_parameter("shimmer", float(spec.get("shimmer", 0.0)))
	_material.set_shader_parameter("molten", 1.0 if bool(spec.get("burns", false)) else 0.0)
	var texture := _texture(str(spec.get("texture", "")))
	_material.set_shader_parameter("has_texture", texture != null)
	if texture != null:
		_material.set_shader_parameter("body_texture", texture)
	material = _material
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	if _rim_line == null:
		_rim_line = Node2D.new()
		_rim_line.name = "Rim"
		_rim_line.draw.connect(_draw_rim)
		add_child(_rim_line)
	_apply_settings()


## The body textures are made by tools/art/make_liquids.py; a checkout that has
## not imported them yet reads the PNG itself, and a missing one is a plain pool.
static func _texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if FileAccess.file_exists(path):
		var picture := Image.load_from_file(path)
		if not picture.is_empty():
			return ImageTexture.create_from_image(picture)
	return null


func _apply_settings() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("motion", 1.0 if Settings.backdrop_motion else 0.0)
	_material.set_shader_parameter("light_scale", Settings.flash_scale())


## A push at [param x] (local px): positive sinks the surface there, the
## springs carry it outwards. [param width] spreads it over several columns.
func disturb(x: float, force: float, width := 8.0) -> void:
	if _heights.is_empty():
		return
	var scale := float(spec.get("waves", {}).get("splash", 1.0))
	var centre := x / COLUMN
	var reach := maxf(1.0, width / COLUMN)
	for i in range(maxi(0, int(centre - reach)), mini(_heights.size(), int(centre + reach) + 1)):
		var fall := 1.0 - absf(float(i) - centre) / (reach + 1.0)
		_speeds[i] += force * scale * maxf(fall, 0.0)


## The surface's height at local [param x], px below the pool's top (negative = above).
func height_at(x: float) -> float:
	if _heights.is_empty():
		return 0.0
	var i := clampi(int(round(x / COLUMN)), 0, _heights.size() - 1)
	return _heights[i] + _swell(float(i) * COLUMN)


func _swell(x: float) -> float:
	if not Settings.backdrop_motion:
		return 0.0
	var waves: Dictionary = spec.get("waves", {})
	var length := maxf(8.0, float(waves.get("length", 50.0)))
	var amp := float(waves.get("amplitude", 1.0))
	var speed := float(waves.get("speed", 1.0))
	return amp * (sin(x / length * TAU + _time * speed) * 0.7 + sin(x / (length * 0.37) * TAU - _time * speed * 1.6) * 0.3)


func _physics_process(delta: float) -> void:
	_time += delta
	var waves: Dictionary = spec.get("waves", {})
	var k := float(waves.get("spring", 0.02))
	var damping := float(waves.get("damping", 0.03))
	var spread := float(waves.get("spread", 0.25))
	var n := _heights.size()
	var moving := 0.0
	for i in n:
		_speeds[i] += -k * _heights[i] - damping * _speeds[i]
		_heights[i] = clampf(_heights[i] + _speeds[i], -MAX_OFFSET, MAX_OFFSET)
		moving += absf(_speeds[i]) + absf(_heights[i]) * 0.2
	for _pass in PASSES:
		for i in n:
			if i > 0:
				var left := spread * (_heights[i] - _heights[i - 1])
				_speeds[i - 1] += left
			if i < n - 1:
				var right := spread * (_heights[i] - _heights[i + 1])
				_speeds[i + 1] += right
	energy = clampf(moving / maxf(1.0, n * 0.4), 0.0, 1.0)
	if _material != null:
		_material.set_shader_parameter("stir", energy)
	queue_redraw()


func _draw() -> void:
	var n := _heights.size()
	if n < 2:
		return
	var top := -MAX_OFFSET - 4.0  # the highest the surface may stand, for the UVs
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	_rim_points.clear()
	for i in n:
		var x := minf(float(i) * COLUMN, size.x)
		var y := roundf(_heights[i] + _swell(x))
		points.append(Vector2(x, y))
		uvs.append(Vector2(x / size.x, (y - top) / (size.y - top)))
		_rim_points.append(Vector2(x, y))
	points.append(Vector2(size.x, size.y))
	uvs.append(Vector2(1.0, 1.0))
	points.append(Vector2(0.0, size.y))
	uvs.append(Vector2(0.0, 1.0))
	draw_polygon(points, PackedColorArray([Color.WHITE]), uvs)
	if _rim_line != null:
		_rim_line.queue_redraw()


## A 1-px line of foam on the surface: it is what catches the eye.
func _draw_rim() -> void:
	if _rim_points.size() > 1:
		_rim_line.draw_polyline(_rim_points, Color(_rim, 0.5 if painted else 0.85), 1.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_READY and Settings.has_signal("changed"):
		Settings.changed.connect(_apply_settings)
