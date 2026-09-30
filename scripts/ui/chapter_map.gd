extends Control
class_name ChapterMap
## The chapter's way through the night, drawn from the pause menu (Dead Cells'
## map, cut to what this game is: one route with forks, not a world). A column
## per room along the way (Route.step), a fork's two ways stacked in one
## column, the places named under their rooms (data/chapters), rest points
## marked. It shows what the player could know: the way walked tonight
## (Game.walked), where they stand, the rooms ahead as far as any night has
## reached (Profile.data.best_wave) — beyond that the places are unnamed.

signal closed

const GOLD := Color(0.95, 0.83, 0.5)
const PALE := Color(0.85, 0.8, 0.7)
const DIM := Color(0.45, 0.43, 0.48)
const REST := Color(0.72, 0.95, 0.8)
const INK := Color(0.04, 0.03, 0.05, 0.92)
const LEFT := 44.0
const RIGHT := 44.0
const MIDDLE := 176.0
const FORK_SPREAD := 26.0
const RADIUS := 5.0

var _nodes: Array = []
var _clock := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # opened from the pause menu
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open() -> void:
	_nodes = layout(Route.rooms(), Game.walked, _here(), int(Profile.data.get("best_wave", 0)))
	visible = true
	queue_redraw()


func close() -> void:
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") \
			or event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed):
		get_viewport().set_input_as_handled()
		close()


func _process(delta: float) -> void:
	if visible:
		_clock += delta
		queue_redraw()  # the ring round "here" breathes


## The room the local run is in, "" outside a night.
func _here() -> String:
	var run := get_tree().current_scene
	if run == null or not ("room_index" in run) or int(run.room_index) < 0:
		return ""
	return str(Route.rooms()[int(run.room_index)])


## Where each room of [param rooms] goes on the map and what it is to the
## player: "here", "walked", "ahead", "passed" (a fork's way not taken) or
## "unknown" (past the furthest any night has reached). Static on its inputs
## so a test can read the map without drawing it.
static func layout(rooms: Array, walked: Array, here: String, best_wave: int) -> Array:
	var out := []
	var here_step := Route.step(rooms, rooms.find(here)) if here != "" else -1
	for index in rooms.size():
		var path := str(rooms[index])
		var step := Route.step(rooms, index)
		var fork := Route.fork_holding(path)
		var row := 0.0
		var passed := false
		if not fork.is_empty():
			var ways: Array = (fork.options as Dictionary).values()
			row = -1.0 if ways.find(path) == 0 else 1.0
			# the other way was walked, or we are past the fork on the other side
			var taken := ways.filter(func(way) -> bool: return walked.has(str(way)) or str(way) == here)
			passed = not taken.is_empty() and not taken.has(path)
		var state := "ahead"
		if path == here:
			state = "here"
		elif passed:
			state = "passed"
		elif walked.has(path):
			state = "walked"
		elif step >= maxi(best_wave, here_step + 2):  # the next room is always in sight
			state = "unknown"
		out.append({
			"path": path, "step": step, "row": row, "state": state,
			"place": str(Data.chapter_for(path).get("id", "")),
			"rest": Data.rest_points.has(path.get_file().get_basename()),
		})
	return out


func _point(node: Dictionary, steps: int) -> Vector2:
	var width := size.x - LEFT - RIGHT
	var x := LEFT + width * (float(node.step) / maxf(1.0, steps - 1.0))
	return Vector2(x, MIDDLE + float(node.row) * FORK_SPREAD)


func _draw() -> void:
	if _nodes.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), INK)
	var font := get_theme_default_font()
	var steps := 0
	for node in _nodes:
		steps = maxi(steps, int(node.step) + 1)
	_centered(font, tr("MAP_TITLE"), Vector2(size.x / 2.0, 58.0), 14, GOLD)

	# the way: each column joined to every room of the next
	for a in _nodes:
		for b in _nodes:
			if int(b.step) == int(a.step) + 1:
				var dim: bool = a.state in ["unknown", "passed"] or b.state in ["unknown", "passed"]
				var lit: bool = a.state in ["walked", "here"] and b.state in ["walked", "here"]
				draw_line(_point(a, steps), _point(b, steps), GOLD if lit else (DIM if dim else PALE * Color(1, 1, 1, 0.6)), 2.0 if lit else 1.0)

	# the places, under their rooms, alternately low and lower so short ones do not collide
	var places := []
	for node in _nodes:
		if not places.has(node.place):
			places.append(node.place)
	for i in places.size():
		var mine := _nodes.filter(func(n: Dictionary) -> bool: return n.place == places[i])
		var x := 0.0
		var known := false
		for node in mine:
			x += _point(node, steps).x
			known = known or node.state != "unknown"
		x /= mine.size()
		var title := tr(str(Data.chapters.get(places[i], {}).get("title", ""))) if known else "???"
		_centered(font, title, Vector2(x, MIDDLE + 56.0 + 14.0 * (i % 2)), 8, PALE if known else DIM)

	for node in _nodes:
		var at := _point(node, steps)
		match str(node.state):
			"here":
				draw_circle(at, RADIUS + 1.0, GOLD)
				draw_arc(at, RADIUS + 5.0 + 1.5 * sin(_clock * 3.0), 0.0, TAU, 24, GOLD, 1.0)
				# above the rest mark when there is one, never on it
				_centered(font, tr("MAP_HERE"), at + Vector2(0, (-24.0 if node.rest else -16.0)), 8, GOLD)
			"walked":
				draw_circle(at, RADIUS, PALE)
			"ahead":
				draw_arc(at, RADIUS, 0.0, TAU, 20, PALE, 1.5)
			"passed":
				draw_arc(at, RADIUS - 1.0, 0.0, TAU, 16, DIM, 1.0)
				draw_line(at + Vector2(-3, -3), at + Vector2(3, 3), DIM, 1.0)
			_:
				draw_circle(at, 1.5, DIM)
		if node.rest and node.state != "unknown":
			var mark := at + Vector2(0, -RADIUS - 7.0)
			draw_line(mark + Vector2(0, -3), mark + Vector2(0, 3), REST, 1.5)
			draw_line(mark + Vector2(-3, 0), mark + Vector2(3, 0), REST, 1.5)

	_centered(font, tr("MAP_LEGEND"), Vector2(size.x / 2.0, size.y - 34.0), 8, DIM)


func _centered(font: Font, text: String, at: Vector2, font_size: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, at - Vector2(width / 2.0, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
