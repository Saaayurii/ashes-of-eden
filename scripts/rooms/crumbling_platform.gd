extends StaticBody2D
## A visible, one-way foothold over an open painted gap. The boards warn before
## giving way and grow back so a missed jump never makes a route one-way.

const STONE := preload("res://assets/decor/platforms/float_2.png")

@export var walk_width := 72.0
@export_enum("stone", "timber") var surface_kind := "stone"
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
	var warning := _remaining >= 0.0
	if surface_kind == "timber":
		_draw_timber(warning)
	else:
		_draw_stone(warning)
	if warning:
		var edge := Color(1.0, 0.64, 0.32, 0.9)
		var progress := 1.0 - maxf(_remaining, 0.0) / maxf(break_delay, 0.01)
		for x in range(16, int(walk_width), 25):
			draw_line(Vector2(x, 1), Vector2(x + progress * 5.0, 5), edge, 1.0)


func _draw_stone(warning: bool) -> void:
	# The graveyard bridge uses the same mossed stone as nearby cornices.
	var source_width := STONE.get_width()
	for x in range(0, int(ceilf(walk_width)), source_width):
		var piece_width := minf(float(source_width), walk_width - x)
		draw_texture_rect_region(STONE, Rect2(x, 0, piece_width, STONE.get_height()),
			Rect2(0, 0, piece_width, STONE.get_height()), Color(1.0, 0.82, 0.7) if warning else Color.WHITE)


func _draw_timber(warning: bool) -> void:
	# The swamp has broken piers, not floating cemetery masonry. Short uneven
	# boards and their braces give these footholds the same silhouette as the
	# piers painted behind them; cracks brighten before they fall away.
	var length := int(ceilf(walk_width))
	var shadow := Color("#1b1b20")
	var wood := Color("#403936") if not warning else Color("#755343")
	var lip := Color("#665b50") if not warning else Color("#b28561")
	draw_rect(Rect2(5, 5, length - 10, 5), shadow)
	for x in range(0, length, 12):
		var width := mini(11, length - x)
		var top := 1 if int(x / 12) % 3 == 1 else 0
		draw_rect(Rect2(x, top, width, 6), wood)
		draw_rect(Rect2(x + 1, top, maxi(width - 2, 1), 1), lip)
		if width >= 6:
			draw_rect(Rect2(x + 3, top + 3, 1, 1), shadow)
			draw_rect(Rect2(x + width - 3, top + 3, 1, 1), shadow)
	for x in [8, length - 11]:
		draw_rect(Rect2(x, 10, 4, 12), shadow)
		draw_rect(Rect2(x + 1, 10, 2, 9), wood)
