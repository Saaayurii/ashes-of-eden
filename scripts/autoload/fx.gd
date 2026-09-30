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
## Particle shapes, white, coloured by the emitter: # solid, + 60 %, : 30 %.
## Drawn at one texel per screen pixel of the 640x360 view, so they stay
## small and sharp; the emitters never scale them up.
const PIXELS := {
	"mote": [".+.", "+#+", ".+."],
	"flake": ["##+", "+#:"],
	"drop": [".+.", "+#+", "###", ".#."],
	"scrap": ["###+", ":##+"],
	"shard": ["#..", "##:", "+##"],
	"feather": [".....+#", "..:+##+", ":+##+..", "+#:...."],
	"wisp": [".:.", ".+.", "+#+", ".#.", ".+.", ".:."],
	"star": ["..+..", "..#..", "+###+", "..#..", "..+.."],
	"ember": ["+#", "#+"],
}
## What a body leaves when it dies, by its material (data/enemies): [shape,
## colour (null = the creature's own), count, launch speed, gravity, spread,
## spin, life]. Few and small: the drawn death animation is the event.
const REMAINS := {
	"flesh": [["drop", Color(0.52, 0.06, 0.07), 9, 120.0, 460.0, 55.0, 0.0, 0.8],
		["flake", Color(0.42, 0.36, 0.34), 5, 30.0, -30.0, 70.0, 90.0, 1.2]],
	"cloth": [["scrap", null, 6, 70.0, 70.0, 80.0, 220.0, 1.3],
		["flake", Color(0.35, 0.32, 0.33), 6, 30.0, -35.0, 70.0, 90.0, 1.2]],
	"plate": [["shard", Color(0.62, 0.6, 0.6), 7, 150.0, 560.0, 60.0, 600.0, 0.8],
		["ember", Color(1.0, 0.62, 0.25), 6, 110.0, 200.0, 70.0, 0.0, 0.45]],
	"mail": [["shard", Color(0.55, 0.55, 0.58), 7, 140.0, 560.0, 60.0, 600.0, 0.8],
		["ember", Color(1.0, 0.7, 0.35), 5, 100.0, 200.0, 70.0, 0.0, 0.4]],
	"spirit": [["wisp", null, 9, 45.0, -60.0, 60.0, 0.0, 1.1],
		["mote", null, 7, 60.0, -20.0, 180.0, 0.0, 0.8]],
	"feather": [["feather", Color(0.13, 0.11, 0.15), 8, 70.0, 45.0, 180.0, 160.0, 1.6],
		["mote", Color(0.55, 0.12, 0.16), 3, 50.0, 200.0, 90.0, 0.0, 0.5]],
	"gold": [["star", Color(1.0, 0.86, 0.5), 8, 70.0, -25.0, 180.0, 0.0, 1.1],
		["mote", Color(1.0, 0.96, 0.8), 10, 110.0, -10.0, 180.0, 0.0, 0.7]],
}

var _smoke_frames: SpriteFrames
var _hit_frames := {}
var _soft: GradientTexture2D
## Tiny pixel shapes drawn 1:1 (see PIXELS): a particle is a glint, a drop,
## a feather, never a soft dot blown up into a square.
var _pixel := {}
var _ember_ramp: Gradient
var _fade_out: Gradient
var _fade_in_out: Gradient
var _shrink: Curve
var _essence_frames := {}


func _ready() -> void:
	_smoke_frames = _strip_frames(SMOKE_STRIP, SMOKE_CELL, 14.0)
	for kind in HIT_STRIPS:
		_hit_frames[kind] = _strip_frames(HIT_STRIPS[kind], HIT_CELL, 20.0)
	_soft = _build_spark(12, 0.35)
	for shape in PIXELS:
		_pixel[shape] = _build_pixels(PIXELS[shape])
	_ember_ramp = Gradient.new()
	_ember_ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	_ember_ramp.colors = PackedColorArray([Color(1.3, 1.2, 0.9, 1), Color(1, 0.7, 0.5, 0.9), Color(0.6, 0.2, 0.1, 0)])
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
	if parent == null or _pixel.is_empty():
		return
	var burst := CPUParticles2D.new()
	burst.texture = _pixel.mote
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
	burst.color = tint
	burst.color_ramp = _fade_out
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
	burst.texture = _pixel.mote
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = spread_px
	burst.direction = Vector2.UP
	burst.spread = 55.0
	burst.initial_velocity_min = rise * 0.4
	burst.initial_velocity_max = rise
	burst.gravity = Vector2(0, -rise * 0.5)
	burst.damping_min = 10.0
	burst.damping_max = 25.0
	burst.color = tint
	burst.color_ramp = _fade_in_out
	burst.z_index = 6
	burst.emitting = true


## What a body leaves behind as it goes, by what it is made of (REMAINS):
## blood for flesh, scraps for cloth, shards and sparks for armour, wisps for
## spirits, feathers for birds, stars for the heavenly. [param tint] is the
## creature's own colour, for the shapes that take it; [param scale] scales
## the count (a boss leaves more), never the size.
func remains(position: Vector2, material: String, tint: Color, scale := 1.0) -> void:
	for recipe in REMAINS.get(material, REMAINS.cloth):
		var shape: String = recipe[0]
		var burst := _burst(position, maxi(2, int(round(recipe[2] * scale))), recipe[7], 0.9)
		if burst == null:
			return
		burst.texture = _pixel[shape]
		burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		burst.emission_sphere_radius = 6.0 * sqrt(scale)
		burst.direction = Vector2.UP
		burst.spread = recipe[5]
		burst.initial_velocity_min = recipe[3] * 0.45
		burst.initial_velocity_max = recipe[3]
		burst.gravity = Vector2(0, recipe[4])
		burst.damping_min = 8.0
		burst.damping_max = 30.0 if recipe[4] < 100.0 else 12.0
		burst.angular_velocity_min = -recipe[6]
		burst.angular_velocity_max = recipe[6]
		burst.angle_min = 0.0
		burst.angle_max = 360.0 if recipe[6] > 0.0 else 0.0
		burst.color = tint if recipe[1] == null else recipe[1]
		burst.color_ramp = _ember_ramp if shape == "ember" else (_fade_in_out if recipe[4] < 0.0 else _fade_out)
		burst.z_index = 6
		burst.emitting = true


## A readable burst of experience-like fragments on every enemy death. It is
## intentionally cosmetic: rewards remain owned by Game.add_essence.
func essence_release(position: Vector2, dark := false, amount := 9) -> void:
	var parent := get_tree().current_scene
	if parent == null:
		return
	var frames: SpriteFrames = _essence_frames[dark]
	var palette := [
		Color(0.91, 0.64, 1.0), Color(1.0, 0.62, 0.83),
		Color(0.62, 0.95, 0.91), Color(1.0, 0.85, 1.0),
	] if dark else [
		Color(1.0, 0.85, 0.52), Color(1.0, 0.98, 0.78),
		Color(0.78, 0.9, 1.0), Color(1.0, 0.7, 0.47),
	]
	for i in maxi(4, int(amount * 0.75)):
		var shard: AnimatedSprite2D = ESSENCE_FRAGMENT.new()
		shard.sprite_frames = frames
		shard.z_index = 6
		shard.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# A broad fan clears the corpse instead of stacking large sprites above it.
		var launch := Vector2.RIGHT.rotated(randf_range(-PI - 0.28, 0.28))
		launch *= randf_range(115.0, 205.0)
		shard.configure(launch, -24.0 if dark else 68.0,
			deg_to_rad(randf_range(-240.0, 240.0)),
			randf_range(0.82, 1.08), randf_range(0.24, 0.40))
		shard.modulate = palette[i % palette.size()]
		parent.add_child(shard)
		shard.global_position = position + Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
	# Tiny contrasting glints carry the palette into the surrounding air.
	var spark_colors := [Color(0.84, 0.39, 0.94, 0.8), Color(0.42, 0.9, 0.82, 0.7)] if dark \
		else [Color(1.0, 0.75, 0.3, 0.82), Color(0.79, 0.9, 1.0, 0.7)]
	for spark_color in spark_colors:
		var motes := _burst(position, maxi(3, int(amount / 2)), 0.9, 0.95)
		motes.texture = _soft
		motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		motes.emission_sphere_radius = 4.0
		motes.direction = Vector2.UP
		motes.spread = 110.0
		motes.initial_velocity_min = 72.0
		motes.initial_velocity_max = 150.0
		motes.gravity = Vector2(0, -8) if dark else Vector2(0, 48)
		motes.scale_amount_min = 0.14
		motes.scale_amount_max = 0.30
		motes.color = spark_color
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
	burst.texture = _pixel.mote
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	burst.emission_rect_extents = Vector2(width, 4)
	burst.direction = Vector2.UP
	burst.spread = 20.0
	burst.initial_velocity_min = 30.0
	burst.initial_velocity_max = 70.0
	burst.gravity = Vector2(0, -30)
	burst.color = tint
	burst.color_ramp = _fade_in_out
	burst.z_index = 6
	burst.emitting = true


## Splinters and shards when a prop breaks: chunks that fly, fall and fade.
func debris(position: Vector2, tint := Color(0.6, 0.45, 0.3), amount := 9) -> void:
	var burst := _burst(position, amount, 0.7)
	if burst == null:
		return
	burst.texture = _pixel.shard
	burst.direction = Vector2.UP
	burst.spread = 60.0
	burst.initial_velocity_min = 70.0
	burst.initial_velocity_max = 160.0
	burst.gravity = Vector2(0, 420)
	burst.angular_velocity_min = -400.0
	burst.angular_velocity_max = 400.0
	burst.angle_max = 360.0
	burst.color = tint
	burst.color_ramp = _fade_out
	burst.z_index = 5
	burst.emitting = true


## A blast's reach, drawn: a thin ring that runs out to [param radius] and
## fades, with glints thrown off its edge. Crisp at any size, unlike a sprite.
func ring(position: Vector2, radius: float, tint: Color, duration := 0.35) -> void:
	var parent := get_tree().current_scene
	if parent == null:
		return
	var line := Line2D.new()
	var points := PackedVector2Array()
	for i in 41:
		points.append(Vector2.RIGHT.rotated(TAU * i / 40.0) * radius)
	line.points = points
	line.width = 2.0
	line.default_color = Color(tint.r * 1.4, tint.g * 1.4, tint.b * 1.4, 0.9)
	line.z_index = 5
	line.global_position = position
	line.scale = Vector2.ONE * 0.15
	parent.add_child(line)
	var tween := line.create_tween()
	tween.tween_property(line, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(line, "width", 1.0, duration)
	tween.parallel().tween_property(line, "modulate:a", 0.0, duration * 0.6).set_delay(duration * 0.5)
	tween.tween_callback(line.queue_free)
	var edge := _burst(position, maxi(8, int(radius / 8.0)), 0.5, 0.8)
	if edge == null:
		return
	edge.texture = _pixel.mote
	edge.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	edge.emission_sphere_radius = radius * 0.8
	edge.spread = 180.0
	edge.initial_velocity_min = 10.0
	edge.initial_velocity_max = 30.0
	edge.gravity = Vector2(0, -20)
	edge.color = tint
	edge.color_ramp = _fade_in_out
	edge.z_index = 6
	edge.emitting = true


## A one-shot light: a hit, a blast, a chest opening. Fades out and frees itself.
func flash(position: Vector2, tint := Color(1, 0.9, 0.7), radius := 60.0, duration := 0.25, energy := 1.2) -> void:
	var parent := get_tree().current_scene
	if parent == null or not Settings.lighting:
		return
	var light := GlowLight.new()
	light.radius = radius
	light.color = tint
	light.energy = energy * Settings.flash_scale()
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
	emitter.texture = _pixel.mote
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.local_coords = false
	emitter.direction = Vector2.UP
	emitter.spread = 180.0
	emitter.initial_velocity_min = 4.0
	emitter.initial_velocity_max = 14.0
	emitter.gravity = Vector2.ZERO
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


## A soft round blob (dust, the essence's glow); what flies fast is PIXELS.
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


## One of PIXELS as a texture: rows of # (solid), + (60 %), : (30 %), . (clear).
func _build_pixels(rows: Array) -> ImageTexture:
	var image := Image.create(str(rows[0]).length(), rows.size(), false, Image.FORMAT_RGBA8)
	for y in rows.size():
		var row := str(rows[y])
		for x in row.length():
			var alpha: float = {"#": 1.0, "+": 0.6, ":": 0.3}.get(row[x], 0.0)
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
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
static func _load_strip_texture(path: String) -> Texture2D:
	# A newly committed PNG has no .godot import entry on a clean checkout.
	# Runtime previews and headless tests must still animate its actual cells.
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if not FileAccess.file_exists(path):
		return null
	var picture := Image.load_from_file(path)
	if picture.is_empty():
		return null
	return ImageTexture.create_from_image(picture)


static func _strip_frames(path: String, cell: Vector2i, fps: float, animation := "default", loop := false) -> SpriteFrames:
	var texture := _load_strip_texture(path)
	if texture == null:
		push_warning("[Fx] missing strip %s" % path)
		return null
	var frames := SpriteFrames.new()
	if texture.get_width() % cell.x != 0 or texture.get_height() != cell.y:
		# Almost always a stale import after a pull that changed the strip and
		# its cell together: every frame would straddle two poses, and the
		# creature would look split in two. `make import` fixes it.
		push_error("[Fx] %s is %dx%d, not whole %dx%d frames — re-import (make import) or fix the cell"
			% [path, texture.get_width(), texture.get_height(), cell.x, cell.y])
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
	var texture := _load_strip_texture(path)
	if texture == null:
		push_warning("[Fx] missing strip %s" % path)
		return false
	if texture.get_width() % cell.x != 0 or texture.get_height() != cell.y:
		# Almost always a stale import after a pull that changed the strip and
		# its cell together: every frame would straddle two poses, and the
		# creature would look split in two. `make import` fixes it.
		push_error("[Fx] %s is %dx%d, not whole %dx%d frames — re-import (make import) or fix the cell"
			% [path, texture.get_width(), texture.get_height(), cell.x, cell.y])
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
