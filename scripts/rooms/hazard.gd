extends Area2D
class_name Hazard
## A pool of liquid (docs/LIQUIDS.md): water, lava, bog or blood — whatever
## data/liquids.json names. The class keeps its old name because lava was the
## first of them and tests, blame and burns still say Hazard.
##
## What it does, all from the kind's data:
## - its surface lives (LiquidSurface): a row of springs every body, blade and
##   bolt pushes, over a slow swell; the body under it scrolls its own texture;
## - a body that comes in splashes (by how fast it fell; a slam is the big one),
##   wades with ripples and sounds, is slowed and held up (Player/Enemy
##   liquid_touch: drag, buoyancy, sink speed, the swim stroke) and carries
##   drips, smoke or mud out with it;
## - lava burns (Player.burn: hurts through a roll, back to the last safe floor)
##   and takes walkers; blood mends enemies, and the hero who leans the kind's
##   heal path; a material in enemy.harms is hurt by standing in it;
## - a bolt that meets it is put out (douses) or eaten (burns), with steam;
## - flyers skimming low leave a wake; bubbles, embers, gas and glints rise on
##   their own; lava lights the room; a loop of it sounds near the pool.
##
## Placed by the room generator: a painted room's "hazards" (lava under the
## painting, painted = true) and "liquids": [[kind, x, y, w, h]] from
## tools/rooms/studio_rooms.json, the studio's «Жидкости». Online every peer
## runs its own copy: the look is local, a body is only moved by its owner
## and an enemy only hurt or mended by the host.

const DATA := "liquids.json"
## A body this many px above the surface still touches it (feet in the swell).
const REACH := 2.0
## A flyer this close above the surface drags a wake.
const WAKE_HEIGHT := 22.0
## A wading body ripples this often.
const WADE_EVERY := 0.3
const DEFAULT_BOUNDS := Vector2(14, 30)

@export var kind := "lava"
@export var size := Vector2(100, 30)
## The painting already shows this liquid: drawn faint, only its life on top.
@export var painted := false
## A blow from it; below zero = the kind's own (data).
@export var damage := -1.0
## Kept for old scenes: the light of a pool whose kind names none.
@export var tint := Color(1.0, 0.45, 0.15)

static var _kinds: Dictionary = {}

var spec: Dictionary = {}
var surface: LiquidSurface
## instance id -> {"body", "since", "wade", "heal"}
var _inside := {}
var _bolts := {}
var _blades := {}
var _wakes := {}
var _ambient_left := 0.0
var _loop: AudioStreamPlayer2D


## Every kind as the game has it (every data root merged).
static func kinds() -> Dictionary:
	if _kinds.is_empty():
		_kinds = DataDoc.doc(DATA).get("kinds", {})
	return _kinds


static func spec_of(id: String) -> Dictionary:
	var all := kinds()
	return all.get(id, all.get("lava", {}))


func _ready() -> void:
	add_to_group("liquids")
	spec = spec_of(kind)
	if damage < 0.0:
		damage = float(spec.get("damage", 0.0))
	collision_layer = 0
	collision_mask = 2 | 4  # players, enemies
	monitorable = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	# a little above the surface too: feet in the swell, a bolt skimming it
	rect.size = size + Vector2(0, REACH + 2.0)
	shape.position = size / 2.0 - Vector2(0, (REACH + 2.0) / 2.0)
	shape.shape = rect
	add_child(shape)
	surface = LiquidSurface.new()
	surface.name = "Surface"
	surface.z_index = 1  # over the feet that stand in it, like DecorFront
	add_child(surface)
	surface.setup(size, spec, painted)
	_dress()
	_ambient_left = randf() * float(spec.get("particles", {}).get("ambient_every", 1.0))


func burns() -> bool:
	return bool(spec.get("burns", false))


## The lava in world space, a little wider: no safe footing is ever inside it.
func danger_rect() -> Rect2:
	return Rect2(global_position, size).grow(24.0)


## The surface's world y over a world x.
func surface_y(world_x: float) -> float:
	return global_position.y + (surface.height_at(world_x - global_position.x) if surface else 0.0)


## How deep a body stands in it, 0 (dry) .. 1 (under), and where its feet are.
func depth_of(body: Node2D) -> float:
	var bounds := _bounds(body)
	var top := surface_y(body.global_position.x)
	return clampf((bounds.end.y - top + REACH) / maxf(bounds.size.y, 1.0), 0.0, 1.0)


func _physics_process(delta: float) -> void:
	var seen := {}
	for body in get_overlapping_bodies():
		if not (body is Player or body is Enemy):
			continue
		if body is Enemy and ((body as Enemy).is_dead() or body.call("_is_flying")):
			continue
		var x := (body as Node2D).global_position.x
		if x < global_position.x or x > global_position.x + size.x:
			continue  # only the middle of a body decides it is in
		var depth := depth_of(body)
		if depth <= 0.0:
			continue
		seen[body.get_instance_id()] = true
		_touch(body, depth, delta)
	for id in _inside.keys():
		if not seen.has(id):
			_leave(id)
	_areas()
	_wake_flyers(delta)
	_ambient(delta)


func _touch(body: Node2D, depth: float, delta: float) -> void:
	var id := body.get_instance_id()
	var state: Dictionary = _inside.get(id, {})
	var local_x := body.global_position.x - global_position.x
	var velocity: Vector2 = body.get("velocity") if "velocity" in body else Vector2.ZERO
	if state.is_empty():
		state = {"body": body, "wade": 0.0, "heal": 0.0, "hurt": 0.0}
		_inside[id] = state
		var strength := clampf(absf(velocity.y) / 320.0, 0.25, 1.6)
		if body is Player and bool(body.get("_slamming")):
			strength = 2.2
		surface.disturb(local_x, 1.2 + strength * 2.4, 6.0 + strength * 6.0)
		LiquidFx.splash(spec, Vector2(body.global_position.x, surface_y(body.global_position.x)), strength)
	else:
		# a body moving through it pushes the surface along: a wake, not a splash
		if absf(velocity.x) > 20.0 and depth < 0.95:
			surface.disturb(local_x - signf(velocity.x) * 4.0, absf(velocity.x) * 0.0016, 6.0)
			state.wade = float(state.wade) - delta
			if float(state.wade) <= 0.0:
				state.wade = WADE_EVERY
				var where := Vector2(body.global_position.x, surface_y(body.global_position.x))
				LiquidFx.ripple(spec, where, 0.8)
				if randf() < 0.5:
					LiquidFx.fling(spec, where, 3, 0.35)
				var cue := str(spec.get("sounds", {}).get("wade", ""))
				if cue != "" and body is Player:
					Audio.play_at(StringName(cue), where, -10.0)
	if body.has_method("liquid_touch"):
		body.liquid_touch(self, depth)
	if body is Player:
		_touch_player(body as Player, state, depth, delta)
	elif body is Enemy:
		_touch_enemy(body as Enemy, state, depth, delta)


func _touch_player(player: Player, state: Dictionary, depth: float, delta: float) -> void:
	if burns() and depth > 0.1:
		player.burn(damage, danger_rect())
	var heal: Dictionary = spec.get("heal", {})
	if not heal.is_empty() and player._is_mine() and not player.is_dead() and depth > 0.3 \
			and Game.lead() >= 2 and Game.dominant_path() == str(heal.get("path", "")):
		state.heal = float(state.heal) + float(heal.get("per_second", 0.0)) * delta
		if float(state.heal) >= 1.0:
			player.heal(floorf(float(state.heal)))
			state.heal = float(state.heal) - floorf(float(state.heal))
			if randf() < 0.4:
				Fx.sparkle(player.global_position + Vector2(0, -8), Color(str(spec.get("colors", {}).get("glow", "#ffffff"))), 3, 8.0)


func _touch_enemy(enemy: Enemy, state: Dictionary, depth: float, delta: float) -> void:
	if Net.active and not Net.is_server():
		return  # enemies live on the host
	if bool(spec.get("kills_walkers", false)) and depth > 0.1:
		LiquidFx.splash(spec, Vector2(enemy.global_position.x, surface_y(enemy.global_position.x)), 1.4)
		Fx.ash(enemy.global_position, Color(1.0, 0.5, 0.2), 14, 70.0, 8.0)
		enemy.take_damage(9999.0, self)
		return
	var material := str(enemy.stats.get("material", "cloth"))
	var harm := float(spec.get("enemy", {}).get("harms", {}).get(material, 0.0))
	if harm > 0.0 and depth > 0.2:
		state.hurt = float(state.hurt) + harm * delta
		if float(state.hurt) >= 1.0:
			var dealt := floorf(float(state.hurt))
			state.hurt = float(state.hurt) - dealt
			enemy.take_damage(dealt, self)
			LiquidFx.steam(enemy.global_position + Vector2(0, -6), Color(0.85, 0.9, 0.95, 0.6), 0.7)
			Audio.play_at(&"sizzle", enemy.global_position, -12.0)
	var mend := float(spec.get("enemy", {}).get("heal_per_second", 0.0))
	if mend > 0.0 and depth > 0.2:
		state.heal = float(state.heal) + mend * delta
		if float(state.heal) >= 1.0:
			enemy.liquid_heal(floorf(float(state.heal)))
			state.heal = float(state.heal) - floorf(float(state.heal))


func _leave(id: int) -> void:
	var state: Dictionary = _inside[id]
	_inside.erase(id)
	var body = state.get("body")
	if not is_instance_valid(body) or not (body as Node).is_inside_tree():
		return
	var node := body as Node2D
	var velocity: Vector2 = node.get("velocity") if "velocity" in node else Vector2.ZERO
	var x := node.global_position.x
	if x >= global_position.x and x <= global_position.x + size.x:
		surface.disturb(x - global_position.x, -1.0 - clampf(absf(velocity.y) / 300.0, 0.0, 1.5), 8.0)
		LiquidFx.splash(spec, Vector2(x, surface_y(x)), clampf(absf(velocity.y) / 400.0, 0.3, 0.9), true)
	LiquidFx.trail(spec, node, _bounds(node).size.y)


## Bolts and the hero's blade: a bolt is put out or eaten, a swing throws spray.
## Neither is monitorable (a bolt hits bodies, a blade is asked by the swing),
## so they are looked for, not waited for: the "projectiles" group and each
## player's Hitbox while it is swinging.
func _areas() -> void:
	var pool := Rect2(global_position - Vector2(0, REACH + 2.0), size + Vector2(0, REACH + 2.0))
	var bolts := {}
	for node in get_tree().get_nodes_in_group("projectiles"):
		var bolt := node as Node2D
		if bolt == null or not pool.has_point(bolt.global_position):
			continue
		var id := bolt.get_instance_id()
		bolts[id] = true
		if _bolts.has(id):
			continue
		var at := Vector2(bolt.global_position.x, surface_y(bolt.global_position.x))
		surface.disturb(bolt.global_position.x - global_position.x, 2.0, 8.0)
		LiquidFx.fling(spec, at, 6, 0.6)
		if burns() or bool(spec.get("douses", false)):
			LiquidFx.steam(at + Vector2(0, -2), Color(0.9, 0.9, 0.95, 0.7), 0.9)
			Audio.play_at(&"sizzle", at, -8.0)
			if bolt.has_method("_burst"):
				bolt.call("_burst")
	_bolts = bolts
	var blades := {}
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Player
		if player == null or player.hitbox == null or not player.hitbox.monitoring:
			continue
		var reach := _bounds(player.hitbox)
		if not reach.intersects(pool):
			continue
		var id := player.get_instance_id()
		blades[id] = true
		if _blades.has(id):
			continue
		var x := clampf(reach.get_center().x, global_position.x, global_position.x + size.x)
		var at := Vector2(x, surface_y(x))
		surface.disturb(x - global_position.x, 1.6, 14.0)
		LiquidFx.fling(spec, at, 7, 0.7)
		LiquidFx.ripple(spec, at, 1.2)
	_blades = blades


## A flyer low over the surface draws a wake under it.
func _wake_flyers(delta: float) -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead() or not enemy.call("_is_flying"):
			continue
		var x := enemy.global_position.x
		if x < global_position.x or x > global_position.x + size.x:
			continue
		var above := surface_y(x) - _bounds(enemy).end.y
		if above < 0.0 or above > WAKE_HEIGHT:
			continue
		var id := enemy.get_instance_id()
		var left := float(_wakes.get(id, 0.0)) - delta
		surface.disturb(x - global_position.x, (1.0 - above / WAKE_HEIGHT) * 0.25, 10.0)
		if left <= 0.0:
			left = 0.35
			LiquidFx.ripple(spec, Vector2(x, surface_y(x)), 0.7 + (1.0 - above / WAKE_HEIGHT) * 0.6)
		_wakes[id] = left


func _ambient(delta: float) -> void:
	var particles: Dictionary = spec.get("particles", {})
	var every := float(particles.get("ambient_every", 0.0))
	if every <= 0.0 or str(particles.get("ambient", "none")) == "none":
		return
	_ambient_left -= delta
	if _ambient_left > 0.0:
		return
	# a wider pool bubbles more often, never less than its own rate
	_ambient_left = every * randf_range(0.5, 1.5) / clampf(size.x / 200.0, 1.0, 4.0)
	var x := randf_range(4.0, maxf(5.0, size.x - 4.0))
	surface.disturb(x, 0.4, 4.0)
	LiquidFx.bubble(spec, Vector2(global_position.x + x, surface_y(global_position.x + x)))


## A body's collision box in world space (Player and Enemy both name it Collision).
func _bounds(body: Node2D) -> Rect2:
	var shape := body.get_node_or_null("Collision") as CollisionShape2D
	if shape != null and shape.shape is RectangleShape2D:
		var extent := (shape.shape as RectangleShape2D).size * shape.global_scale.abs()
		return Rect2(shape.global_position - extent / 2.0, extent)
	return Rect2(body.global_position - DEFAULT_BOUNDS / 2.0, DEFAULT_BOUNDS)


## Embers off lava, a light along a glowing pool, the sound of it nearby.
func _dress() -> void:
	if burns():
		var embers := CPUParticles2D.new()
		embers.name = "Embers"
		embers.position = Vector2(size.x / 2.0, 2.0)
		embers.amount = maxi(6, int(size.x / 8.0))
		embers.lifetime = 1.6
		embers.preprocess = 1.6
		embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		embers.emission_rect_extents = Vector2(size.x / 2.0, 2.0)
		embers.direction = Vector2.UP
		embers.spread = 20.0
		embers.gravity = Vector2(0, -20)
		embers.initial_velocity_min = 15.0
		embers.initial_velocity_max = 45.0
		embers.texture = Fx.pixel("ember")
		embers.color = Color(str(spec.get("particles", {}).get("tint", "#ffb347")))
		embers.color_ramp = Fx.ramp("in_out")
		embers.z_index = 2
		add_child(embers)
		# the heat over it: a faint haze of rising motes, slower and higher
		var haze := embers.duplicate() as CPUParticles2D
		haze.name = "Haze"
		haze.amount = maxi(3, int(size.x / 30.0))
		haze.lifetime = 3.0
		haze.preprocess = 3.0
		haze.initial_velocity_min = 6.0
		haze.initial_velocity_max = 14.0
		haze.texture = Fx.pixel("mote")
		haze.color = Color(1.0, 0.75, 0.5, 0.25)
		add_child(haze)
	var light: Dictionary = spec.get("light", {})
	if not light.is_empty():
		var color := Color(str(light.get("color", tint.to_html())))
		var every := maxf(30.0, float(light.get("every", 90.0)))
		var count := maxi(1, int(size.x / every))
		for i in count:
			Fx.light(self, Vector2(size.x * (i + 0.5) / count, 4.0), color, float(light.get("radius", 70.0)),
				float(light.get("energy", 0.9)), float(light.get("flicker", 0.25)))
	var cue := str(spec.get("sounds", {}).get("ambient", ""))
	if cue != "" and Audio.has_clip(StringName(cue)):
		_loop = AudioStreamPlayer2D.new()
		_loop.name = "Sound"
		_loop.bus = &"SFX"
		_loop.stream = Audio.looping(StringName(cue))
		_loop.position = Vector2(size.x / 2.0, 0.0)
		_loop.max_distance = 360.0 + size.x * 0.5
		_loop.attenuation = 2.0
		_loop.volume_db = -14.0
		_loop.autoplay = true
		add_child(_loop)
