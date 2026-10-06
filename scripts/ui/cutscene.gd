extends Control
class_name CutscenePlayer
## Plays a cutscene from res://data/cutscenes/<id>.json: a list of steps run
## in order (docs/DATA_FORMATS.md, Cutscenes). Letterbox bars, a fade, a camera
## of its own that borrows the room's limits, and a "Skip" hint; the actors are
## the bodies already in the room ("player", "boss", "npc:<id>", "door").
##
## The rule from docs/CORE_LOOP.md: a scene never takes the controls without
## giving them back within seconds, and any button skips it. Skipping is not a
## cut to black: every remaining step is applied instantly (the boss lands
## where it was going, the camera comes home, the bars slide off), so the
## world after a skipped scene is the world after a watched one.
##
## A scene is cinema while it holds the controls: the HUD steps out (the
## touch pad dims), a dialogue with a "cast" cuts the camera to whoever is
## speaking and lets it creep in, a boss is named by a title card, a painted
## panel drifts, and a flash or a burst of ash can land on a beat. Skipping
## takes two presses (the first one only says how), so a thumb still on the
## jump button from the room before does not throw the scene away; the Skip
## button itself still answers at once.
##
## Online (docs/MULTIPLAYER.md) the host starts a scene on every peer; each
## peer plays and skips its own. Actor moves are only applied where the actor
## is simulated — the boss by the host, a body by its owner — and reach the
## other side through the usual synchronizers.

signal finished(cutscene_id: String)

## How a conversation with choices is run. The run sets this so that online
## one player answers for both (Run._story); empty = the dialogue box directly.
var story_hook := Callable()

## Height of one letterbox bar as a share of the screen.
const BAR := 0.1
const SKIP_ACTIONS := ["jump", "attack", "interact", "pause", "ui_cancel", "ui_accept"]
## How long the first skip press waits for the second.
const SKIP_CONFIRM := 2.5
## What the HUD and the touch pad fade to while a scene holds the controls.
const CINEMA_ALPHA := {"HUD": 0.0, "TouchControls": 0.3}
## A cast shot: how long the cut to a speaker takes, then how far and how
## slowly the camera keeps creeping in on them.
const SHOT_TIME := 0.55
const SHOT_CREEP := 0.045
const SHOT_CREEP_TIME := 6.0
const FX_KINDS := ["ash", "sparkle", "dust", "puff", "light", "debris"]

var playing := ""

var _skipped := false
var _aborted := false
var _dialogue_id := ""
var _bars: Array[ColorRect] = []
var _panel: TextureRect
var _fade: ColorRect
var _hint: Button
var _camera: Camera2D
var _tweens: Array[Tween] = []
var _held_player: Player
## Where each move step was heading, so a skip lands the body there and not
## "by" the offset again from wherever the tween was killed.
var _goals := {}
var _skip_armed := 0.0
## Watched before (Profile.scene_seen): one press skips, no confirmation.
var _seen_before := false
var _flash: ColorRect
var _title: Control
var _title_name: Label
var _title_sub: Label
var _title_rule: ColorRect
var _cinema := false
var _cinema_tweens := {}
## speaker key -> actor, while a dialogue with a "cast" runs.
var _cast := {}
var _shot_zoom := 1.0
var _shot_tween: Tween
## Something in the dark (the "presence" step): a glow above the fade, pinned
## to a point in the room, breathing.
var _presence: TextureRect
var _presence_at := Vector2.ZERO
var _presence_strength := 0.0
var _presence_clock := 0.0
## Two slits in the glow's heart, so it reads as somebody, not a lamp.
var _presence_eyes: TextureRect


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_FULL_RECT)
	_panel = TextureRect.new()
	_panel.mouse_filter = MOUSE_FILTER_IGNORE
	_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_panel.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_panel.set_anchors_preset(PRESET_FULL_RECT)
	_panel.visible = false
	add_child(_panel)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_fade)
	_presence = TextureRect.new()
	_presence.mouse_filter = MOUSE_FILTER_IGNORE
	_presence.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_presence.visible = false
	add_child(_presence)
	_presence_eyes = TextureRect.new()
	_presence_eyes.mouse_filter = MOUSE_FILTER_IGNORE
	_presence_eyes.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_presence_eyes.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_presence.add_child(_presence_eyes)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_flash)
	_build_title()
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(PRESET_TOP_WIDE if top else PRESET_BOTTOM_WIDE)
		add_child(bar)
		_bars.append(bar)
	# A real button, not a caption: it has to answer a click whatever the
	# attack key is bound to, and it names the key that does the same.
	_hint = Button.new()
	_hint.flat = true
	_hint.focus_mode = Control.FOCUS_NONE
	_hint.mouse_filter = MOUSE_FILTER_STOP
	_hint.add_theme_font_size_override("font_size", 8)
	_hint.add_theme_color_override("font_color", Color(0.85, 0.82, 0.78, 0.8))
	_hint.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.7, 1.0))
	_hint.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	_hint.grow_horizontal = GROW_DIRECTION_BEGIN
	_hint.grow_vertical = GROW_DIRECTION_BEGIN
	_hint.offset_left = -110
	_hint.offset_top = -18
	_hint.offset_right = -6
	_hint.offset_bottom = -3
	_hint.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.visible = false
	_hint.pressed.connect(_skip)
	add_child(_hint)
	_set_bars(0.0)


## The boss's name in the upper third (clear of the body the camera is on),
## a thin gold rule, its epithet, over a soft dark band so a busy painting
## behind does not swallow the small line.
const TITLE_Y := {"top": 0.27, "bottom": 0.78}
var _title_parts: Array[Control] = []


func _build_title() -> void:
	var title := Control.new()
	title.mouse_filter = MOUSE_FILTER_IGNORE
	title.set_anchors_preset(PRESET_FULL_RECT)
	var band := TextureRect.new()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	gradient.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0)])
	var fill := GradientTexture2D.new()
	fill.gradient = gradient
	fill.width = 64
	fill.height = 4
	band.texture = fill
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.mouse_filter = MOUSE_FILTER_IGNORE
	band.anchor_left = 0.15
	band.anchor_right = 0.85
	band.anchor_top = TITLE_Y.top
	band.anchor_bottom = TITLE_Y.top
	band.offset_top = -30
	band.offset_bottom = 30
	title.add_child(band)
	var box := VBoxContainer.new()
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.anchor_top = TITLE_Y.top
	box.anchor_bottom = TITLE_Y.top
	box.grow_vertical = GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	title.add_child(box)
	var scale := Settings.text_scale()
	_title_name = Label.new()
	_title_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_name.add_theme_font_size_override("font_size", int(26 * scale))
	_title_name.add_theme_color_override("font_color", Color(0.96, 0.89, 0.74))
	_title_name.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.03, 0.9))
	_title_name.add_theme_constant_override("outline_size", 6)
	box.add_child(_title_name)
	_title_rule = ColorRect.new()
	_title_rule.color = Color(0.86, 0.68, 0.36, 0.85)
	_title_rule.custom_minimum_size = Vector2(180, 1)
	_title_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_title_rule.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(_title_rule)
	_title_sub = Label.new()
	_title_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_sub.add_theme_font_size_override("font_size", int(12 * scale))
	_title_sub.add_theme_color_override("font_color", Color(0.93, 0.8, 0.6))
	_title_sub.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.03, 0.95))
	_title_sub.add_theme_constant_override("outline_size", 4)
	box.add_child(_title_sub)
	title.visible = false
	_title_parts = [band, box]
	_title = title
	add_child(_title)


func _exit_tree() -> void:
	if playing.is_empty():
		return
	# Awaited steps can resume after their owner leaves the tree. Restore
	# controls here, while the actors and dialogue groups are still available.
	abort()
	_camera_home(true)
	_release()
	playing = ""
	_dialogue_id = ""


func _input(event: InputEvent) -> void:
	if playing == "" or _skipped:
		return
	# A click on the Skip button is the button's: it skips at once.
	if event is InputEventMouseButton and _hint.visible \
			and _hint.get_global_rect().has_point((event as InputEventMouseButton).position):
		return
	for action in SKIP_ACTIONS:
		if event.is_action_pressed(action):
			get_viewport().set_input_as_handled()
			if _skip_armed > 0.0 or _seen_before:
				_skip()
			else:
				_arm_skip()
			return


func _process(delta: float) -> void:
	if _presence.visible:
		_presence_clock += delta
		var screen := get_viewport().get_canvas_transform() * _presence_at
		_presence.position = screen - _presence.size / 2.0
		_presence.modulate.a = _presence_strength * (0.72 + 0.28 * sin(_presence_clock * 2.1))
	if _skip_armed > 0.0:
		_skip_armed -= delta
		if _skip_armed <= 0.0:
			_disarm_skip()


## The first press: the hint lights up and says a second press will skip.
func _arm_skip() -> void:
	_skip_armed = SKIP_CONFIRM
	_hint.text = "%s  [%s]" % [tr("CUTSCENE_SKIP_AGAIN"), Settings.key_name("jump")]
	_hint.modulate = Color(1.25, 1.15, 0.95, 1.0)


func _disarm_skip() -> void:
	_skip_armed = 0.0
	_hint.text = "%s  [%s]" % [tr("CUTSCENE_SKIP"), Settings.key_name("jump")]
	_hint.modulate = Color(1, 1, 1, 0.6)


## Whether a skip press is waiting for its second (for tests and the HUD).
func skip_armed() -> bool:
	return _skip_armed > 0.0


func _skip() -> void:
	if playing == "" or _skipped:
		return
	_skipped = true
	var box := get_tree().get_first_node_in_group("dialogue_box") as DialogueBox
	if box != null:
		box.skip()


## Runs the scene to its end (or to the skip) and returns.
func play(cutscene_id: String) -> void:
	if playing != "":
		# The room changed under the last scene (run.gd aborts it): let it run
		# out its remaining steps and then play ours. Dropping the new one here
		# is how a boss used to arrive with no arrival.
		abort()
		var frames := 0
		while playing != "" and frames < 240 and is_inside_tree():
			frames += 1
			await get_tree().process_frame
		if not is_inside_tree():
			return
		if playing != "":
			push_warning("Cutscene %s would not end, ignoring %s" % [playing, cutscene_id])
			return
	var spec: Dictionary = Data.cutscenes.get(cutscene_id, {})
	if spec.is_empty():
		push_error("Unknown cutscene: %s" % cutscene_id)
		return
	playing = cutscene_id
	_skipped = false
	_aborted = false
	_dialogue_id = ""
	_goals.clear()
	_seen_before = Profile.scene_seen(cutscene_id)
	_disarm_skip()
	_hint.visible = true
	EventBus.cutscene_started.emit(cutscene_id)
	var steps: Array = spec.get("steps", [])
	var index := 0
	while index < steps.size() and not _skipped and is_inside_tree():
		if _passes(steps[index]):
			await _run(steps[index], false)
		index += 1
	if not is_inside_tree():
		return  # an awaited dialogue outlived the room/session that owned it
	if _skipped and not _aborted:
		_kill_tweens()
		while index < steps.size() and is_inside_tree():
			if _passes(steps[index]):
				await _run(steps[index], true)
			index += 1
	if not is_inside_tree():
		return
	_hint.visible = false
	_release()
	_camera_home(true)
	_set_bars(0.0)
	_panel.visible = false
	_panel.texture = null
	_reset_beats()
	playing = ""
	if not _aborted:
		Profile.record_scene(cutscene_id)
		finished.emit(cutscene_id)
		EventBus.cutscene_finished.emit(cutscene_id)


## The fade is the one thing a scene can leave behind; whoever loads the next
## room clears it.
func clear() -> void:
	_fade.color.a = 0.0
	_panel.visible = false
	_panel.texture = null
	_reset_beats()


## What a beat can leave on screen: a title, a flash, a cast on the camera.
func _reset_beats() -> void:
	_title.visible = false
	_presence.visible = false
	_flash.color.a = 0.0
	_cast.clear()
	_skip_armed = 0.0
	_panel.scale = Vector2.ONE
	_panel.position = Vector2.ZERO
	var box := _dialogue_box()
	if box != null and box.line_shown.is_connected(_on_line):
		box.line_shown.disconnect(_on_line)


func skipping() -> bool:
	return _skipped


## Cut the running scene short from outside (the room is changing under it).
func abort() -> void:
	if playing != "":
		_aborted = true
		_skipped = true
		_kill_tweens()
		_panel.visible = false
		_title.visible = false
		_flash.color.a = 0.0
		var box := get_tree().get_first_node_in_group("dialogue_box") as DialogueBox
		if box != null and box.is_playing(_dialogue_id):
			box.skip()


# ------------------------------------------------------------------ steps ---

## A step can wait on the story: "if" / "unless" name a flag (or a list, all
## of them), "path" the way the run leans (Game.dominant_path). Read when the
## step is reached, so a choice made earlier in the same scene counts.
func _passes(step: Dictionary) -> bool:
	for flag in _flags(step.get("if", [])):
		if not Game.flags.has(flag):
			return false
	for flag in _flags(step.get("unless", [])):
		if Game.flags.has(flag):
			return false
	if step.has("path") and Game.dominant_path() != str(step.path):
		return false
	return true


static func _flags(value: Variant) -> Array:
	return value if value is Array else ([] if str(value) == "" else [str(value)])


## One step, either played out or applied instantly (a skip).
func _run(step: Dictionary, instant: bool) -> void:
	var seconds := 0.0 if instant else float(step.get("time", 0.0))
	match str(step.get("do", "")):
		"hold":
			_hold()
		"release":
			_release()
		"letterbox":
			_tween_bars(BAR if step.get("on", true) else 0.0, seconds)
			if seconds > 0.0:
				await _sleep(seconds)
		"wait":
			if not instant:
				await _sleep(float(step.get("time", 0.5)))
		"camera":
			await _camera_to(step, seconds, instant)
		"move", "walk":
			await _move(step, seconds, instant)
		"anim":
			_anim(step)
		"face":
			var actor := _actor(str(step.get("who", "player")))
			if actor is Player:
				_turn(actor as Player, int(step.get("dir", 1)))
			elif actor is Enemy:
				(actor as Enemy).facing = int(step.get("dir", 1))
		"dialogue":
			await _dialogue(step, instant)
		"appear", "vanish":
			await _fade_actor(step, seconds, str(step.get("do")) == "vanish")
		"shake":
			if not instant:
				Juice.shake(float(step.get("strength", 4.0)))
		"sound":
			if not instant:
				Audio.play(StringName(str(step.get("name", ""))), float(step.get("volume", 0.0)))
		"music":
			Audio.music(StringName(str(step.get("name", ""))))
		"panel":
			await _show_panel(str(step.get("image", "")), seconds, step, instant)
		"panel_clear":
			await _hide_panel(seconds)
		"title":
			if not instant:
				await _show_title(step)
		"flash":
			if not instant:
				_flash_screen(step)
		"presence":
			_set_presence(step, seconds, instant)
		"fx":
			if not instant:
				_burst(step)
		"fade":
			var to := float(step.get("to", 1.0))
			_fade.color = Color(Color(str(step.get("color", "#000000"))), _fade.color.a)
			if instant or seconds <= 0.0:
				_fade.color.a = to
			else:
				var tween := _tween()
				tween.tween_property(_fade, "color:a", to, seconds)
				await _sleep(seconds)
		_:
			push_warning("Cutscene %s: unknown step %s" % [playing, step])


func _panel_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if not FileAccess.file_exists(path):
		return null
	var picture := Image.load_from_file(path)
	return null if picture.is_empty() else ImageTexture.create_from_image(picture)


func _show_panel(path: String, seconds: float, step := {}, instant := false) -> void:
	var texture := _panel_texture(path)
	if texture == null:
		push_warning("Cutscene %s: missing panel %s" % [playing, path])
		return
	_panel.texture = texture
	_panel.modulate.a = 0.0 if seconds > 0.0 else 1.0
	_panel.visible = true
	# A still painting drifts: a slow push in (and an optional pan) for as long
	# as it stays up, so the eye has somewhere to go while the words run.
	_panel.pivot_offset = size / 2.0
	_panel.scale = Vector2.ONE
	_panel.position = Vector2.ZERO
	var drift := float(step.get("drift", 0.05))
	if not instant and drift > 0.0:
		var pan: Array = step.get("pan", [0, 0])
		var drift_time := float(step.get("drift_time", 14.0))
		var tween := _tween()
		tween.set_parallel(true)
		tween.tween_property(_panel, "scale", Vector2.ONE * (1.0 + drift), drift_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(_panel, "position", Vector2(float(pan[0]), float(pan[1])), drift_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if seconds > 0.0:
		var tween := _tween()
		tween.tween_property(_panel, "modulate:a", 1.0, seconds)
		await _sleep(seconds)


func _hide_panel(seconds: float) -> void:
	if not _panel.visible:
		return
	if seconds > 0.0:
		var tween := _tween()
		tween.tween_property(_panel, "modulate:a", 0.0, seconds)
		await _sleep(seconds)
	_panel.visible = false
	_panel.texture = null
	_panel.scale = Vector2.ONE
	_panel.position = Vector2.ZERO


## A boss named on its arrival: "who" (the boss) gives its name and "epithet",
## or "name" / "subtitle" keys say it outright. Fades in, holds, fades out.
func _show_title(step: Dictionary) -> void:
	var actor := _actor(str(step.get("who", ""))) if step.has("who") else null
	var stats: Dictionary = actor.get("stats") if actor != null and actor.get("stats") is Dictionary else {}
	var name_key := str(step.get("name", stats.get("name", "")))
	var sub_key := str(step.get("subtitle", stats.get("epithet", "")))
	if name_key == "":
		return
	_title_name.text = tr(name_key)
	_title_sub.text = tr(sub_key) if sub_key != "" else ""
	_title_sub.visible = sub_key != ""
	_title_rule.custom_minimum_size.x = 0.0
	# "top" by default, clear of a boss standing on the floor; "bottom" for
	# one that hangs in the air where the top would cross it.
	var y: float = TITLE_Y.get(str(step.get("at", "top")), TITLE_Y.top)
	for part in _title_parts:
		part.anchor_top = y
		part.anchor_bottom = y
	_title.modulate.a = 0.0
	_title.visible = true
	if step.has("sound"):
		Audio.play(StringName(str(step.sound)), float(step.get("volume", -6.0)))
	var hold := float(step.get("time", 2.4))
	var tween := _tween()
	tween.set_parallel(true)
	tween.tween_property(_title, "modulate:a", 1.0, 0.6)
	tween.tween_property(_title_rule, "custom_minimum_size:x", 200.0, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(hold)
	tween.chain().tween_property(_title, "modulate:a", 0.0, 0.7)
	if step.get("wait", true):
		await _sleep(0.6 + hold + 0.7)
		_title.visible = false


## The whole screen goes one colour and fades back: a blow, a bell, a drop.
## Dimmed with the rest of the flashes (Settings.flash_scale).
func _flash_screen(step: Dictionary) -> void:
	var strength := float(step.get("strength", 0.7)) * Settings.flash_scale()
	if strength <= 0.0:
		return
	_flash.color = Color(Color(str(step.get("color", "#ffffff"))), strength)
	var tween := _tween()
	tween.tween_property(_flash, "color:a", 0.0, float(step.get("time", 0.45))).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# the painting behind catches the same light (scripts/rooms/backdrop_life.gd)
	EventBus.backdrop_flash.emit(strength, float(step.get("time", 0.45)), _flash.color)


## The dark looks back: a soft glow with a hot core, above the fade (a light
## in the room would be dimmed with it). "on": false lets it go.
func _set_presence(step: Dictionary, seconds: float, instant: bool) -> void:
	if not step.get("on", true):
		if instant or seconds <= 0.0:
			_presence.visible = false
			return
		var out := _tween()
		out.tween_property(self, "_presence_strength", 0.0, seconds)
		out.tween_callback(func() -> void: _presence.visible = false)
		return
	_presence_at = _position_of(step.get("at", "player"))
	var offset: Array = step.get("offset", [0, 0])
	_presence_at += Vector2(float(offset[0]), float(offset[1]))
	var color := Color(str(step.get("color", "#c0181a")))
	var radius := float(step.get("radius", 60.0))
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.45, 1.0])
	gradient.colors = PackedColorArray([color.lightened(0.5), color, Color(color, 0.35), Color(color, 0.0)])
	var glow := GradientTexture2D.new()
	glow.gradient = gradient
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1.0, 0.5)
	glow.width = 64
	glow.height = 64
	_presence.texture = glow
	_presence.size = Vector2.ONE * radius * 2.0
	var eyes := Image.create(14, 3, false, Image.FORMAT_RGBA8)
	var hot := color.lightened(0.75)
	for x in [2, 3, 10, 11]:
		eyes.set_pixel(x, 1, hot)
	for x in [1, 4, 9, 12]:
		eyes.set_pixel(x, 1, Color(hot, 0.55))  # slits, narrowing at the ends
	_presence_eyes.texture = ImageTexture.create_from_image(eyes)
	_presence_eyes.size = Vector2(28, 6)
	_presence_eyes.position = _presence.size / 2.0 - _presence_eyes.size / 2.0
	_presence_eyes.visible = step.get("eyes", true)
	_presence.visible = true
	_presence_clock = 0.0
	var strength := float(step.get("strength", 0.8))
	if instant or seconds <= 0.0:
		_presence_strength = strength
		return
	_presence_strength = 0.0
	var tween := _tween()
	tween.tween_property(self, "_presence_strength", strength, seconds)


## A one-shot effect at an actor or a point, through Fx like everything else.
func _burst(step: Dictionary) -> void:
	var at := _position_of(step.get("at", "player"))
	var offset: Array = step.get("offset", [0, 0])
	at += Vector2(float(offset[0]), float(offset[1]))
	var color := Color(str(step.get("color", "#d8c8a8")))
	var amount := int(step.get("amount", 14))
	match str(step.get("kind", "")):
		"ash":
			Fx.ash(at, color, amount, 40.0, 12.0)
		"sparkle":
			Fx.sparkle(at, color, amount, float(step.get("width", 18.0)))
		"dust":
			Fx.dust(at, Vector2.UP, amount, color)
		"puff":
			Fx.puff(at, float(step.get("scale", 1.0)), color)
		"debris":
			Fx.debris(at, color, amount)
		"light":
			Fx.flash(at, color, float(step.get("radius", 90.0)), float(step.get("time", 0.6)), float(step.get("energy", 1.2)))


## The HUD steps out while the scene has the controls and comes back with
## them; the touch pad only dims, so a thumb can still find Skip.
func _set_cinema(on: bool) -> void:
	if _cinema == on:
		return
	_cinema = on
	for node_name in CINEMA_ALPHA:
		var node := get_parent().get_node_or_null(node_name) as CanvasItem if get_parent() else null
		if node == null:
			continue
		if _cinema_tweens.has(node_name) and (_cinema_tweens[node_name] as Tween).is_valid():
			(_cinema_tweens[node_name] as Tween).kill()
		var tween := node.create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(node, "modulate:a", float(CINEMA_ALPHA[node_name]) if on else 1.0, 0.35)
		_cinema_tweens[node_name] = tween


func cinema() -> bool:
	return _cinema


## Hands off: the local body stops listening, every enemy holds its ground.
func _hold() -> void:
	_set_cinema(true)
	Game.cutscene = true
	var body := _local_player()
	if body != null:
		body.controls_enabled = false
		_held_player = body


func _release() -> void:
	_set_cinema(false)
	Game.cutscene = false
	if _held_player != null and is_instance_valid(_held_player):
		_held_player.controls_enabled = true
		_held_player.release_body()
	_held_player = null


## The scene's own camera, made on the first shot from the room's.
func _ensure_camera() -> bool:
	var home := _home()
	if home == null:
		return false
	if _camera == null:
		_camera = Camera2D.new()
		_camera.position_smoothing_enabled = false
		_camera.process_mode = Node.PROCESS_MODE_ALWAYS  # a cast shot runs under a paused panel
		for limit in ["limit_left", "limit_top", "limit_right", "limit_bottom"]:
			_camera.set(limit, home.get(limit))
		get_tree().current_scene.add_child(_camera)
		_camera.global_position = home.get_screen_center_position()
		_camera.zoom = home.zoom
		_camera.make_current()
	return true


## "to": an actor or a point; "between": two actors, framed together; an
## "offset" nudges either.
func _camera_to(step: Dictionary, seconds: float, instant: bool) -> void:
	var home := _home()
	if home == null or not _ensure_camera():
		return
	var target := str(step.get("to", "player"))
	var goal := home.get_screen_center_position() if target == "player" else _position_of(step.get("to", "player"))
	if target == "player" and not step.has("between"):
		var body := _local_player()
		if body != null:
			goal = body.global_position + home.position
	if step.has("between") and step.between is Array and step.between.size() == 2:
		goal = (_position_of(step.between[0]) + _position_of(step.between[1])) / 2.0 + Vector2(0, -10)
	if step.has("offset"):
		goal += Vector2(float(step.offset[0]), float(step.offset[1]))
	var zoom := Vector2.ONE * float(step.get("zoom", 1.0))
	if instant or seconds <= 0.0:
		_camera.global_position = goal
		_camera.zoom = zoom
		return
	var tween := _tween()
	tween.set_parallel(true)
	tween.tween_property(_camera, "global_position", goal, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_camera, "zoom", zoom, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _sleep(seconds)


## Give the room back to the player's camera, where it always was.
func _camera_home(_instant: bool) -> void:
	var home := _home()
	# leaving the scene mid-cutscene: the player's camera is already on its way out
	if home != null and home.is_inside_tree() and home.enabled:
		home.make_current()
		home.reset_smoothing()
	if is_instance_valid(_camera):
		_camera.queue_free()
	_camera = null


## A body slides (or walks) to a point, or by an offset. Only where the body
## is simulated: the other peers see it through the synchronizer.
func _move(step: Dictionary, seconds: float, instant: bool) -> void:
	var actor := _actor(str(step.get("who", "player")))
	if actor == null or not _simulated_here(actor):
		if not instant and seconds > 0.0:
			await _sleep(seconds)
		return
	var key := step.hash()
	var goal: Vector2 = actor.global_position
	if _goals.has(key):
		goal = _goals[key]
	elif step.has("to"):
		goal = _position_of(step.get("to"))
		if step.has("offset"):
			goal += Vector2(float(step.offset[0]), float(step.offset[1]))
	elif step.has("by"):
		goal = actor.global_position + Vector2(float(step.by[0]), float(step.by[1]))
	_goals[key] = goal
	var walking: bool = step.get("do") == "walk"
	if walking:
		goal.y = actor.global_position.y  # a walk stays on its floor
		_goals[key] = goal
		var dir := signf(goal.x - actor.global_position.x)
		if actor is Player and dir != 0.0:
			_turn(actor as Player, int(dir))
		var gait := "run" if step.get("run", false) else "walk"
		if actor is Player:
			(actor as Player).play_scripted(gait)  # held, or the idle loop takes it back
		elif actor.has_method("_play"):
			actor.call("_play", gait)
	if instant or seconds <= 0.0:
		actor.global_position = goal
	else:
		var tween := _tween()
		var ease_kind := Tween.EASE_OUT if step.get("ease", "in_out") == "out" else Tween.EASE_IN_OUT
		tween.tween_property(actor, "global_position", goal, seconds).set_trans(Tween.TRANS_SINE).set_ease(ease_kind)
		await _sleep(seconds)
	if not is_instance_valid(actor):
		return
	if walking and actor is Player:
		(actor as Player).play_scripted("idle")
	elif walking and actor.has_method("_play"):
		actor.call("_play", "idle")


func _anim(step: Dictionary) -> void:
	var actor := _actor(str(step.get("who", "player")))
	var animation := str(step.get("anim", "idle"))
	if actor is Player:
		(actor as Player).play_scripted(animation)  # the scene owns the body; release() hands it back
	elif actor is Enemy:
		(actor as Enemy)._play(animation, bool(step.get("hold", false)))


func _dialogue(step: Dictionary, instant: bool) -> void:
	var box := get_tree().get_first_node_in_group("dialogue_box") as DialogueBox
	if box == null or instant:
		return
	var id := str(step.get("id", ""))
	_dialogue_id = id
	var blocking: bool = Data.dialogues.get(id, {}).get("blocking", true)
	# A cast: each line cuts the camera to whoever says it (shot and reverse).
	_cast = step.get("cast", {}).duplicate()
	if not _cast.is_empty():
		_shot_zoom = float(step.get("zoom", _camera.zoom.x if _camera != null else 1.2))
		if not box.line_shown.is_connected(_on_line):
			box.line_shown.connect(_on_line)
	# While the panel is up the game is paused and this scene's own "Skip" could
	# not answer a click: hide it, the panel has a Skip of its own.
	_hint.visible = not blocking
	if blocking and story_hook.is_valid():
		await story_hook.call(id)  # choices: one answer for the whole session
		_dialogue_id = ""
	elif blocking or step.get("wait", true):
		await box.play(id)
		_dialogue_id = ""
	else:
		box.play(id)
	if step.get("wait", true) or blocking:
		_cast.clear()
		if box.line_shown.is_connected(_on_line):
			box.line_shown.disconnect(_on_line)
	_hint.visible = playing != ""


## A line from the cast: cut to the speaker and let the camera creep in.
func _on_line(speaker: String) -> void:
	if _skipped or not _cast.has(speaker) or not _ensure_camera():
		return
	var actor := _actor(str(_cast[speaker]))
	if actor == null:
		return
	var goal := actor.global_position + Vector2(0, -18)
	if _shot_tween != null and _shot_tween.is_valid():
		_shot_tween.kill()
	_shot_tween = _tween()
	_shot_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_shot_tween.set_parallel(true)
	_shot_tween.tween_property(_camera, "global_position", goal, SHOT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_shot_tween.tween_property(_camera, "zoom", Vector2.ONE * _shot_zoom, SHOT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_shot_tween.chain().tween_property(_camera, "zoom", Vector2.ONE * _shot_zoom * (1.0 + SHOT_CREEP), SHOT_CREEP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## A figure comes out of the dark, or goes back into it. "ash": true leaves a
## burst of ash where it stood (something struck down, not something leaving).
## A vanished NPC is gone for good; a vanished enemy is only hidden.
func _fade_actor(step: Dictionary, seconds: float, out: bool) -> void:
	var actor := _actor(str(step.get("who", "")))
	if actor == null:
		return
	if not out:
		actor.visible = true
	var target := 0.0 if out else 1.0
	if out and step.get("ash", false):
		Fx.ash(actor.global_position + Vector2(0, -16), Color(0.55, 0.5, 0.55), 26, 45.0, 12.0)
		Fx.puff(actor.global_position + Vector2(0, -12), 1.3, Color(0.6, 0.55, 0.6))
		Audio.play_at(&"enemy_death", actor.global_position)
	if seconds > 0.0:
		var tween := _tween()
		tween.tween_property(actor, "modulate:a", target, seconds)
		await _sleep(seconds)
	if not is_instance_valid(actor):
		return  # the room went away under the scene
	actor.modulate.a = target
	if out:
		if actor.is_in_group("npc"):
			actor.queue_free()
		else:
			actor.visible = false


# ------------------------------------------------------------------ helpers ---

func _turn(body: Player, dir: int) -> void:
	if dir == 0:
		return
	body.facing = dir
	body.body.flip_h = dir < 0
	body.hitbox.scale.x = dir * body.stats.attack_scale


func _dialogue_box() -> DialogueBox:
	return get_tree().get_first_node_in_group("dialogue_box") as DialogueBox if is_inside_tree() else null


func _sleep(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and not _skipped:
		await get_tree().process_frame
		if not is_inside_tree():
			return
		if not get_tree().paused:
			left -= get_process_delta_time()


func _tween() -> Tween:
	var tween := create_tween()
	_tweens.append(tween)
	return tween


func _kill_tweens() -> void:
	for tween in _tweens:
		if tween.is_valid():
			tween.kill()
	_tweens.clear()


func _tween_bars(share: float, seconds: float) -> void:
	if seconds <= 0.0:
		_set_bars(share)
		return
	var tween := _tween()
	tween.tween_method(_set_bars, _bars[0].size.y / maxf(size.y, 1.0), share, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_bars(share: float) -> void:
	var height := size.y * share
	_bars[0].offset_top = 0.0
	_bars[0].offset_bottom = height
	_bars[1].offset_top = -height
	_bars[1].offset_bottom = 0.0
	for bar in _bars:
		bar.visible = height > 0.5


func _local_player() -> Player:
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as Player
		if body != null and body._is_mine():
			return body
	return null


func _home() -> Camera2D:
	var body := _local_player()
	return body.camera if body != null else null


## "player", "boss", "npc:<id>", "door" → the node; anything else → null.
func _actor(who: String) -> Node2D:
	match who:
		"player":
			return _local_player()
		"boss":
			for node in get_tree().get_nodes_in_group("enemies"):
				var enemy := node as Enemy
				if enemy != null and enemy.stats.get("boss", false) and not enemy.is_dead():
					return enemy
			for node in get_tree().get_nodes_in_group("enemies"):
				var enemy := node as Enemy
				if enemy != null and enemy.stats.get("boss", false):
					return enemy  # dead bosses still have a place to look at
		"door":
			var room := get_tree().get_first_node_in_group("room") as Room
			return room.door if room != null else null
	if who.begins_with("npc:"):
		for node in get_tree().get_nodes_in_group("npc"):
			if node.get("npc_id") == who.substr(4):
				return node as Node2D
	return null


## A point: an actor name, or [x, y] in room coordinates.
func _position_of(where: Variant) -> Vector2:
	if where is Array and where.size() == 2:
		return Vector2(float(where[0]), float(where[1]))
	var actor := _actor(str(where))
	if actor == null:
		var body := _local_player()
		return body.global_position if body != null else Vector2.ZERO
	return actor.global_position + (Vector2(0, -12) if actor is Enemy else Vector2.ZERO)


func _simulated_here(actor: Node2D) -> bool:
	if not Net.active:
		return true
	if actor is Player:
		return (actor as Player).is_multiplayer_authority()
	return Net.is_server()
