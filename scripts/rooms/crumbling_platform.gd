extends StaticBody2D
## A visible, one-way foothold over an open painted gap. The boards warn before
## giving way and grow back so a missed jump never makes a route one-way.

const STONE := preload("res://assets/decor/platforms/float_2.png")

@export var walk_width := 72.0
@export var break_delay := 0.9
@export var rebuild_delay := 3.5

var _remaining := -1.0
var _rebuild := -1.0
var _shape: CollisionShape2D
var _sensor: Area2D


func _ready() -> void:
	collision_layer = 16
	collision_mask = 0
	_shape = CollisionShape2D.new()
	var plank := RectangleShape2D.new()
	plank.size = Vector2(walk_width, 8.0)
	_shape.shape = plank
	_shape.position = Vector2(walk_width * 0.5, 4.0)
	_shape.one_way_collision = true
	add_child(_shape)
	_sensor = Area2D.new()
	_sensor.collision_layer = 0
	_sensor.collision_mask = 2
	add_child(_sensor)
	var reach := CollisionShape2D.new()
	var reach_shape := RectangleShape2D.new()
	reach_shape.size = Vector2(walk_width, 22.0)
	reach.shape = reach_shape
	reach.position = Vector2(walk_width * 0.5, -12.0)
	_sensor.add_child(reach)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _rebuild >= 0.0:
		_rebuild -= delta
		if _rebuild < 0.0:
			_shape.set_deferred("disabled", false)
			queue_redraw()
		return
	if _remaining < 0.0:
		for body in _sensor.get_overlapping_bodies():
			if body.is_in_group("player") and body.is_on_floor() \
					and absf(to_local(body.global_position).y + 15.0) < 7.0:
				_remaining = break_delay
				queue_redraw()
				break
	else:
		_remaining -= delta
		queue_redraw()
		if _remaining <= 0.0:
			_remaining = -1.0
			_rebuild = rebuild_delay
			_shape.set_deferred("disabled", true)
			queue_redraw()


func _draw() -> void:
	if _rebuild >= 0.0:
		return
	# Reuse the room's pixel-painted broken masonry. A flat debug-coloured bar
	# reads as a UI overlay, not a piece of the cemetery bridge.
	var warning := _remaining >= 0.0
	var source_width := STONE.get_width()
	for x in range(0, int(ceilf(walk_width)), source_width):
		var piece_width := minf(float(source_width), walk_width - x)
		draw_texture_rect_region(STONE, Rect2(x, 0, piece_width, STONE.get_height()),
			Rect2(0, 0, piece_width, STONE.get_height()), Color(1.0, 0.82, 0.7) if warning else Color.WHITE)
	if warning:
		var edge := Color(1.0, 0.64, 0.32, 0.9)
		var progress := 1.0 - maxf(_remaining, 0.0) / maxf(break_delay, 0.01)
		for x in range(16, int(walk_width), 25):
			draw_line(Vector2(x, 1), Vector2(x + progress * 5.0, 5), edge, 1.0)
