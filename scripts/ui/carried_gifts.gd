extends Control
class_name CarriedGifts
## Pause → Gifts: what our own body carries tonight, in its own words — every
## gift taken (icon, name, path, description), every resonance woken, every
## item found. A night is long and the cards were read once; this is where
## they are read again. Built in code like the chapter map beside it.

signal closed

const INK := Color(0.04, 0.03, 0.05, 0.92)
const DIM := Color(0.6, 0.57, 0.62)
const GOLD := Color(0.95, 0.83, 0.5)
const RESONANCE := Color(0.8, 0.75, 1.0)

var list: VBoxContainer
var _back: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # opened from the pause menu
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = INK
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	center.add_child(column)
	var title := Label.new()
	title.text = "CARRIED_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", GOLD)
	column.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 230)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	list = VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	_back = Button.new()
	_back.text = "MENU_BACK"
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back.pressed.connect(close)
	column.add_child(_back)


## Everything carried, in the order it came: gifts, then resonances, then
## items. Each {kind, name, description, icon (a path or ""), color}.
static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for ability in Game.abilities:
		var path := str(ability.get("path", "will"))
		result.append({"kind": "gift", "name": str(ability.get("name", "")),
			"description": str(ability.get("description", "")),
			"icon": str(ability.get("icon", "")), "color": AbilityPicker.PATH_COLORS.get(path, Color.WHITE),
			"path": path})
	for id in Game.resonances:
		var spec: Dictionary = Resonances.spec(id)
		result.append({"kind": "resonance", "name": str(spec.get("name", id)),
			"description": str(spec.get("description", "")), "icon": "", "color": RESONANCE})
	for id in Game.items:
		var item: Dictionary = Data.items.get(id, {})
		if item.is_empty():
			continue
		result.append({"kind": "item", "name": str(item.get("name", id)),
			"description": str(item.get("description", "")), "icon": str(item.get("icon", "")), "color": GOLD})
	return result


func open() -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var all := entries()
	if all.is_empty():
		var none := Label.new()
		none.text = "CARRIED_NONE"
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.add_theme_color_override("font_color", DIM)
		list.add_child(none)
	for entry in all:
		list.add_child(_row(entry))
	# what one more gift would wake (Resonances.near): a reason for the next pick
	var close := Resonances.near(Game.abilities)
	if not close.is_empty():
		var heading := Label.new()
		heading.text = "CARRIED_NEAR"
		heading.add_theme_font_size_override("font_size", 11)
		heading.add_theme_color_override("font_color", GOLD)
		list.add_child(heading)
	for item in close:
		var missing := tr("PATH_" + str(item.path).to_upper()) if item.has("path") \
			else tr(str(Data.abilities[item.gift].get("name", item.gift)))
		list.add_child(_row({"kind": "near", "name": "", "icon": "", "color": DIM,
			"title": "◇ %s" % tr(str(Resonances.spec(item.id).get("name", item.id))),
			"description": tr("CARRIED_NEAR_NEEDS") % missing}))
	visible = true
	_back.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var icon_path: String = entry.icon
	if icon_path != "" and ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	elif entry.kind == "gift":
		icon.texture = AbilityPicker.PATH_ICONS.get(entry.get("path", "will"))
	row.add_child(icon)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	var name_label := Label.new()
	name_label.text = str(entry.get("title", ("◆ " if entry.kind == "resonance" else "") + tr(entry.name)))
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", entry.color)
	words.add_child(name_label)
	var text := Label.new()
	text.text = tr(entry.description)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 9)
	text.add_theme_color_override("font_color", DIM)
	words.add_child(text)
	row.add_child(words)
	return row


func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		close()
