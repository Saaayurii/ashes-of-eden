extends Area2D
class_name Prop
## Barrels, crates and chests. Everything comes from res://data/props/*.json
## (see docs/DATA_FORMATS.md):
##   kind      "destructible" (hit it) | "chest" (walk into it)
##   sprite    one strip: whole -> cracked -> bursting -> leftovers
##   essence   paid out when it breaks or opens
##   effect    optional alignment nudge, the same block dialogue choices use
##   icon      optional pickup icon that floats out of an opened chest: one path,
##             or a list of paths to pick from, so the same chest does not always
##             hold the same thing
##   reveals   a destructible that hides another prop (a bricked-up doorway and
##             the cache behind it): that prop appears where this one broke
##   still     masonry, not a barrel: no size/tint variation, no sway, no kick
##   note      a record (data/notes) read aloud as a caption and kept in the
##             bestiary; "ash" is paid only the first time it is found
## A prop is never an enemy: it does not count towards the room's kill count and
## nothing in it blocks movement.

@export var prop_id: String = "barrel"

var stats: Dictionary = {}
var hp := 1.0
var _max_hp := 1.0
var _spent := false
var _phase := 0.0
var _idle_clock := 0.0
var _idle_frame := 0
var _kick := Vector2.ZERO
var _kick_rotation := 0.0
var _ambient_timer: Timer
var _base_sprite_position := Vector2.ZERO
var _base_sprite_scale := Vector2.ONE
## A chest glows in its own colour until it is opened (Fx.light).
var _light: GlowLight

@onready var sprite: Sprite2D = $Sprite
@onready var shape: CollisionShape2D = $Collision


func _ready() -> void:
	stats = Data.props.get(prop_id, {})
	if stats.is_empty():
		push_error("Unknown prop id: %s" % prop_id)
		queue_free()
		return
	var spec: Dictionary = stats.get("sprite", {})
	var texture: Texture2D = load(spec.get("path", ""))
	if texture == null:
		push_warning("[Prop] missing strip %s" % spec.get("path", ""))
		queue_free()
		return
	sprite.texture = texture
	sprite.hframes = maxi(1, int(spec.get("frames", 4)))
	sprite.centered = false
	# The strips reserve one or two transparent rows below the drawing. Place
	# the lowest painted pixel, not the cell border, on the platform line.
	var ground_pad := float(spec.get("ground_pad", 1.0))
	sprite.offset = Vector2(-texture.get_width() / sprite.hframes / 2.0,
		-texture.get_height() + ground_pad)
	sprite.frame = 0
	# Position-derived variation is stable between runs. Nearby copies no longer
	# breathe in lockstep or read like objects stamped from a level editor.
	_phase = fposmod(global_position.x * 0.071 + global_position.y * 0.037 + prop_id.hash() * 0.001, TAU)
	if not stats.get("still", false):
		var size_variation := 0.96 + fposmod(absf(sin(_phase * 1.73)), 1.0) * 0.08
		sprite.scale = Vector2(size_variation, size_variation)
		sprite.flip_h = sin(_phase * 2.31) < 0.0
		var value_variation := 0.94 + fposmod(absf(cos(_phase * 1.19)), 1.0) * 0.08
		sprite.modulate = Color(value_variation, value_variation, value_variation, 1.0)
	_base_sprite_position = sprite.position
	_base_sprite_scale = sprite.scale
	var box: Array = stats.get("hitbox", [20, 20])
	var size := Vector2(float(box[0]), float(box[1]))
	(shape.shape as RectangleShape2D).size = size
	shape.position.y = -size.y / 2.0
	_max_hp = maxf(1.0, float(stats.get("hp", 1)))
	hp = _max_hp
	# Anchored to the floor by a shadow, so a body walking past reads as
	# passing in front of it instead of through it.
	Fx.shadow(self, Vector2(0, 1), size.x * 1.5, 0.9)
	if stats.get("kind", "destructible") == "chest":
		body_entered.connect(_on_body_entered)
		var glow := Color(stats.get("glow", "#ffd9a0"))
		_light = Fx.light(self, Vector2(0, -size.y / 2.0), glow, 44.0, 0.7, 0.0, 0.25)
	EventBus.world_impulse.connect(_on_world_impulse)
	_setup_ambient()
	set_process(true)


func _process(delta: float) -> void:
	if _spent or stats.get("still", false):
		return
	_idle_clock += delta
	var idle_frames := mini(int(stats.get("idle_frames", 1)), sprite.hframes)
	if idle_frames > 1 and _idle_clock >= 0.42:
		_idle_clock = 0.0
		_idle_frame = (_idle_frame + 1) % idle_frames
		sprite.frame = _idle_frame
	var t := Time.get_ticks_msec() * 0.001 + _phase
	# Deliberately tiny: the prop feels inhabited by the weather without
	# floating off the floor or making its collision shape swim around.
	var breathe := sin(t * 1.35) * (0.012 if stats.get("ambient", "") != "" else 0.004)
	_kick = _kick.lerp(Vector2.ZERO, minf(1.0, delta * 9.0))
	_kick_rotation = lerpf(_kick_rotation, 0.0, minf(1.0, delta * 11.0))
	sprite.position = _base_sprite_position + _kick
	sprite.rotation = sin(t * 0.73) * 0.006 + _kick_rotation
	sprite.scale = _base_sprite_scale * (1.0 + breathe)


func _on_world_impulse(at: Vector2, direction: Vector2, strength: float, kind: StringName) -> void:
	if _spent or stats.get("still", false):
		return
	var distance := global_position.distance_to(at)
	var reach := 225.0 if kind == &"parry" else 165.0
	if distance >= reach:
		return
	var falloff := 1.0 - distance / reach
	var push := direction.normalized() if direction.length_squared() > 0.01 else Vector2.UP
	_kick += Vector2(push.x * 2.4, -absf(push.y) * 1.2 - 0.8) * strength * falloff
	_kick_rotation += push.x * 0.07 * strength * falloff


func _setup_ambient() -> void:
	var ambient := str(stats.get("ambient", ""))
	if ambient == "":
		return
	if ambient == "candle":
		_light = Fx.light(self, Vector2(0, -34), Color("#ffb45e"), 38.0, 0.46, 0.2, 0.12)
	elif ambient == "soul":
		_light = Fx.light(self, Vector2(0, -30), Color("#8bc8c8"), 42.0, 0.32, 0.08, 0.2)
	_ambient_timer = Timer.new()
	_ambient_timer.wait_time = 2.2 + fposmod(_phase, 1.7)
	_ambient_timer.autostart = true
	_ambient_timer.timeout.connect(_emit_ambient)
	add_child(_ambient_timer)


func _emit_ambient() -> void:
	if _spent or not is_inside_tree():
		return
	match str(stats.get("ambient", "")):
		"candle":
			Fx.sparkle(global_position + Vector2(0, -33), Color(1.0, 0.66, 0.3, 0.72), 3, 7.0)
		"spores":
			Fx.ash(global_position + Vector2(0, -18), Color(0.62, 0.78, 0.34, 0.5), 4, 12.0, 10.0)
		"soul":
			Fx.ash(global_position + Vector2(0, -30), Color(0.48, 0.78, 0.76, 0.55), 3, 18.0, 6.0)
		"bottles":
			Fx.sparkle(global_position + Vector2(12, -18), Color(0.72, 0.88, 0.76, 0.5), 2, 4.0)
		"dust":
			# A secret wall gives itself away to a patient eye: grit trickling
			# out of a crack somewhere on its face.
			var box: Array = stats.get("hitbox", [20, 20])
			var at := Vector2(randf_range(-0.35, 0.35) * float(box[0]), -randf_range(0.3, 0.9) * float(box[1]))
			Fx.dust(global_position + at, Vector2.DOWN, 4, Color(0.62, 0.56, 0.5, 0.6))


## The sword hits props through the same call it uses on enemies.
func take_damage(amount: float, _source: Node = null, _info: Dictionary = {}) -> void:
	if _spent or stats.get("kind", "destructible") != "destructible":
		return
	hp -= amount
	Juice.shake(1.5)
	if hp > 0.0:
		sprite.frame = mini(int(stats.get("hit_frame", 1)), sprite.hframes - 1)
		if not stats.get("still", false):
			_kick = Vector2(randf_range(-2.0, 2.0), -2.5)
			_kick_rotation = randf_range(-0.08, 0.08)
		Fx.puff(global_position + Vector2(0, -8), 0.3, Color(0.8, 0.7, 0.55, 0.7))
		return
	_break()


func _break() -> void:
	_spent = true
	# take_damage() can reach us from an area callback too (scripts/player/player.gd).
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	sprite.frame = mini(2, sprite.hframes - 1)
	Fx.puff(global_position + Vector2(0, -8), 0.9, Color(0.75, 0.62, 0.45))
	Fx.debris(global_position + Vector2(0, -10), Color(stats.get("debris", "#8a6a48")), 10)
	Juice.shake(2.5)
	Audio.play_at(&"prop_break", global_position, -2.0)
	_pay_out()
	_reveal()
	await get_tree().create_timer(0.12).timeout
	if is_inside_tree():
		sprite.frame = sprite.hframes - 1  # the leftovers stay on the floor


func _on_body_entered(body: Node) -> void:
	if _spent or not (body is Player):
		return
	_spent = true
	# We are inside the area's own body_entered: physics is mid-flush and will
	# not let us switch monitoring off until it is done.
	set_deferred("monitoring", false)
	_pay_out(body as Player)
	_show_icon()
	var glow := Color(stats.get("glow", "#ffd9a0"))
	Fx.puff(global_position + Vector2(0, -10), 0.7, glow)
	Fx.sparkle(global_position + Vector2(0, -6), glow, 18, 12.0)
	Fx.flash(global_position + Vector2(0, -10), glow, 90.0, 0.6, 1.4)
	if _light != null:
		create_tween().tween_method(_light.set_base_energy, 0.7, 0.0, 0.8)
	for frame in range(1, sprite.hframes):
		await get_tree().create_timer(0.09).timeout
		if not is_inside_tree():
			return
		sprite.frame = frame


## What was inside, drawn for a moment above the open lid.
func _show_icon() -> void:
	var choice = stats.get("icon", "")
	if choice is Array:
		if choice.is_empty():
			return
		choice = choice[randi() % choice.size()]
	if str(choice) == "":
		return
	var texture: Texture2D = load(str(choice))
	if texture == null:
		return
	var icon := Sprite2D.new()
	icon.texture = texture
	icon.position = Vector2(0, -22)
	icon.z_index = 3
	add_child(icon)
	var tween := create_tween()
	tween.tween_property(icon, "position:y", -44.0, 0.9)
	tween.parallel().tween_property(icon, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tween.tween_callback(icon.queue_free)


func _pay_out(taker: Player = null) -> void:
	Game.add_essence(float(stats.get("essence", 0)))
	if stats.has("effect"):
		Game.apply_effect(stats.effect)
	var heal := float(stats.get("heal", 0.0))
	if heal > 0.0 and taker != null:
		taker.heal(heal)
	# A record is ours only when our own body opened it (online, the other
	# player's puppet walks into chests on this machine too).
	var note := str(stats.get("note", ""))
	if note == "" or (taker != null and not taker.is_multiplayer_authority()):
		return
	var first := Profile.record_note(note)
	var ash := int(stats.get("ash", 0))
	if first and ash > 0:
		Game.ash_earned += ash
		Fx.popup(global_position + Vector2(0, -30), tr("NOTE_ASH") % ash, Color(0.85, 0.82, 0.95))
	EventBus.note_found.emit(note, first)


## The bricked-up doorway is down: whatever it hid stands where it stood.
func _reveal() -> void:
	var hidden := str(stats.get("reveals", ""))
	if hidden == "" or not Data.props.has(hidden):
		return
	var cache: Prop = load("res://scenes/props/prop.tscn").instantiate()
	cache.prop_id = hidden
	cache.position = position
	get_parent().add_child.call_deferred(cache)
	await get_tree().create_timer(0.35).timeout
	if is_instance_valid(cache) and cache.is_inside_tree():
		Fx.sparkle(cache.global_position + Vector2(0, -12), Color(stats.get("glow", "#ffcc78")), 16, 18.0)
		Fx.flash(cache.global_position + Vector2(0, -16), Color("#ffcc78"), 80.0, 0.5, 1.2)
