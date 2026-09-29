extends Node
## Persistent player settings (user://settings.cfg): locale, audio, display,
## key bindings. Applied on startup and whenever changed from the settings menu.

signal changed

const PATH := "user://settings.cfg"
## Order matters: this is the order shown in the language selector.
const LOCALES := ["en", "ru", "uk", "zh_CN"]
const BUSES := ["Master", "Music", "SFX"]
## Actions the player may rebind, in menu order.
const BINDABLE_ACTIONS := ["move_left", "move_right", "jump", "attack", "block", "dash", "heal", "skill", "interact", "pause"]
## Difficulty modes: enemy HP and damage only. Never story or loot (docs/BALANCE.md).
const DIFFICULTIES := {"pilgrim": [0.8, 0.75], "standard": [1.0, 1.0], "judgment": [1.25, 1.35]}
## How much of the curtain between places a player wants to sit through on
## their fifth night: the whole card, a brisk one, or a plain cut. In menu order.
const TRANSITIONS := ["full", "short", "off"]
## On-screen controls: "auto" = phones, tablets and mobile browsers only.
const TOUCH_MODES := ["auto", "on", "off"]

var locale: String = "en"
var volumes := {"Master": 1.0, "Music": 0.8, "SFX": 1.0}
var fullscreen := false
var screen_shake := true
## 2D lights and the night tint of the rooms. Off = the flat look, for weak GPUs.
var lighting := true
var difficulty := "standard"
## The hero's cloak (data/skins); only an unlocked one is ever kept (Skins.unlocked).
var skin := "pilgrim"
## Chapter cards and the ash between rooms (scripts/autoload/curtain.gd).
var transitions := "full"
var touch_mode := "auto"
var touch_scale := 1.0     # 0.7–1.5, how big the on-screen buttons are
var touch_opacity := 0.75  # 0.3–1.0
var touch_left_handed := false  # buttons on the left, stick on the right
var vibration := true  # phones and tablets: a buzz on a blow taken, a parry, a boss down
## Story lines read aloud. On by default, and worth turning off: what ships is
## synthesised (docs/VOICE.md), and a reader who is faster than the voice —
## or who simply dislikes it — should not have to mute the SFX bus to be rid
## of it. Off leaves the captions exactly as they were.
var speech := true
## action -> physical keycode of the primary keyboard key. Gamepad bindings stay as in project.godot.
var keys: Dictionary = {}


func _ready() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	locale = cfg.get_value("general", "locale", _detect_locale())
	for bus in BUSES:
		volumes[bus] = clampf(float(cfg.get_value("audio", bus.to_lower(), volumes[bus])), 0.0, 1.0)
	fullscreen = cfg.get_value("video", "fullscreen", false)
	screen_shake = cfg.get_value("video", "screen_shake", true)
	lighting = cfg.get_value("video", "lighting", true)
	difficulty = cfg.get_value("game", "difficulty", "standard")
	skin = str(cfg.get_value("game", "skin", "pilgrim"))
	if not DIFFICULTIES.has(difficulty):
		difficulty = "standard"
	transitions = cfg.get_value("game", "transitions", "full")
	if not TRANSITIONS.has(transitions):
		transitions = "full"
	touch_mode = cfg.get_value("touch", "mode", "auto")
	if not TOUCH_MODES.has(touch_mode):
		touch_mode = "auto"
	touch_scale = clampf(float(cfg.get_value("touch", "scale", 1.0)), 0.7, 1.5)
	touch_opacity = clampf(float(cfg.get_value("touch", "opacity", 0.75)), 0.3, 1.0)
	touch_left_handed = bool(cfg.get_value("touch", "left_handed", false))
	vibration = bool(cfg.get_value("touch", "vibration", true))
	speech = bool(cfg.get_value("audio", "speech", true))
	for action in BINDABLE_ACTIONS:
		if cfg.has_section_key("keys", action):
			keys[action] = int(cfg.get_value("keys", action))
	apply_all()


func apply_all() -> void:
	TranslationServer.set_locale(locale)
	for bus in BUSES:
		_apply_volume(bus)
	_apply_fullscreen()
	_apply_keys()
	changed.emit()


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("general", "locale", locale)
	for bus in BUSES:
		cfg.set_value("audio", bus.to_lower(), volumes[bus])
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "screen_shake", screen_shake)
	cfg.set_value("video", "lighting", lighting)
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("game", "skin", skin)
	cfg.set_value("game", "transitions", transitions)
	cfg.set_value("touch", "mode", touch_mode)
	cfg.set_value("touch", "scale", touch_scale)
	cfg.set_value("touch", "opacity", touch_opacity)
	cfg.set_value("touch", "left_handed", touch_left_handed)
	cfg.set_value("touch", "vibration", vibration)
	cfg.set_value("audio", "speech", speech)
	for action in keys:
		cfg.set_value("keys", action, keys[action])
	cfg.save(PATH)


func set_locale(code: String) -> void:
	locale = code
	TranslationServer.set_locale(code)
	save()
	changed.emit()


func set_volume(bus: String, linear: float) -> void:
	volumes[bus] = clampf(linear, 0.0, 1.0)
	_apply_volume(bus)
	save()


## Whether the on-screen controls are shown on this device.
##
## In a browser this used to get it wrong. A Web export has no "pc" feature —
## that one is only set on desktop builds — so `not OS.has_feature("pc")` is
## true on every browser, and `is_touchscreen_available()` says yes on any
## machine whose browser merely supports touch events, which is most laptops.
## The result was a phone's thumbstick sitting over a desktop game.
##
## The browser can answer this properly: the `pointer: coarse` media query is
## true for a finger and false for a mouse, which is the actual question. It
## is asked once and remembered — the answer does not change mid-session, and
## a JavaScript call per frame would be absurd.
func touch_enabled() -> bool:
	match touch_mode:
		"on":
			return true
		"off":
			return false
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	if OS.has_feature("web"):
		return _browser_is_touch()
	# Native desktop and anything else: emulate_touch_from_mouse is on for
	# testing, so a real touchscreen is the only thing worth believing.
	return DisplayServer.is_touchscreen_available() and not OS.has_feature("pc")


var _browser_touch := -1  # -1 not asked yet, 0 mouse, 1 finger


func _browser_is_touch() -> bool:
	if _browser_touch < 0:
		_browser_touch = 0
		if ClassDB.class_exists("JavaScriptBridge"):
			var answer: Variant = JavaScriptBridge.eval(
				"window.matchMedia && window.matchMedia('(pointer: coarse)').matches", true)
			_browser_touch = 1 if bool(answer) else 0
	return _browser_touch == 1


## Text is read at arm's length on a desk and at a hand's length on a phone,
## but a phone's pixels are tiny: story text grows when the touch pad is on.
func text_scale() -> float:
	return 1.3 if touch_enabled() else 1.0


func set_vibration(enabled: bool) -> void:
	vibration = enabled
	save()
	changed.emit()


func set_speech(enabled: bool) -> void:
	speech = enabled
	if not enabled:
		Audio.stop_speech()  # whatever is mid-sentence stops there
	save()
	changed.emit()


func set_touch(mode: String, scale: float, opacity: float, left_handed: bool) -> void:
	touch_mode = mode if TOUCH_MODES.has(mode) else "auto"
	touch_scale = clampf(scale, 0.7, 1.5)
	touch_opacity = clampf(opacity, 0.3, 1.0)
	touch_left_handed = left_handed
	save()
	changed.emit()


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply_fullscreen()
	save()


func set_skin(id: String) -> void:
	skin = id
	save()
	changed.emit()


func set_difficulty(mode: String) -> void:
	difficulty = mode if DIFFICULTIES.has(mode) else "standard"
	save()
	changed.emit()


func difficulty_hp() -> float:
	return DIFFICULTIES[difficulty][0]


func difficulty_damage() -> float:
	return DIFFICULTIES[difficulty][1]


func set_screen_shake(enabled: bool) -> void:
	screen_shake = enabled
	save()


func set_transitions(mode: String) -> void:
	transitions = mode if TRANSITIONS.has(mode) else "full"
	save()
	changed.emit()


func set_lighting(enabled: bool) -> void:
	lighting = enabled
	EventBus.lighting_changed.emit()
	save()


## Replaces the keyboard binding of an action with one physical key.
func bind_key(action: String, physical_keycode: int) -> void:
	keys[action] = physical_keycode
	_apply_keys()
	save()
	changed.emit()


func reset_keys() -> void:
	keys.clear()
	_apply_keys()
	save()
	changed.emit()


## Human-readable name of the primary keyboard key of an action.
func key_name(action: String) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			# headless and the browser cannot map a physical key to the layout's
			# own letter: the US name of the key is the next best thing
			if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
				return OS.get_keycode_string(event.physical_keycode)
			return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(event.physical_keycode))
	return "—"


func _apply_volume(bus: String) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volumes[bus], 0.0001)))
	AudioServer.set_bus_mute(index, volumes[bus] <= 0.0)


func _apply_fullscreen() -> void:
	if OS.has_feature("web") or OS.has_feature("mobile") or DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


## Project defaults first, then the player's overrides on top.
func _apply_keys() -> void:
	InputMap.load_from_project_settings()
	for action in keys:
		if not InputMap.has_action(action):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				InputMap.action_erase_event(action, event)
		var key := InputEventKey.new()
		key.physical_keycode = keys[action]
		InputMap.action_add_event(action, key)


func _detect_locale() -> String:
	var system := OS.get_locale()  # e.g. "uk_UA", "zh_Hans_CN"
	for code in LOCALES:
		if system.begins_with(code):
			return code
	if system.begins_with("zh"):
		return "zh_CN"
	return "en"
