extends RefCounted
class_name BackdropLife
## Every backdrop breathes (docs/BACKDROP_LIFE.md). One shader —
## assets/shaders/backdrop_life.gdshaderinc — goes on the room's painting and
## on its depth windows, so the far plate and the picture around it move as
## one. The common rule is the same everywhere: every flame the artist painted
## flickers on its own. What makes a place itself is data
## (data/backdrops.json): a family sets how the flames burn, the room lists
## zones — waterfalls, water, banners and cages that sway, a moon or a window
## that glows, lava, heat haze, stars, veins that beat.

const RULES_PATH := "res://data/backdrops.json"
const SHADER := preload("res://assets/shaders/backdrop_life.gdshader")
const MAX_ZONES := 24
## kind → [shader index, default strength, default speed]
const KINDS := {
	"falls": [0, 1.0, 1.0],
	"water": [1, 1.0, 1.0],
	"sway": [2, 1.5, 1.6],
	"glow": [3, 0.12, 0.8],
	"lava": [4, 1.0, 1.0],
	"haze": [5, 1.0, 1.0],
	"stars": [6, 0.35, 0.6],
	"pulse": [7, 0.8, 0.9],
}
const META := &"backdrop_life"
## A wounded hero hears the walls: below this share of health the veins beat
## harder and faster, fully so at DREAD_FULL.
const DREAD_FROM := 0.4
const DREAD_FULL := 0.1
## How much faster the heart beats at full dread.
const DREAD_TEMPO := 0.9
## The colour lightning lights the painting with; a scene may flash another.
const LIGHTNING := Color(0.7, 0.78, 1.0)
## The flames lean with the hero from the aura's threshold, fully at LEAN_FULL.
const LEAN_FROM := 2
const LEAN_FULL := 6
## The interiors paint their wall onto a sprite of their own.
const INTERIOR_PAINTINGS := ["Interior/AuthoredMasonry/ChurchPainting", "Interior/AuthoredMasonry/PreacherPainting"]

static var _rules: Dictionary = {}


## The rule for [param key] (a room's scene name): {flame, flame_floor, zones}, or {}.
static func rule(key: String) -> Dictionary:
	var rules := _load()
	var rooms: Dictionary = rules.get("rooms", {})
	if not rooms.has(key):
		return {}
	var room: Dictionary = rooms[key]
	var family: Dictionary = rules.get("families", {}).get(str(room.get("family", "")), {})
	return {
		"flame": float(room.get("flame", family.get("flame", 0.5))),
		"flame_floor": float(room.get("flame_floor", family.get("flame_floor", 0.55))),
		"zones": room.get("zones", []),
	}


static func attach(room: Node2D) -> void:
	var painting := painting_of(room)
	if painting == null:
		return
	var materials := attach_sprite(painting, room.scene_file_path.get_file().get_basename())
	if materials.is_empty():
		return
	var found := rule(room.scene_file_path.get_file().get_basename())
	var windows := room.get_node_or_null("DepthWindows")
	if windows != null:
		for child in windows.get_children():
			var window_material := (child as CanvasItem).material as ShaderMaterial
			if window_material != null and not materials.has(window_material):
				configure(window_material, found)
				materials.append(window_material)
	room.set_meta(META, {"painting": painting, "materials": materials})


## Brings any one picture to life under the rule [param key] (the main menu's
## backdrop is not a room). Returns the materials it set, empty without a rule.
static func attach_sprite(sprite: Sprite2D, key: String) -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = []
	var found := rule(key)
	if found.is_empty() or sprite == null:
		return materials
	var material := ShaderMaterial.new()
	material.shader = SHADER
	sprite.material = material
	configure(material, found)
	materials.append(material)
	# the settings may change while the picture is up (the pause menu); the
	# watcher frees with the sprite, and its connection with it
	var watcher := SettingsWatcher.new()
	watcher.name = "BackdropLifeSettings"
	watcher.materials = materials
	sprite.add_child(watcher)
	return materials


## The room answers what happens in it. [param mood] (missing keys are calm):
##   origin, direction  the latest gust, world space   energy  its strength, 0 calm
##   exhale   what is left of the cleared-room swell, 0..1
##   flash    lightning or a scene's flash, 0..1, of colour flash_tint (lightning's blue by default)
##   dread    our own body near death (dread_of), 0..1
##   beat     the heartbeat's own clock (< 0 leaves it on the shader's TIME)
##   rage     a boss fight's heat (rage_of), 0..1
##   path, lead  the path the hero leans to and by how much (Game): the flames take its colour
## Called by Ambience every frame.
static func react(room: Node, mood: Dictionary) -> void:
	if room == null or not room.has_meta(META):
		return
	var life: Dictionary = room.get_meta(META)
	var painting := life.painting as Sprite2D
	if not is_instance_valid(painting):
		return
	var at: Vector2 = painting.get_global_transform().affine_inverse() * (mood.get("origin", Vector2.ZERO) as Vector2)
	var direction: Vector2 = mood.get("direction", Vector2.RIGHT)
	var wind := Vector4(at.x, at.y, float(mood.get("energy", 0.0)), clampf(direction.x, -1.0, 1.0))
	var tint: Color = mood.get("flash_tint", LIGHTNING)
	var lean := lean_of(str(mood.get("path", "")), int(mood.get("lead", 0)))
	for material: ShaderMaterial in life.materials:
		material.set_shader_parameter("life_wind", wind)
		material.set_shader_parameter("life_exhale", float(mood.get("exhale", 0.0)))
		material.set_shader_parameter("life_flash", float(mood.get("flash", 0.0)))
		material.set_shader_parameter("life_flash_tint", Vector3(tint.r, tint.g, tint.b))
		material.set_shader_parameter("life_dread", float(mood.get("dread", 0.0)))
		material.set_shader_parameter("life_beat_clock", float(mood.get("beat", -1.0)))
		material.set_shader_parameter("life_rage", float(mood.get("rage", 0.0)))
		material.set_shader_parameter("life_lean", lean)


## The colour the painted flames take for a lean: the path's tint from
## data/backdrops.json and how strongly, as rgb + a. Below a lead of LEAN_FROM
## (the aura's threshold, Player._update_aura) nothing; full at LEAN_FULL.
static func lean_of(path: String, lead: int) -> Vector4:
	var tints: Dictionary = _load().get("lean", {})
	if lead < LEAN_FROM or not tints.has(path):
		return Vector4(1.0, 1.0, 1.0, 0.0)
	var tint := Color(str(tints[path]))
	return Vector4(tint.r, tint.g, tint.b, clampf(float(lead - 1) / float(LEAN_FULL - 1), 0.2, 1.0))


## How hot a boss fight runs with [param share] of the boss's health left:
## nothing before the first blow, all of it as the last one lands.
static func rage_of(share: float) -> float:
	return clampf(1.0 - share, 0.0, 1.0) if share > 0.0 else 0.0


## How hard the place's heart beats for a body with [param share] of its
## health left: nothing above DREAD_FROM, all of it at DREAD_FULL and below.
static func dread_of(share: float) -> float:
	return clampf((DREAD_FROM - share) / (DREAD_FROM - DREAD_FULL), 0.0, 1.0)


## The sprite that carries the room's picture, or null.
static func painting_of(room: Node) -> Sprite2D:
	for path in ["Painting", "Parallax/Backdrop"] + INTERIOR_PAINTINGS:
		var painting := room.get_node_or_null(path) as Sprite2D
		if painting != null:
			return painting
	return null


static func configure(material: ShaderMaterial, found: Dictionary) -> void:
	var rects := PackedVector4Array()
	var shapes := PackedVector4Array()
	var tints := PackedVector4Array()
	for zone: Dictionary in found.zones:
		if rects.size() >= MAX_ZONES:
			push_warning("[BackdropLife] more than %d zones, the rest stay still" % MAX_ZONES)
			break
		var kind: Array = KINDS.get(str(zone.get("kind", "")), [])
		if kind.is_empty():
			continue
		var r: Array = zone.rect
		rects.append(Vector4(r[0], r[1], r[2], r[3]))
		var extra := 1.0 if str(zone.get("anchor", "hangs")) == "stands" else 0.0
		if kind[0] == 1:
			extra = float(zone.get("floor", 0.12))
		shapes.append(Vector4(kind[0], float(zone.get("strength", kind[1])), float(zone.get("speed", kind[2])), extra))
		var tint := Color(str(zone.get("tint", "#ffffff")))
		tints.append(Vector4(tint.r, tint.g, tint.b, 1.0))
	var count := rects.size()
	while rects.size() < MAX_ZONES:
		rects.append(Vector4.ZERO)
		shapes.append(Vector4.ZERO)
		tints.append(Vector4.ZERO)
	material.set_shader_parameter("life_rect", rects)
	material.set_shader_parameter("life_shape", shapes)
	material.set_shader_parameter("life_tint", tints)
	material.set_shader_parameter("life_count", count)
	material.set_shader_parameter("life_flame", float(found.flame))
	material.set_shader_parameter("life_flame_floor", float(found.flame_floor))
	apply_settings(material)


static func _load() -> Dictionary:
	if not _rules.is_empty():
		return _rules
	if FileAccess.file_exists(RULES_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
		if parsed is Dictionary:
			_rules = parsed
	return _rules


## What the player asked for: light changes as dimmed as `flashes`, and the
## picture held still when `backdrop_motion` is off.
static func apply_settings(material: ShaderMaterial) -> void:
	material.set_shader_parameter("life_light", Settings.flash_scale())
	material.set_shader_parameter("life_motion", 1.0 if Settings.backdrop_motion else 0.0)


## Re-applies the settings to a picture's materials whenever they change.
class SettingsWatcher extends Node:
	var materials: Array[ShaderMaterial] = []

	func _ready() -> void:
		Settings.changed.connect(_refresh)

	func _refresh() -> void:
		for each in materials:
			BackdropLife.apply_settings(each)
