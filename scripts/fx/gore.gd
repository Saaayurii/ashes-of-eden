extends Node2D
class_name Gore
## Blood and torn limbs, as data (data/gore.json, the art studio's «Кровь»).
##
## One layer per room (made on the first drop, freed with the room): the drops
## in the air fly with gravity and are stopped by the room's own colliders, and
## where one lands it leaves a mark — a smear on a floor, a streak down a wall —
## that stays a while and fades. A death throws a gush and grows a pool under
## the body; a body that can be torn apart (`limbs`) is cut into pieces of its
## own drawing — the frame it died in — that fly, bounce, bleed and lie there.
## No two alike: a death picks how it tears (`cuts`: all to pieces, the head
## off, cut in half, an arm off — what is left stands a beat, then topples),
## the cuts are ragged, a stump jets in pulses (`spurt`), every drop and mark
## takes its own shade of the blood (`shade`) and lands as a smear, a splat or
## a broken trail.
## Blood keeps to what it lands on: a mark stops at the edge of the floor it lies
## on and what hangs over drips off it (`drip`), a streak runs down a wall only
## as far as the wall goes (`run`), drops gather under a ledge and fall from
## it, a heavy drop splashes into droplets (`splash`), some fly into the depth
## and stick to the painted wall behind — never to the sky or a far opening
## (`back`) — a fine mist hangs a moment (`mist`), and every mark soaks into
## the painting under it rather than lying on top (`soak`, a multiply pass).
## Pixels drawn 1:1 like Fx.PIXELS, never a soft dot scaled up. All of it is
## cosmetic and local: every peer throws its own, and Settings.gore (full,
## reduced, off) decides how much.

const PATH := "res://data/gore.json"
const KEYS := ["blood", "shade", "drops", "spray", "mist", "stain", "stain_life", "soak", "splash", "run", "drip",
	"back", "gush", "pool", "bleed", "spurt", "limbs", "chance", "fling", "cuts"]
const DEFAULTS := {"blood": "#7a0c10", "shade": 0.15, "drops": 6, "spray": 140.0, "mist": 0, "stain": 1.0,
	"stain_life": 25.0, "soak": 0.5, "splash": 1.0, "run": 10.0, "drip": 0.3, "back": 0.1,
	"gush": 12, "pool": 10.0, "bleed": 0.6, "spurt": 1.2, "limbs": 0, "chance": 0.0, "fling": 150.0,
	"cuts": {"all": 3, "head": 2, "half": 1, "limb": 1}}
## The ways a body tears (`cuts` weighs them): to pieces; the head off; in half
## at the waist; an arm off (a body cut in 4 or fewer has no arms: the head then).
const CUTS := ["all", "head", "half", "limb"]
## How far a cut line wanders, as a share of the body's height or width.
const RAGGED := 0.07
## What a drop is stopped by: the world (layer 1), and a ledge (layer 5) from above.
const WORLD_MASK := 1
const LEDGE_MASK := 16
const GRAVITY := 560.0
const MAX_DROPS := 260
const MAX_STAINS := 520
const MAX_PIECES := 28
const MAX_DRIPS := 40
## A drop's flags: thrown off another (it does not splash again), a speck of
## mist (no mark), bound for the painted wall behind.
const SPLASHED := 1
const MISTY := 2
const BACK := 4
## A drop lands harder than this and splashes, px/s.
const SPLASH_SPEED := 120.0
const NODE_NAME := "Gore"

static var _materials: Dictionary = {}
static var _bodies: Dictionary = {}
static var _loaded := false
## The drawn part of each frame cut so far (_opaque).
static var _bounds := {}
## For the tests: drops thrown, pieces torn, marks left.
static var thrown := 0
static var torn := 0
static var marked := 0

var _drops: Array = []  # [position, velocity, colour, ink, age, pixels, flags, lands (BACK: the age it sticks at)]
var _stains: Array = []  # {p, w, spot, face, c, born, grow, life, seed, kind, soak, lo, hi}
var _drips: Array = []  # {p, left, tick, c, ink}: blood gathering under a ledge or off an edge, falling a drop at a time
var _openings: Array = []  # the painting's openings (sky, far windows), global polygons: nothing sticks there
var _openings_read := false
var _air: Node2D
var _soak: Node2D
var _clock := 0.0
var _busy := false


## The table for one body: its material's keys, then its own laid over them.
static func spec(key: String, material := "") -> Dictionary:
	_load()
	var own: Dictionary = _bodies.get(key, {})
	var mat := str(own.get("material", material))
	var out := DEFAULTS.duplicate()
	out.merge(_materials.get(mat, _materials.get("flesh", {})), true)
	out.merge(own, true)
	return out


## Lets a test (or the studio's live game) hand over its own table.
static func use(materials: Dictionary, bodies := {}) -> void:
	_materials = materials
	_bodies = bodies
	_loaded = true


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_materials = parsed.get("materials", {})
			_bodies = parsed.get("bodies", {})


## 1 at full, 0.5 reduced, 0 off (Settings.gore).
static func amount() -> float:
	return Settings.gore_scale()


## A blow lands on [param body]: drops thrown along [param direction] (away
## from whoever swung) and a wound that drips for a while. [param weight] is
## how heavy the blow was: 1 a plain one, more for a crit, a backstab, a big share.
static func hit(body: Node2D, key: String, material: String, at: Vector2, direction: Vector2, weight := 1.0) -> void:
	var scale := amount()
	if scale <= 0.0 or body == null or not body.is_inside_tree():
		return
	var s := spec(key, material)
	var layer := of(body)
	if layer == null:
		return
	var count := int(round(float(s.drops) * clampf(weight, 0.5, 2.5) * scale * randf_range(0.75, 1.25)))
	layer.spray(at, direction, count, s, 38.0)
	var bleed := float(s.bleed) * clampf(weight, 0.6, 2.0)
	if bleed > 0.0:
		Bleed.wound(body, layer, s, bleed, at - body.global_position)


## The body falls: a gush, a pool that grows under it, and — when its table
## allows and the dice say so — its own drawing torn into pieces. Returns true
## when it was torn: the caller hides the body, the pieces are what is left.
static func death(body: Node2D, key: String, material: String, sprite: AnimatedSprite2D, direction: Vector2, violent := false) -> bool:
	var scale := amount()
	if scale <= 0.0 or body == null or not body.is_inside_tree():
		return false
	var s := spec(key, material)
	var layer := of(body)
	if layer == null:
		return false
	var centre := body.global_position + Vector2(0, -10)
	layer.spray(centre, direction + Vector2(0, randf_range(-0.9, -0.3)),
		int(round(float(s.gush) * scale * randf_range(0.75, 1.25))), s, randf_range(55.0, 90.0))
	if float(s.pool) > 0.0:
		layer.pool(body.global_position + Vector2(0, -6), float(s.pool), s)
	var limbs := int(s.limbs)
	var chance := float(s.chance) * (2.0 if violent else 1.0)
	if scale < 1.0 or limbs < 2 or sprite == null or not sprite.visible or randf() >= chance:
		return false
	return layer.tear(sprite, limbs, direction, s, pick_cut(s.get("cuts", {}), limbs)) > 0


## One of CUTS, by the weights in [param weights] (a missing one weighs nothing;
## none at all is "all"). A body without arms (4 pieces or fewer) loses its head instead.
static func pick_cut(weights: Dictionary, limbs: int) -> String:
	var total := 0.0
	for way in CUTS:
		total += maxf(float(weights.get(way, 0.0)), 0.0)
	var way := "all"
	if total > 0.0:
		var roll := randf() * total
		for w in CUTS:
			roll -= maxf(float(weights.get(w, 0.0)), 0.0)
			if roll < 0.0:
				way = w
				break
	if way == "limb" and limbs < 5:
		way = "head"
	return way


## The room's layer, made the first time something bleeds in it.
static func of(node: Node) -> Gore:
	if node == null or not node.is_inside_tree():
		return null
	var tree := node.get_tree()
	var room := tree.get_first_node_in_group("room")
	var parent: Node = room if room != null else tree.current_scene
	if parent == null:
		return null
	var layer := parent.get_node_or_null(NODE_NAME) as Gore
	if layer == null:
		layer = Gore.new()
		layer.name = NODE_NAME
		parent.add_child(layer)
	return layer


func _ready() -> void:
	# the marks lie on the room (z 0, after its terrain, under the bodies the run
	# holds); the drops in flight are over everything but the numbers
	z_index = 0
	_air = Node2D.new()
	_air.name = "Air"
	_air.z_index = 5
	_air.draw.connect(_draw_air)
	add_child(_air)
	# the same marks again, multiplied into whatever is painted under them: blood
	# that soaks into the stone instead of lying on it
	_soak = Node2D.new()
	_soak.name = "Soak"
	var multiply := CanvasItemMaterial.new()
	multiply.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_soak.material = multiply
	_soak.draw.connect(_paint.bind(_soak, true))
	add_child(_soak)


## Throws [param count] drops out of [param at] along [param direction], fanned
## by [param spread] degrees.
func spray(at: Vector2, direction: Vector2, count: int, s: Dictionary, spread := 40.0) -> void:
	var colour := Color(str(s.blood))
	var shade := float(s.get("shade", 0.0))
	# every blow its own tilt; now and then the spray breaks into a jet and a mist
	var dir := (direction.normalized() if direction.length() > 0.01 else Vector2.UP).rotated(randf_range(-0.22, 0.22))
	var speed := float(s.spray) * randf_range(0.85, 1.15)
	var jet := randf() < 0.35
	var how := ink(s)
	for i in count:
		var in_jet := jet and i < count / 3.0
		var fan := spread * (0.25 if in_jet else 1.0)
		var v := dir.rotated(deg_to_rad(randf_range(-fan, fan))) * speed * (randf_range(0.9, 1.35) if in_jet else randf_range(0.3, 1.1))
		v.y -= randf_range(10.0, 60.0)  # a blow lifts the drops before they fall
		drop(at + Vector2(randf_range(-3, 3), randf_range(-3, 3)), v, shaded(colour, shade), how)
	# a fine mist: faint specks, slow, gone before they land
	var faint := colour
	faint.a *= 0.45
	for i in int(round(float(s.get("mist", 0)) * clampf(count / maxf(float(s.drops), 1.0), 0.5, 2.0))):
		drop(at + Vector2(randf_range(-4, 4), randf_range(-4, 4)),
			dir.rotated(deg_to_rad(randf_range(-spread, spread) * 1.4)) * speed * randf_range(0.1, 0.45), shaded(faint, shade), how, MISTY)


## [param colour] a shade darker or lighter, by up to [param amount]: no two drops the same red.
func shaded(colour: Color, amount: float) -> Color:
	if amount <= 0.0:
		return colour
	var k := randf_range(-amount, amount)
	return colour.darkened(-k) if k < 0.0 else colour.lightened(k * 0.6)


## What a drop carries of its body's table: how its marks look and behave.
## [param size] scales the marks (a drip leaves smaller ones than a gush).
static func ink(s: Dictionary, size := 1.0) -> Dictionary:
	return {"stain": float(s.get("stain", 1.0)) * size, "life": float(s.get("stain_life", 25.0)),
		"soak": float(s.get("soak", 0.0)), "splash": float(s.get("splash", 0.0)), "run": float(s.get("run", 0.0)),
		"drip": float(s.get("drip", 0.0)), "back": float(s.get("back", 0.0))}


func drop(at: Vector2, velocity: Vector2, colour: Color, how: Dictionary, flags := 0) -> void:
	if _drops.size() >= MAX_DROPS:
		_drops.pop_front()
	if flags == 0 and randf() < float(how.get("back", 0.0)):
		flags = BACK
	# most drops a pixel, some a clot of two; mist and splashes a pixel
	var pixels := 2 if flags & (SPLASHED | MISTY) == 0 and randf() < 0.18 else 1
	_drops.append([at, velocity, colour, how, 0.0, pixels, flags, randf_range(0.06, 0.32)])
	Gore.thrown += 1
	_busy = true


## A pool spreading on the floor under [param at] to [param width] pixels.
func pool(at: Vector2, width: float, s: Dictionary) -> void:
	var hit := _ray(at, at + Vector2(0, 80), WORLD_MASK | LEDGE_MASK)
	if hit.is_empty():
		return
	var colour := Color(str(s.blood)).darkened(0.15)
	var shade := float(s.get("shade", 0.0)) * 0.5
	var floor_at: Vector2 = hit.position
	var span := surface(hit)
	var how := ink(s)
	how.life = float(s.stain_life) * 1.4
	# one pool, never the same: a main spread and a few runs off it, each at its own pace;
	# it stops at the floor's edge and what reaches over it runs off in drips
	mark(floor_at, width * randf_range(0.8, 1.2), 0, shaded(colour, shade), how, randf_range(1.2, 2.2), 0, span)
	how = ink(s)
	for i in randi_range(1, 3):
		mark(floor_at + Vector2(randf_range(-width, width) * 0.6, 0), width * randf_range(0.25, 0.5), 0,
			shaded(colour, shade), how, randf_range(0.8, 2.6), 0, span)


## Where on its surface a ray's [param hit] can be marked: the x range of a
## floor's or a ceiling's face, the y range of a wall's, from the shape it hit.
## A shape that is not a box is unbounded.
func surface(hit: Dictionary) -> Vector2:
	var any := Vector2(-INF, INF)
	var body := hit.get("collider") as CollisionObject2D
	if body == null:
		return any
	var owner_id := body.shape_find_owner(int(hit.get("shape", 0)))
	var node := body.shape_owner_get_owner(owner_id) as CollisionShape2D
	if node == null or not node.shape is RectangleShape2D:
		return any
	var size: Vector2 = (node.shape as RectangleShape2D).size
	var box := node.global_transform * Rect2(-size / 2.0, size)
	var normal: Vector2 = hit.get("normal", Vector2.UP)
	return Vector2(box.position.y, box.end.y) if absf(normal.x) > 0.6 else Vector2(box.position.x, box.end.x)


## A mark where a drop or a piece landed. [param face]: 0 a floor (smears
## along), 1 a wall (streaks down, further with the ink's `run`), 2 the
## underside of a ledge, 3 the painted wall behind. [param kind] -1 picks one:
## 0 a smear, 1 a splat with spatter round it, 2 a broken trail. [param span]
## is the surface it lies on (`surface`): it is not drawn past it, and what a
## floor mark reaches over the edge with drips off.
func mark(at: Vector2, width: float, face: int, colour: Color, how: Dictionary, grow := 0.25, kind := -1,
		span := Vector2(-INF, INF)) -> void:
	var life := float(how.get("life", 20.0))
	if width < 0.5 or life <= 0.0:
		return
	if _stains.size() >= MAX_STAINS:
		_stains.pop_front()
	if kind < 0:
		kind = [0, 0, 1, 2].pick_random()
	at = at.round()
	var length := width
	if face == 1 or face == 3:
		# blood runs down a wall: some streaks a pixel, some a long way, never past the wall's foot
		length = width * randf_range(0.7, 1.4) + float(how.get("run", 0.0)) * randf_range(0.2, 1.2) * (0.4 if face == 3 else 1.0)
		if face == 1:
			length = minf(length, span.y - at.y)
		grow = maxf(grow, length / randf_range(6.0, 16.0))
	elif face == 0 and is_finite(span.x):
		# what reaches over the edge of a ledge runs off it
		for edge in [span.x, span.y]:
			if absf(at.x - edge) < maxf(width * 0.6, 2.0) and randf() < 0.35 + float(how.get("drip", 0.0)):
				var at_edge := Vector2(edge + (-0.5 if edge == span.x else 0.5), at.y)
				_drip_from(at_edge, colour, how, randi_range(1, 3))
	elif face == 2 and randf() < float(how.get("drip", 0.0)) * 2.0:
		_drip_from(at + Vector2(0, 1), colour, how, randi_range(1, 4))
	_stains.append({"p": at, "w": length, "spot": width, "face": face, "c": colour, "born": _clock, "grow": grow,
		"life": life * randf_range(0.8, 1.2), "seed": randi(), "kind": kind, "soak": float(how.get("soak", 0.0)),
		"lo": span.x, "hi": span.y})
	Gore.marked += 1
	_busy = true


func _drip_from(at: Vector2, colour: Color, how: Dictionary, count: int) -> void:
	if _drips.size() >= MAX_DRIPS:
		_drips.pop_front()
	_drips.append({"p": at, "left": count, "tick": randf_range(0.2, 0.9), "c": colour, "ink": how})
	_busy = true


## The painting's openings — the sky, a far window — where nothing can stick.
func _in_opening(at: Vector2) -> bool:
	if not _openings_read:
		_openings_read = true
		var room := get_parent() as Node2D
		var windows := room.get_node_or_null("DepthWindows") as Node2D if room else null
		if windows != null:
			for i in range(1, 32):
				var outline := RoomLayers.window_outline(room, i)
				if outline.size() < 3:
					break
				var feather := windows.get_node_or_null("Window%dFeather1" % i) as Node2D
				_openings.append((feather.global_transform if feather else windows.global_transform) * outline)
	for polygon in _openings:
		if Geometry2D.is_point_in_polygon(at, polygon):
			return true
	return false


## Cuts the frame [param sprite] shows into pieces, [param way] (one of CUTS),
## and throws what flies; what is left stands a beat and topples the way the blow went.
func tear(sprite: AnimatedSprite2D, limbs: int, direction: Vector2, s: Dictionary, way := "all") -> int:
	if sprite.sprite_frames == null:
		return 0
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame) as AtlasTexture
	if texture == null or texture.atlas == null:
		return 0
	var cell := texture.region
	var bounds := _opaque(texture.atlas, cell)
	var parts := cut(bounds, limbs, way, RAGGED)
	var pieces := get_tree().get_nodes_in_group("gore_piece")
	for i in maxi(0, pieces.size() + parts.size() - MAX_PIECES):
		(pieces[i] as Node).queue_free()
	var centre := bounds.get_center()
	var away := direction.normalized() if direction.length() > 0.01 else Vector2.ZERO
	var side := signf(away.x) if absf(away.x) > 0.1 else (1.0 if randf() < 0.5 else -1.0)
	var hold := randf_range(0.12, 0.45)  # what stands, stands together
	var made := 0
	for part in parts:
		var rect: Rect2 = part.rect
		var piece := GorePiece.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = texture.atlas
		atlas.region = Rect2(cell.position + rect.position, rect.size)
		atlas.filter_clip = true
		piece.texture = atlas
		piece.flip_h = sprite.flip_h
		piece.self_modulate = sprite.self_modulate
		piece.scale = sprite.global_scale.abs()
		piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var local := rect.get_center()
		var out := (local - centre)
		var mirror := -1.0 if sprite.flip_h else 1.0
		if sprite.flip_h:
			local.x = cell.size.x - local.x
			out.x = -out.x
		var place := sprite.global_transform * (local - cell.size / 2.0 + sprite.offset)
		var half := rect.size * piece.scale * 0.5
		var bleed := maxf(float(s.bleed), 0.4) * randf_range(1.1, 2.0)
		if part.stands:
			piece.setup(self, Vector2(side * randf_range(5.0, 25.0), 0.0), 0.0, s, bleed, half)
			piece.stand(hold + randf_range(0.0, 0.08), side * PI / 2.0 * randf_range(0.85, 1.0))
		else:
			var launch := (out.normalized() * randf_range(0.5, 0.9) + away * randf_range(0.6, 1.0)
				+ Vector2(randf_range(-0.2, 0.2), -1.0)).normalized()
			var fling := float(s.fling) * randf_range(0.55, 1.15) * (randf_range(1.1, 1.35) if part.name == "head" else 1.0)
			piece.setup(self, launch * fling, randf_range(-14.0, 14.0) * (1.0 + away.length()), s, bleed, half)
		var stump: Vector2 = part.stump
		if stump != Vector2.ZERO and float(s.get("spurt", 0.0)) > 0.0:
			piece.stump(Vector2(stump.x * mirror, stump.y) * rect.size * 0.5, Vector2(stump.x * mirror, stump.y).normalized(),
				float(s.spurt) * randf_range(0.6, 1.3) * (1.4 if part.stands else 1.0))
		piece.name = "Piece_" + str(part.name)
		add_child(piece)
		piece.global_position = place
		made += 1
	# what was inside empties where it stood
	spray(sprite.global_position, Vector2(side * 0.3, -1), int(float(s.gush) * randf_range(0.3, 0.6)), s, 70.0)
	Gore.torn += made
	return made


## Where the pieces lie in an opaque [param b] for a body cut in [param limbs]
## (2–6), torn [param way] (CUTS); each line wanders by up to [param ragged] of
## the body. A part: {name, rect, stands (left standing), stump (where its wound
## faces: up, down or aside, in the drawing's own axes; zero for none)}.
static func cut(b: Rect2, limbs: int, way := "all", ragged := 0.0) -> Array:
	var out: Array = []
	if limbs < 2:
		return out
	var x := b.position.x
	var y := b.position.y
	var w := maxf(b.size.x, 2.0)
	var h := maxf(b.size.y, 3.0)
	var j := func(v: float) -> float: return v + randf_range(-ragged, ragged)
	var neck: float = clampf(j.call(0.3), 0.15, 0.45)
	var waist: float = clampf(j.call(0.64), neck + 0.15, 0.85)
	var middle: float = clampf(j.call(0.5), 0.3, 0.7)
	var arm: float = clampf(j.call(0.3), 0.18, 0.4)
	var legs: float = clampf(j.call(0.5), 0.35, 0.65)
	var add := func(name: String, x0: float, x1: float, a: float, z: float, stands: bool, stump: Vector2) -> void:
		var top := y + floorf(h * a)
		var r := Rect2(floorf(x0), top, maxf(1.0, floorf(x1) - floorf(x0)), maxf(1.0, y + floorf(h * z) - top))
		out.append({"name": name, "rect": r, "stands": stands, "stump": stump})
	if way == "limb" and limbs < 5:
		way = "head"
	match way:
		"head":
			add.call("head", x + w * 0.2, x + w * 0.8, 0.0, neck, false, Vector2.DOWN)
			add.call("body", x, x + w, neck, 1.0, true, Vector2.UP)
		"half":
			add.call("upper", x, x + w, 0.0, middle, false, Vector2.DOWN)
			add.call("lower", x, x + w, middle, 1.0, true, Vector2.UP)
		"limb":
			if randf() < 0.5:
				add.call("arm_l", x, x + w * arm, neck, waist, false, Vector2.RIGHT)
				add.call("body", x + w * arm, x + w, 0.0, waist, true, Vector2.LEFT)
			else:
				add.call("arm_r", x + w * (1.0 - arm), x + w, neck, waist, false, Vector2.LEFT)
				add.call("body", x, x + w * (1.0 - arm), 0.0, waist, true, Vector2.RIGHT)
			add.call("legs", x, x + w, waist, 1.0, true, Vector2.ZERO)
		_:
			if limbs == 2:
				add.call("upper", x, x + w, 0.0, middle, false, Vector2.DOWN)
				add.call("lower", x, x + w, middle, 1.0, false, Vector2.UP)
				return out
			add.call("head", x + w * 0.2, x + w * 0.8, 0.0, neck, false, Vector2.DOWN)
			if limbs >= 5:
				add.call("arm_l", x, x + w * arm, neck, waist, false, Vector2.ZERO)
				add.call("torso", x + w * arm, x + w * (1.0 - arm), neck, waist, false, Vector2.UP)
				add.call("arm_r", x + w * (1.0 - arm), x + w, neck, waist, false, Vector2.ZERO)
			else:
				add.call("torso", x, x + w, neck, waist, false, Vector2.UP)
			if limbs == 3 or limbs == 5:
				add.call("legs", x, x + w, waist, 1.0, false, Vector2.ZERO)
			else:
				add.call("leg_l", x, x + w * legs, waist, 1.0, false, Vector2.ZERO)
				add.call("leg_r", x + w * legs, x + w, waist, 1.0, false, Vector2.ZERO)
	return out


## The drawn part of a frame, in the frame's own pixels; measured once per frame
## of a strip. A renderer that cannot read the picture back (headless) gets the
## middle of the cell.
static func _opaque(atlas: Texture2D, cell: Rect2) -> Rect2:
	var key := "%d:%s" % [atlas.get_instance_id(), cell]
	if _bounds.has(key):
		return _bounds[key]
	var found := Rect2(cell.size * Vector2(0.25, 0.2), cell.size * Vector2(0.5, 0.75))
	var image := atlas.get_image()
	if image != null and not image.is_empty():
		if image.is_compressed():
			image.decompress()
		var used := image.get_region(Rect2i(cell)).get_used_rect()
		if used.size.x >= 3 and used.size.y >= 3:
			found = Rect2(used)
	_bounds[key] = found
	return found


func _physics_process(delta: float) -> void:
	_tick_drips(delta)
	if _drops.is_empty():
		return
	var keep: Array = []
	var born: Array = []
	for d in _drops:
		var v: Vector2 = d[1]
		var flags: int = d[6]
		var how: Dictionary = d[3]
		v.y += GRAVITY * delta * (0.35 if flags & MISTY else 1.0)
		v.x *= 1.0 - (3.0 if flags & MISTY else 0.6) * delta
		var from: Vector2 = d[0]
		var to: Vector2 = from + v * delta
		d[4] += delta
		if flags & MISTY:
			if d[4] < randf_range(0.25, 0.7):
				d[0] = to
				d[1] = v
				keep.append(d)
			continue
		if flags & BACK and d[4] >= d[7]:
			# it flew into the depth and met the painted wall behind
			if not _in_opening(from):
				mark(from, randf_range(1.0, 2.5) * float(how.stain) * float(d[5]), 3, d[2], how, 0.25, [1, 1, 0].pick_random())
			continue
		var hit := _ray(from, to, WORLD_MASK | (LEDGE_MASK if v.y > 0.0 else 0))
		if not hit.is_empty():
			var normal: Vector2 = hit.normal
			var size := float(how.stain) * float(d[5]) * (0.5 if flags & SPLASHED else 1.0)
			if absf(normal.x) > 0.6:
				mark(hit.position, randf_range(1.0, 2.5) * size, 1, d[2], how, 0.25, -1, surface(hit))
			elif normal.y > 0.6:
				mark(hit.position, randf_range(1.0, 2.0) * size, 2, d[2], how, 0.25, 0, surface(hit))
			else:
				mark(hit.position, randf_range(1.0, 3.5) * size, 0, d[2], how, 0.25, -1, surface(hit))
				# a heavy drop splashes: a few droplets thrown back up off the floor
				if flags & SPLASHED == 0 and v.length() > SPLASH_SPEED:
					var force := clampf(v.length() / 320.0, 0.3, 1.0)
					for i in int(round(float(how.splash) * randf_range(0.3, 1.3) * force)):
						born.append([hit.position + Vector2(0, -1), Vector2(randf_range(-55.0, 55.0) + v.x * 0.2,
							-randf_range(35.0, 95.0) * force), d[2], how])
			continue
		if d[4] > 4.0:  # fell out of the room
			continue
		d[0] = to
		d[1] = v
		keep.append(d)
	_drops = keep
	for b in born:
		drop(b[0], b[1], b[2], b[3], SPLASHED)
	_air.queue_redraw()


## Drops gathered under a ledge or at a floor's edge fall one at a time.
func _tick_drips(delta: float) -> void:
	if _drips.is_empty():
		return
	var left: Array = []
	for dr in _drips:
		dr.tick -= delta
		if dr.tick <= 0.0:
			drop(dr.p, Vector2(randf_range(-3, 3), randf_range(0, 20)), dr.c, dr.ink, SPLASHED)
			dr.left -= 1
			dr.tick = randf_range(0.35, 1.4)
		if dr.left > 0:
			left.append(dr)
	_drips = left


func _process(delta: float) -> void:
	_clock += delta
	if not _busy:
		return
	# a mark at rest needs no redraw: only one growing, fading or going
	var redraw := false
	var living: Array = []
	for st in _stains:
		var age: float = _clock - st.born
		if age >= st.life:
			redraw = true
			continue
		living.append(st)
		if age < st.grow + 0.05 or age > st.life - 3.0:
			redraw = true
	_stains = living
	if redraw:
		queue_redraw()
		_soak.queue_redraw()
	_busy = not _stains.is_empty()


func _draw() -> void:
	_paint(self, false)


## Every mark, on [param canvas]: as it lies (its alpha less what soaked in),
## or [param soaked] — the share that soaked in, as a tint the multiply pass
## lays into the painting (white changes nothing).
func _paint(canvas: CanvasItem, soaked: bool) -> void:
	for st in _stains:
		var age: float = _clock - st.born
		var grown := clampf(age / maxf(st.grow, 0.01), 0.0, 1.0)
		grown = 1.0 - (1.0 - grown) * (1.0 - grown)
		var c: Color = st.c
		var fade := clampf((st.life - age) / 3.0, 0.0, 1.0)
		var soak: float = st.get("soak", 0.0)
		if soaked:
			if soak <= 0.0:
				continue
			var tint := Color(c.r, c.g, c.b)
			c = Color.WHITE.lerp(tint, soak * c.a * fade)
		else:
			c.a *= fade * (1.0 - soak * 0.85)
			if c.a <= 0.01:
				continue
		var p: Vector2 = to_local(st.p)
		var lo: float = st.get("lo", -INF)
		var hi: float = st.get("hi", INF)
		if is_finite(lo):
			lo = to_local(Vector2(lo, 0)).x
			hi = to_local(Vector2(hi, 0)).x
		var w: float = maxf(1.0, round(st.w * grown))
		var kind: int = st.get("kind", 0)
		var face: int = st.get("face", 0)
		var rng := RandomNumberGenerator.new()
		rng.seed = st.seed
		match face:
			1:
				# a streak running down, a drop gathering at its end; some streaks fork
				canvas.draw_rect(Rect2(p.x, p.y - 1, 1, w), c)
				if w > 3.0:
					canvas.draw_rect(Rect2(p.x, p.y + w - 1, 1, 1), c.darkened(0.3))
				if kind == 1 and w > 4.0:
					canvas.draw_rect(Rect2(p.x + (1 if st.seed % 2 == 0 else -1), p.y + floorf(w / 3.0), 1, floorf(w / 2.0)), c.darkened(0.1))
			2:
				# under a ledge: a blot clinging to the underside, a bead hanging off it
				var r := maxf(1.0, round(float(st.spot) * grown))
				_span(canvas, Rect2(p.x - floorf(r / 2.0), p.y, r, 1), c, lo, hi)
				if r >= 2.0:
					canvas.draw_rect(Rect2(p.x + rng.randi_range(-1, 0), p.y + 1, 1, 1), c.darkened(0.25))
			3:
				# on the painted wall behind: a splat, its spatter, and what runs down from it
				var r := maxf(1.0, floorf(float(st.spot) * 0.6))
				canvas.draw_rect(Rect2(p.x - floorf(r / 2.0), p.y - floorf(r / 2.0), r, r), c)
				for k in rng.randi_range(1, 3):
					canvas.draw_rect(Rect2(p.x + rng.randi_range(-3, 3), p.y + rng.randi_range(-3, 2), 1, 1), c)
				if w > r:
					canvas.draw_rect(Rect2(p.x + rng.randi_range(-floori(r / 2.0), 0), p.y, 1, w), c.darkened(0.1))
					canvas.draw_rect(Rect2(p.x, p.y + w, 1, 1), c.darkened(0.3))
			_:
				match kind:
					1:
						# a splat: a blot two rows deep and spatter thrown round it
						var r := maxf(1.0, floorf(w / 3.0))
						_span(canvas, Rect2(p.x - r, p.y - 1, r * 2.0, 1), c, lo, hi)
						_span(canvas, Rect2(p.x - floorf(r / 2.0), p.y - 2, maxf(1.0, r), 1), c.darkened(0.15), lo, hi)
						for k in maxi(2, int(w / 2.0)):
							_span(canvas, Rect2(p.x + rng.randf_range(-w, w), p.y - 1 - rng.randi_range(0, 1), 1, 1), c, lo, hi)
					2:
						# a broken trail: dashes along the lip
						var at := p.x - floorf(w / 2.0)
						while at < p.x + w / 2.0:
							var dash := float(rng.randi_range(1, 3))
							_span(canvas, Rect2(at, p.y - 1, dash, 1), c, lo, hi)
							at += dash + float(rng.randi_range(1, 2))
					_:
						# a smear along the floor's lip, thicker in the middle, a few spatters beside
						_span(canvas, Rect2(p.x - floorf(w / 2.0), p.y - 1, w, 1), c, lo, hi)
						if w >= 4.0:
							_span(canvas, Rect2(p.x - floorf(w / 4.0), p.y - 2, maxf(1.0, floorf(w / 2.0)), 1), c.darkened(0.2), lo, hi)
						if w >= 7.0:
							for k in int(w / 5.0):
								_span(canvas, Rect2(p.x + rng.randf_range(-w * 0.8, w * 0.8), p.y - 1 - rng.randi_range(0, 1), 1, 1), c, lo, hi)


## A row of a mark, cut to the surface it lies on (local x from [param lo] to [param hi]).
static func _span(canvas: CanvasItem, r: Rect2, c: Color, lo: float, hi: float) -> void:
	if is_finite(lo):
		var left := maxf(r.position.x, lo)
		var right := minf(r.end.x, hi)
		if right <= left:
			return
		r = Rect2(left, r.position.y, right - left, r.size.y)
	canvas.draw_rect(r, c)


func _draw_air() -> void:
	for d in _drops:
		var v: Vector2 = d[1]
		var p: Vector2 = to_local(d[0]).round()
		# a fast drop is a streak of two; a drop flying into the depth shrinks as it goes
		var size: int = d[5]
		var c: Color = d[2]
		if d[6] & BACK:
			c.a *= 1.0 - 0.5 * clampf(d[4] / maxf(d[7], 0.01), 0.0, 1.0)
		_air.draw_rect(Rect2(p, Vector2(size, (2 if absf(v.y) > 120.0 else 1) + size - 1)), c)


func _ray(from: Vector2, to: Vector2, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, mask)
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_ray(query)


## A wound that keeps dripping for a while: a child of the bleeding body, so it
## goes where the body goes and is freed with it.
class Bleed extends Node:
	var layer: Gore
	var colour := Color.RED
	var how := {}
	var shade := 0.0
	var left := 0.0
	var at := Vector2.ZERO
	var _tick := 0.0

	static func wound(body: Node2D, gore: Gore, s: Dictionary, seconds: float, offset: Vector2) -> void:
		var b := body.get_node_or_null("Bleed") as Bleed
		if b == null:
			b = Bleed.new()
			b.name = "Bleed"
			body.add_child(b)
		b.layer = gore
		b.colour = Color(str(s.blood))
		b.how = Gore.ink(s, 0.7)
		b.shade = float(s.get("shade", 0.0))
		b.left = maxf(b.left, seconds)
		b.at = offset

	func _process(delta: float) -> void:
		left -= delta
		if left <= 0.0 or not is_instance_valid(layer):
			queue_free()
			return
		_tick -= delta
		if _tick > 0.0:
			return
		_tick = randf_range(0.07, 0.16)
		var body := get_parent() as Node2D
		if body == null:
			return
		layer.drop(body.global_position + at + Vector2(randf_range(-3, 3), 0),
			Vector2(randf_range(-15, 15), randf_range(-10, 20)), layer.shaded(colour, shade), how)
