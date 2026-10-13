extends Sprite2D
class_name GorePiece
## A piece of a torn body (Gore.tear): its own drawing, cut from the frame it
## died in. A piece that flies spins, bounces off the room's colliders, trails
## blood while the wound is fresh and marks where it lands; what is left
## standing (a body without its head, the legs under a cut waist) holds a beat
## on its feet and then topples the way the blow went. A stump jets in pulses
## for a while. Then it lies, and fades.

const GRAVITY := 620.0
const BOUNCE := 0.32
const LIE := 14.0
const FADE := 1.2
const MAX_AIR := 5.0
## How fast a fall over speeds up, rad/s².
const TOPPLE := 22.0

var velocity := Vector2.ZERO
var spin := 0.0
var _layer: Gore
var _blood := Color.RED
var _stain := 1.0
var _ink := {}
var _drip_ink := {}
var _spurt_ink := {}
var _shade := 0.0
var _bleed := 1.0
var _half := Vector2(2, 2)
var _air := 0.0
var _resting := false
var _floor_y := 0.0
var _lain := 0.0
var _drip := 0.0
## Seconds it stands before it falls (what is left standing; 0 for what flies).
var _hold := 0.0
## The angle it settles at: toppling for what stood, the nearest side for what flew.
var _target := NAN
## The stump: where on the piece it is (its own pixels from the centre, before
## rotation) and which way it points; seconds it jets for.
var _stump := Vector2.ZERO
var _stump_dir := Vector2.ZERO
var _spurt := 0.0
var _spurt_full := 0.0
var _pulse := 0.0
var _topple_v := 0.0


func setup(layer: Gore, launch: Vector2, turn: float, s: Dictionary, bleed: float, half: Vector2) -> void:
	_layer = layer
	velocity = launch
	spin = turn
	_blood = Color(str(s.blood))
	_stain = float(s.stain)
	_ink = Gore.ink(s)
	_drip_ink = Gore.ink(s, 0.8)
	_spurt_ink = Gore.ink(s, 0.9)
	_shade = float(s.get("shade", 0.0))
	_bleed = bleed
	_half = half.max(Vector2(1.0, 1.0))


## What was left standing: it holds [param seconds], then falls over to [param angle].
func stand(seconds: float, angle: float) -> void:
	_hold = seconds
	_target = angle
	spin = 0.0


## A stump at [param at] (its own pixels from the centre) pointing [param dir],
## jetting in pulses for [param seconds].
func stump(at: Vector2, dir: Vector2, seconds: float) -> void:
	_stump = at
	_stump_dir = dir
	_spurt = seconds
	_spurt_full = seconds


func is_resting() -> bool:
	return _resting and (is_nan(_target) or is_equal_approx(rotation, _target))


func _ready() -> void:
	add_to_group("gore_piece")
	z_index = 1


## How far the rotated piece reaches from its centre, down and sideways.
func _reach() -> Vector2:
	var c := absf(cos(rotation))
	var s := absf(sin(rotation))
	return Vector2(_half.x * c + _half.y * s, _half.y * c + _half.x * s)


func _physics_process(delta: float) -> void:
	_bleed_and_spurt(delta)
	if _hold > 0.0:
		_hold -= delta
		return
	if not is_nan(_target) and (_resting or spin == 0.0):
		_topple_v += TOPPLE * delta  # a fall over gathers speed
		rotation = move_toward(rotation, _target, _topple_v * delta)
	if _resting:
		global_position.y = _floor_y - _reach().y  # keeps its side on the floor as it settles
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
	if is_nan(_target) or spin != 0.0:
		rotation += spin * delta
	var step := velocity * delta
	var reach := _reach()
	var n := step.normalized()
	var ahead := absf(n.x) * reach.x + absf(n.y) * reach.y
	var mask := Gore.WORLD_MASK | (Gore.LEDGE_MASK if velocity.y > 0.0 else 0)
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step + n * ahead, mask)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position += step
		return
	var normal: Vector2 = hit.normal
	var wall := absf(normal.x) > 0.6
	global_position = hit.position + normal * (reach.x if wall else reach.y)
	if is_instance_valid(_layer):
		var face := 1 if wall else (2 if normal.y > 0.6 else 0)
		_layer.mark(hit.position, randf_range(2.0, 4.5) * _stain, face, _layer.shaded(_blood, _shade), _ink, 0.25, -1,
			_layer.surface(hit))
	if normal.y < -0.6:  # a floor
		velocity = Vector2(velocity.x * randf_range(0.4, 0.65), -absf(velocity.y) * BOUNCE * randf_range(0.7, 1.2))
		spin *= randf_range(0.3, 0.6)
		if absf(velocity.y) < 40.0:
			velocity = Vector2.ZERO
			_resting = true
			_floor_y = hit.position.y
			if is_nan(_target):
				_target = snappedf(rotation, PI / 2.0)  # rolls over onto whichever side is nearest
			spin = 0.0
	elif wall:
		velocity.x = -velocity.x * BOUNCE
		spin = -spin
	else:  # a ceiling
		velocity.y = absf(velocity.y) * BOUNCE


func _bleed_and_spurt(delta: float) -> void:
	if not is_instance_valid(_layer):
		return
	var root := global_position + (_stump * scale).rotated(rotation) if _stump_dir != Vector2.ZERO else global_position
	if _bleed > 0.0:
		_bleed -= delta
		_drip -= delta
		if _drip <= 0.0:
			_drip = (0.05 if not _resting else 0.22) * randf_range(0.6, 1.5)
			_layer.drop(root, Vector2(randf_range(-20, 20), randf_range(-30, 10)) - velocity * 0.1,
				_layer.shaded(_blood, _shade), _drip_ink)
	if _spurt <= 0.0:
		return
	_spurt -= delta
	_pulse -= delta
	if _pulse > 0.0:
		return
	# a heartbeat that weakens: each pulse a jet of a few drops out of the stump
	var strength := clampf(_spurt / maxf(_spurt_full, 0.01), 0.2, 1.0)
	_pulse = randf_range(0.14, 0.26) / (0.6 + strength * 0.4)
	var dir := _stump_dir.rotated(rotation)
	for i in randi_range(2, 4):
		var v := dir.rotated(randf_range(-0.25, 0.25)) * randf_range(80.0, 170.0) * strength
		_layer.drop(root, v + velocity * 0.5, _layer.shaded(_blood, _shade), _spurt_ink)
