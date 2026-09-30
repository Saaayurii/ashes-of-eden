extends Control
## Full-screen theatre that belongs to the player's own eyes, not to the room:
## the red that comes up around the frame when we are hit, and the eyelids
## that blink open when the body comes to. Sits first in the UI layer so the
## HUD is drawn over it. Everything is built here in code: two soft-edged
## black lids and one ColorRect with assets/shaders/vignette.gdshader.

const VIGNETTE_SHADER := preload("res://assets/shaders/vignette.gdshader")
## Below this fraction of the bar the edges keep a faint pulse.
const LOW_HP := 0.25
## The blink: (how far open, seconds to get there), in order. Closed at the start.
const WAKE_BLINK := [[0.3, 0.4], [0.0, 0.12], [0.65, 0.45], [0.0, 0.1], [1.0, 0.7]]
const REVIVE_BLINK := [[0.5, 0.2], [0.0, 0.08], [1.0, 0.4]]

var _vignette: ColorRect
var _material: ShaderMaterial
var _lids: Array[TextureRect] = []
var _lids_root: Control
var _open := 1.0
var _hit := 0.0        # the burst of a hit, fading
var _low := 0.0        # the low-health floor
var _pulse := 0.0
var _blink: Tween


func _ready() -> void:
	# Our eyes are not part of the world: a blink that a dialogue or a menu
	# pauses halfway would leave the lids shut over the whole conversation.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = VIGNETTE_SHADER
	_vignette = ColorRect.new()
	_vignette.material = _material
	_vignette.mouse_filter = MOUSE_FILTER_IGNORE
	_vignette.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_vignette)
	# A lid is black up to its edge, then fades over a few pixels: a soft edge
	# reads as skin, a hard one as a letterbox.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.82, 1.0])
	gradient.colors = PackedColorArray([Color.BLACK, Color.BLACK, Color(0, 0, 0, 0)])
	for flipped in [false, true]:
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 4
		texture.height = 64
		texture.fill_from = Vector2(0.5, 1.0 if flipped else 0.0)
		texture.fill_to = Vector2(0.5, 0.0 if flipped else 1.0)
		var lid := TextureRect.new()
		lid.texture = texture
		lid.stretch_mode = TextureRect.STRETCH_SCALE
		lid.mouse_filter = MOUSE_FILTER_IGNORE
		lid.set_anchors_preset(PRESET_BOTTOM_WIDE if flipped else PRESET_TOP_WIDE)
		lid.grow_vertical = GROW_DIRECTION_BEGIN if flipped else GROW_DIRECTION_END
		_lids.append(lid)
	# The lids go over the HUD (eyes shut hide the bars too) but under the
	# dialogue and menus: a control of their own, slotted in right after the HUD.
	var lids := Control.new()
	lids.name = "Lids"
	lids.mouse_filter = MOUSE_FILTER_IGNORE
	lids.set_anchors_preset(PRESET_FULL_RECT)
	for lid in _lids:
		lids.add_child(lid)
	var parent := get_parent()
	parent.add_child.call_deferred(lids)
	var hud := parent.get_node_or_null("HUD")
	if hud == null:
		hud = parent.get_node_or_null("DuelHud")
	if hud != null:
		parent.move_child.call_deferred(lids, hud.get_index() + 1)
	_lids_root = lids
	_set_open(1.0)
	EventBus.player_hurt.connect(_on_hurt)
	EventBus.player_hp_changed.connect(_on_hp_changed)
	EventBus.player_waking.connect(_on_waking)
	resized.connect(func() -> void: _set_open(_open))


func _process(delta: float) -> void:
	_hit = maxf(0.0, _hit - delta * (1.6 if _hit > 0.5 else 1.0))
	_pulse += delta * 3.0
	var low := _low * (0.7 + 0.3 * sin(_pulse))
	_material.set_shader_parameter("strength", clampf(maxf(_hit, low), 0.0, 1.0) * Settings.flash_scale())


## [param fraction] is the blow as a share of the bar: a scratch is a flicker
## at the edges, a third of the bar brings the red well into the frame; the
## middle, where the fight is, is never covered.
func _on_hurt(fraction: float) -> void:
	_hit = maxf(_hit, clampf(0.28 + fraction * 1.2, 0.28, 0.7))


func _on_hp_changed(hp: float, max_hp: float) -> void:
	var share := hp / maxf(max_hp, 1.0)
	_low = 0.0 if share > LOW_HP or hp <= 0.0 else lerpf(0.22, 0.06, share / LOW_HP)


## The eyes open: shut, a crack, shut, half, shut, open. Over roughly the
## time the body takes to get up, so the first thing seen is Elian on his feet.
func _on_waking(seconds: float) -> void:
	var steps: Array = WAKE_BLINK if seconds > 1.0 else REVIVE_BLINK
	var total := 0.0
	for step in steps:
		total += float(step[1])
	var scale := seconds / total
	if _blink != null:
		_blink.kill()
	_set_open(0.0)
	_blink = create_tween()
	var from := 0.0
	for step in steps:
		var to := float(step[0])
		var ease_kind := Tween.EASE_IN if to == 0.0 else Tween.EASE_OUT
		_blink.tween_method(_set_open, from, to, float(step[1]) * scale).set_trans(Tween.TRANS_CUBIC).set_ease(ease_kind)
		from = to


func _set_open(value: float) -> void:
	_open = value
	var lid_height := (1.0 - value) * size.y * 0.5
	# Offsets, not size: the bottom lid hangs from the bottom anchor upwards.
	_lids[0].offset_top = 0.0
	_lids[0].offset_bottom = lid_height
	_lids[1].offset_top = -lid_height
	_lids[1].offset_bottom = 0.0
	for lid in _lids:
		lid.visible = lid_height > 0.5
