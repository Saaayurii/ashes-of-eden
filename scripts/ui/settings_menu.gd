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
	for action in Settings.BINDABLE_ACTIONS:
		var button: Button = bindings.get_node_or_null(action)
		if button:
			button.text = tr("SETTINGS_PRESS_KEY") if _rebinding == action else Settings.key_name(action)


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
