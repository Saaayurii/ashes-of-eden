extends Node2D
class_name Foliage
## Painted trees answer the hero (docs/BACKDROP_LIFE.md, «Деревья»). A sway
## zone of data/backdrops.json that names a style ("tree": "willow") is a tree:
## its crown hangs on a damped spring that a blow, a body pushing through it, a
## gust or a landing sets swinging — the life shader bends the painting by
## life_bend, so the picture itself leans and settles — and it sheds what it is
## made of (data/foliage.json): leaves, threads of moss and twigs that tumble
## down through the gusts, settle on the room's floors and ledges, are kicked
## up again by a running body and fade. A litter of old leaves lies under each
## crown from the start, so the first dash already scatters something.
## A crown may hold ravens (the zone's "birds"): they sit on branch tops the
## painting already has, lean with it, fidget, and leave in a flurry when the
## crown is struck or a body comes at them fast, flying off out of the room and
## coming back to the same branches a while later.
## Cosmetic and local on every peer: it reads the bodies' positions (which every
## peer has), never sends a thing, and never touches gameplay or collision.

const RULES_PATH := "res://data/foliage.json"
const NODE_NAME := "Foliage"
## Leaves alive at once; past it the oldest lying one gives way.
const MAX_LEAVES := 240
const WORLD_MASK := 1
const LEDGE_MASK := 16
## Pulls every leaf down; its drag (GRAVITY / the style's fall) holds it back.
const GRAVITY := 260.0
## How far from a crown a gust still stirs it, world pixels.
const GUST_REACH := 220.0
## A swing lands on a crown this close to it.
const STRIKE_SLOP := 12.0
## The crown's swing speed (px/s of lean) for a gust of strength 1, and for a blow.
const GUST_PUSH := 6.0
const STRIKE_PUSH := 24.0
## A body faster than this through a crown pushes it and tears leaves loose.
const BRUSH_SPEED := 60.0
## The crown's acceleration per px/s of a body pushing through it.
const BRUSH_PUSH := 0.4
## Leaves torn loose a second per 100 px/s of a body pushing through.
const BRUSH_SHED := 3.0
## A body this fast sideways kicks up the leaves it runs through.
const KICK_SPEED := 70.0
const KICK_REACH := 14.0
## A body's feet below its origin (the collision box is centred on it).
const FEET := 15.0
const RUSTLE_GAP := 0.35
## How long the air keeps a gust's push, and how hard it blows.
const AIR_FADE := 1.4
const AIR_PUSH := 70.0
## Old leaves under a crown at the start, per pixel of its width (× shed).
const LITTER := 0.04
## A swing this close to a falling leaf cuts it in two, world pixels.
const CUT_REACH := 20.0
## A leaf on a pool (Hazard) floats this many times its rest, drifting at this
## share of the air; a body wading within WAKE_REACH pushes it aside.
const FLOAT_REST := 2.0
const FLOAT_DRIFT := 0.25
const WAKE_REACH := 14.0
## Ravens a crown may hold; how far apart they sit and how much brighter the
## sky over a branch must be for one to sit on it (painting pixels, 0..255).
const MAX_BIRDS := 4
const PERCH_GAP := 16
const PERCH_CONTRAST := 22
## A body slower than this does not scare a raven, unless it comes within a
## third of the reach; a startled one crouches up to STARTLE seconds first.
const SCARE_SPEED := 70.0
const STARTLE := 0.3
## A raven that has not left the room by then is gone anyway.
const FLIGHT := 12.0
const WINGBEAT_GAP := 0.5

enum { LEAF, STRAND, TWIG }
enum { PERCHED, STARTLED, FLEEING, GONE, RETURNING }

## A raven's shapes, facing right, 1:1 pixels: # body, = beak. Sitting, the
## feet are at column SIT_FEET of the bottom row; flying, the shape is centred.
const SIT := ["......##.", ".....###=", ".....###.", "....####.", "...#####.", "..#####..", ".###.#...", "##...#..."]
const PECK := [".........", ".........", ".........", "....###..", "...#####.", "..#######", ".###.#.#=", "##...#..."]
const SIT_FEET := 5
const FLY_UP := ["....#......", "....##.....", ".....##....", "..#######=.", ".####......", "...........", "..........."]
const FLY_MID := ["...........", "...........", "...######..", "..#######=.", ".####......", "...........", "..........."]
const FLY_DOWN := ["...........", "...........", "...........", "..#######=.", ".#####.....", ".....##....", "......#...."]

var trees: Array[Crown] = []
var leaves: Array[Leaf] = []
var birds: Array[Bird] = []
var _room := Rect2(-1e6, -1e6, 2e6, 2e6)
var _last_wingbeat := -1.0
var _materials: Array[ShaderMaterial] = []
var _bends := PackedFloat32Array()
var _bodies := {}
var _air_origin := Vector2.ZERO
var _air_direction := Vector2.RIGHT
var _air_energy := 0.0
var _time := 0.0
var _settled := true
var _bottom := 1e9
var _right := 1e9
var _random := RandomNumberGenerator.new()
var _pools: Array[Dictionary] = []   # {node: Hazard, rect: Rect2}, read with the litter

static var _styles: Dictionary = {}
static var _ravens: Dictionary = {}


## A tree's crown: the zone's rect in the world, its style and its spring.
class Crown:
	var zone := 0
	var rect := Rect2()
	var style: Dictionary = {}
	var lean := 0.0   # px at the crown's free end, + to the right
	var speed := 0.0
	var drift := 0.0  # leaves owed to the night's own breath
	var torn := 0.0   # leaves owed to a body pushing through
	var rustle := 0.0
	var perches: Array[Vector2] = []    # where its ravens sit, world space
	var lifts := PackedFloat32Array()   # how far its lean carries each perch


## A raven on a crown: it sits on its perch, leaning with the crown.
class Bird:
	var crown: Crown
	var perch := Vector2.ZERO
	var lift := 0.0
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var state := PERCHED
	var facing := 1.0
	var timer := 0.0   # perched: to the next fidget; startled: to the take-off; flying: in the air; gone: to coming back
	var pecking := 0.0
	var wing := 0.0
	var pace := 1.0


class Leaf:
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var phase := 0.0
	var spin := 3.0
	var color := Color.WHITE
	var shape := 0
	var length := 1
	var drag := 10.0
	var flutter := 10.0
	var rest := 6.0
	var life := 0.0
	var lying := false
	var bounced := false
	var cut := false   # halved by a blade: a leaf is one pixel, a strand shorter
	var pool := {}     # the pool it floats on, empty on dry ground


## Gives [param room] its trees, or nothing when none of its zones is one.
## After BackdropLife.attach: the crowns bend through its materials.
static func attach(room: Node2D) -> Foliage:
	var found := crowns_of(room)
	if found.is_empty():
		return null
	var foliage := Foliage.new()
	foliage.name = NODE_NAME
	foliage.trees = found
	room.add_child(foliage)
	return foliage


## The room's trees, in world space, each knowing its zone's index in the shader.
static func crowns_of(room: Node2D) -> Array[Crown]:
	var out: Array[Crown] = []
	var painting := BackdropLife.painting_of(room)
	if painting == null or painting.texture == null:
		return out
	var known := styles()
	var local := painting.get_rect()
	var pixels := painting.region_rect.size if painting.region_enabled else painting.texture.get_size()
	var to_world := painting.get_global_transform()
	var scale := local.size / pixels
	var image: Image = null
	var index := 0
	for zone: Dictionary in BackdropLife.rule(BackdropLife.room_key(room)).get("zones", []):
		var kind := str(zone.get("kind", ""))
		# counted as BackdropLife.configure counts them: unknown kinds skipped, the shader holds MAX_ZONES
		if not BackdropLife.KINDS.has(kind):
			continue
		if index >= BackdropLife.MAX_ZONES:
			break
		var style := str(zone.get("tree", ""))
		if kind == "sway" and known.has(style):
			var r: Array = zone.rect
			var crown := Crown.new()
			crown.zone = index
			crown.rect = to_world * Rect2(local.position + Vector2(r[0], r[1]) * local.size / pixels, Vector2(r[2], r[3]) * local.size / pixels)
			crown.style = known[style]
			var count := mini(int(zone.get("birds", 0)), MAX_BIRDS)
			if count > 0:
				if image == null:
					image = painting.texture.get_image()
					if image != null and image.is_compressed():
						image.decompress()
				var origin := Vector2i(painting.region_rect.position) if painting.region_enabled else Vector2i.ZERO
				var stands := str(zone.get("anchor", "")) == "stands"
				var spots := perches_in(image, Rect2i(origin + Vector2i(int(r[0]), int(r[1])), Vector2i(int(r[2]), int(r[3]))), stands, count, index * 7919 + int(r[0]))
				for spot in spots:
					# the feet on the pixel over the branch's top; the lean grows as the shader's, with the square of the way from the root
					var along := (float(spot.y) - float(r[1])) / float(r[3])
					crown.perches.append(to_world * (local.position + (Vector2(spot - origin) + Vector2(0.5, 0.0)) * scale))
					crown.lifts.append(pow(1.0 - along if stands else along, 2.0) * scale.x * to_world.get_scale().x)
			out.append(crown)
		index += 1
	return out


## The leaf styles of data/foliage.json, every root merged.
static func styles() -> Dictionary:
	if _styles.is_empty() and DataDoc.exists(RULES_PATH):
		_styles = DataDoc.doc(RULES_PATH).get("styles", {})
	return _styles


## How the ravens look and how wary they are (data/foliage.json "birds").
static func ravens() -> Dictionary:
	if _ravens.is_empty() and DataDoc.exists(RULES_PATH):
		_ravens = DataDoc.doc(RULES_PATH).get("birds", {})
	return _ravens


## Branch tops a raven can sit on inside [param rect] of [param image]: a dark
## pixel with six brighter ones over it (sky or mist, room for the bird) on a
## bough that goes on to either side — never a lone twig tip, never the air.
## A hanging crown's lowest quarter is left out (its trailing ends, and the
## distant trees under it). Up to [param count], PERCH_GAP apart, the ones
## with the brightest sky behind them first — a black bird reads against it —
## jittered by [param seed], so the same room always seats them alike.
static func perches_in(image: Image, rect: Rect2i, stands: bool, count: int, seed: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if image == null or count <= 0:
		return out
	rect = rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if rect.size.x < 8 or rect.size.y < 12:
		return out
	var part := image.get_region(rect)
	part.convert(Image.FORMAT_L8)
	var lum := part.get_data()
	var w := rect.size.x
	var found: Array[Vector2i] = []
	var scores: Array[float] = []
	var random := RandomNumberGenerator.new()
	random.seed = seed
	for y in range(8, rect.size.y - 2 if stands else int(rect.size.y * 0.75)):
		for x in range(3, w - 3):
			var dark := lum[y * w + x] + PERCH_CONTRAST
			if lum[(y + 1) * w + x] >= dark:
				continue
			if mini(lum[y * w + x - 2], lum[(y + 1) * w + x - 2]) >= dark or mini(lum[y * w + x + 2], lum[(y + 1) * w + x + 2]) >= dark:
				continue
			var sky := 255
			for k in range(2, 10):
				sky = mini(sky, lum[(y - k) * w + x])
				if sky < dark:
					break
			if sky >= dark:
				found.append(Vector2i(x, y))
				scores.append(sky - lum[y * w + x] + random.randf() * 12.0)
	var order := range(found.size())
	order.sort_custom(func(a: int, b: int) -> bool: return scores[a] > scores[b])
	for index in order:
		var spot := found[index]
		if out.size() >= count:
			break
		if out.all(func(taken: Vector2i) -> bool: return (taken - spot).length() >= PERCH_GAP):
			out.append(spot)
	for i in out.size():
		out[i] += rect.position
	return out


func _ready() -> void:
	# on the room, after its terrain, under the bodies the run holds (like Gore)
	z_index = 0
	_random.randomize()
	var room := get_parent() as Node2D
	if room != null:
		if room.has_meta(BackdropLife.META):
			for each in (room.get_meta(BackdropLife.META) as Dictionary).get("materials", []):
				_materials.append(each)
		if room.get("height") != null:
			_bottom = float(room.get("height")) + 60.0
			_right = float(room.get("width")) + 60.0
			_room = Rect2(0.0, 0.0, float(room.get("width")), float(room.get("height")))
	for crown in trees:
		for i in crown.perches.size():
			var bird := Bird.new()
			bird.crown = crown
			bird.perch = crown.perches[i]
			bird.lift = crown.lifts[i]
			bird.position = bird.perch
			bird.facing = 1.0 if _random.randf() < 0.5 else -1.0
			bird.timer = _random.randf_range(0.5, 4.0)
			birds.append(bird)
	_bends.resize(BackdropLife.MAX_ZONES)
	EventBus.world_impulse.connect(_on_world_impulse)
	EventBus.enemy_died.connect(_on_enemy_died)
	_lay_litter.call_deferred()


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_time += delta
	_air_energy = move_toward(_air_energy, 0.0, delta / AIR_FADE)
	var moving := _track_bodies(delta)
	for crown in trees:
		_update_crown(crown, moving, delta)
	var i := leaves.size() - 1
	while i >= 0:
		if not _update_leaf(leaves[i], moving, delta):
			leaves.remove_at(i)
		i -= 1
	for bird in birds:
		_update_bird(bird, moving, delta)
	_push_bends()
	queue_redraw()


## Every body in the room this frame: [centre, velocity]. Velocity is read from
## how far it moved, so a peer's body (whose velocity is not replicated) counts.
func _track_bodies(delta: float) -> Array:
	var out: Array = []
	var seen := {}
	for group in ["player", "enemies"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node2D
			if body == null or not body.is_visible_in_tree() or Swarm.spares(body):
				continue  # the locusts leave the garden be (Rev. 9:4)
			var id := body.get_instance_id()
			seen[id] = true
			var at := body.global_position
			var was: Vector2 = _bodies.get(id, at)
			_bodies[id] = at
			var velocity := (at - was) / delta
			if velocity.length() > 1500.0:
				velocity = Vector2.ZERO  # placed, not moved
			out.append([at, velocity])
	for id in _bodies.keys():
		if not seen.has(id):
			_bodies.erase(id)
	return out


func _update_crown(crown: Crown, moving: Array, delta: float) -> void:
	var style := crown.style
	crown.rustle = maxf(0.0, crown.rustle - delta)
	for each in moving:
		var at: Vector2 = each[0]
		var velocity: Vector2 = each[1]
		var fast := velocity.length()
		if fast < BRUSH_SPEED or not crown.rect.grow(4.0).has_point(at):
			continue
		crown.speed += velocity.x * BRUSH_PUSH * delta
		crown.torn += float(style.get("shed", 1.0)) * fast / 100.0 * BRUSH_SHED * delta
		while crown.torn >= 1.0:
			crown.torn -= 1.0
			_spawn(crown, at + Vector2(_random.randf_range(-10.0, 10.0), _random.randf_range(-14.0, 6.0)), velocity * 0.2)
		if fast > 120.0:
			_rustle(crown, at, -6.0)
	# the spring: a crown leans, swings back past rest and settles
	var omega := TAU * float(style.get("stiff", 1.2))
	var damp := float(style.get("damp", 0.18))
	crown.speed += (-omega * omega * crown.lean - 2.0 * damp * omega * crown.speed) * delta
	crown.lean += crown.speed * delta
	var most := float(style.get("bend", 2.5))
	if absf(crown.lean) > most:
		crown.lean = signf(crown.lean) * most
		crown.speed *= -0.3
	# the night's own breath, more of it while a gust is near
	crown.drift += float(style.get("drift", 0.05)) * crown.rect.size.x / 100.0 * (1.0 + 3.0 * _air_near(crown.rect.get_center())) * delta
	while crown.drift >= 1.0:
		crown.drift -= 1.0
		_spawn(crown, _inside(crown.rect))


## Moves one leaf; false when it is gone.
func _update_leaf(leaf: Leaf, moving: Array, delta: float) -> bool:
	if leaf.lying:
		leaf.life -= delta
		if leaf.life <= 0.0:
			return false
		if not leaf.pool.is_empty():
			return _float(leaf, moving, delta)
		for each in moving:
			var velocity: Vector2 = each[1]
			if absf(velocity.x) < KICK_SPEED:
				continue
			var off := leaf.position - (each[0] as Vector2) - Vector2(0.0, FEET)
			if absf(off.x) < KICK_REACH and off.y > -FEET * 2.0 and off.y < 4.0:
				_lift(leaf, Vector2(velocity.x * _random.randf_range(0.25, 0.5), -_random.randf_range(50.0, 110.0) * minf(1.0, absf(velocity.x) / 200.0)))
				break
		return true
	# a leaf falls at GRAVITY / drag through still air, swings by its flutter
	# and goes where the air goes: drag pulls it toward the air's own speed
	leaf.phase += leaf.spin * delta
	var swing := Vector2(cos(leaf.phase) * leaf.flutter, sin(leaf.phase * 2.0) * leaf.flutter * 0.25)
	leaf.velocity.y += GRAVITY * delta
	leaf.velocity += (_air_at(leaf.position) + swing - leaf.velocity) * minf(1.0, leaf.drag * delta)
	var to := leaf.position + leaf.velocity * delta
	if leaf.velocity.y > 0.0:
		var pool := _pool_crossed(leaf.position, to)
		if not pool.is_empty():
			return _settle_on(leaf, pool)
	var hit := _ray(leaf.position, to, WORLD_MASK | (LEDGE_MASK if leaf.velocity.y > 0.0 else 0))
	if hit.is_empty():
		leaf.position = to
	else:
		var normal: Vector2 = hit.normal
		if normal.y < -0.6:
			if leaf.shape == TWIG and not leaf.bounced and leaf.velocity.y > 50.0:
				# a stick hits the floor end first and hops once
				leaf.bounced = true
				leaf.position = (hit.position as Vector2) + normal
				leaf.velocity = Vector2(leaf.velocity.x * 0.5, -leaf.velocity.y * 0.35)
			else:
				leaf.position = (hit.position as Vector2) - Vector2(0.0, 0.5)
				leaf.velocity = Vector2.ZERO
				leaf.lying = true
				leaf.life = leaf.rest
		else:
			leaf.position = (hit.position as Vector2) + normal
			leaf.velocity = leaf.velocity.bounce(normal.normalized()) * 0.3
	return leaf.position.y < _bottom and leaf.position.x > -60.0 and leaf.position.x < _right


## A leaf on a pool: it rides the surface, drifts with the air and is pushed
## aside by a body wading past.
func _float(leaf: Leaf, moving: Array, delta: float) -> bool:
	var node = leaf.pool.node
	if not is_instance_valid(node):
		return false
	var rect: Rect2 = leaf.pool.rect
	var drift := _air_at(leaf.position).x * FLOAT_DRIFT
	for each in moving:
		var off := leaf.position - (each[0] as Vector2)
		if absf(off.x) < WAKE_REACH and absf(off.y) < FEET * 2.0:
			drift += (each[1] as Vector2).x * 0.5 + signf(off.x) * 12.0
	leaf.velocity.x = lerpf(leaf.velocity.x, drift, minf(1.0, delta * 2.0))
	leaf.position.x = clampf(leaf.position.x + leaf.velocity.x * delta, rect.position.x + 1.0, rect.end.x - 2.0)
	leaf.position.y = float(node.surface_y(leaf.position.x)) - 0.5
	return true


## The pool whose surface the step [param from] → [param to] goes down through,
## or whose body it is already in (a swell can rise past a leaf between frames).
func _pool_crossed(from: Vector2, to: Vector2) -> Dictionary:
	for pool in _pools:
		var rect: Rect2 = pool.rect
		if from.x < rect.position.x or from.x > rect.end.x or not is_instance_valid(pool.node):
			continue
		var top := float(pool.node.surface_y(from.x))
		if to.y >= top and from.y <= rect.end.y:
			return pool
	return {}


## A leaf come down onto [param pool]: it floats, or flares and is gone on what
## burns. False when it is gone.
func _settle_on(leaf: Leaf, pool: Dictionary) -> bool:
	var node = pool.node
	var top := float(node.surface_y(leaf.position.x))
	var surface = node.get("surface")
	if surface != null and is_instance_valid(surface):
		surface.disturb(leaf.position.x - (pool.rect as Rect2).position.x, 0.04, 3.0)
	if node.burns():
		Fx.sparkle(Vector2(leaf.position.x, top - 1.0), Color(1.0, 0.55, 0.2), 3, 3.0)
		return false
	leaf.position.y = top - 0.5
	leaf.velocity = Vector2(leaf.velocity.x * 0.2, 0.0)
	leaf.lying = true
	leaf.pool = pool
	leaf.life = leaf.rest * FLOAT_REST
	return true


## A blade through a falling leaf: it parts into two halves flung apart across
## the blow.
func _cut(leaf: Leaf, direction: Vector2) -> void:
	leaf.cut = true
	if leaf.shape == STRAND:
		leaf.length = maxi(1, leaf.length / 2)
	var across := Vector2(-direction.y, direction.x).normalized() * _random.randf_range(25.0, 50.0)
	var push := direction.normalized() * _random.randf_range(20.0, 50.0)
	if leaves.size() < MAX_LEAVES:
		var half := Leaf.new()
		for key in ["position", "phase", "color", "shape", "length", "drag", "flutter", "rest", "cut"]:
			half.set(key, leaf.get(key))
		half.spin = leaf.spin * 1.6
		half.phase += PI * 0.5
		half.velocity = leaf.velocity + push - across
		leaves.append(half)
	leaf.velocity += push + across
	leaf.spin *= 1.6


func _update_bird(bird: Bird, moving: Array, delta: float) -> void:
	var look := ravens()
	var reach := float(look.get("scare", 64.0))
	var seat := bird.perch + Vector2(bird.crown.lean * bird.lift, 0.0)
	match bird.state:
		PERCHED:
			bird.position = seat
			bird.pecking = maxf(0.0, bird.pecking - delta)
			bird.timer -= delta
			if bird.timer <= 0.0:
				# it turns round now and then, or dips its head at the bark
				bird.timer = _random.randf_range(1.5, 5.0)
				if _random.randf() < 0.35:
					bird.facing = -bird.facing
				else:
					bird.pecking = _random.randf_range(0.25, 0.6)
			var threat = _threat(bird.position, moving, reach)
			if threat != null:
				startle(bird, threat)
		STARTLED:
			bird.position = seat
			bird.timer -= delta
			if bird.timer <= 0.0:
				_take_off(bird)
		FLEEING:
			bird.timer += delta
			bird.wing += delta * (14.0 if bird.timer < 1.0 else 9.0)
			var top := float(look.get("speed", 150.0)) * bird.pace
			bird.velocity.x = move_toward(bird.velocity.x, bird.facing * top, top * 1.2 * delta)
			bird.velocity.y = move_toward(bird.velocity.y, -top * 0.4, top * 0.8 * delta)
			bird.position += bird.velocity * delta
			if not _room.grow(40.0).has_point(bird.position) or bird.timer > FLIGHT:
				bird.state = GONE
				bird.timer = float(look.get("away", 20.0)) * _random.randf_range(0.7, 1.3)
		GONE:
			bird.timer -= delta
			if bird.timer <= 0.0:
				if _threat(bird.perch, moving, reach * 2.0) != null:
					bird.timer = 3.0
				else:
					_come_back(bird)
		RETURNING:
			bird.timer += delta
			var off := seat - bird.position
			var gap := off.length()
			if gap < 1.5:
				bird.state = PERCHED
				bird.position = seat
				bird.velocity = Vector2.ZERO
				bird.timer = _random.randf_range(1.0, 3.0)
				return
			var top := float(look.get("speed", 150.0)) * 0.7 * bird.pace
			var want := off / gap * minf(top, gap * 2.5 + 12.0)
			bird.velocity = want if gap < 6.0 else bird.velocity.lerp(want, minf(1.0, 3.0 * delta))
			bird.position += bird.velocity * delta
			if absf(off.x) > 2.0:
				bird.facing = signf(off.x)
			# it beats its wings to climb and to stop, and glides between
			if bird.velocity.y < -10.0 or gap < 30.0 or fmod(bird.timer, 1.6) < 0.5:
				bird.wing += delta * 11.0
			else:
				bird.wing = 0.25
			var threat = _threat(bird.position, moving, reach)
			if threat != null:
				startle(bird, threat)


## The body nearest [param point] that would scare a raven there, or null:
## anything within a third of [param reach], or a fast one within it.
func _threat(point: Vector2, moving: Array, reach: float) -> Variant:
	for each in moving:
		var gap := (each[0] as Vector2).distance_to(point)
		if gap < reach * 0.35 or (gap < reach and (each[1] as Vector2).length() > SCARE_SPEED):
			return each[0]
	return null


## Something at [param from] frightens [param bird]: a sitting one crouches a
## beat and goes, one coming back to its branch turns away at once.
func startle(bird: Bird, from: Vector2) -> void:
	if bird.state != PERCHED and bird.state != RETURNING:
		return
	var away := bird.position.x - from.x
	bird.facing = signf(away) if absf(away) > 2.0 else (1.0 if _random.randf() < 0.5 else -1.0)
	if bird.state == RETURNING:
		_take_off(bird)
	else:
		bird.state = STARTLED
		bird.timer = _random.randf_range(0.0, STARTLE)


func _take_off(bird: Bird) -> void:
	var leaving := bird.state != RETURNING
	bird.state = FLEEING
	bird.timer = 0.0
	bird.wing = 0.0
	bird.pace = _random.randf_range(0.85, 1.2)
	if leaving:
		bird.velocity = Vector2(bird.facing * _random.randf_range(30.0, 60.0), -_random.randf_range(90.0, 140.0))
		bird.crown.speed += bird.facing * -0.6  # the branch kicks back as it leaps
	if _time - _last_wingbeat > WINGBEAT_GAP:
		_last_wingbeat = _time
		Audio.play_at(&"wingbeat", bird.position)
	# one leaving scares the rest of the flock near it
	var flock := float(ravens().get("flock", 90.0))
	for other in birds:
		if other != bird and other.state == PERCHED and other.position.distance_to(bird.position) < flock:
			startle(other, bird.position - Vector2(bird.facing * 8.0, 0.0))


## Back from wherever it went: in from high to one side, gliding down to its branch.
func _come_back(bird: Bird) -> void:
	var side := 1.0 if _random.randf() < 0.5 else -1.0
	bird.state = RETURNING
	bird.timer = 0.0
	bird.pace = _random.randf_range(0.85, 1.2)
	bird.position = Vector2(bird.perch.x + side * _random.randf_range(280.0, 420.0), minf(bird.perch.y - 200.0, _room.position.y - 30.0))
	bird.velocity = Vector2(-side * 60.0, 30.0)
	bird.facing = -side


func _lift(leaf: Leaf, velocity: Vector2) -> void:
	leaf.lying = false
	leaf.bounced = false
	leaf.pool = {}
	leaf.life = 0.0
	leaf.position.y -= 1.0
	leaf.velocity = velocity


func _on_enemy_died(_enemy_id: StringName, at: Vector2) -> void:
	_on_world_impulse(at, Vector2.UP, 0.55, &"enemy_death")


## A dash, a jump, a landing, a parry, a swing (EventBus.world_impulse): the
## air moves, the leaves near it go with it, and a crown near it swings — a
## swing that reaches into a crown strikes it and throws a shower of leaves.
func _on_world_impulse(at: Vector2, direction: Vector2, strength: float, kind: StringName) -> void:
	if strength <= 0.0:
		return
	_air_origin = at
	_air_direction = direction.normalized() if direction.length_squared() > 0.01 else Vector2.UP
	_air_energy = maxf(_air_energy, strength)
	var reach := GUST_REACH * 0.6
	for leaf in leaves:
		var gap := leaf.position.distance_to(at)
		if gap > reach:
			continue
		var near := (1.0 - gap / reach) * strength
		var away := (leaf.position - at).normalized() if gap > 1.0 else Vector2.UP
		var push := (away + _air_direction * 0.6) * near * 90.0
		if not leaf.pool.is_empty():
			leaf.velocity.x += push.x * 0.3
			continue
		if kind == &"attack" and not leaf.lying and not leaf.cut and leaf.shape != TWIG and gap < CUT_REACH:
			_cut(leaf, direction if direction.length_squared() > 0.01 else Vector2.RIGHT)
			continue
		if leaf.lying:
			if near < 0.25:
				continue
			_lift(leaf, Vector2(push.x, minf(push.y, -40.0 * near)))
		else:
			leaf.velocity += push
	# a blow, a landing or a parry close by is enough for a raven
	var wary := float(ravens().get("scare", 64.0)) * 1.5 * strength
	for bird in birds:
		if bird.position.distance_to(at) < wary:
			startle(bird, at)
	for crown in trees:
		var gap := _gap(crown.rect, at)
		if gap > GUST_REACH:
			continue
		var near := 1.0 - gap / GUST_REACH
		var side := signf(direction.x) if absf(direction.x) > 0.3 else (1.0 if _random.randf() < 0.5 else -1.0)
		var shed := float(crown.style.get("shed", 1.0))
		if kind == &"attack" and gap <= STRIKE_SLOP:
			crown.speed += side * strength * STRIKE_PUSH
			for bird in birds:
				if bird.crown == crown:
					startle(bird, at)
			var struck := Vector2(clampf(at.x, crown.rect.position.x, crown.rect.end.x), clampf(at.y, crown.rect.position.y, crown.rect.end.y))
			for i in roundi(float(crown.style.get("burst", 12)) * (0.6 + strength * 0.5)):
				_spawn(crown, struck + Vector2(_random.randf_range(-18.0, 18.0), _random.randf_range(-16.0, 8.0)), Vector2(side * _random.randf_range(10.0, 60.0), _random.randf_range(-50.0, 10.0)))
			_rustle(crown, struck, -2.0)
		else:
			crown.speed += side * strength * near * GUST_PUSH
			for i in int(strength * near * shed * 3.0 + _random.randf()):
				_spawn(crown, _inside(crown.rect))
			if strength * near > 0.9:
				_rustle(crown, crown.rect.get_center(), -8.0)


## The old leaves under every crown: thrown down onto whatever floor lies below.
## Deferred a physics frame — the room's shapes are not in the space at _ready.
func _lay_litter() -> void:
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("liquids"):
		if node is Hazard and get_parent().is_ancestor_of(node):
			_pools.append({"node": node, "rect": Rect2(node.global_position, node.size)})
	for crown in trees:
		for i in int(crown.rect.size.x * LITTER * float(crown.style.get("shed", 1.0))):
			var x := _random.randf_range(crown.rect.position.x, crown.rect.end.x)
			var hit := _ray(Vector2(x, crown.rect.end.y), Vector2(x, crown.rect.end.y + 600.0), WORLD_MASK | LEDGE_MASK)
			if hit.is_empty():
				continue
			var leaf := _spawn(crown, (hit.position as Vector2) - Vector2(0.0, 0.5))
			if leaf == null:
				continue
			var pool := _pool_crossed(Vector2(x, crown.rect.end.y), hit.position)
			if not pool.is_empty() and _settle_on(leaf, pool):
				leaf.life = leaf.rest * FLOAT_REST * 3.0  # the old leaves on a pool drift off in time
				continue
			if not pool.is_empty():
				leaves.erase(leaf)
				continue
			leaf.lying = true
			leaf.life = 1e6  # litter stays until something scatters it


func _spawn(crown: Crown, at: Vector2, velocity := Vector2.ZERO) -> Leaf:
	if leaves.size() >= MAX_LEAVES:
		var oldest := -1
		var least := INF
		for i in leaves.size():
			if leaves[i].lying and leaves[i].life < least:
				least = leaves[i].life
				oldest = i
		if oldest < 0:
			return null
		leaves.remove_at(oldest)
	var style := crown.style
	var leaf := Leaf.new()
	var twig := _random.randf() < float(style.get("twigs", 0.0))
	leaf.shape = TWIG if twig else (STRAND if str(style.get("shape", "leaf")) == "strand" else LEAF)
	leaf.length = _random.randi_range(3, 5) if twig else (_random.randi_range(2, 4) if leaf.shape == STRAND else 1)
	var colors: Array = style.get("colors", ["#3a4630"])
	leaf.color = Color(str(colors[_random.randi() % colors.size()]))
	leaf.color = leaf.color.darkened(0.25) if twig else leaf.color.lightened(_random.randf_range(-0.08, 0.12))
	var fall := float(style.get("fall", 20.0)) * _random.randf_range(0.8, 1.25) * (2.5 if twig else 1.0)
	leaf.drag = GRAVITY / maxf(fall, 1.0)
	leaf.flutter = float(style.get("flutter", 12.0)) * _random.randf_range(0.6, 1.3) * (0.2 if twig else 1.0)
	leaf.spin = _random.randf_range(2.5, 5.5) * (2.0 if twig else 1.0)
	leaf.phase = _random.randf() * TAU
	leaf.rest = float(style.get("rest", 6.0)) * _random.randf_range(0.7, 1.3)
	leaf.position = at
	leaf.velocity = velocity + Vector2(_random.randf_range(-10.0, 10.0), _random.randf_range(-6.0, 4.0))
	leaves.append(leaf)
	return leaf


## Hands every crown's lean to the painting and its openings (the shader's
## + leans left). Silent once all have settled.
func _push_bends() -> void:
	var swinging := false
	for crown in trees:
		if absf(crown.lean) < 0.005 and absf(crown.speed) < 0.02:
			crown.lean = 0.0
			crown.speed = 0.0
		else:
			swinging = true
		_bends[crown.zone] = -crown.lean
	if not swinging and _settled:
		return
	_settled = not swinging
	for each in _materials:
		each.set_shader_parameter("life_bend", _bends)


func _rustle(crown: Crown, at: Vector2, volume_db: float) -> void:
	if crown.rustle > 0.0:
		return
	crown.rustle = RUSTLE_GAP
	Audio.play_at(&"rustle", at, volume_db)


## The air at [param point]: the night's slow breath and the last gust, which
## fades over AIR_FADE and with distance from where it began.
func _air_at(point: Vector2) -> Vector2:
	var air := Vector2(sin(_time * 0.3) * 6.0, 0.0)
	return air + _air_direction * _air_energy * _air_near(point) * AIR_PUSH


func _air_near(point: Vector2) -> float:
	if _air_energy <= 0.0:
		return 0.0
	return clampf(1.0 - point.distance_to(_air_origin) / (GUST_REACH * 1.5), 0.0, 1.0) * _air_energy


## How far [param point] is from [param rect]: 0 inside it.
static func _gap(rect: Rect2, point: Vector2) -> float:
	return Vector2(maxf(maxf(rect.position.x - point.x, point.x - rect.end.x), 0.0),
		maxf(maxf(rect.position.y - point.y, point.y - rect.end.y), 0.0)).length()


## A spot a leaf comes loose from: anywhere across the crown, in its lower three quarters.
func _inside(rect: Rect2) -> Vector2:
	return Vector2(_random.randf_range(rect.position.x, rect.end.x), _random.randf_range(rect.position.y + rect.size.y * 0.25, rect.end.y))


func _ray(from: Vector2, to: Vector2, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, mask)
	return get_world_2d().direct_space_state.intersect_ray(query)


## 1:1 pixel shapes (Fx.PIXELS' rule): a leaf is a 2x1 pixel that turns
## edge-on and over as it tumbles, moss a hanging thread, a twig a spinning stick.
func _draw() -> void:
	for leaf in leaves:
		var color := leaf.color
		if leaf.lying and leaf.life < 1.5:
			color.a *= leaf.life / 1.5
		var at := leaf.position.floor()
		match leaf.shape:
			LEAF:
				var face := cos(leaf.phase)
				if leaf.cut:
					draw_rect(Rect2(at, Vector2.ONE), color if face > 0.0 else color.darkened(0.3))
				elif leaf.lying:
					draw_rect(Rect2(at, Vector2(2.0, 1.0)), color)
				elif absf(face) < 0.35:
					draw_rect(Rect2(at, Vector2.ONE), color)
				else:
					draw_rect(Rect2(at, Vector2(2.0, 1.0)), color if face > 0.0 else color.darkened(0.3))
			STRAND:
				if leaf.lying:
					draw_rect(Rect2(at, Vector2(leaf.length, 1.0)), color)
				else:
					var lean := clampf(roundf(leaf.velocity.x / 25.0), -1.0, 1.0)
					var top := ceili(leaf.length / 2.0)
					draw_rect(Rect2(at, Vector2(1.0, top)), color)
					draw_rect(Rect2(at + Vector2(-lean, top), Vector2(1.0, leaf.length - top)), color)
			TWIG:
				var angle := 0.0 if leaf.lying else leaf.phase
				var along := Vector2(cos(angle), sin(angle))
				for i in leaf.length:
					draw_rect(Rect2((leaf.position + along * (i - leaf.length * 0.5)).floor(), Vector2.ONE), color)
	if birds.is_empty() or not is_inside_tree():
		return
	var look := ravens()
	var body := Color(str(look.get("body", "#0e0c12")))
	var rim := Color(str(look.get("rim", "#5a5670")))
	var beak := Color(str(look.get("beak", "#2a2830")))
	for bird in birds:
		if bird.state == GONE:
			continue
		var shape: Array
		var corner: Vector2
		if bird.state == PERCHED or bird.state == STARTLED:
			shape = PECK if bird.pecking > 0.0 or bird.state == STARTLED else SIT
			var feet: int = SIT_FEET if bird.facing > 0.0 else (shape[0] as String).length() - 1 - SIT_FEET
			corner = bird.position.floor() - Vector2(feet, shape.size())
		else:
			shape = [FLY_UP, FLY_MID, FLY_DOWN, FLY_MID][int(bird.wing * 4.0) % 4]
			corner = (bird.position - Vector2((shape[0] as String).length(), shape.size()) * 0.5).floor()
		_draw_shape(shape, corner, bird.facing < 0.0, body, rim, beak)


## One raven's shape at [param corner]: the top of every part lit by the
## sky (rim), so a black bird still reads against a dark crown.
func _draw_shape(shape: Array, corner: Vector2, flip: bool, body: Color, rim: Color, beak: Color) -> void:
	var width: int = (shape[0] as String).length()
	for y in shape.size():
		var row: String = shape[y]
		for x in width:
			var c := row[x]
			if c == ".":
				continue
			var color := beak if c == "=" else (rim if y == 0 or (shape[y - 1] as String)[x] == "." else body)
			draw_rect(Rect2(corner + Vector2(width - 1 - x if flip else x, y), Vector2.ONE), color)
