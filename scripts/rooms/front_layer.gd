extends Node2D
class_name FrontLayer
## The plane in front of the hero (docs/DEPTH.md, tools/rooms/front.py).
##
## Each child is a piece cut from the painting, darkened and softened, standing
## where it was placed when the camera looks straight at it. Nearer than the
## stone, it slides faster: at depth d its centre lies at
## rest + (rest − camera) · (d − 1), the rule a Parallax2D layer follows, without one
## layer per piece. A body behind a piece sees through it (FADED), so the plane
## never hides a blow; it takes no light, because it stands between the lamps
## and the eye. Settings → Moving backdrops off holds every piece still.

## How much of a piece is left while a body is behind it.
const FADED := 0.32
## How fast it fades out and back, per second.
const FADE_SPEED := 5.0
## A body's middle, above its feet.
const BODY_LIFT := 20.0
## The part of a piece's box that counts as covering.
const INNER := Vector2(0.8, 0.85)

## One per child, in order: how much faster than the camera it moves.
@export var depths := PackedFloat32Array()

var _rest: Array[Vector2] = []


func _ready() -> void:
	for child in get_children():
		_rest.append((child as Node2D).position)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	var focus := camera.get_screen_center_position() - global_position
	var moving := Settings.backdrop_motion
	var bodies: Array[Vector2] = []
	for player in get_tree().get_nodes_in_group("player"):
		bodies.append((player as Node2D).global_position - global_position - Vector2(0.0, BODY_LIFT))
	for i in _rest.size():
		var piece := get_child(i) as Sprite2D
		if piece == null:
			continue
		piece.position = at(_rest[i], focus, depths[i] if moving and i < depths.size() else 1.0)
		var behind := false
		if piece.texture != null:
			# the soft rim and the empty corners of the box hide nothing
			var size := piece.texture.get_size() * INNER
			var box := Rect2(piece.position - size * 0.5, size)
			for body in bodies:
				if box.has_point(body):
					behind = true
		piece.modulate.a = move_toward(piece.modulate.a, FADED if behind else 1.0, FADE_SPEED * delta)


## Where a piece at rest point `rest` and depth `depth` stands while the camera
## looks at `focus`.
static func at(rest: Vector2, focus: Vector2, depth: float) -> Vector2:
	return rest + (rest - focus) * (depth - 1.0)

