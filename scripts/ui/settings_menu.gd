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
	_build_speech()
	_build_skin()
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
	if _touch_mode:
		_touch_mode.select(Settings.TOUCH_MODES.find(Settings.touch_mode))
		_touch_scale.set_value_no_signal(Settings.touch_scale)
		_touch_opacity.set_value_no_signal(Settings.touch_opacity)
		_touch_left.set_pressed_no_signal(Settings.touch_left_handed)
		_vibration.set_pressed_no_signal(Settings.vibration)
	if _speech:
		_speech.set_pressed_no_signal(Settings.speech)
	for action in Settings.BINDABLE_ACTIONS:
		var button: Button = bindings.get_node_or_null(action)
		if button:
			button.text = tr("SETTINGS_PRESS_KEY") if _rebinding == action else Settings.key_name(action)


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
		if event is InputEventKey and event.pressed:
			get_viewport().set_input_as_handled()
			if event.physical_keycode != KEY_ESCAPE:
				Settings.bind_key(_rebinding, event.physical_keycode)
			_rebinding = ""
			_refresh()
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
