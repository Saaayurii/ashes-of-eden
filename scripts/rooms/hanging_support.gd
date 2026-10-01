extends Node2D
## Structural hangers for small return ledges. Chains continue into masonry;
## timber braces continue into the painted swamp dock above their tread.

@export var walk_width := 80.0
@export var left_length := 180.0
@export var right_length := 180.0
@export var timber := false


func _draw() -> void:
	if timber:
		_draw_timber()
		return
	_draw_chain(12.0, left_length)
	_draw_chain(walk_width - 12.0, right_length)
	var iron := Color("#302929")
	var glint := Color("#675449")
	draw_rect(Rect2(5, 7, walk_width - 10.0, 3), iron)
	for x in [12.0, walk_width - 12.0]:
		draw_rect(Rect2(x - 3.0, 4, 7, 3), iron)
		draw_rect(Rect2(x - 1.0, 4, 2, 1), glint)


func _draw_timber() -> void:
	# A braced lower tread belongs to the wooden dock above it, rather than
	# reading as a second, unsupported island over the swamp water.
	var dark := Color("#1d2020")
	var wood := Color("#302f2b")
	var edge := Color("#48443b")
	var left := 9.0
	var right := walk_width - 9.0
	draw_line(Vector2(left, -left_length + 12), Vector2(right, -5), dark, 3.0, false)
	for beam in [[left, left_length], [right, right_length]]:
		var x: float = beam[0]
		var length: float = beam[1]
		draw_rect(Rect2(x - 3, -length, 7, length + 9), dark)
		draw_rect(Rect2(x - 1, -length + 3, 2, length - 2), wood)
		for y in range(-int(length) + 8, 0, 13):
			draw_rect(Rect2(x + 1, y, 2, 2), edge)
	draw_rect(Rect2(4, 8, walk_width - 8, 3), dark)


func _draw_chain(x: float, length: float) -> void:
	var dark := Color("#272426")
	var edge := Color("#69574e")
	var top := -int(length)
	for y in range(top, 0, 8):
		# Off-centre paired links avoid a single straight UI-looking line.
		var sway := -1 if int(y / 8) % 2 == 0 else 1
		draw_rect(Rect2(x + sway - 1, y, 4, 6), dark)
		draw_rect(Rect2(x + sway, y + 1, 1, 4), edge)
		draw_rect(Rect2(x - sway - 1, y + 4, 4, 4), dark)
		draw_rect(Rect2(x - sway, y + 5, 1, 2), edge)
