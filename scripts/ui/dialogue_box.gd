extends Control
class_name DialogueBox
## Plays a data-driven dialogue from res://data/dialogues (see docs/DATA_FORMATS.md).
## Two modes:
##   blocking (default) – pauses the game, panel at the bottom, Continue/Skip/choices.
##   "blocking": false  – captions at the top while you keep playing; auto-advance,
##                        no choices allowed. Used for the first minutes so the
##                        player's hands never leave the controls.
## Always skippable: story is optional by design.
##
## A third look for talking to people (NPCs, on the interact key): no panel at
## all. Each line appears as a speech bubble over the head of whoever says it,
## types itself out, and waits; the answers float over Elian's head. Same
## dialogue data, same routers, choices and effects — only where it is drawn
## changes ([method play_bubble]).

signal _answered(choice)  # a choice Dictionary, or null for "continue"
signal _released  # the running dialogue has finished
## This screen answered: the choice index, or -1 for "continue". The run relays
## it to the other player so both see the same story (docs/MULTIPLAYER.md).
signal answered_locally(choice_index: int)

## Co-op: true on the screens that watch. The buttons are shown but dead, and
## the box waits for [method answer_remote] instead of for a click here.
var remote := false

var _skipped := false
var _busy := false
var _blocking := true
var _choices: Array = []

## Bubble mode: who is talking and who is listening, in the world. Null = panel.
var _speaker_body: Node2D
var _listener_body: Node2D
var _bubble: PanelContainer
var _bubble_name: Label
var _bubble_text: Label
var _bubble_hint: Label
var _bubble_tail: Polygon2D
var _answers: PanelContainer
var _answer_list: VBoxContainer
var _bubble_anchor: Node2D
var _typing: Tween

@onready var panel: Control = %Panel
@onready var caption: Label = %Caption
@onready var speaker_label: Label = %Speaker
@onready var text_label: Label = %Text
@onready var choices_box: VBoxContainer = %Choices
@onready var continue_button: Button = %Continue
@onready var skip_button: Button = %Skip


func _ready() -> void:
	if Settings.text_scale() != 1.0:
		for label in [caption, speaker_label, text_label]:
			var size: int = label.get_theme_font_size("font_size")
			label.add_theme_font_size_override("font_size", int(round(size * Settings.text_scale())))
	visible = false
	panel.visible = false
	caption.visible = false
	continue_button.pressed.connect(_on_continue)
	skip_button.pressed.connect(_on_skip)


## Speech bubble: how wide a line may get before it wraps, in screen pixels,
## and how far over the feet the head is (NPC origin is the sole, the player's
## is the middle of the body).
const BUBBLE_WIDTH := Vector2(64, 168)
const NPC_HEAD := 50.0
const PLAYER_HEAD := 34.0
## Characters typed per second; a line never takes longer than TYPE_MAX.
const TYPE_RATE := 55.0
const TYPE_MAX := 1.4


func _process(_delta: float) -> void:
	if _speaker_body != null:
		_place_bubbles()


func _input(event: InputEvent) -> void:
	if _in_bubbles() and visible and not remote:
		_bubble_input(event)
		return
	# Only the panel answers to Enter / Space. Captions have nothing to
	# continue, and swallowing the key here used to eat the Space a cutscene
	# listens for: its "Skip" looked dead.
	if visible and _blocking and panel.visible and not remote and continue_button.visible \
			and event.is_action_pressed("ui_accept"):
		_on_continue()
		get_viewport().set_input_as_handled()


func play(dialogue_id: String) -> void:
	if _busy:
		if _blocking:
			push_warning("Dialogue already running, ignoring %s" % dialogue_id)
			return
		_skipped = true  # captions yield to a real dialogue
		await _released
	var dialogue: Dictionary = Data.dialogues.get(dialogue_id, {})
	if dialogue.is_empty():
		push_error("Unknown dialogue: %s" % dialogue_id)
		return

	var blocking: bool = dialogue.get("blocking", true)
	_busy = true
	_blocking = blocking
	_skipped = false
	if blocking:
		Net.set_paused(true)
	visible = true
	panel.visible = blocking and not _in_bubbles()
	caption.visible = not blocking
	EventBus.dialogue_started.emit(dialogue_id)

	var nodes: Dictionary = dialogue.get("nodes", {})
	var node_id: String = dialogue.get("start", "")
	while node_id != "" and not _skipped:
		var node: Dictionary = nodes.get(node_id, {})
		if node.is_empty():
			push_error("Dialogue %s: missing node \"%s\"" % [dialogue_id, node_id])
			break
		if node.has("branches"):
			# A router: no text, just "where next" by story flags set earlier
			# (Game.flags). First matching branch wins; "next" is the fallback.
			node_id = node.get("next", "")
			for branch in node.branches:
				# "flag": a story flag set earlier; "path": the way the player leans
				# (Game.dominant_path(): grace / temptation / will).
				var by_flag: bool = branch.has("flag") and Game.flags.has(branch.flag)
				var by_path: bool = branch.has("path") and Game.dominant_path() == branch.path
				if by_flag or by_path:
					node_id = branch.get("next", "")
					break
			continue
		var choice = null
		# If somebody recorded this line in the language being played, it is
		# read out over the caption; if not, spoken is 0.0 and everything below
		# times itself the way it did before there was any voice at all.
		var spoken := Audio.speak(str(node.get("text", "")))
		if blocking and _in_bubbles():
			_show_bubble(node)
			choice = await _answered
		elif blocking:
			_show(node)
			choice = await _answered
		else:
			caption.text = "%s: %s" % [tr(node.get("speaker", "")), tr(node.get("text", ""))]
			# Frame-counted rather than a timer: freezes while the game is paused
			# (gift picker) and can be cut short by _skipped at any moment.
			# A caption never leaves before the voice reading it has finished.
			var remaining := maxf(_caption_seconds(caption.text), spoken + 0.35)
			while remaining > 0.0 and not _skipped:
				await get_tree().process_frame
				if not is_inside_tree():
					return
				if not get_tree().paused:
					remaining -= get_process_delta_time()
		if _skipped:
			break
		if choice == null:
			node_id = node.get("next", "")
		else:
			Game.apply_effect(choice.get("effect", {}))
			EventBus.choice_made.emit(dialogue_id, choice.get("id", ""))
			node_id = choice.get("next", "")

	# Skipping a scene must not leave a voice talking over the room it cut to.
	Audio.stop_speech()
	visible = false
	_hide_bubbles()
	if blocking:
		Net.set_paused(false)
	_busy = false
	_released.emit()
	EventBus.dialogue_finished.emit(dialogue_id)


# ---------------------------------------------------------------- bubbles ---

## Talk to somebody standing in the world: the lines go over their heads.
## [param speaker] says everything that is not Elian's; [param listener] is
## our body, and Elian's lines and the answers float over it.
func play_bubble(dialogue_id: String, speaker: Node2D, listener: Node2D) -> void:
	if is_blocking_open():
		return  # captions are fine: play() makes them yield
	_build_bubbles()
	_speaker_body = speaker
	_listener_body = listener
	await play(dialogue_id)
	_speaker_body = null
	_listener_body = null


func _in_bubbles() -> bool:
	return _speaker_body != null and is_instance_valid(_speaker_body)


func _build_bubbles() -> void:
	if _bubble != null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.07, 0.93)
	style.border_color = Color(0.62, 0.53, 0.4, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 4
	_bubble = PanelContainer.new()
	_bubble.add_theme_stylebox_override("panel", style)
	_bubble.mouse_filter = MOUSE_FILTER_STOP
	_bubble.gui_input.connect(_on_bubble_clicked)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	_bubble.add_child(column)
	_bubble_name = _small_label(7, Color(0.95, 0.8, 0.5))
	column.add_child(_bubble_name)
	_bubble_text = _small_label(8, Color(0.95, 0.93, 0.88))
	_bubble_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_bubble_text)
	_bubble_hint = _small_label(7, Color(0.8, 0.75, 0.65, 0.8))
	_bubble_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_bubble_hint)
	add_child(_bubble)
	_bubble_tail = Polygon2D.new()
	_bubble_tail.polygon = PackedVector2Array([Vector2(-4, 0), Vector2(4, 0), Vector2(0, 5)])
	_bubble_tail.color = style.bg_color
	add_child(_bubble_tail)
	_answers = PanelContainer.new()
	var answer_style := style.duplicate() as StyleBoxFlat
	answer_style.border_color = Color(0.75, 0.68, 0.55, 1.0)
	_answers.add_theme_stylebox_override("panel", answer_style)
	_answer_list = VBoxContainer.new()
	_answer_list.add_theme_constant_override("separation", 1)
	_answers.add_child(_answer_list)
	add_child(_answers)
	_hide_bubbles()


func _small_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", int(round(font_size * Settings.text_scale())))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = MOUSE_FILTER_IGNORE
	return label


func _hide_bubbles() -> void:
	if _bubble == null:
		return
	_bubble.visible = false
	_bubble_tail.visible = false
	_answers.visible = false


## One line over the head of whoever says it; the answers, if any, over Elian.
func _show_bubble(node: Dictionary) -> void:
	Audio.play(&"dialogue_blip")
	var speaker_key: String = node.get("speaker", "")
	_bubble_anchor = _listener_body if speaker_key == "SPEAKER_ELIAN" else _speaker_body
	_bubble_name.text = tr(speaker_key)
	var line := tr(node.get("text", ""))
	_bubble_text.text = line
	_bubble_text.custom_minimum_size.x = clampf(line.length() * 4.2, BUBBLE_WIDTH.x, BUBBLE_WIDTH.y)
	_bubble_text.visible_ratio = 0.0
	_bubble_hint.text = ""
	_choices = node.get("choices", [])
	# Same reason as in _show: gone from the tree before the new list exists.
	for child in _answer_list.get_children():
		_answer_list.remove_child(child)
		child.queue_free()
	_bubble.visible = true
	_bubble_tail.visible = true
	_answers.visible = false
	_bubble.reset_size()
	if _typing != null:
		_typing.kill()
	_typing = create_tween()
	_typing.tween_property(_bubble_text, "visible_ratio", 1.0, minf(line.length() / TYPE_RATE, TYPE_MAX))
	_typing.tween_callback(_line_typed)
	_place_bubbles()


## The line is all there: now the key to go on, or the answers.
func _line_typed() -> void:
	_typing = null
	if _choices.is_empty():
		_bubble_hint.text = "%s ▸" % Settings.key_name("interact")
		return
	for index in _choices.size():
		var button := Button.new()
		button.text = "%d. %s" % [index + 1, tr(_choices[index].get("text", ""))]
		button.flat = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", int(round(8 * Settings.text_scale())))
		button.add_theme_color_override("font_color", Color(0.85, 0.82, 0.76))
		button.add_theme_color_override("font_focus_color", Color(1.0, 0.86, 0.5))
		button.add_theme_color_override("font_hover_color", Color(1.0, 0.86, 0.5))
		button.pressed.connect(_on_choice.bind(index))
		_answer_list.add_child(button)
	_answers.visible = true
	_answers.reset_size()
	_answer_list.get_child(0).grab_focus.call_deferred()
	_place_bubbles()


## Keep both bubbles over their heads and inside the screen, every frame:
## the camera may still be settling while somebody talks.
func _place_bubbles() -> void:
	if _bubble == null or not _bubble.visible or _bubble_anchor == null or not is_instance_valid(_bubble_anchor):
		return
	var canvas := get_viewport().get_canvas_transform()
	var screen := get_viewport_rect().size
	var head := _bubble_anchor.global_position - Vector2(0, NPC_HEAD if _bubble_anchor == _speaker_body else PLAYER_HEAD)
	var tip: Vector2 = canvas * head
	var bubble_size := _bubble.size
	var at := Vector2(tip.x - bubble_size.x / 2.0, tip.y - bubble_size.y - 5.0)
	at.x = clampf(at.x, 4.0, screen.x - bubble_size.x - 4.0)
	at.y = clampf(at.y, 4.0, screen.y - bubble_size.y - 4.0)
	_bubble.position = at
	_bubble_tail.position = Vector2(clampf(tip.x, at.x + 6.0, at.x + bubble_size.x - 6.0), at.y + bubble_size.y - 1.0)
	if _answers.visible and _listener_body != null and is_instance_valid(_listener_body):
		var own: Vector2 = canvas * (_listener_body.global_position - Vector2(0, PLAYER_HEAD))
		var answer_size := _answers.size
		var spot := Vector2(own.x - answer_size.x / 2.0, own.y - answer_size.y - 5.0)
		# never on top of the line being answered
		if Rect2(spot, answer_size).intersects(Rect2(at, bubble_size)):
			spot.y = at.y + bubble_size.y + 8.0
		spot.x = clampf(spot.x, 4.0, screen.x - answer_size.x - 4.0)
		spot.y = clampf(spot.y, 4.0, screen.y - answer_size.y - 4.0)
		_answers.position = spot


## Interact / Enter / Space: finish the typing, then go on. Escape skips the
## whole talk. Number keys pick an answer.
func _bubble_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_on_skip()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and not _choices.is_empty() and _typing == null:
		var number: int = (event as InputEventKey).keycode - KEY_1
		if number >= 0 and number < _choices.size():
			_on_choice(number)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_advance_bubble()
		get_viewport().set_input_as_handled()


func _on_bubble_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance_bubble()
		accept_event()


func _advance_bubble() -> void:
	if _typing != null:
		_typing.kill()
		_bubble_text.visible_ratio = 1.0
		_line_typed()
		return
	if _choices.is_empty():
		_on_continue()
	else:
		var focused := get_viewport().gui_get_focus_owner()
		if focused is Button and focused.get_parent() == _answer_list:
			(focused as Button).pressed.emit()


## Reading time: slow enough to read, short enough to not outstay the fight.
func _caption_seconds(text: String) -> float:
	return clampf(1.5 + text.length() * 0.05, 2.5, 6.0)


func _show(node: Dictionary) -> void:
	# One soft tick per line: the voice of a story told in captions.
	Audio.play(&"dialogue_blip")
	speaker_label.text = node.get("speaker", "")
	text_label.text = node.get("text", "")
	# Out of the tree now, not at the end of the frame: queue_free() alone
	# leaves the previous line's buttons visible and connected for one more
	# frame, and each is bound to an index into the _choices we are replacing.
	# A fast click — or an automated one — lands on the old button and reads
	# past the end of the new list.
	for child in choices_box.get_children():
		choices_box.remove_child(child)
		child.queue_free()
	_choices = node.get("choices", [])
	continue_button.visible = _choices.is_empty()
	continue_button.disabled = remote
	skip_button.disabled = remote
	for index in _choices.size():
		var button := Button.new()
		button.text = _choices[index].get("text", "")
		button.disabled = remote
		button.pressed.connect(_on_choice.bind(index))
		choices_box.add_child(button)
	if remote:
		return  # somebody else is holding the controller
	if _choices.is_empty():
		continue_button.grab_focus()
	else:
		choices_box.get_child(0).grab_focus()


func _on_choice(index: int) -> void:
	# A button that outlived the line it belonged to answers for a choice that
	# no longer exists. The buttons are removed from the tree now, so this
	# should not happen; ignoring it beats crashing the conversation if it does.
	if index < 0 or index >= _choices.size():
		return
	answered_locally.emit(index)
	_answered.emit(_choices[index])


func _on_continue() -> void:
	answered_locally.emit(-1)
	_answered.emit(null)


func _on_skip() -> void:
	_skipped = true
	answered_locally.emit(-1)
	_answered.emit(null)


## Whether a dialogue is on screen in any form (panel, captions or bubbles).
func is_open() -> bool:
	return _busy


## A conversation that holds the game (panel or bubbles). Captions do not count:
## they run over play, and a real talk pushes them aside.
func is_blocking_open() -> bool:
	return _busy and _blocking


## Cut the running dialogue short from outside (a skipped cutscene).
func skip() -> void:
	if _busy:
		_on_skip()


## The other player answered: replay it here so both stories stay in step.
func answer_remote(choice_index: int) -> void:
	if not _busy:
		return
	if choice_index < 0 or choice_index >= _choices.size():
		_answered.emit(null)
	else:
		_answered.emit(_choices[choice_index])
