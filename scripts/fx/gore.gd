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
## Pixels drawn 1:1 like Fx.PIXELS, never a soft dot scaled up. All of it is
## cosmetic and local: every peer throws its own, and Settings.gore (full,
## reduced, off) decides how much.

const PATH := "res://data/gore.json"
const KEYS := ["blood", "drops", "spray", "stain", "stain_life", "gush", "pool", "bleed", "limbs", "chance", "fling"]
const DEFAULTS := {"blood": "#7a0c10", "drops": 6, "spray": 140.0, "stain": 1.0, "stain_life": 25.0, "gush": 12,
	"pool": 10.0, "bleed": 0.6, "limbs": 0, "chance": 0.0, "fling": 150.0}
## What a drop is stopped by: the world (layer 1), and a ledge (layer 5) from above.
const WORLD_MASK := 1
const LEDGE_MASK := 16
const GRAVITY := 560.0
const MAX_DROPS := 260
const MAX_STAINS := 520
const MAX_PIECES := 28
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

var _drops: Array = []  # [position, velocity, colour, stain size, stain life, age]
var _stains: Array = []  # {p, w, wall, c, born, grow, life}
var _air: Node2D
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
	var count := int(round(float(s.drops) * clampf(weight, 0.5, 2.5) * scale))
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
	layer.spray(centre, direction + Vector2(0, -0.6), int(round(float(s.gush) * scale)), s, 75.0)
	if float(s.pool) > 0.0:
		layer.pool(body.global_position + Vector2(0, -6), float(s.pool), s)
	var limbs := int(s.limbs)
	var chance := float(s.chance) * (2.0 if violent else 1.0)
	if scale < 1.0 or limbs < 2 or sprite == null or not sprite.visible or randf() >= chance:
		return false
	return layer.tear(sprite, limbs, direction, s) > 0


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


## Throws [param count] drops out of [param at] along [param direction], fanned
## by [param spread] degrees.
func spray(at: Vector2, direction: Vector2, count: int, s: Dictionary, spread := 40.0) -> void:
	var colour := Color(str(s.blood))
	var dir := direction.normalized() if direction.length() > 0.01 else Vector2.UP
	var speed := float(s.spray)
	for i in count:
		var v := dir.rotated(deg_to_rad(randf_range(-spread, spread))) * speed * randf_range(0.35, 1.15)
		v.y -= randf_range(10.0, 60.0)  # a blow lifts the drops before they fall
		drop(at + Vector2(randf_range(-3, 3), randf_range(-3, 3)), v, colour, float(s.stain), float(s.stain_life))


func drop(at: Vector2, velocity: Vector2, colour: Color, stain: float, life: float) -> void:
	if _drops.size() >= MAX_DROPS:
		_drops.pop_front()
	_drops.append([at, velocity, colour, stain, life, 0.0])
	Gore.thrown += 1
	_busy = true


## A pool spreading on the floor under [param at] to [param width] pixels.
func pool(at: Vector2, width: float, s: Dictionary) -> void:
	var hit := _ray(at, at + Vector2(0, 80), WORLD_MASK | LEDGE_MASK)
	if hit.is_empty():
		return
	var colour := Color(str(s.blood)).darkened(0.15)
	var floor_at: Vector2 = hit.position
	mark(floor_at, width * randf_range(0.85, 1.15), false, colour, float(s.stain_life) * 1.4, 1.6)
	mark(floor_at + Vector2(randf_range(-width, width) * 0.5, 0), width * 0.4, false, colour, float(s.stain_life), 1.1)


## A mark where a drop or a piece landed. [param wall] streaks down instead of
## smearing along.
func mark(at: Vector2, width: float, wall: bool, colour: Color, life: float, grow := 0.25) -> void:
	if width < 0.5 or life <= 0.0:
		return
	if _stains.size() >= MAX_STAINS:
		_stains.pop_front()
	_stains.append({"p": at.round(), "w": width, "wall": wall, "c": colour, "born": _clock, "grow": grow,
		"life": life, "seed": randi()})
	Gore.marked += 1
	_busy = true


## Cuts the frame [param sprite] shows into [param limbs] pieces and throws them.
func tear(sprite: AnimatedSprite2D, limbs: int, direction: Vector2, s: Dictionary) -> int:
	if sprite.sprite_frames == null:
		return 0
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame) as AtlasTexture
	if texture == null or texture.atlas == null:
		return 0
	var cell := texture.region
	var bounds := _opaque(texture.atlas, cell)
	var pieces := get_tree().get_nodes_in_group("gore_piece")
	for i in maxi(0, pieces.size() + limbs - MAX_PIECES):
		(pieces[i] as Node).queue_free()
	var centre := bounds.get_center()
	var made := 0
	for part in cut(bounds, limbs):
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
		if sprite.flip_h:
			local.x = cell.size.x - local.x
			out.x = -out.x
		var place := sprite.global_transform * (local - cell.size / 2.0 + sprite.offset)
		var away := direction.normalized() if direction.length() > 0.01 else Vector2.ZERO
		var launch := (out.normalized() * 0.7 + away * 0.8 + Vector2(0, -1.0)).normalized()
		var fling := float(s.fling) * randf_range(0.55, 1.1) * (1.2 if part.name == "head" else 1.0)
		piece.setup(self, launch * fling, randf_range(-12.0, 12.0) * (1.0 + away.length()),
			Color(str(s.blood)), float(s.stain), float(s.stain_life), maxf(float(s.bleed), 0.4) * 1.6,
			minf(rect.size.x, rect.size.y) * piece.scale.x * 0.5)
		piece.name = "Piece_" + str(part.name)
		add_child(piece)
		piece.global_position = place
		made += 1
	# the torso empties where it stood
	spray(sprite.global_position, Vector2(0, -1), int(float(s.gush) * 0.5), s, 70.0)
	Gore.torn += made
	return made


## Where [param limbs] pieces lie in an opaque [param b]: upper and lower; a
## head, a torso and the legs; the legs apart; the arms off the torso.
static func cut(b: Rect2, limbs: int) -> Array:
	var x := b.position.x
	var y := b.position.y
	var w := maxf(b.size.x, 2.0)
	var h := maxf(b.size.y, 3.0)
	var row := func(a: float, z: float) -> Array: return [y + floorf(h * a), y + floorf(h * z)]
	var out: Array = []
	var add := func(name: String, x0: float, x1: float, band: Array) -> void:
		var r := Rect2(floorf(x0), band[0], maxf(1.0, floorf(x1) - floorf(x0)), maxf(1.0, band[1] - band[0]))
		out.append({"name": name, "rect": r})
	if limbs <= 2:
		add.call("upper", x, x + w, row.call(0.0, 0.5))
		add.call("lower", x, x + w, row.call(0.5, 1.0))
		return out
	add.call("head", x + w * 0.2, x + w * 0.8, row.call(0.0, 0.3))
	if limbs >= 5:
		add.call("arm_l", x, x + w * 0.3, row.call(0.3, 0.64))
		add.call("torso", x + w * 0.3, x + w * 0.7, row.call(0.3, 0.64))
		add.call("arm_r", x + w * 0.7, x + w, row.call(0.3, 0.64))
	else:
		add.call("torso", x, x + w, row.call(0.3, 0.64))
	if limbs == 3 or limbs == 5:
		add.call("legs", x, x + w, row.call(0.64, 1.0))
	else:
		add.call("leg_l", x, x + w * 0.5, row.call(0.64, 1.0))
		add.call("leg_r", x + w * 0.5, x + w, row.call(0.64, 1.0))
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
	if _drops.is_empty():
		return
	var keep: Array = []
	for d in _drops:
		var v: Vector2 = d[1]
		v.y += GRAVITY * delta
		v.x *= 1.0 - 0.6 * delta
		var from: Vector2 = d[0]
		var to: Vector2 = from + v * delta
		d[5] += delta
		var hit := _ray(from, to, WORLD_MASK | (LEDGE_MASK if v.y > 0.0 else 0))
		if not hit.is_empty():
			var normal: Vector2 = hit.normal
			var wall := absf(normal.x) > 0.6
			if normal.y < 0.6:  # not a ceiling: a ceiling just takes the drop
				mark(hit.position, (randf_range(1.0, 3.5) if not wall else randf_range(2.0, 5.0)) * float(d[3]),
					wall, d[2], float(d[4]))
			continue
		if d[5] > 4.0:  # fell out of the room
			continue
		d[0] = to
		d[1] = v
		keep.append(d)
	_drops = keep
	_air.queue_redraw()


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
	_busy = not _stains.is_empty()


func _draw() -> void:
	for st in _stains:
		var age: float = _clock - st.born
		var grown := clampf(age / maxf(st.grow, 0.01), 0.0, 1.0)
		grown = 1.0 - (1.0 - grown) * (1.0 - grown)
		var c: Color = st.c
		c.a *= clampf((st.life - age) / 3.0, 0.0, 1.0)
		var p: Vector2 = to_local(st.p)
		var w: float = maxf(1.0, round(st.w * grown))
		if st.wall:
			draw_rect(Rect2(p.x, p.y - 1, 1, w), c)
			if w > 3.0:
				draw_rect(Rect2(p.x, p.y + w - 1, 1, 1), c.darkened(0.3))
		else:
			# a smear along the floor's lip, thicker in the middle, a few spatters beside
			draw_rect(Rect2(p.x - floorf(w / 2.0), p.y - 1, w, 1), c)
			if w >= 4.0:
				draw_rect(Rect2(p.x - floorf(w / 4.0), p.y - 2, maxf(1.0, floorf(w / 2.0)), 1), c.darkened(0.2))
			if w >= 7.0:
				var rng := RandomNumberGenerator.new()
				rng.seed = st.seed
				for k in int(w / 5.0):
					draw_rect(Rect2(p.x + rng.randf_range(-w * 0.8, w * 0.8), p.y - 1 - rng.randi_range(0, 1), 1, 1), c)


func _draw_air() -> void:
	for d in _drops:
		var v: Vector2 = d[1]
		var p: Vector2 = to_local(d[0]).round()
		# a fast drop is a streak of two
		_air.draw_rect(Rect2(p, Vector2(1, 2 if absf(v.y) > 120.0 else 1)), d[2])


func _ray(from: Vector2, to: Vector2, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, mask)
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_ray(query)


## A wound that keeps dripping for a while: a child of the bleeding body, so it
## goes where the body goes and is freed with it.
class Bleed extends Node:
	var layer: Gore
	var colour := Color.RED
	var stain := 1.0
	var life := 20.0
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
		b.stain = float(s.stain)
		b.life = float(s.stain_life)
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
			Vector2(randf_range(-15, 15), randf_range(-10, 20)), colour, stain * 0.7, life)
