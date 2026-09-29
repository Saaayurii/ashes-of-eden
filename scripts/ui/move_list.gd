extends PanelContainer
class_name MoveList
## The practice yard's list of moves (docs/TECHNIQUES.md, data/techniques):
## each one's name and keys, dim until it is done once, then gold with a
## tick, and its name over the hero's head every time it comes off. Only in
## the yard: a night does not stop to grade the player.

const DIM := Color(0.62, 0.6, 0.66)
const DONE := Color(0.98, 0.85, 0.5)

var _rows := {}  # technique id -> Label
var _done := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.07, 0.72)
	style.border_color = Color(0.55, 0.45, 0.3, 0.8)
	style.set_border_width_all(1)
	style.set_content_margin_all(5)
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	add_child(column)
	var foe := str(Data.enemies.get(Game.practice, {}).get("name", Game.practice))
	var header := Label.new()
	header.text = tr("PRACTICE_HUD") % tr(foe)
	header.add_theme_color_override("font_color", DIM)
	header.add_theme_font_size_override("font_size", 8)
	column.add_child(header)
	var title := Label.new()
	title.text = tr("TECH_TITLE")
	title.add_theme_color_override("font_color", DONE)
	title.add_theme_font_size_override("font_size", 10)
	column.add_child(title)
	var ids: Array = Data.techniques.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return int(Data.techniques[a].get("order", 99)) < int(Data.techniques[b].get("order", 99)))
	for id in ids:
		var spec: Dictionary = Data.techniques[id]
		var row := Label.new()
		row.name = id
		row.add_theme_font_size_override("font_size", 8)
		row.add_theme_color_override("font_color", DIM)
		column.add_child(row)
		_rows[id] = row
		_write(id)
	EventBus.technique_performed.connect(_on_performed)
	# top right, under nothing: the HUD keeps the top left
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 6)


func _write(id: String) -> void:
	var spec: Dictionary = Data.techniques[id]
	var mark := "✓ " if _done.has(id) else "· "
	var fresh := "  ★" if spec.get("new", false) and not _done.has(id) else ""
	_rows[id].text = "%s%s — %s%s" % [mark, tr(str(spec.name)), tr(str(spec.input)), fresh]


func is_done(id: String) -> bool:
	return _done.has(id)


func _on_performed(id: String) -> void:
	if not _rows.has(id):
		return
	for node in get_tree().get_nodes_in_group("player"):
		if node.is_multiplayer_authority():
			Fx.popup(node.global_position + Vector2(0, -46), tr(str(Data.techniques[id].name)), DONE, 9)
	if _done.has(id):
		return
	_done[id] = true
	_write(id)
	var row: Label = _rows[id]
	row.add_theme_color_override("font_color", DONE)
	row.modulate = Color(1.6, 1.4, 1.0)
	create_tween().tween_property(row, "modulate", Color.WHITE, 0.5)
