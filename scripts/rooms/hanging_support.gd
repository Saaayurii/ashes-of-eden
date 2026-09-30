extends Node2D
## Rusted chain hangers for the two return ledges in the lava crypt. Their
## anchors continue into painted masonry above, so the footholds do not read
## as arbitrary blocks over the chasm.

@export var walk_width := 80.0
@export var left_length := 180.0
@export var right_length := 180.0


func _draw() -> void:
	_draw_chain(12.0, left_length)
	_draw_chain(walk_width - 12.0, right_length)
	var iron := Color("#302929")
	var glint := Color("#675449")
	draw_rect(Rect2(5, 7, walk_width - 10.0, 3), iron)
	for x in [12.0, walk_width - 12.0]:
		draw_rect(Rect2(x - 3.0, 4, 7, 3), iron)
		draw_rect(Rect2(x - 1.0, 4, 2, 1), glint)


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
