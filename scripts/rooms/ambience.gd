extends Node2D
class_name Ambience
## The life of a place that has nothing to do with the fight: ravens crossing
## the sky, leaves, wisps over the graves, dust in a crypt, low fog, lightning.
## Which effects a room gets is data (data/ambience.json, matched by the room's
## scene name), so a new room only needs a name. Everything is CPUParticles2D
## or a sprite: the GL Compatibility renderer and the Web build have no GPU
## particles. Added by Room._ready. It observes physical beats from the player
## so the scenery answers them, but never changes gameplay or collision.

const RULES_PATH := "res://data/ambience.json"
const RAVEN_STRIP := "res://assets/sprites/raven_fly.png"
const RAVEN_CELL := Vector2i(48, 28)
const FOG_SHADER := preload("res://assets/shaders/fog.gdshader")
const STORM_CLOUDS := preload("res://assets/environment/storm_clouds_v1.png")

var width := 1280.0
var height := 360.0
var _lightning_timer := 0.0
var _lightning_gap := Vector2(6.0, 16.0)
var _flash: ColorRect
var _birds: Array[AnimatedSprite2D] = []
var _bird_speed := {}
var _cloud_layers: Array[Parallax2D] = []
var _cloud_sprites: Array[Sprite2D] = []
var _reactive_sprites: Array[Sprite2D] = []
var _rest_rotation := {}
var _wind_energy := 0.0
var _wind_origin := Vector2.ZERO
var _wind_direction := Vector2.RIGHT
var _clear_glow := 0.0
var _elapsed := 0.0
var _hero: CharacterBody2D


func _ready() -> void:
	EventBus.world_impulse.connect(_on_world_impulse)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.room_cleared.connect(_on_room_cleared)
	call_deferred("_collect_reactive_scenery")


## Reads the rule table and builds the matching effects under [param room].
static func attach(room: Node2D, scene_name: String, room_width: float, room_height: float) -> Ambience:
	var effects := _effects_for(scene_name)
	if effects.is_empty():
		return null
	var ambience := Ambience.new()
	ambience.name = "Ambience"
	ambience.width = room_width
	ambience.height = room_height
	ambience.z_index = 2  # with the weather, over the props, under the effects
	room.add_child(ambience)
	for effect in effects:
		ambience._build(str(effect))
	return ambience


static func _effects_for(scene_name: String) -> Array:
	if not FileAccess.file_exists(RULES_PATH):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
	if not parsed is Dictionary:
		return []
	for rule in parsed.get("rules", []):
		var needle := str(rule.get("match", ""))
		if needle != "" and scene_name.contains(needle):
			return rule.get("effects", [])
	return parsed.get("default", [])


func _build(effect: String) -> void:
	match effect:
		"ravens":
			_ravens(3)
		"bats":
			_ravens(5, true)
		"leaves":
			_leaves(Color(0.45, 0.3, 0.16, 0.85))
		"petals":
			_leaves(Color(0.75, 0.55, 0.6, 0.8))
		"wisps":
			_wisps()
		"motes":
			_motes()
		"embers":
			_embers()
		"low_fog":
			_low_fog()
		"lightning":
			_lightning_timer = randf_range(2.0, 6.0)
		"clouds":
			_clouds()
		_:
			push_warning("[Ambience] unknown effect \"%s\"" % effect)


func _process(delta: float) -> void:
	_elapsed += delta
	_wind_energy = move_toward(_wind_energy, 0.0, delta * 0.8)
	_clear_glow = move_toward(_clear_glow, 0.0, delta * 0.12)
	_update_clouds(delta)
	_update_reactive_scenery(delta)
	for bird in _birds:
		var speed: float = _bird_speed[bird]
		bird.position.x += speed * delta
		bird.position.y += sin(Time.get_ticks_msec() / 500.0 + bird.get_index()) * 6.0 * delta
		if (speed > 0.0 and bird.position.x > width + 80.0) or (speed < 0.0 and bird.position.x < -80.0):
			_relaunch(bird)
	if _lightning_timer > 0.0:
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_strike()


# -------------------------------------------------------------- depth ---

## Two translucent banks at different speeds separate the painted sky from
## the playable stone. The generated texture is deliberately sparse: it adds
## depth without hiding the artist's original panel.
func _clouds() -> void:
	for i in 2:
		var layer := Parallax2D.new()
		layer.name = "CloudsFar" if i == 0 else "CloudsNear"
		layer.scroll_scale = Vector2(0.18 + i * 0.14, 0.08 + i * 0.08)
		layer.repeat_size = Vector2(maxf(width, 960.0), 0.0)
		layer.z_index = -1
		add_child(layer)
		_cloud_layers.append(layer)
		for copy in 2:
			var cloud := Sprite2D.new()
			cloud.texture = STORM_CLOUDS
			cloud.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			cloud.position = Vector2(width * (0.25 + copy * 0.62), height * (0.08 + i * 0.11))
			var scale_factor := (0.42 + i * 0.11) * maxf(0.75, width / 1280.0)
			cloud.scale = Vector2(scale_factor * (-1.0 if copy == 1 else 1.0), scale_factor)
			cloud.modulate = Color(0.62, 0.69, 0.82, 0.11 + i * 0.055)
			layer.add_child(cloud)
			_cloud_sprites.append(cloud)


func _update_clouds(delta: float) -> void:
	for i in _cloud_layers.size():
		var drift := (3.0 + i * 3.5) * (1.0 + _wind_energy * 1.8)
		_cloud_layers[i].scroll_offset.x += drift * delta * _wind_direction.x
	for i in _cloud_sprites.size():
		var base_alpha := 0.11 + (i / 2) * 0.055
		_cloud_sprites[i].modulate.a = base_alpha + _clear_glow * 0.035


## Trees, brush, grass and loose graveyard silhouettes keep their authored
## positions; only a few degrees of rotation are layered on top. A dash bends
## nearby shapes more than a jump, and the motion falls off with distance.
func _collect_reactive_scenery() -> void:
	var room := get_parent()
	if room == null:
		return
	_collect_reactive_under(room)


func _collect_reactive_under(node: Node) -> void:
	for child in node.get_children():
		if child == self:
			continue
		if child is Sprite2D and _is_reactive_name(str(child.name).to_lower()):
			var sprite := child as Sprite2D
			_reactive_sprites.append(sprite)
			_rest_rotation[sprite] = sprite.rotation
		_collect_reactive_under(child)


func _is_reactive_name(value: String) -> bool:
	for needle in ["tree", "grass", "bush", "brush", "sapling", "deadwood", "leaves", "railing", "fence"]:
		if value.contains(needle):
			return true
	return false


func _update_reactive_scenery(delta: float) -> void:
	if _hero == null or not is_instance_valid(_hero):
		for node in get_tree().get_nodes_in_group("player"):
			if node is CharacterBody2D:
				_hero = node
				break
	for sprite in _reactive_sprites:
		if not is_instance_valid(sprite):
			continue
		var rest := float(_rest_rotation.get(sprite, 0.0))
		var natural := sin(_elapsed * 0.75 + sprite.global_position.x * 0.017) * 0.008
		var distance := sprite.global_position.distance_to(_wind_origin)
		var gust := _wind_energy * clampf(1.0 - distance / 300.0, 0.0, 1.0)
		if _hero != null:
			var hero_distance := absf(sprite.global_position.x - _hero.global_position.x)
			natural += clampf(1.0 - hero_distance / 180.0, 0.0, 1.0) * _hero.velocity.x * 0.000025
		var target := rest + natural + gust * _wind_direction.x * 0.045
		sprite.rotation = lerp_angle(sprite.rotation, target, 1.0 - exp(-delta * 6.0))


func _on_world_impulse(at: Vector2, direction: Vector2, strength: float, _kind: StringName) -> void:
	if not Rect2(-120.0, -120.0, width + 240.0, height + 240.0).has_point(at):
		return
	_wind_origin = at
	_wind_direction = direction.normalized() if direction.length_squared() > 0.01 else Vector2.RIGHT
	_wind_energy = maxf(_wind_energy, strength)
	_spawn_air_wake(at, _wind_direction, strength)


func _spawn_air_wake(at: Vector2, direction: Vector2, strength: float) -> void:
	var wake := CPUParticles2D.new()
	wake.one_shot = true
	wake.explosiveness = 0.9
	wake.amount = clampi(int(5.0 + strength * 8.0), 5, 18)
	wake.lifetime = 0.45 + strength * 0.18
	wake.texture = Fx._build_spark(3, 0.35)
	wake.position = at
	wake.direction = direction
	wake.spread = 42.0
	wake.gravity = Vector2(0.0, -4.0)
	wake.initial_velocity_min = 18.0 * strength
	wake.initial_velocity_max = 42.0 * strength
	wake.scale_amount_min = 0.35
	wake.scale_amount_max = 0.9
	wake.color = Color(0.72, 0.76, 0.82, 0.22)
	wake.color_ramp = Fx._build_ramp([[0.0, 0.0], [0.15, 0.8], [1.0, 0.0]])
	add_child(wake)
	wake.finished.connect(wake.queue_free)
	wake.emitting = true


func _on_enemy_died(_enemy_id: StringName, at: Vector2) -> void:
	_on_world_impulse(at, Vector2(0.0, -1.0), 0.55, &"enemy_death")


func _on_room_cleared(_index: int) -> void:
	_clear_glow = 1.0
	_wind_origin = Vector2(width * 0.5, height * 0.5)
	_wind_direction = Vector2.RIGHT
	_wind_energy = maxf(_wind_energy, 0.8)


# ------------------------------------------------------------------ birds ---

func _ravens(count: int, small := false) -> void:
	var frames := SpriteFrames.new()
	if not Fx.add_strip(frames, RAVEN_STRIP, RAVEN_CELL, 12.0, "fly", true):
		return
	for i in count:
		var bird := AnimatedSprite2D.new()
		bird.sprite_frames = frames
		bird.play("fly")
		bird.frame = randi() % maxi(1, frames.get_frame_count("fly"))
		bird.scale = Vector2.ONE * (0.45 if small else randf_range(0.55, 0.8))
		bird.modulate = Color(0.25, 0.22, 0.28, 0.9)  # a silhouette against the sky
		add_child(bird)
		_birds.append(bird)
		_relaunch(bird, true)


func _relaunch(bird: AnimatedSprite2D, first := false) -> void:
	var to_right := randf() < 0.5
	_bird_speed[bird] = randf_range(40.0, 75.0) * (1.0 if to_right else -1.0)
	bird.flip_h = not to_right
	var start_x := randf_range(0.0, width) if first else (-60.0 if to_right else width + 60.0)
	bird.position = Vector2(start_x, randf_range(30.0, height * 0.45))
	bird.visible = first
	if not first:
		# Birds come in flocks with gaps, not on a conveyor belt.
		var timer := get_tree().create_timer(randf_range(3.0, 12.0))
		timer.timeout.connect(_show_bird_after_gap.bind(weakref(bird)))


func _show_bird_after_gap(bird_ref: WeakRef) -> void:
	var bird = bird_ref.get_ref()
	if bird is AnimatedSprite2D:
		bird.visible = true


# -------------------------------------------------------------- particles ---

func _particles(amount: int, lifetime: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = maxi(4, amount)
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.position = Vector2(width / 2.0, height / 2.0)
	p.emission_rect_extents = Vector2(width / 2.0 + 60.0, height / 2.0)
	add_child(p)
	return p


func _leaves(tint: Color) -> void:
	var p := _particles(int(width / 40.0), 7.0)
	p.texture = Fx._build_spark(3, 0.9)
	p.position.y = -20.0
	p.emission_rect_extents.y = 10.0
	p.direction = Vector2(0.4, 1.0)
	p.spread = 30.0
	p.gravity = Vector2(6.0, 14.0)
	p.initial_velocity_min = 12.0
	p.initial_velocity_max = 30.0
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.scale_amount_min = 0.9
	p.scale_amount_max = 1.6
	p.color = tint
	p.color_ramp = Fx._build_ramp([[0.0, 0.0], [0.1, 1.0], [0.9, 1.0], [1.0, 0.0]])


func _wisps() -> void:
	var p := _particles(int(width / 110.0), 9.0)
	p.texture = Fx._build_spark(10, 0.4)
	p.position.y = height * 0.7
	p.emission_rect_extents.y = height * 0.2
	p.direction = Vector2(0.0, -1.0)
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 12.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.color = Color(0.55, 0.8, 1.0, 0.55)
	p.color_ramp = Fx._build_ramp([[0.0, 0.0], [0.3, 1.0], [0.7, 0.8], [1.0, 0.0]])
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = material


func _motes() -> void:
	var p := _particles(int(width / 16.0), 12.0)
	p.texture = Fx._build_spark(3, 0.5)
	p.direction = Vector2(1.0, 0.0)
	p.spread = 180.0
	p.gravity = Vector2(0.0, -1.5)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 7.0
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.8
	p.color = Color(0.85, 0.8, 0.7, 0.4)
	p.color_ramp = Fx._build_ramp([[0.0, 0.0], [0.2, 1.0], [0.8, 1.0], [1.0, 0.0]])


func _embers() -> void:
	var p := _particles(int(width / 30.0), 6.0)
	p.texture = Fx._build_spark(4, 0.6)
	p.position.y = height + 10.0
	p.emission_rect_extents.y = 8.0
	p.direction = Vector2(0.0, -1.0)
	p.spread = 25.0
	p.gravity = Vector2(0.0, -12.0)
	p.initial_velocity_min = 15.0
	p.initial_velocity_max = 45.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.color = Color(1.0, 0.6, 0.25, 0.8)
	p.color_ramp = Fx._build_ramp([[0.0, 0.0], [0.15, 1.0], [0.8, 0.7], [1.0, 0.0]])


func _low_fog() -> void:
	var fog := ColorRect.new()
	var material := ShaderMaterial.new()
	material.shader = FOG_SHADER
	var noise := NoiseTexture2D.new()
	noise.seamless = true
	noise.noise = FastNoiseLite.new()
	noise.noise.frequency = 0.02
	material.set_shader_parameter("noise", noise)
	material.set_shader_parameter("density", 0.5)
	material.set_shader_parameter("speed", 0.03)
	material.set_shader_parameter("bottom_bias", 0.2)
	fog.material = material
	fog.size = Vector2(width + 200.0, height * 0.35)
	fog.position = Vector2(-100.0, height * 0.7)
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fog)


# --------------------------------------------------------------- lightning ---

func _strike() -> void:
	_lightning_timer = randf_range(_lightning_gap.x, _lightning_gap.y)
	if _flash == null:
		_flash = ColorRect.new()
		_flash.color = Color(0.85, 0.9, 1.0, 0.0)
		_flash.size = Vector2(width + 400.0, height + 400.0)
		_flash.position = Vector2(-200.0, -200.0)
		_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash.z_index = 3
		add_child(_flash)
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.55, 0.04)
	tween.tween_property(_flash, "color:a", 0.1, 0.08)
	tween.tween_property(_flash, "color:a", 0.4, 0.05)
	tween.tween_property(_flash, "color:a", 0.0, 0.35)
	Fx.flash(Vector2(randf_range(0.0, width), 40.0), Color(0.8, 0.85, 1.0), 400.0, 0.4, 1.5)
	# Thunder arrives after the light, the way it does.
	get_tree().create_timer(randf_range(0.4, 1.6)).timeout.connect(func() -> void: Audio.play(&"thunder", -6.0))
