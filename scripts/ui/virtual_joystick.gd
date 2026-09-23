extends Control
## Floating virtual joystick for touch screens. Touch anywhere on this control,
## drag to move. Feeds the same move_* actions the keyboard uses.

@export var radius := 36.0

var _touch_index := -1
var _center := Vector2.ZERO

@onready var base: Control = $Base
@onready var knob: Control = $Base/Knob


func _ready() -> void:
	base.visible = false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			_center = event.position
			base.position = _center - base.size / 2.0
			base.visible = true
			_update(event.position)
		elif not event.pressed and event.index == _touch_index:
			_release()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update(event.position)


func _update(pos: Vector2) -> void:
	var offset := pos - _center
	if offset.length() > radius:
		offset = offset.normalized() * radius
	knob.position = base.size / 2.0 + offset - knob.size / 2.0
	var vector := offset / radius
	_press("move_left", -vector.x)
	_press("move_right", vector.x)
	_press("move_up", -vector.y)
	_press("move_down", vector.y)


func _press(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _release() -> void:
	_touch_index = -1
	base.visible = false
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)
