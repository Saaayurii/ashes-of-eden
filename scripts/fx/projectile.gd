extends Area2D
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
## blade, sacred, umbral or wraith; set by the firing actor.
var visual_style := ""
const ART := {
	"blade": preload("res://assets/sprites/projectiles/blade_wave_v2.png"),
	"sacred": preload("res://assets/sprites/projectiles/sacred_bolt_v2.png"),
	"umbral": preload("res://assets/sprites/projectiles/umbral_bolt_v2.png"),
	"wraith": preload("res://assets/sprites/projectiles/wraith_flight_v3.png"),
	"zealot": preload("res://assets/sprites/projectiles/zealot_flight_v3.png"),
	"acolyte": preload("res://assets/sprites/projectiles/acolyte_flight_v3.png"),
	"preacher": preload("res://assets/sprites/projectiles/preacher_flight_v3.png"),
	"cult": preload("res://assets/sprites/projectiles/cult_flight_v3.png"),
	"ash": preload("res://assets/sprites/projectiles/ash_flight_v3.png"),
	"ophanim": preload("res://assets/sprites/projectiles/ophanim_flight_v3.png"),
}
const FLIGHT_FPS := {
	"wraith": 12.0, "zealot": 11.0, "acolyte": 13.0,
	"preacher": 9.0, "cult": 11.0, "ash": 12.0, "ophanim": 10.0,
}
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
	Fx.light(self, Vector2.ZERO, tint, 20.0 if visual_style != "ophanim" else 29.0, 0.26, 0.0, 0.2)
	Fx.trail(self, tint, 6 if visual_style in ["ash", "cult"] else 8, 0.25)
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
		"return":
			if not _turned_back and _flight_clock >= motion_amount:
				_turned_back = true
				direction = -direction
				speed *= 1.2
				travel = speed * delta
	position += direction * travel


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


func _set_art() -> void:
	var painted: Texture2D = ART.get(visual_style, ART["sacred"])
	$Art.texture = painted
	$Echo.texture = painted
	var animated := FLIGHT_FPS.has(visual_style)
	$Art.hframes = 4 if animated else 1
	$Echo.hframes = 4 if animated else 1
	$Art.frame = 0
	$Echo.frame = 0
	$Art.rotation = direction.angle()
	$Echo.rotation = direction.angle()
	var art_scale := 0.76 if visual_style == "blade" else 0.62
	if visual_style == "ophanim":
		art_scale = 0.48
	$Art.scale = Vector2.ONE * art_scale
	$Echo.scale = Vector2.ONE * art_scale * 0.55
	$Echo.modulate = Color(1, 1, 1, 0.36)
	$Art.material.set_shader_parameter("motion_kind", _motion_kind())
	$Echo.material.set_shader_parameter("motion_kind", _motion_kind())
	$Art.material.set_shader_parameter("use_frames", animated)
	$Echo.material.set_shader_parameter("use_frames", animated)


func _motion_kind() -> int:
	match visual_style:
		"wraith", "cult", "umbral": return 2
		"ash": return 3
		"ophanim": return 4
		"preacher", "acolyte", "zealot", "sacred": return 1
		_: return 0


func _animate_art() -> void:
	var t := _flight_clock
	if FLIGHT_FPS.has(visual_style):
		var frame_index := int(floor(t * float(FLIGHT_FPS[visual_style]))) % 4
		$Art.frame = frame_index
		$Echo.frame = (frame_index + 3) % 4
	var pulse := sin(t * 17.0)
	var base_angle := direction.angle()
	var scale_base := 0.76 if visual_style == "blade" else (0.48 if visual_style == "ophanim" else 0.62)
	$Art.material.set_shader_parameter("phase", t)
	$Echo.material.set_shader_parameter("phase", t + 0.32)
	$Art.scale = Vector2.ONE * scale_base * (1.0 + 0.07 * pulse)
	$Art.position = Vector2(0, sin(t * 20.0) * 0.7).rotated(base_angle)
	$Art.rotation = base_angle
	$Echo.visible = true
	$Echo.modulate.a = 0.20 + 0.12 * (1.0 + pulse) * 0.5
	$Echo.position = Vector2(-9.0, sin(t * 15.0) * 3.0).rotated(base_angle)
	$Echo.rotation = base_angle
	$Echo.scale = Vector2.ONE * scale_base * (0.45 + 0.1 * pulse)
	match visual_style:
		"zealot":
			$Art.position = Vector2(0, sin(t * 19.0) * 2.0).rotated(base_angle)
			$Echo.position = Vector2(-7.0, -sin(t * 19.0) * 4.0).rotated(base_angle)
			$Echo.modulate = Color(1.0, 0.86, 0.46, 0.36)
		"acolyte":
			$Art.scale.y *= 0.78
			$Echo.position = Vector2(-11.0, sin(t * 28.0) * 2.0).rotated(base_angle)
			$Echo.modulate = Color(1.0, 0.9, 0.65, 0.20 + 0.15 * absf(pulse))
		"preacher":
			$Art.scale *= 1.0 + 0.16 * sin(t * 11.0)
			$Echo.scale *= 1.25
			$Echo.modulate = Color(1.0, 0.94, 0.75, 0.27)
		"cult":
			$Art.rotation = base_angle + sin(t * 16.0) * 0.12
			$Echo.position = Vector2(-7.0, sin(t * 22.0) * 4.5).rotated(base_angle)
			$Echo.modulate = Color(0.72, 0.38, 1.0, 0.34)
		"ash":
			$Art.position = Vector2(0, sin(t * 37.0) * 0.8).rotated(base_angle)
			$Echo.position = Vector2(-12.0, sin(t * 20.0) * 2.0).rotated(base_angle)
			$Echo.modulate = Color(1.0, 0.24, 0.08, 0.32)
		"ophanim":
			$Art.rotation = base_angle + t * 9.0
			$Art.position = Vector2.ZERO
			$Echo.rotation = base_angle - t * 6.0
			$Echo.position = Vector2.ZERO
			$Echo.scale = Vector2.ONE * scale_base * (0.70 + 0.08 * pulse)
			$Echo.modulate = Color(0.53, 0.78, 1.0, 0.38)
		"wraith":
			$Art.scale.y *= 1.0 + 0.16 * sin(t * 13.0)
			$Echo.position = Vector2(-8.0, sin(t * 25.0) * 4.0).rotated(base_angle)
			$Echo.modulate = Color(0.28, 1.0, 0.72, 0.3)


func _burst() -> void:
	match visual_style:
		"blade":
			Fx.hit(global_position, "spark", 0.55, direction.x < 0.0)
			Fx.impact(global_position, direction, Color(1.0, 0.9, 0.68), 9)
		"umbral", "cult":
			Fx.debris(global_position, Color(0.58, 0.32, 0.8), 8)
			Fx.ash(global_position, Color(0.75, 0.37, 0.88), 7, 36.0, 4.0)
		"ash":
			Fx.debris(global_position, Color(0.9, 0.28, 0.12), 9)
			Fx.ash(global_position, Color(1.0, 0.4, 0.16), 8, 38.0, 4.0)
		"wraith":
			Fx.ash(global_position, Color(0.43, 0.95, 0.7), 10, 62.0, 5.0)
		"ophanim":
			Fx.sparkle(global_position, Color(0.72, 0.87, 1.0), 14, 7.0)
		_:
			Fx.sparkle(global_position, Color(1.0, 0.91, 0.63), 11, 6.0)
	Fx.flash(global_position, tint, 42.0, 0.22)
	queue_free()
