extends Node
class_name ActionFx
## Particles on any action of any body, as data (data/action_fx.json, the art
## studio's «Частицы»). Attached to a body's AnimatedSprite2D: an animation it
## plays is a trigger — its emitters fire at the start, on chosen frames, or
## every so often while it plays — and the game names a few moments that are
## not an animation of their own: step, jump, land, roll, wake (event()).
## Everything goes through Fx, so it is as cheap and as cosmetic as the rest.

const PATH := "res://data/action_fx.json"
const KINDS := ["dust", "puff", "sparkle", "ash", "debris", "ring", "flash"]
const ANCHORS := ["feet", "body", "head", "hand", "back"]
const EVENTS := ["step", "jump", "land", "roll", "wake"]
const NODE_NAME := "ActionFx"

static var _bodies: Dictionary = {}
static var _loaded := false
## How many emitters have fired, for the tests.
static var emitted := 0

var key := ""
var sprite: AnimatedSprite2D
## Where the anchors sit, from the owner's origin: the player's and the
## enemies' bodies stand differently on their colliders.
var anchors := {"feet": Vector2(0, 14), "body": Vector2(0, -10), "head": Vector2(0, -24),
	"hand": Vector2(12, -12), "back": Vector2(-6, 6)}
var _now: Array = []
var _every := {}
var _last_frame := -1


static func rules(body_key: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
			if parsed is Dictionary:
				_bodies = parsed.get("bodies", {})
	return _bodies.get(body_key, {})


## Lets a test (or the studio's live game) hand over its own table.
static func use(bodies: Dictionary) -> void:
	_bodies = bodies
	_loaded = true


static func attach(owner: Node2D, body_sprite: AnimatedSprite2D, body_key: String, body_anchors := {}) -> ActionFx:
	var existing := owner.get_node_or_null(NODE_NAME) as ActionFx
	if existing != null:
		existing.queue_free()
	var fx := ActionFx.new()
	fx.name = NODE_NAME
	fx.key = body_key
	fx.sprite = body_sprite
	fx.anchors.merge(body_anchors, true)
	owner.add_child(fx)
	return fx


## A moment the game names (EVENTS), on the body that has an ActionFx.
static func event(owner: Node, event_name: String) -> void:
	var fx := owner.get_node_or_null(NODE_NAME) as ActionFx
	if fx != null:
		for spec: Dictionary in rules(fx.key).get(event_name, []):
			fx.emit(spec)


func _ready() -> void:
	if sprite == null:
		return
	sprite.animation_changed.connect(_on_animation)
	sprite.frame_changed.connect(_on_frame)
	_on_animation()


func _on_animation() -> void:
	_now = rules(key).get(str(sprite.animation), [])
	_every.clear()
	_last_frame = -1
	for spec: Dictionary in _now:
		if str(spec.get("when", "start")) == "start":
			emit(spec)
	_on_frame()


## Each frame once: a looping animation fires its frame-0 emitters on every lap,
## and an animation change followed by its own frame_changed does not fire twice.
func _on_frame() -> void:
	if sprite.frame == _last_frame:
		return
	_last_frame = sprite.frame
	for spec: Dictionary in _now:
		if str(spec.get("when", "start")) == "frames" and _lists_frame(spec.get("frames", []), sprite.frame):
			emit(spec)


## JSON gives 2.0, a hand-made table 2: a frame is a frame either way.
static func _lists_frame(frames: Array, frame: int) -> bool:
	for f in frames:
		if int(f) == frame:
			return true
	return false


func _process(delta: float) -> void:
	if not sprite or not sprite.is_playing() or not sprite.is_visible_in_tree():
		return
	for i in _now.size():
		var spec: Dictionary = _now[i]
		if str(spec.get("when", "start")) != "every":
			continue
		var left := float(_every.get(i, 0.0)) - delta
		if left <= 0.0:
			emit(spec)
			left = maxf(0.05, float(spec.get("every", 0.3)))
		_every[i] = left


func emit(spec: Dictionary) -> void:
	if randf() > float(spec.get("chance", 1.0)):
		return
	var owner_body := get_parent() as Node2D
	if owner_body == null:
		return
	var facing := 1.0 if not ("facing" in owner_body) else signf(float(owner_body.get("facing")))
	if facing == 0.0:
		facing = 1.0
	var anchor: Vector2 = anchors.get(str(spec.get("at", "feet")), anchors.feet)
	var offset: Array = spec.get("offset", [0, 0])
	var at := owner_body.global_position + Vector2(anchor.x * facing, anchor.y) \
		+ Vector2(float(offset[0]) * facing, float(offset[1]))
	var dir_raw: Array = spec.get("dir", [0, -1])
	var dir := Vector2(float(dir_raw[0]) * facing, float(dir_raw[1]))
	var count := int(spec.get("count", 6))
	var size := float(spec.get("size", 0.0))
	var has_color := spec.has("color") and Color.html_is_valid(str(spec.color))
	var color := Color(str(spec.color)) if has_color else Color(0.62, 0.56, 0.5, 0.75)
	emitted += 1
	match str(spec.get("fx", "dust")):
		"dust":
			if has_color:
				Fx.dust(at, dir, count, color)
			else:
				Fx.dust(at, dir, count)
		"puff":
			Fx.puff(at, size if size > 0.0 else 0.7, color if has_color else Color.WHITE)
		"sparkle":
			Fx.sparkle(at, color if has_color else Color(1, 0.9, 0.6), count, size if size > 0.0 else 12.0)
		"ash":
			Fx.ash(at, color if has_color else Color(0.8, 0.75, 0.7), count, float(spec.get("rise", 40.0)), size if size > 0.0 else 10.0)
		"debris":
			Fx.debris(at, color if has_color else Color(0.6, 0.45, 0.3), count)
		"ring":
			Fx.ring(at, size if size > 0.0 else 24.0, color if has_color else Color(1, 0.9, 0.7))
		"flash":
			Fx.flash(at, color if has_color else Color(1, 0.9, 0.7), size if size > 0.0 else 40.0, 0.2)
