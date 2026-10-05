extends Control
## The whole game under two thumbs, for phones, tablets and mobile browsers.
##
## One full-screen layer owns every touch, so any number of fingers work at
## once (run and block, hold block and swing): a finger that lands in the
## stick half drives a floating stick; a finger on a button holds its action
## until it lifts. Every action a keyboard has is here — move (and down to drop
## through a ledge), jump, attack, roll, block, heal, skill, talk, pause.
##
## Sizes come from the screen, not from pixels: the unit is a share of the
## viewport's short side, so a phone and a tablet both get thumb-sized
## buttons, scaled again by Settings.touch_scale. The notch / home-bar safe
## area is kept clear. Settings: touch_mode (auto/on/off), touch_scale,
## touch_opacity, touch_left_handed.
##
## While the game is paused (a menu, the gift cards, a story choice) the pad
## steps aside and lets the GUI have the touch. And a touch never reaches the
## game as the emulated left click that the "attack" action is bound to.

const ICONS := {
	"attack": preload("res://assets/ui/icons/swords.png"),
	"heal": preload("res://assets/ui/icons/potion.png"),
	"skill": preload("res://assets/ui/icons/sun.png"),
}
const RING := Color(0.84, 0.66, 0.34)
const RING_DARK := Color(0.12, 0.09, 0.08)
const DISK := Color(0.06, 0.05, 0.07)
const GLYPH := Color(0.95, 0.9, 0.8)
const STICK_DEADZONE := 0.22
## Pushing the stick this far down (or up) also presses move_down / move_up.
const STICK_VERTICAL := 0.6

## name -> {action, pos (unit offsets from the anchor), radius (units), hold}
const LAYOUT := {
	"attack": {"action": "attack", "at": Vector2(0.0, 0.0), "r": 1.15},
	"jump": {"action": "jump", "at": Vector2(0.15, -2.45), "r": 0.95},
	"dash": {"action": "dash", "at": Vector2(-2.45, 0.35), "r": 0.9},
	"block": {"action": "block", "at": Vector2(-2.05, -2.05), "r": 0.85},
	"skill": {"action": "skill", "at": Vector2(-4.25, -0.35), "r": 0.8},
	"heal": {"action": "heal", "at": Vector2(-3.9, -2.45), "r": 0.7},
	"talk": {"action": "interact", "at": Vector2(-1.25, -4.05), "r": 0.65},
}

var _unit := 24.0
var _margin := Vector2(12, 12)
var _buttons := {}        # name -> {center, radius, action}
var _fingers := {}        # touch index -> button name, or "stick"
var _stick_index := -1
var _stick_origin := Vector2.ZERO
var _stick_now := Vector2.ZERO
var _stick_radius := 40.0
var _pause_center := Vector2.ZERO
var _pause_radius := 16.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().size_changed.connect(_layout)
	Settings.changed.connect(_layout)
	for child in get_children():
		child.queue_free()  # the old rectangles and TouchScreenButtons
	_layout()


func _process(_delta: float) -> void:
	visible = Settings.touch_enabled() and not get_tree().paused
	if not visible and not _fingers.is_empty():
		_release_all()
	queue_redraw()


# ------------------------------------------------------------------ layout ---

func _layout() -> void:
	var view := get_viewport_rect().size
	var short := minf(view.x, view.y)
	# A phone held sideways is ~360 short units; a tablet in 4:3 has more room.
	_unit = short * 0.062 * Settings.touch_scale
	_margin = _safe_margin() + Vector2(_unit * 0.6, _unit * 0.6)
	var left := Settings.touch_left_handed
	var anchor := Vector2(_margin.x + _unit * 1.4 if left else view.x - _margin.x - _unit * 1.4,
		view.y - _margin.y - _unit * 1.3)
	_buttons.clear()
	for name in LAYOUT:
		var spec: Dictionary = LAYOUT[name]
		var at: Vector2 = spec.at
		if left:
			at.x = -at.x
		_buttons[name] = {"center": anchor + at * _unit, "radius": float(spec.r) * _unit, "action": spec.action}
	_stick_radius = _unit * 1.6
	_pause_radius = _unit * 0.55
	# Top centre: the HUD owns the left corner, the minimap the right one.
	_pause_center = Vector2(view.x / 2.0, _margin.y + _pause_radius * 0.6)


## The notch / rounded corners / home bar, in this canvas's units.
func _safe_margin() -> Vector2:
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or screen.x <= 0:
		return Vector2.ZERO
	var view := get_viewport_rect().size
	var to_view := view / Vector2(screen)
	var left_right := maxf(safe.position.x, screen.x - safe.end.x) * to_view.x
	var bottom := maxf(0.0, screen.y - safe.end.y) * to_view.y
	return Vector2(left_right, bottom)


# ------------------------------------------------------------------- input ---

func _input(event: InputEvent) -> void:
	if not visible:
		return
	# The emulated left click a touch also produces would be an attack.
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		var at := _to_canvas(event.position)
		if event.pressed:
			_press(event.index, at)
		else:
			_lift(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _stick_index:
			_stick_now = _to_canvas(event.position)
			_apply_stick()
		get_viewport().set_input_as_handled()


## Touch positions arrive in window pixels; the pad draws in the stretched
## 640-wide canvas. The final transform maps one to the other.
func _to_canvas(screen_position: Vector2) -> Vector2:
	return get_viewport().get_final_transform().affine_inverse() * screen_position


func _press(index: int, at: Vector2) -> void:
	if at.distance_to(_pause_center) <= _pause_radius * 1.3:
		var pause := InputEventAction.new()
		pause.action = "pause"
		pause.pressed = true
		Input.parse_input_event(pause)
		return
	for name in _buttons:
		var b: Dictionary = _buttons[name]
		if at.distance_to(b.center) <= b.radius * 1.15:  # a little forgiveness for thumbs
			_fingers[index] = name
			Input.action_press(b.action)
			return
	var view := get_viewport_rect().size
	var stick_side := at.x > view.x * 0.5 if Settings.touch_left_handed else at.x < view.x * 0.5
	if stick_side and _stick_index == -1:
		_stick_index = index
		_fingers[index] = "stick"
		_stick_origin = at
		_stick_now = at
		_apply_stick()


func _lift(index: int) -> void:
	var name: String = _fingers.get(index, "")
	_fingers.erase(index)
	if name == "stick":
		_stick_index = -1
		for action in ["move_left", "move_right", "move_up", "move_down"]:
			Input.action_release(action)
	elif _buttons.has(name):
		var action: String = _buttons[name].action
		# Another finger may still hold the same button.
		if not _fingers.values().has(name):
			Input.action_release(action)


func _apply_stick() -> void:
	var offset := _stick_now - _stick_origin
	if offset.length() > _stick_radius:
		# Drag the origin along: the stick follows a thumb that wanders.
		_stick_origin = _stick_now - offset.normalized() * _stick_radius
		offset = _stick_now - _stick_origin
	var v := offset / _stick_radius
	_hold("move_right", v.x if v.x > STICK_DEADZONE else 0.0)
	_hold("move_left", -v.x if v.x < -STICK_DEADZONE else 0.0)
	_hold("move_down", 1.0 if v.y > STICK_VERTICAL else 0.0)
	_hold("move_up", 1.0 if v.y < -STICK_VERTICAL else 0.0)


func _hold(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, clampf(strength, 0.0, 1.0))
	else:
		Input.action_release(action)


func _release_all() -> void:
	for index in _fingers.keys():
		_lift(index)
	_fingers.clear()
	_stick_index = -1


# -------------------------------------------------------------------- draw ---

func _draw() -> void:
	var alpha := Settings.touch_opacity
	# The stick: a ring where the thumb landed, a knob under it.
	if _stick_index != -1:
		_ring(_stick_origin, _stick_radius, alpha * 0.55, false)
		var knob := _stick_origin + (_stick_now - _stick_origin).limit_length(_stick_radius)
		_ring(knob, _unit * 0.7, alpha, true)
	else:
		# A faint hint of where the stick lives.
		var view := get_viewport_rect().size
		var hint := Vector2(view.x - _margin.x - _unit * 2.4 if Settings.touch_left_handed else _margin.x + _unit * 2.4,
			view.y - _margin.y - _unit * 2.0)
		_ring(hint, _stick_radius, alpha * 0.22, false)
	var player := _own_player()
	for name in _buttons:
		var b: Dictionary = _buttons[name]
		var held := _fingers.values().has(name)
		var dim := 1.0
		if name == "talk" and not _npc_near(player):
			dim = 0.4
		if name == "skill" and player != null and (player.get("skill") as Dictionary).is_empty():
			dim = 0.35
		if name == "heal" and player != null and int(player.get("heal_charges")) <= 0:
			dim = 0.4
		_ring(b.center, b.radius * (0.92 if held else 1.0), alpha * dim, held)
		_glyph(name, b.center, b.radius, alpha * dim)
		_cooldown(name, b.center, b.radius, player, alpha)
	_ring(_pause_center, _pause_radius, alpha * 0.8, false)
	var bar := Vector2(_pause_radius * 0.18, _pause_radius * 0.8)
	draw_rect(Rect2(_pause_center + Vector2(-bar.x * 2.0, -bar.y / 2.0), bar), Color(GLYPH, alpha))
	draw_rect(Rect2(_pause_center + Vector2(bar.x, -bar.y / 2.0), bar), Color(GLYPH, alpha))


func _ring(at: Vector2, radius: float, alpha: float, filled: bool) -> void:
	draw_circle(at, radius, Color(DISK, 0.55 * alpha if not filled else 0.8 * alpha))
	draw_arc(at, radius, 0.0, TAU, 40, Color(RING_DARK, alpha), maxf(2.0, radius * 0.16), true)
	draw_arc(at, radius - 1.0, PI * 1.05, PI * 1.95, 20, Color(RING.lightened(0.25), alpha), 1.0, true)
	draw_arc(at, radius - 1.0, 0.0, TAU, 40, Color(RING, alpha * (1.0 if filled else 0.75)), 1.2, true)


func _glyph(name: String, at: Vector2, radius: float, alpha: float) -> void:
	var c := Color(GLYPH, alpha)
	var s := radius * 0.5
	if ICONS.has(name):
		var tex: Texture2D = ICONS[name]
		var size := Vector2.ONE * radius * 1.05
		draw_texture_rect(tex, Rect2(at - size / 2.0, size), false, Color(1, 1, 1, alpha))
		return
	match name:
		"jump":
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s), at + Vector2(s * 0.9, s * 0.2), at + Vector2(-s * 0.9, s * 0.2)]), c)
			draw_rect(Rect2(at + Vector2(-s * 0.25, s * 0.2), Vector2(s * 0.5, s * 0.6)), c)
		"dash":
			for i in 3:
				var x := -s * 0.7 + i * s * 0.55
				draw_polyline(PackedVector2Array([at + Vector2(x, -s * 0.6), at + Vector2(x + s * 0.45, 0), at + Vector2(x, s * 0.6)]), Color(c, alpha * (0.45 + i * 0.27)), maxf(1.5, s * 0.18))
		"block":
			var shield := PackedVector2Array([at + Vector2(-s * 0.75, -s * 0.8), at + Vector2(s * 0.75, -s * 0.8),
				at + Vector2(s * 0.7, s * 0.1), at + Vector2(0, s * 0.9), at + Vector2(-s * 0.7, s * 0.1)])
			draw_colored_polygon(shield, Color(RING, alpha * 0.9))
			draw_polyline(shield + PackedVector2Array([shield[0]]), c, 1.2)
		"talk":
			draw_circle(at + Vector2(0, -s * 0.1), s * 0.75, c)
			draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 0.4, s * 0.45), at + Vector2(-s * 0.1, s * 0.5), at + Vector2(-s * 0.6, s * 0.95)]), c)
			for i in 3:
				draw_circle(at + Vector2(-s * 0.35 + i * s * 0.35, -s * 0.1), s * 0.1, Color(DISK, alpha))


## A dark sweep over a button that is recharging, and the flasks left on heal.
func _cooldown(name: String, at: Vector2, radius: float, player: Node, alpha: float) -> void:
	if player == null:
		return
	var left := 0.0
	match name:
		"dash":
			left = float(player.get("_dash_cd")) / maxf(0.01, float(player.stats.get("dash_cooldown", 1.0)))
		"skill":
			var spec: Dictionary = player.get("skill")
			if not spec.is_empty():
				left = float(player.get("_skill_cd")) / maxf(0.01, float(spec.get("cooldown", 1.0)))
		"heal":
			var charges := int(player.get("heal_charges"))
			var font := get_theme_default_font()
			draw_string(font, at + Vector2(radius * 0.35, radius * 0.95), str(charges), HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius * 0.7), Color(GLYPH, alpha))
	if left > 0.01:
		var steps := 24
		var points := PackedVector2Array([at])
		for i in steps + 1:
			var angle := -PI / 2.0 + TAU * clampf(left, 0.0, 1.0) * float(i) / steps
			points.append(at + Vector2(cos(angle), sin(angle)) * radius * 0.9)
		draw_colored_polygon(points, Color(0, 0, 0, 0.55 * alpha))


func _own_player() -> Node:
	for node in get_tree().get_nodes_in_group("player"):
		if node.is_multiplayer_authority():
			return node
	return null


func _npc_near(player: Node) -> bool:
	if player == null:
		return false
	if Game.practice != "":
		return true  # the yard's talk button changes the drill (PracticeDrills)
	# a person to talk to, or a thing that asks before it is used (a rest
	# point, a cursed chest)
	for npc in get_tree().get_nodes_in_group("npc") + get_tree().get_nodes_in_group("interactable"):
		if npc is Node2D and (npc as Node2D).global_position.distance_to(player.global_position) < 70.0:
			return true
	return false
