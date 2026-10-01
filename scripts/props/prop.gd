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
##   niche     a picture drawn behind the prop, bottom on its floor, that stays
##             when it breaks: the doorway a secret wall bricks up, so it reads as
##             a niche in the wall and the cache is found standing in it
##   curse     a chest that opens only on `interact`, never by walking into it,
##             and lays its price on the opener: wounds land twice as hard
##             until that many enemies have fallen (Player.take_curse)
##   interact  a chest that opens only on `interact` (a curse implies it), with
##             "prompt" (a key) over it while our body stands there
##   requires_flag  not there at all until the story sets this flag (the book
##             under the church altar appears once Matthew has spoken of it)
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
var _idle_offsets: Array[float] = []
var _authored_sprite_offset := Vector2.ZERO
static var _floor_padding_cache := {}
## A chest glows in its own colour until it is opened (Fx.light).
var _light: GlowLight
## A cursed chest's offer, over it while our own body stands at it.
var _prompt: Label
## Hidden until Game.flags has stats.requires_flag.
var _waiting := false

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
	if stats.has("niche"):
		_add_niche(_load_niche(str(stats.niche)))
	sprite.centered = false
	# The strips reserve one or two transparent rows below the drawing. Place
	# the lowest painted pixel, not the cell border, on the platform line.
	var ground_pad := float(spec.get("ground_pad", _floor_padding(texture, sprite.hframes)))
	sprite.offset = Vector2(-texture.get_width() / sprite.hframes / 2.0,
		-texture.get_height() + ground_pad)
	sprite.frame = 0
	_authored_sprite_offset = sprite.offset
	var idle_count := mini(int(stats.get("idle_frames", 1)), sprite.hframes)
	for frame in idle_count:
		_idle_offsets.append(-texture.get_height() + _frame_padding(texture, sprite.hframes, frame))
	# Position-derived material variation is stable between runs. Nearby copies
	# differ subtly without lifting their feet or breathing like living bodies.
	_phase = fposmod(global_position.x * 0.071 + global_position.y * 0.037 + prop_id.hash() * 0.001, TAU)
	if not stats.get("still", false):
		var size_variation := 0.96 + fposmod(absf(sin(_phase * 1.73)), 1.0) * 0.08
		sprite.scale = Vector2(size_variation, size_variation)
		sprite.flip_h = sin(_phase * 2.31) < 0.0
		var value_variation := 0.94 + fposmod(absf(cos(_phase * 1.19)), 1.0) * 0.08
		sprite.modulate = Color(value_variation, value_variation, value_variation, 1.0)
	# A bricked-up secret can borrow the painted wall beneath it until struck.
	# This affects only props opting in; damage reveals their normal crack strip.
	sprite.modulate.a = clampf(float(stats.get("concealed_alpha", 1.0)), 0.0, 1.0)
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
		if int(stats.get("curse", 0)) > 0 or stats.get("interact", false):
			_add_prompt()
		else:
			body_entered.connect(_on_body_entered)
		var glow := Color(stats.get("glow", "#ffd9a0"))
		_light = Fx.light(self, Vector2(0, -size.y / 2.0), glow, 44.0, 0.7, 0.0, 0.25)
	EventBus.world_impulse.connect(_on_world_impulse)
	_setup_ambient()
	if stats.has("requires_flag") and not Game.flags.has(str(stats.requires_flag)):
		_waiting = true
		visible = false
	set_process(true)


## Ground the drawing, not a cell's transparent border. Frame zero also sets
## the authored baseline for opening, bursting and remains.
## Behind everything the prop draws, and behind what it reveals (a sibling
## added after it), but in front of the painting.
static func _load_niche(path: String) -> Texture2D:
	# Fresh checkouts can run headless before the editor imports optional PNGs.
	# Loading the image directly also keeps these painted wall details visible
	# during automated room tests instead of silently dropping them.
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var picture := Image.load_from_file(path)
	if picture.is_empty():
		return null
	return ImageTexture.create_from_image(picture)


func _add_niche(texture: Texture2D) -> void:
	if texture == null:
		push_warning("[Prop] missing niche for %s" % prop_id)
		return
	var niche := Sprite2D.new()
	niche.name = "Niche"
	niche.texture = texture
	niche.centered = false
	niche.offset = Vector2(-texture.get_width() / 2.0, -texture.get_height())
	add_child(niche)
	move_child(niche, 0)


static func _floor_padding(texture: Texture2D, frames: int) -> int:
	return _frame_padding(texture, frames, 0)


static func _frame_padding(texture: Texture2D, frames: int, frame: int) -> int:
	var key := "%s:%d:%d" % [texture.get_instance_id(), frames, frame]
	if _floor_padding_cache.has(key):
		return _floor_padding_cache[key]
	var image := texture.get_image()
	if image == null:
		return 1
	if image.is_compressed():
		image.decompress()
	var cell_width := int(image.get_width() / frames)
	for y in range(image.get_height() - 1, -1, -1):
		for x in range(frame * cell_width, (frame + 1) * cell_width):
			if image.get_pixel(x, y).a >= 0.1:
				var padding := image.get_height() - y - 1
				_floor_padding_cache[key] = padding
				return padding
	return 1


func _process(delta: float) -> void:
	if _waiting:
		if not Game.flags.has(str(stats.requires_flag)):
			return
		# the story has spoken of it: it is there now
		_waiting = false
		visible = true
		Fx.sparkle(global_position + Vector2(0, -10), Color(stats.get("glow", "#ffd9a0")), 12, 12.0)
	if _prompt != null:
		_offer()
	if _spent or stats.get("still", false):
		return
	_idle_clock += delta
	var idle_frames := mini(int(stats.get("idle_frames", 1)), sprite.hframes)
	if idle_frames > 1 and _idle_clock >= 0.42:
		_idle_clock = 0.0
		_idle_frame = (_idle_frame + 1) % idle_frames
		sprite.frame = _idle_frame
	# Only intact idle cells are grounded independently. Bursting / remains
	# retain their authored vertical motion and are never snapped upward.
	if sprite.frame < _idle_offsets.size():
		sprite.offset.y = _idle_offsets[sprite.frame]
	else:
		sprite.offset = _authored_sprite_offset
	_kick = _kick.lerp(Vector2.ZERO, minf(1.0, delta * 9.0))
	_kick_rotation = lerpf(_kick_rotation, 0.0, minf(1.0, delta * 11.0))
	sprite.position = _base_sprite_position + _kick
	sprite.rotation = _kick_rotation
	sprite.scale = _base_sprite_scale


func _on_world_impulse(at: Vector2, direction: Vector2, strength: float, kind: StringName) -> void:
	if _spent or stats.get("still", false):
		return
	var distance := global_position.distance_to(at)
	var reach := 225.0 if kind == &"parry" else 165.0
	if distance >= reach:
		return
	var falloff := 1.0 - distance / reach
	var push := direction.normalized() if direction.length_squared() > 0.01 else Vector2.UP
	_kick += Vector2(push.x * 1.2, 0) * strength * falloff
	_kick_rotation += push.x * 0.015 * strength * falloff


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
		sprite.modulate.a = 1.0
		sprite.frame = mini(int(stats.get("hit_frame", 1)), sprite.hframes - 1)
		sprite.offset = _authored_sprite_offset
		if not stats.get("still", false):
			_kick = Vector2(randf_range(-1.2, 1.2), 0)
			_kick_rotation = randf_range(-0.015, 0.015)
		Fx.puff(global_position + Vector2(0, -8), 0.3, Color(0.8, 0.7, 0.55, 0.7))
		return
	_break()


func _break() -> void:
	_spent = true
	_rest_on_floor()
	sprite.modulate.a = 1.0
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


func _add_prompt() -> void:
	add_to_group("interactable")
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.position = Vector2(-60, -50)
	_prompt.size = Vector2(120, 14)
	_prompt.add_theme_font_size_override("font_size", 8)
	_prompt.modulate = Color(1.0, 0.6, 0.55)
	_prompt.z_index = 3
	_prompt.visible = false
	add_child(_prompt)


## A cursed chest asks before it opens: standing at it shows the price, and
## `interact` pays it.
func _offer() -> void:
	var taker := _local_taker()
	_prompt.visible = taker != null and not _spent and not Game.cutscene
	if not _prompt.visible:
		return
	var offer := tr(str(stats.prompt)) if stats.has("prompt") else tr("CHEST_CURSED_PROMPT") % int(stats.get("curse", 0))
	_prompt.text = "%s  %s" % [Settings.key_name("interact"), offer]
	if Input.is_action_just_pressed("interact"):
		open(taker)


## Our own body, alive and standing at this chest.
func _local_taker() -> Player:
	var box: Array = stats.get("hitbox", [20, 20])
	var reach := float(box[0]) * 0.5 + 12.0
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as Player
		if body != null and body.is_multiplayer_authority() and not body.is_dead() \
				and absf(body.global_position.x - global_position.x) <= reach \
				and absf(body.global_position.y - global_position.y) <= 24.0:
			return body
	return null


## Opens a cursed chest for [param taker], here and, online, on the other peer
## (where the opener is a puppet that never walked into anything).
func open(taker: Player) -> void:
	if _spent or taker == null:
		return
	if Net.active:
		_net_open.rpc()
	_on_body_entered(taker)


@rpc("any_peer", "call_remote", "reliable")
func _net_open() -> void:
	var sender := multiplayer.get_remote_sender_id()
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as Player
		if body != null and body.get_multiplayer_authority() == sender:
			_on_body_entered(body)
			return


func _on_body_entered(body: Node) -> void:
	if _spent or _waiting or not (body is Player):
		return
	_spent = true
	remove_from_group("interactable")
	if _prompt != null:
		_prompt.visible = false
	_rest_on_floor()
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


func _rest_on_floor() -> void:
	sprite.offset = _authored_sprite_offset
	sprite.position = _base_sprite_position
	sprite.rotation = 0.0
	sprite.scale = _base_sprite_scale
	_kick = Vector2.ZERO
	_kick_rotation = 0.0


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
	if taker != null and stats.get("kind", "") == "chest" and taker.is_multiplayer_authority():
		if taker.stats.chest_heal > 0.0:
			taker.heal(taker.stats.chest_heal)
		taker.take_curse(int(stats.get("curse", 0)))
		# a blood altar: a hand of gifts for a share of the bar (Run._on_blood_offered)
		if float(stats.get("blood_price", 0.0)) > 0.0:
			EventBus.blood_offered.emit(taker, float(stats.blood_price))
		# the item is the opener's: it goes onto their body, on their machine
		var rarity := str(stats.get("item", ""))
		if rarity != "":
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			var id := ItemSystem.roll(rarity, rng)
			if id != "":
				ItemSystem.give(taker, id)
				Fx.popup(global_position + Vector2(0, -40),
					tr("HUD_ITEM_FOUND") % tr(str(Data.items[id].name)), Color(1.0, 0.86, 0.55), 9)
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
