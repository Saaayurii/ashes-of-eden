extends StaticBody2D
class_name Npc
## A person who is not trying to kill you. Data-driven like everything else
## (res://data/npcs/*.json): a sprite strip and a caption dialogue.
## Walk up and the key to talk floats over their head; press it and they
## speak, once. Nobody starts a conversation at you. The world stops being
## only enemies.
## The body is on no physics layer: you walk through people, they never
## block a ledge.
##
## They are alive in small ways: they turn to face whoever walks up; the ones
## with a "wander" radius stroll about their spot, the ones with a "path"
## (waypoints relative to their spot) walk their round, pausing "pace" seconds
## at each stop — or, with "travel": "fade", are simply elsewhere when you
## look again. A "light" is carried like an enemy's; "motes" is a colour of
## dust that hangs about them. After the talk, "lines" are muttered now and
## then while the player is close. Meeting one (being in the same room) and
## talking to one are both written to the profile: the bestiary keeps a page
## per person.
##
## Some fight back. A "guard" block in the data
##   {"range": 140, "reach": 34, "damage": 12, "cooldown": 1.1, "speed": 60, "leash": 50}
## makes them walk at any enemy that comes within range on their ledge and
## swing at it; leash is how far from their spot they will go (the room's
## ledge decides it, there is no gravity on a person). Strips "walk" and "attack" in sprite.animations are used when
## drawn; without them the idle strip walks with a bob and the swing is a
## lunge behind the sword's slash. Enemies live on the host, so only the host
## lets a swing land (the animation plays everywhere).

@export var npc_id: String = "knight"

## How close the player has to be for the "…" marker and the turn of the head.
const NEAR := 110.0
const WALK_SPEED := 22.0
const SLASH_FRAMES := preload("res://assets/sprites/slash_frames.tres")
## How far above or below the feet an enemy still counts as "on my ledge".
const SAME_LEDGE := 48.0

var spec: Dictionary = {}
var _spoken := false
var _home := Vector2.ZERO
var _goal := Vector2.ZERO
var _wander := 0.0
var _wait := 0.0
var _bob := 0.0
var _faces_left := false
var _path: Array = []  # waypoints in world space
var _stop := 0
var _fading := false
var _lines: Array = []
var _line_left := 0.0
var _line_cd := 0.0
var _speech: Label
var _has_anim := {}
var _guard: Dictionary = {}
var _target: Node2D
var _swing_cd := 0.0
var _swinging := 0.0
var _slash: AnimatedSprite2D
## Player bodies standing in the talk area right now.
var _in_reach: Array[Node] = []

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var area: Area2D = $TalkArea
@onready var marker: Label = $Marker


func _ready() -> void:
	spec = Data.npcs.get(npc_id, {})
	if spec.is_empty():
		push_error("Unknown npc id: %s" % npc_id)
		return
	var sprite_spec: Dictionary = spec.get("sprite", {})
	var size: Array = sprite_spec.get("cell", [32, 44])
	var cell := Vector2i(int(size[0]), int(size[1]))
	var frames := SpriteFrames.new()
	var fps := float(sprite_spec.get("fps", 4))
	# one strip, or a strip per animation like the enemies have
	var strips: Dictionary = sprite_spec.get("animations", {})
	if sprite_spec.has("path"):
		strips = strips.duplicate()
		strips["idle"] = sprite_spec.path
	for anim in strips:
		if Fx.add_strip(frames, strips[anim], cell, fps, anim, anim not in ["attack", "interact"]):
			_has_anim[anim] = true
	if _has_anim.has("idle"):
		sprite.sprite_frames = frames
		sprite.position.y = -cell.y / 2.0 + 1.0 + float(sprite_spec.get("ground_offset", 0.0))
		# Most strips have 1 px padding; individually drawn sheets may need a
		# small grounding correction without moving every other NPC.
		sprite.play("idle")
		sprite.frame = randi() % maxi(1, frames.get_frame_count("idle"))
	_guard = spec.get("guard", {})
	if not _guard.is_empty():
		_slash = AnimatedSprite2D.new()
		_slash.sprite_frames = SLASH_FRAMES
		_slash.position = Vector2(0, -14)
		_slash.scale = Vector2.ONE * 0.85
		_slash.visible = false
		_slash.animation_finished.connect(func() -> void: _slash.visible = false)
		add_child(_slash)
	_faces_left = spec.get("face", "right") == "left"
	sprite.flip_h = _faces_left
	Fx.shadow(self, Vector2(0, 1), 20.0, 0.7)
	marker.visible = false
	_home = global_position
	_goal = _home
	_wander = float(spec.get("wander", 0.0))
	_wait = randf_range(1.0, 3.0)
	for point in spec.get("path", []):
		_path.append(_home + Vector2(float(point[0]), float(point[1])))
	if spec.has("light"):
		var light: Dictionary = spec.light
		Fx.light(self, Vector2(0, -16), Color(light.get("color", "#ffb060")), float(light.get("radius", 40)),
			float(light.get("energy", 0.6)), float(light.get("flicker", 0.2)), float(light.get("breathe", 0.0)))
	if spec.has("motes"):
		var motes := Fx.trail(self, Color(spec.motes), 8, 1.6)
		motes.position = Vector2(0, -18)
		motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		motes.emission_sphere_radius = 10.0
		motes.initial_velocity_min = 2.0
		motes.initial_velocity_max = 6.0
	_lines = spec.get("lines", [])
	_line_cd = randf_range(3.0, 6.0)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	Profile.record_seen("npc:" + npc_id)
	if _scripted():
		# Somebody who exists only for a scene (data/cutscenes: "appear" /
		# "vanish"): out of sight until it is called, and never talked to on E.
		modulate.a = 0.0
		visible = false
		marker.visible = false


func _scripted() -> bool:
	return bool(spec.get("scripted", false))


func _process(delta: float) -> void:
	if _scripted():
		var watcher := _nearest_player()
		if watcher != null:
			sprite.flip_h = watcher.global_position.x < global_position.x
		return
	var player := _nearest_player()
	var near := player != null and player.global_position.distance_to(global_position) < NEAR
	if not _guard.is_empty() and _fight(delta):
		marker.visible = false
		return
	if near:
		# turn to whoever came up; nothing else, a person does not fidget while spoken to
		sprite.flip_h = player.global_position.x < global_position.x
		_goal = global_position
		if sprite.animation == "walk":
			sprite.play("idle")
	elif not _path.is_empty():
		_walk_round(delta)
	elif _wander > 0.0:
		_stroll(delta)
	else:
		sprite.flip_h = _faces_left
	if _spoken:
		marker.visible = false
		_mutter(delta, near)
		return
	var can_talk := _local_in_reach()
	marker.visible = near
	if near:
		# The key to press once they are close enough; a "…" while still walking up.
		marker.text = Settings.key_name("interact") if can_talk else "…"
		marker.position.y = -42.0 + sin(Time.get_ticks_msec() / 400.0) * 2.0
	if can_talk and Input.is_action_just_pressed("interact") and not _dialogue_open():
		_talk()


## The round: walk (or fade) to the next stop, pause there, go on.
func _walk_round(delta: float) -> void:
	if _fading:
		return
	var goal: Vector2 = _path[_stop]
	if global_position.distance_to(goal) < 1.5:
		_bob = 0.0
		sprite.offset.y = 0.0
		if sprite.animation == "walk":
			sprite.play("idle")
		_wait -= delta
		if _wait <= 0.0:
			_stop = (_stop + 1) % _path.size()
			_wait = float(spec.get("pace", 4.0)) * randf_range(0.7, 1.3)
			if spec.get("travel", "walk") == "fade":
				_fade_to(_path[_stop])
		return
	_step_towards(goal, delta, WALK_SPEED)


## Gone when you blink: out here, in over there.
func _fade_to(goal: Vector2) -> void:
	_fading = true
	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 0.6)
	tween.tween_callback(func() -> void: global_position = goal)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.6)
	tween.tween_callback(func() -> void: _fading = false)


func _step_towards(goal: Vector2, delta: float, speed: float) -> void:
	var step := signf(goal.x - global_position.x)
	if step != 0.0:
		sprite.flip_h = step < 0.0
	global_position = global_position.move_toward(goal, speed * delta)
	if _has_anim.has("walk"):
		sprite.play("walk")
	else:
		_bob += delta * 9.0
		sprite.offset.y = -absf(sin(_bob)) * 1.5


## Something said under the breath, now and then, while the player is close.
func _mutter(delta: float, near: bool) -> void:
	if _speech != null and _line_left > 0.0:
		_line_left -= delta
		_speech.position.y = -46.0 + sin(Time.get_ticks_msec() / 500.0) * 1.5
		if _line_left <= 0.0:
			create_tween().tween_property(_speech, "modulate:a", 0.0, 0.5)
		return
	if _lines.is_empty() or not near:
		return
	_line_cd -= delta
	if _line_cd > 0.0:
		return
	_line_cd = randf_range(9.0, 16.0)
	_line_left = 3.2
	if _speech == null:
		_speech = Label.new()
		_speech.add_theme_font_size_override("font_size", 8)
		_speech.add_theme_color_override("font_color", Color(0.9, 0.88, 0.8))
		_speech.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		_speech.add_theme_constant_override("shadow_offset_x", 1)
		_speech.add_theme_constant_override("shadow_offset_y", 1)
		_speech.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_speech.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_speech.z_index = 10
		add_child(_speech)
	_speech.text = tr(_lines[randi() % _lines.size()])
	_speech.modulate.a = 1.0
	_speech.reset_size()
	_speech.position = Vector2(-_speech.size.x / 2.0, -46.0)


## A few steps one way, a pause, a few steps back: the strip has no walk
## cycle, so the body bobs a little to sell the stride.
func _stroll(delta: float) -> void:
	if absf(_goal.x - global_position.x) < 1.0:
		_bob = 0.0
		if sprite.animation == "walk":
			sprite.play("idle")
		_wait -= delta
		if _wait <= 0.0:
			_goal = _home + Vector2(randf_range(-_wander, _wander), 0.0)
			_wait = randf_range(2.0, 5.0)
		return
	_step_towards(Vector2(_goal.x, global_position.y), delta, WALK_SPEED)


## True while there is an enemy to deal with. Walks at it along the ledge,
## never further than the guard's range from home, and swings when in reach.
func _fight(delta: float) -> bool:
	_swing_cd -= delta
	if _swinging > 0.0:
		_swinging -= delta
		return true
	_target = _nearest_enemy()
	if _target == null:
		if _has_anim.has("walk") and sprite.animation == "walk":
			sprite.play("idle")
		sprite.offset.y = 0.0
		return false
	var dx := _target.global_position.x - global_position.x
	sprite.flip_h = dx < 0.0
	var reach := float(_guard.get("reach", 34))
	if absf(dx) > reach:
		var leash := float(_guard.get("leash", _guard.get("range", 140)))  # never off the ledge
		var goal := clampf(_target.global_position.x - signf(dx) * reach * 0.8, _home.x - leash, _home.x + leash)
		global_position.x = move_toward(global_position.x, goal, float(_guard.get("speed", 60)) * delta)
		if _has_anim.has("walk"):
			sprite.play("walk")
		else:
			_bob += delta * 11.0
			sprite.offset.y = -absf(sin(_bob)) * 1.5
		return true
	sprite.offset.y = 0.0
	if _swing_cd <= 0.0:
		_swing(signf(dx) if dx != 0.0 else 1.0)
	return true


func _swing(facing: float) -> void:
	_swinging = 0.4
	_swing_cd = float(_guard.get("cooldown", 1.1))
	Audio.play(&"swing", -8.0)
	if _has_anim.has("attack"):
		sprite.play("attack")
		if not sprite.animation_finished.is_connected(_end_action_animation):
			sprite.animation_finished.connect(_end_action_animation, CONNECT_ONE_SHOT)
	else:
		# no swing drawn: the body lunges and comes back
		var tween := create_tween()
		tween.tween_property(sprite, "position:x", facing * 7.0, 0.08).set_ease(Tween.EASE_OUT)
		tween.tween_property(sprite, "position:x", 0.0, 0.2).set_ease(Tween.EASE_IN)
	if _slash != null:
		_slash.position.x = facing * 18.0
		_slash.flip_h = facing < 0.0
		_slash.visible = true
		_slash.play("white")
	get_tree().create_timer(0.12).timeout.connect(_land_swing.bind(facing))


func _land_swing(facing: float) -> void:
	if not is_inside_tree():
		return
	var reach := float(_guard.get("reach", 34)) + 10.0
	var damage := float(_guard.get("damage", 12))
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node2D
		if body == null or not body.has_method("take_damage") or (body.has_method("is_dead") and body.is_dead()):
			continue
		var d := body.global_position - global_position
		if signf(d.x) != facing or absf(d.x) > reach or absf(d.y) > SAME_LEDGE:
			continue
		Fx.impact(body.global_position + Vector2(0, -10), Vector2(facing, -0.3), Color(0.9, 0.9, 1.0), 6)
		if not Net.active or Net.is_server():
			body.take_damage(damage, self)


## The closest living enemy within range, on this ledge.
func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_d := float(_guard.get("range", 140))
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node2D
		if body == null or (body.has_method("is_dead") and body.is_dead()):
			continue
		var d := body.global_position - global_position
		if absf(d.y) > SAME_LEDGE or absf(d.x) >= best_d:
			continue
		best_d = absf(d.x)
		best = body
	return best


func _on_body_entered(body: Node) -> void:
	if body is Player and not _in_reach.has(body):
		_in_reach.append(body)


func _on_body_exited(body: Node) -> void:
	_in_reach.erase(body)


## Our own body (not the other player's) is close enough to talk.
func _local_in_reach() -> bool:
	for body in _in_reach:
		if is_instance_valid(body) and (body as Player).is_multiplayer_authority():
			return true
	return false


func _dialogue_open() -> bool:
	var dialogue := get_tree().get_first_node_in_group("dialogue_box") as DialogueBox
	return dialogue != null and dialogue.is_blocking_open()


func _talk() -> void:
	_spoken = true
	marker.visible = false
	var visitor := _nearest_player()
	if visitor != null:
		sprite.flip_h = visitor.global_position.x < global_position.x
	if _has_anim.has("interact"):
		sprite.play("interact")
		if not sprite.animation_finished.is_connected(_end_action_animation):
			sprite.animation_finished.connect(_end_action_animation, CONNECT_ONE_SHOT)
	Profile.record_met("npc:" + npc_id)
	var dialogue := get_tree().get_first_node_in_group("dialogue_box") as DialogueBox
	if dialogue and spec.has("dialogue"):
		# Talked to where they stand: the lines go over their head, not into a panel.
		dialogue.play_bubble(spec.dialogue, self, visitor if visitor != null else self)


func _end_action_animation() -> void:
	if is_inside_tree() and _has_anim.has("idle"):
		sprite.play("idle")


## Whoever is closest: there may be two bodies in a session.
func _nearest_player() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("player"):
		var d: float = (node as Node2D).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = node
	return best
