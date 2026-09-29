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
	for action in SKIP_ACTIONS:
		if event.is_action_pressed(action):
			_skip()
			get_viewport().set_input_as_handled()
			return


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
	_hint.text = "%s  [%s]" % [tr("CUTSCENE_SKIP"), Settings.key_name("jump")]
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
	playing = ""
	if not _aborted:
		finished.emit(cutscene_id)
		EventBus.cutscene_finished.emit(cutscene_id)


## The fade is the one thing a scene can leave behind; whoever loads the next
## room clears it.
func clear() -> void:
	_fade.color.a = 0.0
	_panel.visible = false
	_panel.texture = null


func skipping() -> bool:
	return _skipped


## Cut the running scene short from outside (the room is changing under it).
func abort() -> void:
	if playing != "":
		_aborted = true
		_skipped = true
		_kill_tweens()
		_panel.visible = false
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
				(actor as Player).facing = int(step.get("dir", 1))
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
			await _show_panel(str(step.get("image", "")), seconds)
		"panel_clear":
			await _hide_panel(seconds)
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


func _show_panel(path: String, seconds: float) -> void:
	var texture := _panel_texture(path)
	if texture == null:
		push_warning("Cutscene %s: missing panel %s" % [playing, path])
		return
	_panel.texture = texture
	_panel.modulate.a = 0.0 if seconds > 0.0 else 1.0
	_panel.visible = true
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


## Hands off: the local body stops listening, every enemy holds its ground.
func _hold() -> void:
	Game.cutscene = true
	var body := _local_player()
	if body != null:
		body.controls_enabled = false
		_held_player = body


func _release() -> void:
	Game.cutscene = false
	if _held_player != null and is_instance_valid(_held_player):
		_held_player.controls_enabled = true
		_held_player.release_body()
	_held_player = null


func _camera_to(step: Dictionary, seconds: float, instant: bool) -> void:
	var home := _home()
	if home == null:
		return
	if _camera == null:
		_camera = Camera2D.new()
		_camera.position_smoothing_enabled = false
		for limit in ["limit_left", "limit_top", "limit_right", "limit_bottom"]:
			_camera.set(limit, home.get(limit))
		get_tree().current_scene.add_child(_camera)
		_camera.global_position = home.get_screen_center_position()
		_camera.zoom = home.zoom
		_camera.make_current()
	var target := str(step.get("to", "player"))
	var goal := home.get_screen_center_position() if target == "player" else _position_of(step.get("to", "player"))
	if target == "player":
		var body := _local_player()
		if body != null:
			goal = body.global_position + home.position
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
	if home != null:
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
	elif step.has("by"):
		goal = actor.global_position + Vector2(float(step.by[0]), float(step.by[1]))
	_goals[key] = goal
	var walking: bool = step.get("do") == "walk"
	if walking:
		var dir := signf(goal.x - actor.global_position.x)
		if actor is Player and dir != 0.0:
			(actor as Player).facing = int(dir)
			(actor as Player).body.flip_h = dir < 0.0
		if actor.has_method("_play"):
			actor.call("_play", "walk")
	if instant or seconds <= 0.0:
		actor.global_position = goal
	else:
		var tween := _tween()
		var ease_kind := Tween.EASE_OUT if step.get("ease", "in_out") == "out" else Tween.EASE_IN_OUT
		tween.tween_property(actor, "global_position", goal, seconds).set_trans(Tween.TRANS_SINE).set_ease(ease_kind)
		await _sleep(seconds)
	if not is_instance_valid(actor):
		return
	if walking and actor.has_method("_play"):
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
	_hint.visible = playing != ""


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
