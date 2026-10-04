extends CanvasLayer
## The curtain: what the player looks at between one place and the next.
##
## An autoload, so it outlives the scene under it — the same ash that carries
## you from room to room carries you from the menu into a night, from a death
## to the verdict, and back out again (change_scene below).
##
## Whoever is changing the world calls cover() first and reveal() once the new
## world stands, so the swap — a freed room, a teleported body, a whole scene —
## happens behind a screen that is already black. The curtain itself is
## assets/shaders/ash_curtain.gdshader: the picture burns out along a noise
## front instead of fading.
##
## A new place (data/chapters/*.json) is announced in full: the chapter over
## the area's name, an epigraph under it, embers drifting up the black. A room
## that only continues the place it is in gets the curtain and a small line at
## the bottom, so "clear, door, next" is not stopped dead every time.
##
## Any button cuts the card short (docs/GDD.md: nothing holds the controls for
## long). The curtain itself is never skipped — it is what hides the seam.
##
## Online (docs/MULTIPLAYER.md) the host tells everyone to cover up and only
## calls the swap when its own screen is black (Run._go_to_room); the card and
## the curtain themselves are local theatre, each peer plays its own. A peer
## that is still burning when the swap arrives is snapped shut (snap_closed).

## Seconds: the curtain closing, its three beats on the card, the curtain opening.
const COVER := 0.7
const UNCOVER := 0.9
const CARD_IN := 1.1
const CARD_HOLD := 1.5
const CARD_OUT := 0.55
## The same room-to-room move inside one place is quicker on every count: the
## name at the bottom, a beat, and on. A card is an event; this is a doorway.
const QUICK_COVER := 0.55
const QUICK_UNCOVER := 0.65
const LINE_IN := 0.3
const LINE_HOLD := 0.45
## How far the title rises as it fades in.
const TITLE_RISE := 6.0
const SKIP_ACTIONS := ["jump", "attack", "interact", "dash", "pause", "ui_accept", "ui_cancel"]

## How much of all this a player in a hurry sees (Settings.transitions):
## "short" plays every beat at this fraction of its length and drops the hold,
## "off" is a plain cut.
const BRISK := 0.45
## How long the curtain waits for a scene that was handed a covered screen to
## open it, before it gives up and opens it itself.
const HANDOVER := 5.0
## The card before a scene the room is about to play: name the place and get
## out of the way, the scene is the thing.
const BEFORE_SCENE_HOLD := 0.35
## A painted threshold appears only when entering a new place, not between
## every two rooms of the same chapter. Keep gameplay geometry separate.
const PASSAGE_ART := {
	"swamp": preload("res://assets/ui/transitions/graveyard_to_swamp.png"),
}

## No curtain, no card, no waiting: _load_room stays synchronous. On by default
## under a tool script (godot -s ...), which drives the game with nobody
## watching and should not spend a minute of CI on theatre; smoke_test turns it
## off again to check the card itself.
var instant := false
## True from the first frame of the curtain to the last of the reveal: the run
## waits on this before it hands the controls back.
var active := false

var _skipped := false
var _tween: Tween
var _title_home := 0.0
## Whose hands we took while the screen was covered.
var _held: Player
## How long the curtain takes; the quiet transitions are quicker (see above).
var _cover_time := COVER
var _uncover_time := UNCOVER
## Every duration of the run now playing, scaled by the player's setting.
var _scale := 1.0
## The room we are opening starts a scene of its own: the card steps aside.
var _brisk := false

@onready var ash: ColorRect = %Ash
@onready var card: Control = %Card
@onready var passage_art: TextureRect = %PassageArt
@onready var embers: CPUParticles2D = %Embers
@onready var chapter_label: Label = %Chapter
@onready var rule: ColorRect = %Rule
@onready var title: Label = %Title
@onready var epigraph: Label = %Epigraph
@onready var line: Label = %Line


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # a paused tree still gets its curtain
	layer = 200  # over everything, including a pause menu that is open
	var args := OS.get_cmdline_args()
	instant = args.has("-s") or args.has("--script")
	# The overline is the theme's display face, letterspaced. Taking the theme's
	# own font as the base keeps its fallback chain, so the card is not a row of
	# tofu in zh_CN.
	var spaced := FontVariation.new()
	spaced.base_font = title.get_theme_font("font", "TitleLabel")
	spaced.spacing_glyph = 2
	chapter_label.add_theme_font_override("font", spaced)
	line.add_theme_font_override("font", spaced)
	_title_home = title.position.y
	_set_progress(0.0)
	card.modulate.a = 0.0
	passage_art.visible = false
	line.modulate.a = 0.0
	embers.emitting = false
	visible = false


func _input(event: InputEvent) -> void:
	if not active or _skipped:
		return
	for action in SKIP_ACTIONS:
		if event.is_action_pressed(action):
			_skipped = true
			get_viewport().set_input_as_handled()
			return


## Burns the picture away; returns with the screen covered. [param from_black]
## is the start of a run or of a loaded save: there is no room on screen yet,
## so there is nothing to burn.
func cover(chapter: Dictionary = {}, grand := false, from_black := false) -> void:
	active = true
	_skipped = false
	_hold()
	_scale = BRISK if Settings.transitions == "short" else 1.0
	_cover_time = (COVER if grand else QUICK_COVER) * _scale
	_uncover_time = (UNCOVER if grand else QUICK_UNCOVER) * _scale
	# The ash burns in the colour of the place we are walking into; there is
	# always enough of the ember left in it to read as fire and not as a wipe.
	var ember := Color(1.0, 0.55, 0.22)
	if chapter.has("color"):
		ember = ember.lerp(Color(str(chapter.color)), 0.45)
	(ash.material as ShaderMaterial).set_shader_parameter("ember", ember)
	if _cut():
		_hard_cover()
		return
	visible = true
	if from_black:
		_hard_cover()
		return
	_kill()
	_tween = create_tween()
	_tween.tween_method(_set_progress, _progress(), 1.0, _cover_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _tween.finished


## The card (when [param chapter] is not empty), then the curtain opens again.
## [param grand] is a place we have not been to yet: the full page. Otherwise
## the name goes at the bottom for a moment and we walk on.
## [param brisk] is a room that has a scene of its own waiting: the card names
## the place and goes, instead of holding while the scene waits its turn.
func reveal(chapter: Dictionary = {}, grand := false, brisk := false) -> void:
	_brisk = brisk
	if _cut():
		_set_progress(0.0)
		visible = false
		_release()
		active = false
		return
	visible = true
	if not chapter.is_empty() and chapter.has("title"):
		if grand:
			await _play_card(chapter)
		else:
			await _play_line(chapter)
	_kill()
	_tween = create_tween()
	_tween.tween_method(_set_progress, _progress(), 0.0, _uncover_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _tween.finished
	visible = false
	_release()
	active = false


## The whole world changes: burn down, swap the scene, burn back up. An empty
## [param path] reloads the scene we are in (the retry button). [param
## keep_closed] hands the black over to whatever is being opened — a run draws
## its own chapter card the moment it starts, and two curtains in a row would
## only blink at the player. [param while_black] runs once the screen is out,
## for the work that should not be seen (leaving a session, unpausing).
func change_scene(path := "", keep_closed := false, while_black := Callable()) -> void:
	await cover({}, true)
	var tree := get_tree()
	if tree == null:
		return
	if while_black.is_valid():
		while_black.call()  # leaving a session, unpausing: things nobody should watch
	if path == "":
		tree.reload_current_scene()
	else:
		tree.change_scene_to_file(path)
	if keep_closed and not _cut():
		active = false  # the new scene takes it from here, still covered
		_release()
		_watch_handover()
		return
	# One frame for the new scene to stand up before we look at it.
	await tree.process_frame
	await tree.process_frame
	await reveal()


func _play_card(chapter: Dictionary) -> void:
	var chapter_id := str(chapter.get("id", ""))
	passage_art.visible = PASSAGE_ART.has(chapter_id)
	if passage_art.visible:
		passage_art.texture = PASSAGE_ART[chapter_id]
	chapter_label.text = tr(str(chapter.get("chapter", "")))
	title.text = tr(str(chapter.get("title", "")))
	epigraph.text = tr(str(chapter.subtitle)) if chapter.has("subtitle") else ""
	var tint := Color(str(chapter.get("color", "#f2d98c")))
	title.add_theme_color_override("font_color", tint)
	rule.color = Color(tint.r, tint.g, tint.b, 0.7)
	if chapter.has("sound"):
		Audio.play(StringName(str(chapter.sound)), -3.0)
	card.modulate.a = 1.0
	embers.restart()
	embers.emitting = true
	for part in [chapter_label, title, epigraph]:
		part.modulate.a = 0.0
	title.position.y = _title_home
	rule.scale.x = 0.0
	_kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(chapter_label, "modulate:a", 1.0, CARD_IN * 0.45 * _scale)
	_tween.tween_property(rule, "scale:x", 1.0, CARD_IN * 0.7 * _scale).set_delay(CARD_IN * 0.25 * _scale) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(title, "modulate:a", 1.0, CARD_IN * 0.6 * _scale).set_delay(CARD_IN * 0.35 * _scale)
	_tween.tween_property(title, "position:y", _title_home, CARD_IN * 0.75 * _scale) \
		.from(_title_home + TITLE_RISE).set_delay(CARD_IN * 0.35 * _scale) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(epigraph, "modulate:a", 1.0, CARD_IN * 0.5 * _scale).set_delay(CARD_IN * 0.7 * _scale)
	await _wait(CARD_IN * _scale + CARD_HOLD * _scale * (BEFORE_SCENE_HOLD if _brisk else 1.0))
	_kill()
	_tween = create_tween()
	_tween.tween_property(card, "modulate:a", 0.0, CARD_OUT * _scale * (0.4 if _skipped else 1.0))
	await _tween.finished
	embers.emitting = false


## The quieter one: the place we are already in, named once at the bottom.
func _play_line(chapter: Dictionary) -> void:
	line.text = tr(str(chapter.get("title", "")))
	_kill()
	_tween = create_tween()
	_tween.tween_property(line, "modulate:a", 1.0, LINE_IN * _scale)
	await _wait((LINE_IN + LINE_HOLD) * _scale)
	_kill()
	_tween = create_tween()
	_tween.tween_property(line, "modulate:a", 0.0, LINE_IN * _scale)
	await _tween.finished


## Nobody moves behind the curtain: the enemies of the room being built are
## already on their feet, and the body cannot fight what it cannot see. Same
## two switches the cutscene player uses, so the two never argue over the hands.
func _hold() -> void:
	if _held != null or get_tree() == null:
		return
	Game.cutscene = true
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as Player
		if body != null and body._is_mine():
			body.controls_enabled = false
			_held = body
			return


func _release() -> void:
	Game.cutscene = false
	if _held != null and is_instance_valid(_held):
		_held.controls_enabled = true
		_held.release_body()
	_held = null


## Sleeps, but wakes early when the player presses anything.
func _wait(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and not _skipped:
		# An autoload outlives the tree: on the way out there is nothing to wait on.
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame
		left -= get_process_delta_time()


## The swap is happening now: whatever the curtain was doing, it is black from
## this frame on. Online the host's curtain finishes first, so a guest can be
## told to swap with a little of the old room still burning.
func snap_closed() -> void:
	if instant:
		return
	active = true
	_hold()
	_hard_cover()


## Nobody should ever be left staring at black. If whoever we handed the
## covered screen to has not taken it — a scene that does not know about the
## curtain, a run that failed to load — open it ourselves.
func _watch_handover() -> void:
	var waited := 0.0
	while waited < HANDOVER:
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame
		waited += get_process_delta_time()
		if active or _progress() < 0.99:
			return  # somebody took it
	push_warning("[Curtain] nothing opened the curtain in %.0fs; opening it" % HANDOVER)
	await reveal()


## A tool script, or a player who asked for no theatre at all.
func _cut() -> bool:
	return instant or Settings.transitions == "off"


func _hard_cover() -> void:
	_kill()
	visible = true
	_set_progress(1.0)


func _set_progress(value: float) -> void:
	(ash.material as ShaderMaterial).set_shader_parameter("progress", value)


func _progress() -> float:
	return float((ash.material as ShaderMaterial).get_shader_parameter("progress"))


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
