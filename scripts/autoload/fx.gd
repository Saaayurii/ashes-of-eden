extends Node
## Spawns fire-and-forget effects into the current scene: smoke puffs, sparks,
## dust, ash, light flashes, floating damage numbers. Cheap to call from anywhere.
##
## Everything here is CPUParticles2D or a sprite on purpose: the GL
## Compatibility renderer and the Web build have no GPU particles. Lights are
## GlowLight (PointLight2D) and obey the "Lighting" setting by themselves.
## Draw order inside a room (see docs/DATA_FORMATS.md, Rooms): props and
## characters sit at z 0, foreground clutter at 1, weather at 2, effects 5-6,
## numbers 10.

const SMOKE_STRIP := "res://assets/sprites/smoke.png"
const SMOKE_CELL := Vector2i(32, 32)
## What a sword leaves on a body: drawn strips, cut by tools/art/slice_hero.py.
const HIT_STRIPS := {"spark": "res://assets/sprites/hit_spark.png", "blood": "res://assets/sprites/hit_blood.png"}
const HIT_CELL := Vector2i(80, 48)
const SHADOW_TEXTURE := preload("res://assets/fx/shadow_blob.tres")
const ESSENCE_LIGHT_SHEET := preload("res://assets/fx/essence_light_flight_v3.png")
const ESSENCE_DARK_SHEET := preload("res://assets/fx/essence_dark_flight_v3.png")
const ESSENCE_FRAGMENT := preload("res://scripts/fx/essence_fragment.gd")

var _smoke_frames: SpriteFrames
var _hit_frames := {}
var _spark: GradientTexture2D
var _soft: GradientTexture2D
var _chunk: ImageTexture
var _fade_out: Gradient
var _fade_in_out: Gradient
var _shrink: Curve
var _essence_frames := {}


func _ready() -> void:
	_smoke_frames = _strip_frames(SMOKE_STRIP, SMOKE_CELL, 14.0)
	for kind in HIT_STRIPS:
		_hit_frames[kind] = _strip_frames(HIT_STRIPS[kind], HIT_CELL, 20.0)
	_spark = _build_spark()
	_soft = _build_spark(12, 0.35)
	_chunk = _build_chunk()
	_fade_out = _build_ramp([[0.0, 1.0], [0.6, 0.9], [1.0, 0.0]])
	_fade_in_out = _build_ramp([[0.0, 0.0], [0.15, 1.0], [0.7, 0.8], [1.0, 0.0]])
	_shrink = Curve.new()
	_shrink.add_point(Vector2(0.0, 1.0))
	_shrink.add_point(Vector2(1.0, 0.15))
	_essence_frames[false] = _essence_sprite_frames(ESSENCE_LIGHT_SHEET)
	_essence_frames[true] = _essence_sprite_frames(ESSENCE_DARK_SHEET)


## The drawn burst of a hit: "spark" for steel on flesh, "blood" for the blow
## that opens something. [param flip] mirrors it to face the way the blade went.
func hit(position: Vector2, kind := "spark", scale := 1.0, flip := false) -> void:
	var parent := get_tree().current_scene
	var frames: SpriteFrames = _hit_frames.get(kind)
	if parent == null or frames == null:
		return
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.global_position = position
	sprite.scale = Vector2.ONE * scale
	sprite.flip_h = flip
	sprite.rotation = randf_range(-0.3, 0.3)
	sprite.z_index = 6
	parent.add_child(sprite)
	sprite.play("default")
	sprite.animation_finished.connect(sprite.queue_free)


func puff(position: Vector2, scale := 1.0, tint := Color.WHITE) -> void:
	var parent := get_tree().current_scene
	if parent == null or _smoke_frames == null:
		return
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = _smoke_frames
	sprite.global_position = position
	sprite.scale = Vector2.ONE * scale
	sprite.modulate = tint
	sprite.z_index = 5
	sprite.flip_h = randf() < 0.5
	parent.add_child(sprite)
	sprite.play("default")
	sprite.animation_finished.connect(sprite.queue_free)


## The spray of sparks a sword throws off a body. CPUParticles on purpose:
## the GL Compatibility renderer and the Web build have no GPU particles.
## [param direction] points away from whoever swung.
func impact(position: Vector2, direction: Vector2, tint := Color(1, 0.88, 0.65), amount := 9) -> void:
	var parent := get_tree().current_scene
	if parent == null or _spark == null:
		return
	var burst := CPUParticles2D.new()
	burst.texture = _spark
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = amount
	burst.lifetime = 0.3
	burst.direction = direction.normalized() if direction.length() > 0.01 else Vector2.RIGHT
	burst.spread = 42.0
	burst.initial_velocity_min = 90.0
	burst.initial_velocity_max = 230.0
	burst.gravity = Vector2(0, 340)
	burst.damping_min = 120.0
	burst.damping_max = 260.0
	burst.scale_amount_min = 0.4
	burst.scale_amount_max = 1.1
	burst.color = tint
	burst.z_index = 6
	burst.global_position = position
	burst.emitting = true
	parent.add_child(burst)
	burst.finished.connect(burst.queue_free)


## Ground dust: a boot landing, a roll, a body dropping. [param direction]
## is where the dust is kicked; Vector2.UP for a plain landing.
func dust(position: Vector2, direction := Vector2.UP, amount := 7, tint := Color(0.62, 0.56, 0.5, 0.75)) -> void:
	var burst := _burst(position, amount, 0.45)
	if burst == null:
		return
	burst.texture = _soft
	burst.direction = direction.normalized() if direction.length() > 0.01 else Vector2.UP
	burst.spread = 70.0
	burst.initial_velocity_min = 25.0
	burst.initial_velocity_max = 70.0
	burst.gravity = Vector2(0, -40)
	burst.damping_min = 60.0
	burst.damping_max = 120.0
	burst.scale_amount_min = 0.5
	burst.scale_amount_max = 1.1
	burst.color = tint
	burst.color_ramp = _fade_out
	burst.z_index = 4
	burst.emitting = true


## What a body leaves behind: motes of its own colour drifting up and out.
## Ash for the possessed, a soul for a spirit; [param rise] is how fast it climbs.
func ash(position: Vector2, tint := Color(0.8, 0.75, 0.7), amount := 16, rise := 40.0, spread_px := 10.0) -> void:
	var burst := _burst(position, amount, 1.1)
	if burst == null:
		return
	burst.texture = _spark
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = spread_px
	burst.direction = Vector2.UP
	burst.spread = 55.0
	burst.initial_velocity_min = rise * 0.4
	burst.initial_velocity_max = rise
	burst.gravity = Vector2(0, -rise * 0.5)
	burst.damping_min = 10.0
	burst.damping_max = 25.0
	burst.scale_amount_min = 0.5
	burst.scale_amount_max = 1.3
	burst.scale_amount_curve = _shrink
	burst.color = tint
	burst.color_ramp = _fade_in_out
	burst.z_index = 6
	burst.emitting = true


## A readable burst of experience-like fragments on every enemy death. It is
## intentionally cosmetic: rewards remain owned by Game.add_essence.
func essence_release(position: Vector2, dark := false, amount := 9) -> void:
	var parent := get_tree().current_scene
	if parent == null:
		return
	var frames: SpriteFrames = _essence_frames[dark]
	for i in maxi(4, int(amount * 0.75)):
		var shard: AnimatedSprite2D = ESSENCE_FRAGMENT.new()
		shard.sprite_frames = frames
		shard.z_index = 7
		shard.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var launch := Vector2.UP.rotated(deg_to_rad(randf_range(-52.5, 52.5)))
		launch *= randf_range(55.0, 105.0) if dark else randf_range(68.0, 135.0)
		shard.configure(launch, -12.0 if dark else 90.0,
			deg_to_rad(randf_range(-170.0, 170.0)),
			randf_range(1.05, 1.25) if dark else randf_range(0.92, 1.08),
			randf_range(0.5, 0.85 if dark else 0.75))
		parent.add_child(shard)
		shard.global_position = position + Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
	var motes := _burst(position, maxi(4, int(amount / 2)), 1.35, 0.85)
	motes.texture = _soft
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 6.0
	motes.direction = Vector2.UP
	motes.spread = 58.0
	motes.initial_velocity_min = 22.0
	motes.initial_velocity_max = 62.0
	motes.gravity = Vector2(0, -28)
	motes.scale_amount_min = 0.35
	motes.scale_amount_max = 0.65
	motes.color = Color(0.49, 0.89, 0.82, 0.55) if dark else Color(1.0, 0.97, 0.78, 0.7)
	motes.color_ramp = _fade_in_out
	motes.z_index = 7
	motes.emitting = true


func _essence_sprite_frames(sheet: Texture2D) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.add_animation("dissolve")
	frames.set_animation_speed("dissolve", 4.0)
	frames.set_animation_loop("dissolve", false)
	var cell_width := sheet.get_width() / 4
	for index in 4:
		var cell := AtlasTexture.new()
		cell.atlas = sheet
		cell.region = Rect2(index * cell_width, 0, cell_width, sheet.get_height())
		cell.filter_clip = true
		frames.add_frame("dissolve", cell)
	return frames


## A chest opening, a heal, a shrine waking: twinkles floating up.
func sparkle(position: Vector2, tint := Color(1, 0.9, 0.6), amount := 14, width := 14.0) -> void:
	var burst := _burst(position, amount, 0.9, 0.7)
	if burst == null:
		return
	burst.texture = _spark
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	burst.emission_rect_extents = Vector2(width, 4)
	burst.direction = Vector2.UP
	burst.spread = 20.0
	burst.initial_velocity_min = 30.0
	burst.initial_velocity_max = 70.0
	burst.gravity = Vector2(0, -30)
	burst.scale_amount_min = 0.4
	burst.scale_amount_max = 1.0
	burst.scale_amount_curve = _shrink
	burst.color = tint
	burst.color_ramp = _fade_in_out
	burst.z_index = 6
	burst.emitting = true


## Splinters and shards when a prop breaks: chunks that fly, fall and fade.
func debris(position: Vector2, tint := Color(0.6, 0.45, 0.3), amount := 9) -> void:
	var burst := _burst(position, amount, 0.7)
	if burst == null:
		return
	burst.texture = _chunk
	burst.direction = Vector2.UP
	burst.spread = 60.0
	burst.initial_velocity_min = 70.0
	burst.initial_velocity_max = 160.0
	burst.gravity = Vector2(0, 420)
	burst.angular_velocity_min = -400.0
	burst.angular_velocity_max = 400.0
	burst.scale_amount_min = 0.7
	burst.scale_amount_max = 1.4
	burst.color = tint
	burst.color_ramp = _fade_out
	burst.z_index = 5
	burst.emitting = true


## A one-shot light: a hit, a blast, a chest opening. Fades out and frees itself.
func flash(position: Vector2, tint := Color(1, 0.9, 0.7), radius := 60.0, duration := 0.25, energy := 1.2) -> void:
	var parent := get_tree().current_scene
	if parent == null or not Settings.lighting:
		return
	var light := GlowLight.new()
	light.radius = radius
	light.color = tint
	light.energy = energy
	light.global_position = position
	parent.add_child(light)
	var tween := light.create_tween()
	tween.tween_property(light, "energy", 0.0, duration).set_ease(Tween.EASE_IN)
	tween.tween_callback(light.queue_free)


## A light that belongs to something: a carried lantern, a chest, a ghost.
## Parented so it moves with its owner and dies with it.
func light(parent: Node, offset: Vector2, tint: Color, radius: float, energy := 1.0, flicker := 0.0, breathe := 0.0) -> GlowLight:
	var light := GlowLight.new()
	light.name = "Light"
	light.position = offset
	light.radius = radius
	light.color = tint
	light.energy = energy
	light.flicker = flicker
	light.breathe = breathe
	parent.add_child(light)
	return light


## A trail of motes something leaves while it moves (projectiles). Parented;
## particles are emitted in world space so they hang in the air behind it.
func trail(parent: Node, tint: Color, amount := 12, lifetime := 0.45) -> CPUParticles2D:
	var emitter := CPUParticles2D.new()
	emitter.name = "Trail"
	emitter.texture = _spark
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.local_coords = false
	emitter.direction = Vector2.UP
	emitter.spread = 180.0
	emitter.initial_velocity_min = 4.0
	emitter.initial_velocity_max = 14.0
	emitter.gravity = Vector2.ZERO
	emitter.scale_amount_min = 0.5
	emitter.scale_amount_max = 1.0
	emitter.scale_amount_curve = _shrink
	emitter.color = tint
	emitter.color_ramp = _fade_out
	emitter.z_index = 4
	parent.add_child(emitter)
	return emitter


## The soft blob under something standing on the floor. Anchors props and
## bodies to the ground so a character walking past a barrel reads as "in
## front of", not "through". Sized to the owner's footprint in pixels.
func shadow(parent: Node, offset: Vector2, width := 24.0, opacity := 1.0) -> Sprite2D:
	var blob := Sprite2D.new()
	blob.name = "Shadow"
	blob.texture = SHADOW_TEXTURE
	blob.position = offset
	blob.scale = Vector2(width / SHADOW_TEXTURE.width, 1.0)
	blob.modulate.a = opacity
	blob.show_behind_parent = true
	parent.add_child(blob)
	return blob


func damage_number(position: Vector2, amount: float, color := Color(1, 0.95, 0.8)) -> void:
	popup(position + Vector2(randf_range(-6, 6), 0), str(int(round(amount))), color, 10)


## A word that floats up and fades: a damage number, the "!" over a head that
## just turned, the name of a special hit. Centred on [param position].
func popup(position: Vector2, text: String, color := Color(1, 0.95, 0.8), font_size := 10) -> void:
	var parent := get_tree().current_scene
	if parent == null:
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(80, 14)
	label.z_index = 10
	label.top_level = true
	parent.add_child(label)
	label.global_position = position + Vector2(-40, -22)
	var tween := label.create_tween()
	tween.tween_property(label, "global_position:y", label.global_position.y - 18.0, 0.55).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.55).set_delay(0.2)
	tween.tween_callback(label.queue_free)


## One-shot emitter in the current scene, freed when the last particle dies.
func _burst(position: Vector2, amount: int, lifetime: float, explosiveness := 1.0) -> CPUParticles2D:
	var parent := get_tree().current_scene
	if parent == null:
		return null
	var burst := CPUParticles2D.new()
	burst.one_shot = true
	burst.explosiveness = explosiveness
	burst.amount = amount
	burst.lifetime = lifetime
	burst.local_coords = false
	burst.global_position = position
	parent.add_child(burst)
	burst.finished.connect(burst.queue_free)
	return burst


## A soft dot; a spark is just one of these thrown fast and dimmed by gravity.
## [param core] is how far the fully opaque centre reaches (1 = hard edge).
func _build_spark(size := 4, core := 0.0) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, core, 1.0]) if core > 0.0 else PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]) if core > 0.0 \
		else PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = size
	texture.height = size
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	return texture


## A hard 3x3 square: a splinter, a shard.
func _build_chunk() -> ImageTexture:
	var image := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


## Alpha over a particle's life: [[t, alpha], ...].
func _build_ramp(points: Array) -> Gradient:
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for point in points:
		offsets.append(float(point[0]))
		colors.append(Color(1, 1, 1, float(point[1])))
	gradient.offsets = offsets
	gradient.colors = colors
	return gradient


## Builds SpriteFrames from a horizontal strip of equal cells.
static func _strip_frames(path: String, cell: Vector2i, fps: float, animation := "default", loop := false) -> SpriteFrames:
	var texture: Texture2D = load(path)
	if texture == null:
		push_warning("[Fx] missing strip %s" % path)
		return null
	var frames := SpriteFrames.new()
	if not frames.has_animation(animation):
		frames.add_animation(animation)
	frames.set_animation_speed(animation, fps)
	frames.set_animation_loop(animation, loop)
	for i in int(texture.get_width() / cell.x):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(i * cell.x, 0, cell.x, cell.y)
		frames.add_frame(animation, atlas)
	return frames


## Adds one more strip as an animation to an existing SpriteFrames.
static func add_strip(frames: SpriteFrames, path: String, cell: Vector2i, fps: float, animation: String, loop := true) -> bool:
	if path.strip_edges().is_empty() or path == "res://":
		push_warning("[Fx] empty path for animation %s" % animation)
		return false
	var texture: Texture2D = load(path)
	if texture == null:
		push_warning("[Fx] missing strip %s" % path)
		return false
	if not frames.has_animation(animation):
		frames.add_animation(animation)
	frames.set_animation_speed(animation, fps)
	frames.set_animation_loop(animation, loop)
	for i in int(texture.get_width() / cell.x):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(i * cell.x, 0, cell.x, cell.y)
		frames.add_frame(animation, atlas)
	return true
