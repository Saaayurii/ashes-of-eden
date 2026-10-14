class_name LiquidFx
extends RefCounted
## What a pool throws off (docs/LIQUIDS.md): splashes, drops, ripples, bubbles,
## steam, glints and the drips a body carries out. The drawn strips are made by
## tools/art/make_liquids.py into assets/fx/liquids/ (cells in its
## manifest.json); a strip that is missing leaves only the particles, so a
## checkout without them still splashes. Static: Hazard asks, the scene keeps.

const DIR := "res://assets/fx/liquids/"
## name: [cell, fps, tinted by the liquid]. The manifest, when there, wins.
const STRIPS := {
	"splash": [Vector2i(32, 32), 16.0, true],
	"splash_big": [Vector2i(48, 48), 14.0, true],
	"lava_splash": [Vector2i(48, 48), 13.0, false],
	"ripple": [Vector2i(32, 8), 12.0, true],
	"bubble": [Vector2i(8, 8), 10.0, true],
	"lava_pop": [Vector2i(16, 16), 11.0, false],
	"gas_pop": [Vector2i(16, 16), 10.0, false],
	"steam": [Vector2i(24, 24), 10.0, true],
	"drip": [Vector2i(4, 8), 10.0, true],
	"surface_glint": [Vector2i(8, 3), 12.0, true],
}
## The pixel shape and colour of what a splash flings, by its kind in the data
## (particles.splash): [PIXELS shape, gravity, speed].
const FLUNG := {
	"drops": ["drop", 520.0, 150.0],
	"magma": ["ember", 420.0, 130.0],
	"mud": ["flake", 600.0, 110.0],
	"blood": ["drop", 560.0, 140.0],
}
## What leaves the pool with a body (particles.trail).
const TRAILS := {
	"drips": ["drop", 380.0],
	"smoke": ["mote", -40.0],
	"mud": ["flake", 420.0],
}

static var _frames := {}
static var _manifest: Dictionary = {}
static var _manifest_read := false


static func frames(name: String) -> SpriteFrames:
	if _frames.has(name):
		return _frames[name]
	var info: Array = STRIPS.get(name, [Vector2i(16, 16), 10.0, true])
	var cell: Vector2i = info[0]
	var fps: float = info[1]
	var listed: Dictionary = _read_manifest().get(name, {})
	if listed.get("cell") is Array and (listed.cell as Array).size() == 2:
		cell = Vector2i(int(listed.cell[0]), int(listed.cell[1]))
	fps = float(listed.get("fps", fps))
	var path := DIR + name + ".png"
	var made: SpriteFrames = null
	if ResourceLoader.exists(path) or FileAccess.file_exists(path):
		made = Fx._strip_frames(path, cell, fps)
	_frames[name] = made
	return made


static func _read_manifest() -> Dictionary:
	if not _manifest_read:
		_manifest_read = true
		var path := DIR + "manifest.json"
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_manifest = parsed
	return _manifest


static func tinted(name: String) -> bool:
	var listed: Dictionary = _read_manifest().get(name, {})
	return bool(listed.get("tint", STRIPS.get(name, [null, 0, true])[2]))


## One drawn strip, played once where it is put and freed after.
static func play(name: String, where: Vector2, tint := Color.WHITE, scale := 1.0, z := 5, flip := false) -> AnimatedSprite2D:
	var parent := Fx.get_tree().current_scene if Fx.is_inside_tree() else null
	var made := frames(name)
	if parent == null or made == null:
		return null
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = made
	sprite.centered = true
	# a splash stands on the surface: its cell's bottom row is the water line
	var cell := made.get_frame_texture("default", 0).get_size() if made.get_frame_count("default") > 0 else Vector2(16, 16)
	sprite.offset = Vector2(0, -cell.y * 0.5) if name in ["splash", "splash_big", "lava_splash", "steam"] else Vector2.ZERO
	sprite.global_position = where.round()
	sprite.scale = Vector2.ONE * scale
	sprite.flip_h = flip
	sprite.z_index = z
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if tinted(name):
		sprite.modulate = tint
	parent.add_child(sprite)
	sprite.play("default")
	sprite.animation_finished.connect(sprite.queue_free)
	return sprite


## A body meeting the surface: [param strength] 0.3 a step, 1 a fall, 2 a slam.
static func splash(spec: Dictionary, where: Vector2, strength: float, rising := false) -> void:
	var particles: Dictionary = spec.get("particles", {})
	var tint := Color(str(particles.get("tint", "#ffffff")))
	var burns := bool(spec.get("burns", false))
	var big := strength >= 1.1
	if burns:
		play("lava_splash" if big else "lava_pop", where, Color.WHITE, 1.0 if big else 1.2)
		steam(where + Vector2(0, -4), Color(1.0, 0.75, 0.55, 0.7), 0.8 + strength * 0.4)
	else:
		play("splash_big" if big else "splash", where, tint, 1.0, 5, randf() < 0.5)
	if not rising:
		play("ripple", where + Vector2(0, 1), Color(tint, 0.8), 1.0 + strength * 0.5, 4)
	fling(spec, where, int(5 + strength * 9), strength)
	var sounds: Dictionary = spec.get("sounds", {})
	var cue := str(sounds.get("exit" if rising else ("big" if big else "enter"), ""))
	if cue != "":
		Audio.play_at(StringName(cue), where, -6.0 + minf(strength, 2.0) * 3.0)
	if Fx.is_inside_tree():
		EventBus.world_impulse.emit(where, Vector2.UP, clampf(strength * 0.5, 0.15, 1.0), &"splash")


## Drops thrown up out of the surface and falling back, by particles.splash.
static func fling(spec: Dictionary, where: Vector2, amount: int, strength := 1.0) -> void:
	var particles: Dictionary = spec.get("particles", {})
	var how: Array = FLUNG.get(str(particles.get("splash", "drops")), FLUNG.drops)
	var burst := Fx._burst(where + Vector2(0, -1), maxi(2, amount), 0.9)
	if burst == null:
		return
	burst.texture = Fx.pixel(str(how[0]))
	burst.direction = Vector2.UP
	burst.spread = 38.0
	burst.initial_velocity_min = float(how[2]) * 0.45 * clampf(strength, 0.4, 1.6)
	burst.initial_velocity_max = float(how[2]) * clampf(strength, 0.5, 1.8)
	burst.gravity = Vector2(0, float(how[1]))
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	burst.emission_rect_extents = Vector2(4.0 + strength * 4.0, 1.0)
	var tint := Color(str(particles.get("tint", "#ffffff")))
	burst.color = tint
	burst.color_ramp = Fx.ramp("out")
	burst.z_index = 5
	burst.emitting = true


static func ripple(spec: Dictionary, where: Vector2, scale := 1.0) -> void:
	var tint := Color(str(spec.get("particles", {}).get("tint", "#ffffff")))
	play("ripple", where + Vector2(0, 1), Color(tint, 0.6), scale, 4)


static func bubble(spec: Dictionary, where: Vector2) -> void:
	var particles: Dictionary = spec.get("particles", {})
	match str(particles.get("ambient", "")):
		"embers":
			play("lava_pop", where + Vector2(0, -6), Color.WHITE, 1.0, 4)
			if randf() < 0.5:
				Fx.ash(where, Color(1.0, 0.6, 0.25), 4, 50.0, 3.0)
		"gas":
			play("gas_pop", where + Vector2(0, -6), Color.WHITE, 1.0, 4)
		"clots":
			# a thick dark bubble that rises slowly and leaves a clot on the rim
			var dark := Color(str(spec.get("colors", {}).get("deep", "#3a0508")))
			var pop := play("bubble", where + Vector2(0, -2), dark.lightened(0.25), 1.3, 4)
			if pop != null:
				pop.speed_scale = 0.6
			play("drip", where + Vector2(randf_range(-3, 3), -1), dark, 1.0, 4)
		"glints":
			play("surface_glint", where + Vector2(0, -1), Color(str(spec.get("colors", {}).get("foam", "#ffffff"))), 1.0, 4)
			return
		_:
			play("bubble", where + Vector2(0, -3), Color(str(particles.get("tint", "#ffffff"))), 1.0, 4)
	var cue := str(spec.get("sounds", {}).get("bubble", ""))
	if cue != "" and randf() < 0.45:
		Audio.play_at(StringName(cue), where, -14.0)


static func steam(where: Vector2, tint := Color(0.9, 0.92, 0.95, 0.7), scale := 1.0) -> void:
	if play("steam", where, tint, scale, 6) == null:
		Fx.puff(where, 0.6 * scale, tint)


## What a body carries out of the pool for a while (particles.trail): drips
## off water and blood, smoke off lava, clods off the bog. Freed by itself.
static func trail(spec: Dictionary, body: Node2D, height: float) -> void:
	var particles: Dictionary = spec.get("particles", {})
	var kind := str(particles.get("trail", ""))
	if kind == "" or kind == "none" or not TRAILS.has(kind) or body == null or not body.is_inside_tree():
		return
	var old := body.get_node_or_null("LiquidTrail")
	if old != null:
		old.queue_free()
		old.name = "LiquidTrailOld"
	var how: Array = TRAILS[kind]
	var time := float(particles.get("trail_time", 1.2))
	var drip := CPUParticles2D.new()
	drip.name = "LiquidTrail"
	drip.amount = 6 if kind != "smoke" else 10
	drip.lifetime = 0.6 if kind != "smoke" else 1.1
	drip.local_coords = false
	drip.position = Vector2(0, -height * 0.5)
	drip.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	drip.emission_rect_extents = Vector2(5, height * 0.4)
	drip.texture = Fx.pixel(str(how[0]))
	drip.gravity = Vector2(0, float(how[1]))
	drip.direction = Vector2.UP if kind == "smoke" else Vector2.DOWN
	drip.spread = 25.0
	drip.initial_velocity_min = 5.0
	drip.initial_velocity_max = 25.0
	drip.color = Color(str(particles.get("tint", "#ffffff"))) if kind != "smoke" else Color(0.35, 0.32, 0.3, 0.7)
	drip.color_ramp = Fx.ramp("out")
	drip.z_index = 4
	body.add_child(drip)
	# timers on the emitter itself: they go with it if the body is freed first
	var stop := Timer.new()
	stop.wait_time = time
	stop.one_shot = true
	stop.autostart = true
	stop.timeout.connect(drip.set_emitting.bind(false))
	drip.add_child(stop)
	var gone := Timer.new()
	gone.wait_time = time + drip.lifetime + 0.1
	gone.one_shot = true
	gone.autostart = true
	gone.timeout.connect(drip.queue_free)
	drip.add_child(gone)
