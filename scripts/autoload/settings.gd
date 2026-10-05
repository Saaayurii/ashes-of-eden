extends Node
## Persistent player settings (user://settings.cfg): locale, audio, display,
## key bindings. Applied on startup and whenever changed from the settings menu.

signal changed
## The player picked up the other device (a pad after the keyboard, or back):
## prompts that name a button read key_name() again.
signal device_changed

const PATH := "user://settings.cfg"
## Order matters: this is the order shown in the language selector.
const LOCALES := ["en", "ru", "uk", "zh_CN"]
const BUSES := ["Master", "Music", "SFX"]
## Actions the player may rebind, in menu order.
const BINDABLE_ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "block", "dash", "heal", "skill", "interact", "pause"]
## How the hands sit (Settings.control_scheme), in menu order: "keyboard" is
## the project's own map (both hands on the keys: WASD + J/K/L), "mouse" the
## left hand on WASD and the right on the mouse — MOUSE_LAYOUT replaces the
## keyboard and mouse half of the map, the hero turns to the cursor when he
## swings, casts or guards (mouse_aims), and the cursor is a crosshair in play.
## Each scheme keeps its own rebinds; a pad and the touch pad are never touched.
const CONTROL_SCHEMES := ["keyboard", "mouse"]
## A binding is one int: a key's physical keycode, or minus a mouse button's
## index (MOUSE_BUTTON_LEFT = 1 → -1). The first of an action's list is the one
## a prompt names and the one a rebind replaces.
const MOUSE_LAYOUT := {
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
	"jump": [KEY_SPACE, KEY_W], "attack": [-MOUSE_BUTTON_LEFT], "block": [-MOUSE_BUTTON_RIGHT],
	"dash": [KEY_SHIFT], "heal": [KEY_R], "skill": [KEY_Q, -MOUSE_BUTTON_MIDDLE],
	"interact": [KEY_E], "pause": [KEY_ESCAPE],
}
## Mouse buttons a binding may use: not the wheel, whose "press" has no release.
const MOUSE_BINDABLE := [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]
const MOUSE_NAMES := {MOUSE_BUTTON_LEFT: "MOUSE_LEFT", MOUSE_BUTTON_RIGHT: "MOUSE_RIGHT", MOUSE_BUTTON_MIDDLE: "MOUSE_MIDDLE",
	MOUSE_BUTTON_XBUTTON1: "MOUSE_BACK", MOUSE_BUTTON_XBUTTON2: "MOUSE_FORWARD"}
## Difficulty modes: enemy HP and damage only. Never story or loot (docs/BALANCE.md).
const DIFFICULTIES := {"pilgrim": [0.8, 0.75], "standard": [1.0, 1.0], "judgment": [1.25, 1.35]}
## How much of the curtain between places a player wants to sit through on
## their fifth night: the whole card, a brisk one, or a plain cut. In menu order.
const TRANSITIONS := ["full", "short", "off"]
## On-screen controls: "auto" = phones, tablets and mobile browsers only.
const TOUCH_MODES := ["auto", "on", "off"]
## Story text, hints and toasts, on top of what a touch screen already adds.
const TEXT_SIZES := {"normal": 1.0, "large": 1.25, "largest": 1.5}
## "reduced" dims every flash of light, the white of a blow and the red at the
## screen's edge when hurt: for eyes that flashing tires or worse.
const FLASHES := ["full", "reduced"]
## The whole night slowed (Settings.game_speed, Juice.base_scale): an assist,
## like the auto swing — enemies, wind-ups, the hero, all of it at once.
const GAME_SPEEDS := [1.0, 0.9, 0.8, 0.7, 0.6]

var locale: String = "en"
var volumes := {"Master": 1.0, "Music": 0.8, "SFX": 1.0}
var fullscreen := false
var screen_shake := true
## 2D lights and the night tint of the rooms. Off = the flat look, for weak GPUs.
var lighting := true
var text_size := "normal"
var flashes := "full"
## The assist swing: the sword comes out by itself at an awake enemy in reach
## (Player._auto_swing). Off by default; the casual way to play on a phone.
var auto_attack := false
## Numbers over the struck (Fx.damage_number). Off for a quieter screen: the
## blow still flashes, staggers and sounds, only the figure is not drawn.
var damage_numbers := true
## Block by toggling, not holding (Player): an assist for hands that tire.
var block_toggle := false
## One of GAME_SPEEDS. Never online (both bodies must run one clock) and never
## in the night of the day (every player is measured on the same one): time_scale().
var game_speed := 1.0
var difficulty := "standard"
var vial := 0
## Whether a new night may draw an omen (data/omens); the night of the day
## draws the day's own whatever this says, so every player meets the same.
var omens := true
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
var control_scheme := "keyboard"
## With the mouse scheme: the hero turns to the cursor for a swing, a skill and
## a guard. Off leaves the mouse as plain buttons and the stick as the only aim.
var mouse_aim := true
## action -> binding (see MOUSE_LAYOUT) of the primary key or button, per
## scheme: keys for "keyboard", mouse_keys for "mouse". Gamepad bindings stay
## as in project.godot.
var keys: Dictionary = {}
var mouse_keys: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the pad is noticed in the pause menu too (_input)
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	locale = cfg.get_value("general", "locale", _detect_locale())
	for bus in BUSES:
		volumes[bus] = clampf(float(cfg.get_value("audio", bus.to_lower(), volumes[bus])), 0.0, 1.0)
	fullscreen = cfg.get_value("video", "fullscreen", false)
	screen_shake = cfg.get_value("video", "screen_shake", true)
	lighting = cfg.get_value("video", "lighting", true)
	text_size = str(cfg.get_value("access", "text_size", "normal"))
	if not TEXT_SIZES.has(text_size):
		text_size = "normal"
	auto_attack = bool(cfg.get_value("access", "auto_attack", false))
	damage_numbers = bool(cfg.get_value("access", "damage_numbers", true))
	flashes = str(cfg.get_value("access", "flashes", "full"))
	if not FLASHES.has(flashes):
		flashes = "full"
	difficulty = cfg.get_value("game", "difficulty", "standard")
	vial = clampi(int(cfg.get_value("game", "vial", 0)), 0, 5)
	omens = bool(cfg.get_value("game", "omens", true))
	block_toggle = bool(cfg.get_value("access", "block_toggle", false))
	game_speed = float(cfg.get_value("access", "game_speed", 1.0))
	if not GAME_SPEEDS.has(game_speed):
		game_speed = 1.0
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
	control_scheme = str(cfg.get_value("controls", "scheme", "keyboard"))
	if not CONTROL_SCHEMES.has(control_scheme):
		control_scheme = "keyboard"
	mouse_aim = bool(cfg.get_value("controls", "mouse_aim", true))
	for action in BINDABLE_ACTIONS:
		if cfg.has_section_key("keys", action):
			keys[action] = int(cfg.get_value("keys", action))
		if cfg.has_section_key("keys_mouse", action):
			mouse_keys[action] = int(cfg.get_value("keys_mouse", action))
	_make_crosshair()
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
	cfg.set_value("access", "text_size", text_size)
	cfg.set_value("access", "flashes", flashes)
	cfg.set_value("access", "auto_attack", auto_attack)
	cfg.set_value("access", "damage_numbers", damage_numbers)
	cfg.set_value("access", "game_speed", game_speed)
	cfg.set_value("access", "block_toggle", block_toggle)
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("game", "vial", vial)
	cfg.set_value("game", "omens", omens)
	cfg.set_value("game", "skin", skin)
	cfg.set_value("game", "transitions", transitions)
	cfg.set_value("touch", "mode", touch_mode)
	cfg.set_value("touch", "scale", touch_scale)
	cfg.set_value("touch", "opacity", touch_opacity)
	cfg.set_value("touch", "left_handed", touch_left_handed)
	cfg.set_value("touch", "vibration", vibration)
	cfg.set_value("audio", "speech", speech)
	cfg.set_value("controls", "scheme", control_scheme)
	cfg.set_value("controls", "mouse_aim", mouse_aim)
	for action in keys:
		cfg.set_value("keys", action, keys[action])
	for action in mouse_keys:
		cfg.set_value("keys_mouse", action, mouse_keys[action])
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
	return (1.3 if touch_enabled() else 1.0) * float(TEXT_SIZES.get(text_size, 1.0))


func set_text_size(size: String) -> void:
	text_size = size if TEXT_SIZES.has(size) else "normal"
	save()
	changed.emit()


## How much of a flash to show: 1 in full, a third when reduced (Fx.flash,
## the white of a hit, the hurt vignette).
func flash_scale() -> float:
	return 0.35 if flashes == "reduced" else 1.0


## How fast a night runs: game_speed, except online and in the night of the day.
## A tool script (`godot -s`) runs at full speed unless it asks ([param in_tools]):
## its timings are measured, and the setting on disk is whoever ran it last.
func time_scale(in_tools := false) -> float:
	if Net.active or Game.daily != "":
		return 1.0
	var args := OS.get_cmdline_args()
	if not in_tools and (args.has("-s") or args.has("--script")):
		return 1.0
	return game_speed


func set_block_toggle(enabled: bool) -> void:
	block_toggle = enabled
	save()
	changed.emit()


func set_game_speed(speed: float) -> void:
	game_speed = speed if GAME_SPEEDS.has(speed) else 1.0
	save()
	changed.emit()


func set_damage_numbers(enabled: bool) -> void:
	damage_numbers = enabled
	save()
	changed.emit()


func set_auto_attack(enabled: bool) -> void:
	auto_attack = enabled
	save()
	changed.emit()


func set_flashes(mode: String) -> void:
	flashes = mode if FLASHES.has(mode) else "full"
	save()
	changed.emit()


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


func set_omens(enabled: bool) -> void:
	omens = enabled
	save()
	changed.emit()


## The vial of wrath the next night is played under (scripts/run/vials.gd);
## Vials.for_new_night holds it to what the profile has opened.
func set_vial(tier: int) -> void:
	vial = clampi(tier, 0, 5)
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
	bind(action, physical_keycode)


## Rebinds [param action] in the scheme in hand to one key (a physical keycode)
## or mouse button (minus its index). Another bindable action that had it as
## its primary gets this one's old primary instead, so no two actions ever
## fight over a key and nothing is left unbound.
func bind(action: String, binding: int) -> void:
	if binding == 0 or (binding < 0 and not MOUSE_BINDABLE.has(-binding)):
		return
	var map := overrides()
	var old := primary(action)
	for other in BINDABLE_ACTIONS:
		if other != action and primary(other) == binding and old != 0:
			map[other] = old
	map[action] = binding
	_apply_keys()
	save()
	changed.emit()


## The binding a key or button press would make (see MOUSE_LAYOUT), or 0 for
## an event a binding cannot use (the wheel, a pad, a key with no position).
static func binding_of(event: InputEvent) -> int:
	if event is InputEventKey:
		var key := event as InputEventKey
		return int(key.physical_keycode) if key.physical_keycode != KEY_NONE else int(key.keycode)
	if event is InputEventMouseButton and MOUSE_BINDABLE.has((event as InputEventMouseButton).button_index):
		return -int((event as InputEventMouseButton).button_index)
	return 0


## The first key or mouse button of an action as the map stands, or 0.
func primary(action: String) -> int:
	if not InputMap.has_action(action):
		return 0
	for event in InputMap.action_get_events(action):
		var binding := binding_of(event)
		if binding != 0:
			return binding
	return 0


## The rebinds of the scheme in hand.
func overrides() -> Dictionary:
	return mouse_keys if control_scheme == "mouse" else keys


## Back to the scheme's own layout (only the scheme in hand).
func reset_keys() -> void:
	overrides().clear()
	_apply_keys()
	save()
	changed.emit()


func set_control_scheme(scheme: String) -> void:
	if not CONTROL_SCHEMES.has(scheme):
		return
	control_scheme = scheme
	_apply_keys()
	save()
	changed.emit()


func set_mouse_aim(enabled: bool) -> void:
	mouse_aim = enabled
	save()
	changed.emit()


## Whether the hero turns to the cursor now: the mouse scheme with aiming on,
## and the player's hand on the keyboard and mouse rather than a pad or glass.
func mouse_aims() -> bool:
	return control_scheme == "mouse" and mouse_aim and not using_pad and not touch_enabled()


## Human-readable name of the primary keyboard key of an action.
## Xbox names for the pad's buttons (JoyButton order): what a prompt shows
## while the player is on a pad — any pad, the layout Godot maps them to.
const PAD_BUTTONS := ["A", "B", "X", "Y", "View", "Guide", "Menu", "LS", "RS", "LB", "RB",
	"D-Up", "D-Down", "D-Left", "D-Right"]
## The device the player last pressed something on (Settings.device_changed).
var using_pad := false


func _process(_delta: float) -> void:
	_update_cursor()


func _input(event: InputEvent) -> void:
	var pad := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5)
	var other := event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch
	if (pad and not using_pad) or (other and using_pad):
		using_pad = pad
		device_changed.emit()


## The name of the button that does [param action] on the device in hand: a
## pad's button while the player is on a pad and the action has one, else the
## key. [param on_pad] false asks for the key whatever is in hand (rebinding).
func key_name(action: String, on_pad := true) -> String:
	if on_pad and using_pad:
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton:
				var index := int((event as InputEventJoypadButton).button_index)
				return PAD_BUTTONS[index] if index < PAD_BUTTONS.size() else "#%d" % index
			if event is InputEventJoypadMotion:
				var axis := int((event as InputEventJoypadMotion).axis)
				return "LT" if axis == JOY_AXIS_TRIGGER_LEFT else ("RT" if axis == JOY_AXIS_TRIGGER_RIGHT else ("LS" if axis < 2 else "RS"))
	var binding := primary(action)
	return binding_name(binding) if binding != 0 else "—"


## What a binding is called: a mouse button by its short name, a key by the
## letter the player's own layout prints on it.
func binding_name(binding: int) -> String:
	if binding < 0:
		return tr(MOUSE_NAMES[-binding]) if MOUSE_NAMES.has(-binding) else "M%d" % -binding
	# headless and the browser cannot map a physical key to the layout's own
	# letter: the US name of the key is the next best thing
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return OS.get_keycode_string(binding)
	return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(binding))


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


## Project defaults first, then the scheme's layout, then the player's
## rebinds of that scheme on top. Pad events are never touched.
func _apply_keys() -> void:
	InputMap.load_from_project_settings()
	if control_scheme == "mouse":
		for action in MOUSE_LAYOUT:
			_set_bindings(action, MOUSE_LAYOUT[action])
	var map := overrides()
	for action in map:
		_set_bindings(action, [int(map[action])])


## Replaces the key and mouse half of an action with [param bindings], in order.
func _set_bindings(action: String, bindings: Array) -> void:
	if not InputMap.has_action(action):
		return
	for event in InputMap.action_get_events(action):
		if event is InputEventKey or event is InputEventMouseButton:
			InputMap.action_erase_event(action, event)
	for binding in bindings:
		var event: InputEvent
		if int(binding) < 0:
			var button := InputEventMouseButton.new()
			button.button_index = (-int(binding)) as MouseButton
			event = button
		else:
			var key := InputEventKey.new()
			key.physical_keycode = int(binding) as Key
			event = key
		event.device = -1  # every keyboard and mouse, as project.godot has them
		InputMap.action_add_event(action, event)


## The crosshair the mouse scheme shows in play (CURSOR_CROSS). Drawn here,
## pale bone with a dark rim so it reads on the night and on fire alike.
func _make_crosshair() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("mobile"):
		return
	var size := 21
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size / 2
	var ink := Color(0.95, 0.88, 0.7)
	var rim := Color(0.08, 0.05, 0.05, 0.9)
	for pass_index in 2:
		var color := rim if pass_index == 0 else ink
		var grow := 1 if pass_index == 0 else 0
		for i in range(3, 8):  # four ticks with a gap round the centre
			for w in range(-grow, grow + 1):
				for point in [Vector2i(c - i, c + w), Vector2i(c + i, c + w), Vector2i(c + w, c - i), Vector2i(c + w, c + i)]:
					image.set_pixelv(point, color)
		for w in range(-grow, grow + 1):
			for h in range(-grow, grow + 1):
				image.set_pixel(c + w, c + h, color)
	Input.set_custom_mouse_cursor(image, Input.CURSOR_CROSS, Vector2(c, c))


var _cursor_shape := Input.CURSOR_ARROW


## The crosshair stands for the cursor only while a body of ours is ours to
## steer; menus, dialogue and the pause get the arrow back.
func _update_cursor() -> void:
	var shape := Input.CURSOR_ARROW
	if mouse_aims() and not get_tree().paused:
		for node in get_tree().get_nodes_in_group("player"):
			if (not Net.active or node.is_multiplayer_authority()) and bool(node.get("controls_enabled")):
				shape = Input.CURSOR_CROSS
				break
	if shape != _cursor_shape:
		_cursor_shape = shape
		Input.set_default_cursor_shape(shape)


func _detect_locale() -> String:
	var system := OS.get_locale()  # e.g. "uk_UA", "zh_Hans_CN"
	for code in LOCALES:
		if system.begins_with(code):
			return code
	if system.begins_with("zh"):
		return "zh_CN"
	return "en"
