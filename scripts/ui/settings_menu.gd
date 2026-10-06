extends Control
class_name SettingsMenu
## Settings overlay: works from the main menu and from the pause menu.
## Everything is applied immediately and saved by the Settings autoload.

signal closed

const NATIVE_NAMES := {"en": "English", "ru": "Русский", "uk": "Українська", "zh_CN": "简体中文"}

var _rebinding: String = ""  # action waiting for a key

@onready var language: OptionButton = %Language
@onready var difficulty: OptionButton = %Difficulty
@onready var transitions: OptionButton = %Transitions
@onready var sliders := {"Master": %MasterSlider, "Music": %MusicSlider, "SFX": %SfxSlider}
@onready var fullscreen: CheckButton = %Fullscreen
@onready var shake: CheckButton = %Shake
@onready var lighting: CheckButton = %Lighting
@onready var bindings: GridContainer = %Bindings
@onready var back_button: Button = %Back


func _ready() -> void:
	for i in Settings.LOCALES.size():
		var code: String = Settings.LOCALES[i]
		language.add_item(NATIVE_NAMES.get(code, code), i)
	language.item_selected.connect(func(index: int) -> void: Settings.set_locale(Settings.LOCALES[index]))
	for mode in Settings.DIFFICULTIES:
		difficulty.add_item("DIFF_" + mode.to_upper())
	difficulty.item_selected.connect(func(index: int) -> void: Settings.set_difficulty(Settings.DIFFICULTIES.keys()[index]))
	for mode in Settings.TRANSITIONS:
		transitions.add_item("TRANSITIONS_" + mode.to_upper())
	transitions.item_selected.connect(func(index: int) -> void: Settings.set_transitions(Settings.TRANSITIONS[index]))
	for bus in sliders:
		var slider: HSlider = sliders[bus]
		slider.value_changed.connect(func(value: float) -> void: Settings.set_volume(bus, value))
	fullscreen.toggled.connect(Settings.set_fullscreen)
	fullscreen.get_parent().visible = not (OS.has_feature("web") or OS.has_feature("mobile"))
	shake.toggled.connect(Settings.set_screen_shake)
	lighting.toggled.connect(Settings.set_lighting)
	%ResetKeys.pressed.connect(Settings.reset_keys)
	back_button.pressed.connect(close)
	Settings.changed.connect(_refresh)
	_build_bindings()
	_build_scheme()
	_build_speech()
	_build_skin()
	_build_vial()
	_build_access()
	_build_touch()
	_refresh()


func open() -> void:
	_refresh()
	visible = true
	back_button.grab_focus()


func close() -> void:
	_rebinding = ""
	visible = false
	closed.emit()


func _refresh() -> void:
	language.select(Settings.LOCALES.find(Settings.locale))
	difficulty.select(Settings.DIFFICULTIES.keys().find(Settings.difficulty))
	transitions.select(Settings.TRANSITIONS.find(Settings.transitions))
	for bus in sliders:
		sliders[bus].set_value_no_signal(Settings.volumes[bus])
	fullscreen.set_pressed_no_signal(Settings.fullscreen)
	shake.set_pressed_no_signal(Settings.screen_shake)
	lighting.set_pressed_no_signal(Settings.lighting)
	_fill_skins()
	_fill_vials()
	if _text_size:
		_text_size.select(Settings.TEXT_SIZES.keys().find(Settings.text_size))
		_flashes.select(Settings.FLASHES.find(Settings.flashes))
		_backdrop_motion.set_pressed_no_signal(Settings.backdrop_motion)
		_auto_attack.set_pressed_no_signal(Settings.auto_attack)
		_damage_numbers.set_pressed_no_signal(Settings.damage_numbers)
		_game_speed.select(Settings.GAME_SPEEDS.find(Settings.game_speed))
		_block_toggle.set_pressed_no_signal(Settings.block_toggle)
	if _touch_mode:
		_touch_mode.select(Settings.TOUCH_MODES.find(Settings.touch_mode))
		_touch_scale.set_value_no_signal(Settings.touch_scale)
		_touch_opacity.set_value_no_signal(Settings.touch_opacity)
		_touch_left.set_pressed_no_signal(Settings.touch_left_handed)
		_vibration.set_pressed_no_signal(Settings.vibration)
	if _speech:
		_speech.set_pressed_no_signal(Settings.speech)
	if _scheme:
		_scheme.select(Settings.CONTROL_SCHEMES.find(Settings.control_scheme))
		_mouse_aim.set_pressed_no_signal(Settings.mouse_aim)
		_mouse_aim.get_parent().visible = Settings.control_scheme == "mouse"
	for action in Settings.BINDABLE_ACTIONS:
		var button: Button = bindings.get_node_or_null(action)
		if button:
			button.text = tr("SETTINGS_PRESS_KEY") if _rebinding == action else Settings.key_name(action, false)


## On-screen controls (scripts/ui/touch_pad.gd): built here rather than in the
## scene so the rows sit just above the key bindings wherever those move to.
var _touch_mode: OptionButton
var _touch_scale: HSlider
var _touch_opacity: HSlider
var _touch_left: CheckButton
var _vibration: CheckButton
## Story lines read aloud. Built here beside the volume sliders rather than in
## the scene, so it sits with the rest of the sound instead of at the bottom.
var _speech: CheckButton
var _skin: OptionButton


func _build_speech() -> void:
	var sfx_row: Node = sliders["SFX"].get_parent()
	var box: Node = sfx_row.get_parent()
	_speech = CheckButton.new()
	var row := _row("SETTINGS_SPEECH", _speech)
	box.add_child(row)
	box.move_child(row, sfx_row.get_index() + 1)
	_speech.toggled.connect(Settings.set_speech)


## Accessibility, under the lighting switch it sits beside: how big story
## text is, and whether flashes are dimmed (Settings.text_size / flashes).
var _text_size: OptionButton
var _flashes: OptionButton
var _backdrop_motion: CheckButton
var _auto_attack: CheckButton
var _damage_numbers: CheckButton
var _game_speed: OptionButton
var _block_toggle: CheckButton


func _build_access() -> void:
	var anchor: Node = lighting.get_parent()
	var box: Node = anchor.get_parent()
	_text_size = OptionButton.new()
	for size in Settings.TEXT_SIZES:
		_text_size.add_item("TEXT_SIZE_" + size.to_upper())
	_text_size.item_selected.connect(func(index: int) -> void: Settings.set_text_size(Settings.TEXT_SIZES.keys()[index]))
	_flashes = OptionButton.new()
	for mode in Settings.FLASHES:
		_flashes.add_item("FLASHES_" + mode.to_upper())
	_flashes.item_selected.connect(func(index: int) -> void: Settings.set_flashes(Settings.FLASHES[index]))
	var at := anchor.get_index() + 1
	_backdrop_motion = CheckButton.new()
	_backdrop_motion.toggled.connect(Settings.set_backdrop_motion)
	_auto_attack = CheckButton.new()
	_auto_attack.toggled.connect(Settings.set_auto_attack)
	_damage_numbers = CheckButton.new()
	_damage_numbers.toggled.connect(Settings.set_damage_numbers)
	_game_speed = OptionButton.new()
	for speed in Settings.GAME_SPEEDS:
		_game_speed.add_item("%d%%" % roundi(speed * 100.0))
	_game_speed.item_selected.connect(func(index: int) -> void: Settings.set_game_speed(Settings.GAME_SPEEDS[index]))
	_game_speed.tooltip_text = "SETTINGS_GAME_SPEED_HINT"
	_block_toggle = CheckButton.new()
	_block_toggle.toggled.connect(Settings.set_block_toggle)
	for pair in [["SETTINGS_TEXT_SIZE", _text_size, "TextSizeRow"], ["SETTINGS_FLASHES", _flashes, "FlashesRow"],
			["SETTINGS_BACKDROP_MOTION", _backdrop_motion, "BackdropMotionRow"],
			["SETTINGS_AUTO_ATTACK", _auto_attack, "AutoAttackRow"],
			["SETTINGS_DAMAGE_NUMBERS", _damage_numbers, "DamageNumbersRow"],
			["SETTINGS_GAME_SPEED", _game_speed, "GameSpeedRow"],
			["SETTINGS_BLOCK_TOGGLE", _block_toggle, "BlockToggleRow"]]:
		var row := _row(pair[0], pair[1])
		row.name = pair[2]
		box.add_child(row)
		box.move_child(row, at)
		at += 1


## The vial of wrath for the next night (scripts/run/vials.gd), under the
## difficulty; only once a dawn has opened the first, and only the ones opened.
var _vial: OptionButton
## Omens on or off (Settings.omens), under the vial; shown once they have begun.
var _omens: CheckButton


func _build_vial() -> void:
	var anchor: Node = difficulty.get_parent()
	_vial = OptionButton.new()
	var row := _row("SETTINGS_VIAL", _vial)
	row.name = "VialRow"
	anchor.get_parent().add_child(row)
	anchor.get_parent().move_child(row, anchor.get_index() + 1)
	_vial.item_selected.connect(func(index: int) -> void: Settings.set_vial(index))
	_omens = CheckButton.new()
	_omens.toggled.connect(Settings.set_omens)
	var omen_row := _row("SETTINGS_OMENS", _omens)
	omen_row.name = "OmensRow"
	anchor.get_parent().add_child(omen_row)
	anchor.get_parent().move_child(omen_row, row.get_index() + 1)


func _fill_vials() -> void:
	if _vial == null:
		return
	_vial.clear()
	_vial.add_item("VIAL_NONE")
	for tier in range(1, Vials.opened() + 1):
		_vial.add_item(tr(str(Vials.spec(tier).get("name", ""))))
		_vial.set_item_tooltip(tier, tr(str(Vials.spec(tier).get("description", ""))))
	_vial.get_parent().visible = Vials.opened() > 0
	_vial.select(clampi(Settings.vial, 0, Vials.opened()))
	_omens.set_pressed_no_signal(Settings.omens)
	_omens.get_parent().visible = int(Profile.data.get("nights", 0)) >= Omens.FROM_NIGHT


## The cloak: every skin listed, the locked ones greyed with how to earn them.
func _build_skin() -> void:
	var anchor: Node = difficulty.get_parent()
	_skin = OptionButton.new()
	_skin.custom_minimum_size = Vector2(130, 0)
	var row := _row("SETTINGS_SKIN", _skin)
	anchor.get_parent().add_child(row)
	anchor.get_parent().move_child(row, anchor.get_index() + 1)
	_skin.item_selected.connect(func(index: int) -> void:
		var id: String = Skins.ids()[index]
		if Skins.unlocked(id):
			Settings.set_skin(id)
		else:
			_refresh())


func _fill_skins() -> void:
	if _skin == null:
		return
	_skin.clear()
	var ids := Skins.ids()
	for i in ids.size():
		var entry := Skins.spec(ids[i])
		var open := Skins.unlocked(ids[i])
		_skin.add_item(tr(str(entry.get("name", ids[i]))) if open else tr("SKIN_LOCKED") % tr(str(entry.get("name", ids[i]))), i)
		_skin.set_item_tooltip(i, tr(str(entry.get("description", ""))))
		_skin.set_item_disabled(i, not open)
	_skin.select(ids.find(Skins.worn(Settings.skin)))


func _build_touch() -> void:
	var box: Container = bindings.get_parent()
	var anchor := box.get_node_or_null("ControlsTitle")
	var index := anchor.get_index() if anchor else bindings.get_index()
	var title := Label.new()
	title.text = "SETTINGS_TOUCH"
	if anchor:
		title.add_theme_color_override("font_color", anchor.get_theme_color("font_color"))
		title.add_theme_font_size_override("font_size", anchor.get_theme_font_size("font_size"))
	var rows: Array[Control] = [title]
	_touch_mode = OptionButton.new()
	for mode in Settings.TOUCH_MODES:
		_touch_mode.add_item("TOUCH_" + mode.to_upper())
	rows.append(_row("SETTINGS_TOUCH_MODE", _touch_mode))
	_touch_scale = _slider(0.7, 1.5)
	rows.append(_row("SETTINGS_TOUCH_SCALE", _touch_scale))
	_touch_opacity = _slider(0.3, 1.0)
	rows.append(_row("SETTINGS_TOUCH_OPACITY", _touch_opacity))
	_touch_left = CheckButton.new()
	rows.append(_row("SETTINGS_TOUCH_LEFT", _touch_left))
	_vibration = CheckButton.new()
	rows.append(_row("SETTINGS_VIBRATION", _vibration))
	_vibration.toggled.connect(Settings.set_vibration)
	for i in rows.size():
		box.add_child(rows[i])
		box.move_child(rows[i], index + i)
	_touch_mode.item_selected.connect(func(_i: int) -> void: _push_touch())
	_touch_scale.value_changed.connect(func(_v: float) -> void: _push_touch())
	_touch_opacity.value_changed.connect(func(_v: float) -> void: _push_touch())
	_touch_left.toggled.connect(func(_on: bool) -> void: _push_touch())


func _row(label_key: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_key
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	control.custom_minimum_size.x = 130
	row.add_child(control)
	return row


func _slider(lo: float, hi: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = 0.05
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return slider


func _push_touch() -> void:
	Settings.set_touch(Settings.TOUCH_MODES[_touch_mode.selected], _touch_scale.value, _touch_opacity.value, _touch_left.button_pressed)


## Keyboard alone or keyboard and mouse (Settings.control_scheme), right
## under the Controls title so the bindings below show what it chose.
var _scheme: OptionButton
var _mouse_aim: CheckButton


func _build_scheme() -> void:
	var box: Container = bindings.get_parent()
	var anchor := box.get_node_or_null("ControlsTitle")
	var at := anchor.get_index() + 1 if anchor else bindings.get_index()
	_scheme = OptionButton.new()
	for scheme in Settings.CONTROL_SCHEMES:
		_scheme.add_item("CONTROLS_" + scheme.to_upper())
	_scheme.tooltip_text = "SETTINGS_SCHEME_HINT"
	_scheme.item_selected.connect(func(index: int) -> void:
		_rebinding = ""
		Settings.set_control_scheme(Settings.CONTROL_SCHEMES[index]))
	var row := _row("SETTINGS_SCHEME", _scheme)
	row.name = "SchemeRow"
	box.add_child(row)
	box.move_child(row, at)
	_mouse_aim = CheckButton.new()
	_mouse_aim.tooltip_text = "SETTINGS_MOUSE_AIM_HINT"
	_mouse_aim.toggled.connect(Settings.set_mouse_aim)
	var aim_row := _row("SETTINGS_MOUSE_AIM", _mouse_aim)
	aim_row.name = "MouseAimRow"
	box.add_child(aim_row)
	box.move_child(aim_row, at + 1)


func _build_bindings() -> void:
	for action in Settings.BINDABLE_ACTIONS:
		var label := Label.new()
		label.text = "ACTION_" + action.to_upper()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bindings.add_child(label)
		var button := Button.new()
		button.name = action
		button.custom_minimum_size = Vector2(110, 0)
		button.pressed.connect(func() -> void: _start_rebind(action))
		bindings.add_child(button)


func _start_rebind(action: String) -> void:
	_rebinding = action
	_refresh()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _rebinding != "":
		# A key, or a mouse button (not the wheel); Escape gives up. The click
		# that opened the wait was its release, so this press is a new one.
		var pressed := (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed() and not event.is_echo()
		if pressed:
			get_viewport().set_input_as_handled()
			var binding := Settings.binding_of(event)
			if binding != KEY_ESCAPE and binding != 0:
				Settings.bind(_rebinding, binding)
			if binding != 0:
				_rebinding = ""
			_refresh()
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
