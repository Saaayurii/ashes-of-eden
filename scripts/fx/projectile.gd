extends Area2D
class_name Projectile
## A slow, readable bolt. Hurts the player, dies on walls, times out.

var damage := 10.0
var speed := 170.0
var direction := Vector2.RIGHT
## Flight geometry is chosen by the attack data, independently of the sprite.
## wave: lateral sway; accelerate: gathers speed; arc: bends toward the floor;
## surge: hangs briefly before rushing; return: turns back if the first pass misses.
var motion := "straight"
var motion_amount := 0.0
var tint := Color(1, 0.85, 0.5)
## The look, a key of data/projectiles.json (STYLES); set by the firing actor.
var visual_style := ""
## The attack's own size on top of the style's (projectile_scale in its data).
var size := 1.0
## The enemy id of whoever loosed it, so a death by it is blamed on them.
var shooter_id := ""
const STYLES_PATH := "res://data/projectiles.json"
## Every key a style may leave out, at the value a plain bolt has.
const LOOK := {"frames": 1, "fps": 10.0, "scale": 0.62, "light": 20.0, "trail": 8, "shader": 0,
	"pulse": 0.07, "breathe": [0.0, 0.0], "squash": [1.0, 0.0, 0.0], "bob": [0.7, 20.0], "wiggle": [0.0, 0.0], "spin": 0.0}
const ECHO := {"offset": 9.0, "sway": [3.0, 15.0], "scale": 0.45, "spin": 0.0, "color": "#ffffff", "alpha": -1.0}
const BURST := [{"fx": "sparkle", "color": "#ffe8a1", "count": 11, "size": 6}]
## How hard a homing bolt looks for its quarry, in px.
const HOME_REACH := 420.0
static var _styles: Dictionary = {}
static var _sheets: Dictionary = {}
var _look: Dictionary = {}
var _echo: Dictionary = {}
## A client's copy of a bolt the host already fired: it flies and bursts on
## walls, but only the host's bolt is allowed to hurt anyone.
var cosmetic := false
## Thrown by the player rather than at them: it bites enemies and breakables,
## and the walls still stop it.
var friendly := false
var _life := 4.0
var _reflected := false
var _flight_clock := 0.0
var _lateral_offset := 0.0
var _turned_back := false


func _ready() -> void:
	if visual_style.is_empty():
		visual_style = "blade" if friendly else "sacred"
	# Shader uniforms must belong to this bolt, never to every bolt sharing the scene.
	$Art.material = $Art.material.duplicate()
	$Echo.material = $Art.material.duplicate()
	_set_art()
	Fx.light(self, Vector2.ZERO, tint, float(_look.light) * sqrt(size), 0.26, 0.0, 0.2)
	Fx.trail(self, tint, int(_look.trail), 0.25)
	if friendly:
		collision_mask = 1 | 4  # walls and enemies (layer 3)
	elif cosmetic:
		collision_mask = 1  # walls only
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_advance_motion(delta)
	_life -= delta
	_animate_art()
	if _life <= 0.0:
		_burst()


func _advance_motion(delta: float) -> void:
	_flight_clock += delta
	var travel := speed * delta
	match motion:
		"accelerate":
			travel *= 1.0 + minf(_flight_clock, 2.0) * motion_amount
		"surge":
			# The preacher's psalm appears to hang in the air before it rushes.
			travel *= 0.2 + 1.5 * clampf((_flight_clock - motion_amount) / 0.45, 0.0, 1.0)
		"arc":
			position.y += motion_amount * _flight_clock * delta
		"wave":
			var lateral := sin(_flight_clock * 9.0) * motion_amount
			position += direction.orthogonal() * (lateral - _lateral_offset)
			_lateral_offset = lateral
		"home":
			# turns toward its quarry at motion_amount radians a second
			var quarry := _quarry()
			if quarry != null:
				var want := (quarry.global_position + Vector2(0, -12) - global_position).angle()
				var turn := clampf(wrapf(want - direction.angle(), -PI, PI), -motion_amount * delta, motion_amount * delta)
				direction = direction.rotated(turn)
		"return":
			if not _turned_back and _flight_clock >= motion_amount:
				_turned_back = true
				direction = -direction
				speed *= 1.2
				travel = speed * delta
	position += direction * travel


func _quarry() -> Node2D:
	var best: Node2D = null
	var near := HOME_REACH
	for node in get_tree().get_nodes_in_group("enemies" if friendly else "player"):
		var body := node as Node2D
		if body == null or (body.has_method("is_dead") and body.call("is_dead")):
			continue
		var d := body.global_position.distance_to(global_position)
		if d < near:
			near = d
			best = body
	return best


func _on_body_entered(body: Node) -> void:
	if friendly:
		if not (body is Player) and body.has_method("take_damage"):
			body.take_damage(damage, self, {"knockback": 0.8})
	elif body is Player and not cosmetic:
		body.take_damage(damage, self)
		if _reflected:
			return  # the player's parry turned it round (reflect): it flies on
	_burst()


## Sent back by a parry: the bolt is the player's now, faster and heavier, and
## it goes home the way it came. The host's bolt is the real one; a client's
## cosmetic copy simply dies on the blade.
func reflect(_by: Node2D) -> void:
	if cosmetic:
		return
	_reflected = true
	friendly = true
	direction = -direction
	motion = "straight"
	_lateral_offset = 0.0
	_turned_back = false
	speed *= 1.35
	damage *= 1.5
	_life = 4.0
	collision_mask = 1 | 4  # walls and enemies (layer 3)
	tint = Color(0.8, 0.92, 1.0)
	visual_style = "sacred"
	_set_art()


## The style's look: data/projectiles.json, read once, every missing key at LOOK's value.
static func style(key: String) -> Dictionary:
	if _styles.is_empty() and FileAccess.file_exists(STYLES_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(STYLES_PATH))
		if parsed is Dictionary:
			_styles = parsed.get("styles", {})
	var raw: Dictionary = _styles.get(key, _styles.get("sacred", {}))
	var look := LOOK.duplicate()
	look.merge(raw, true)
	return look


static func has_style(key: String) -> bool:
	style(key)
	return _styles.has(key)


static func sheet(path: String) -> Texture2D:
	if not _sheets.has(path):
		_sheets[path] = load(path) if ResourceLoader.exists(path) else null
	return _sheets[path]


func _set_art() -> void:
	_look = style(visual_style)
	_echo = ECHO.duplicate()
	_echo.merge(_look.get("echo", {}), true)
	var painted := sheet(str(_look.get("sheet", "")))
	$Art.texture = painted
	$Echo.texture = painted
	var frames := maxi(1, int(_look.frames))
	$Art.hframes = frames
	$Echo.hframes = frames
	$Art.frame = 0
	$Echo.frame = 0
	$Art.rotation = direction.angle()
	$Echo.rotation = direction.angle()
	$Art.scale = Vector2.ONE * _base_scale()
	$Echo.scale = Vector2.ONE * _base_scale() * 0.55
	$Echo.modulate = Color(1, 1, 1, 0.36)
	$Art.material.set_shader_parameter("motion_kind", int(_look.shader))
	$Echo.material.set_shader_parameter("motion_kind", int(_look.shader))
	$Art.material.set_shader_parameter("use_frames", frames > 1)
	$Echo.material.set_shader_parameter("use_frames", frames > 1)


func _base_scale() -> float:
	return float(_look.scale) * size


func _animate_art() -> void:
	var t := _flight_clock
	var frames := int(_look.frames)
	if frames > 1:
		var frame_index := int(floor(t * float(_look.fps))) % frames
		$Art.frame = frame_index
		$Echo.frame = (frame_index + frames - 1) % frames
	var pulse := sin(t * 17.0)
	var base_angle := direction.angle()
	var scale_base := _base_scale()
	var breathe: Array = _look.breathe
	var squash: Array = _look.squash
	var bob: Array = _look.bob
	var wiggle: Array = _look.wiggle
	$Art.material.set_shader_parameter("phase", t)
	$Echo.material.set_shader_parameter("phase", t + 0.32)
	$Art.scale = Vector2.ONE * scale_base * (1.0 + float(_look.pulse) * pulse) * (1.0 + float(breathe[0]) * sin(t * float(breathe[1])))
	$Art.scale.y *= float(squash[0]) + float(squash[1]) * sin(t * float(squash[2]))
	$Art.position = Vector2(0, sin(t * float(bob[1])) * float(bob[0])).rotated(base_angle)
	$Art.rotation = base_angle + float(wiggle[0]) * sin(t * float(wiggle[1])) + float(_look.spin) * t
	var sway: Array = _echo.sway
	$Echo.visible = true
	var tint_echo := Color(str(_echo.color))
	tint_echo.a = float(_echo.alpha) if float(_echo.alpha) >= 0.0 else 0.20 + 0.12 * (1.0 + pulse) * 0.5
	$Echo.modulate = tint_echo
	$Echo.position = Vector2(-float(_echo.offset), sin(t * float(sway[1])) * float(sway[0])).rotated(base_angle)
	$Echo.rotation = base_angle + float(_echo.spin) * t
	$Echo.scale = Vector2.ONE * scale_base * (float(_echo.scale) + 0.1 * pulse)


func _burst() -> void:
	for part: Dictionary in _look.get("burst", BURST):
		var color := Color(str(part.get("color", "#ffe8a1")))
		var count := int(part.get("count", 10))
		match str(part.get("fx", "sparkle")):
			"spark":
				Fx.hit(global_position, "spark", 0.55, direction.x < 0.0)
				Fx.impact(global_position, direction, color, count)
			"debris":
				Fx.debris(global_position, color, count)
			"ash":
				Fx.ash(global_position, color, count, float(part.get("spread", 37.0)), float(part.get("size", 4.0)))
			_:
				Fx.sparkle(global_position, color, count, float(part.get("size", 6.0)))
	Fx.flash(global_position, tint, 42.0 * sqrt(size), 0.22)
	queue_free()
