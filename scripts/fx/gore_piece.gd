extends Sprite2D
class_name GorePiece
## A piece of a torn body (Gore.tear): its own drawing, cut from the frame it
## died in. It flies, spins, bounces off the room's colliders, trails blood
## while the wound is fresh, marks where it lands, lies a while and fades.

const GRAVITY := 620.0
const BOUNCE := 0.32
const LIE := 14.0
const FADE := 1.2
const MAX_AIR := 5.0

var velocity := Vector2.ZERO
var spin := 0.0
var _layer: Gore
var _blood := Color.RED
var _stain := 1.0
var _stain_life := 20.0
var _bleed := 1.0
var _radius := 3.0
var _air := 0.0
var _resting := false
var _lain := 0.0
var _drip := 0.0


func setup(layer: Gore, launch: Vector2, turn: float, blood: Color, stain: float, stain_life: float,
		bleed: float, radius: float) -> void:
	_layer = layer
	velocity = launch
	spin = turn
	_blood = blood
	_stain = stain
	_stain_life = stain_life
	_bleed = bleed
	_radius = maxf(radius, 1.5)


func _ready() -> void:
	add_to_group("gore_piece")
	z_index = 1


func _physics_process(delta: float) -> void:
	if _bleed > 0.0:
		_bleed -= delta
		_drip -= delta
		if _drip <= 0.0 and is_instance_valid(_layer):
			_drip = 0.05 if not _resting else 0.22
			_layer.drop(global_position, Vector2(randf_range(-20, 20), randf_range(-30, 10)) - velocity * 0.1,
				_blood, _stain * 0.8, _stain_life)
	if _resting:
		_lain += delta
		if _lain > LIE:
			modulate.a = 1.0 - (_lain - LIE) / FADE
			if _lain > LIE + FADE:
				queue_free()
		return
	_air += delta
	if _air > MAX_AIR:  # it went down a pit
		queue_free()
		return
	velocity.y += GRAVITY * delta
	rotation += spin * delta
	var step := velocity * delta
	var reach := step + step.normalized() * _radius
	var mask := Gore.WORLD_MASK | (Gore.LEDGE_MASK if velocity.y > 0.0 else 0)
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + reach, mask)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position += step
		return
	var normal: Vector2 = hit.normal
	global_position = hit.position + normal * _radius
	if is_instance_valid(_layer):
		_layer.mark(hit.position, randf_range(2.0, 4.0) * _stain, absf(normal.x) > 0.6, _blood, _stain_life)
	if normal.y < -0.6:  # a floor
		velocity = Vector2(velocity.x * 0.55, -absf(velocity.y) * BOUNCE)
		spin *= 0.5
		if absf(velocity.y) < 40.0:
			velocity = Vector2.ZERO
			_resting = true
			# lie flat-ish on whichever side it fell
			rotation = snappedf(rotation, PI / 2.0)
	elif absf(normal.x) > 0.6:  # a wall
		velocity.x = -velocity.x * BOUNCE
		spin = -spin
	else:  # a ceiling
		velocity.y = absf(velocity.y) * BOUNCE
