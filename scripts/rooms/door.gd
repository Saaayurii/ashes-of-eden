extends Area2D
class_name Door
## Exit of a room. Chained shut until the room is cleared; walking into it when
## open emits [signal entered]. The gate strip (assets/decor/door_gate.png) is
## one locked frame followed by the gate swinging open.

signal entered

const OPEN_FPS := 12.0
## Painted rooms already contain an architectural doorway; the generic cage
## sprite used by constructed rooms would sit visibly on top of that artwork.
@export var painted_arch := false

var open := false:
	set(value):
		open = value
		_refresh()

@onready var gate: Sprite2D = $Gate
@onready var glow: Sprite2D = $Glow
## Lit when the chain gives: the way out is the brightest thing in the room.
var _light: GlowLight
var _painted_was_open := false
var _entered_once := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_light = Fx.light(self, Vector2(0, -10), Color(1.0, 0.85, 0.55), 90.0, 0.0, 0.2)
	gate.visible = not painted_arch
	if painted_arch:
		glow.position.y = -8.0
		glow.scale = Vector2(1.15, 1.45)
	_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return
	glow.visible = open
	if _light != null and not open:
		_light.set_base_energy(0.12 if painted_arch else 0.0)
	if not open:
		_painted_was_open = false
		_entered_once = false
		gate.frame = 0
	elif painted_arch:
		if not _painted_was_open:
			_painted_was_open = true
			_open_painted_arch()
	elif gate.frame == 0:
		_swing()
	if open:
		# Opening does not generate body_entered for a hero already waiting
		# inside the locked gate. Defer until room listeners are connected.
		call_deferred("_check_waiting_player")


func _check_waiting_player() -> void:
	if not open or _entered_once or not is_inside_tree():
		return
	for body in get_overlapping_bodies():
		_on_body_entered(body)
		if _entered_once:
			return


func _open_painted_arch() -> void:
	# Keep the masonry and carved entrance from the painting. Only light and
	# motes change when the passage becomes usable.
	Fx.sparkle(global_position + Vector2(0, -8), Color(1.0, 0.85, 0.6), 8, 7.0)
	if _light != null:
		create_tween().tween_method(_light.set_base_energy, 0.12, 0.55, 0.5)
	Audio.play(&"door_open", -6.0)


## The chain gives: a puff, a shake, then the gate opens frame by frame.
func _swing() -> void:
	Fx.puff(global_position, 0.8, Color(1.0, 0.9, 0.65))
	Fx.sparkle(global_position + Vector2(0, 10), Color(1.0, 0.9, 0.65), 12, 10.0)
	if _light != null:
		create_tween().tween_method(_light.set_base_energy, 0.0, 0.9, 0.6)
	Juice.shake(2.0)
	Audio.play(&"door_open", -3.0)
	for frame in range(1, gate.hframes):
		await get_tree().create_timer(1.0 / OPEN_FPS).timeout
		if not is_inside_tree():
			return
		gate.frame = frame


func _on_body_entered(body: Node) -> void:
	# Teleporting from a previous room can leave a queued body_entered event.
	# Accept only a body that is still physically at this gate now.
	if open and not _entered_once and body is Player and not body.is_dead() \
			and (body.global_position - global_position).length_squared() < 48.0 * 48.0:
		_entered_once = true
		entered.emit()
