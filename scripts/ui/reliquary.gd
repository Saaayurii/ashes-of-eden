extends Control
class_name Reliquary
## The reliquary, from the main menu: every relic (Relics.all), what it does,
## what it costs, the Ash in hand, and a button to buy what can be bought.
## Built in code, like the chapter map; the relics themselves are data.

signal closed

const GOLD := Color(0.95, 0.83, 0.5)
const DIM := Color(0.55, 0.53, 0.58)

var _ash: Label
var _list: VBoxContainer
var _back: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.04, 0.97)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 90
	panel.offset_right = -90
	panel.offset_top = 22
	panel.offset_bottom = -18
	panel.add_theme_constant_override("separation", 6)
	add_child(panel)
	var title := Label.new()
	title.text = "RELIQUARY_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_font_size_override("font_size", 16)
	panel.add_child(title)
	_ash = Label.new()
	_ash.name = "Ash"
	_ash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ash.add_theme_color_override("font_color", DIM)
	panel.add_child(_ash)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	_back = Button.new()
	_back.text = "MENU_BACK"
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back.pressed.connect(close)
	panel.add_child(_back)


func open() -> void:
	_fill()
	visible = true
	var first := _list.find_child("Buy*", true, false) as Button
	(first if first != null and not first.disabled else _back).grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _fill() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_ash.text = tr("RELIQUARY_ASH") % int(Profile.data.get("ash", 0))
	for relic in Relics.all():
		var row := HBoxContainer.new()
		row.name = "Row_" + str(relic.id)
		row.add_theme_constant_override("separation", 10)
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name := Label.new()
		var owned := Relics.owned(relic.id)
		name.text = tr(str(relic.name)) + ("  ◆" if owned else "")
		name.add_theme_color_override("font_color", GOLD if owned else Color(0.9, 0.86, 0.8))
		words.add_child(name)
		var what := Label.new()
		what.text = tr(str(relic.description)) % tr(str(relic.name)) if relic.has("early") else tr(str(relic.description))
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		what.add_theme_font_size_override("font_size", 9)
		what.add_theme_color_override("font_color", DIM)
		words.add_child(what)
		row.add_child(words)
		var buy := Button.new()
		buy.name = "Buy_" + str(relic.id)
		buy.custom_minimum_size = Vector2(92, 0)
		buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if owned:
			buy.text = tr("RELIQUARY_OWNED")
			buy.disabled = true
		elif relic.has("needs") and not Relics.owned(str(relic.needs)):
			buy.text = tr("RELIQUARY_NEEDS") % tr(str(Relics.spec(str(relic.needs)).get("name", "")))
			buy.disabled = true
		else:
			buy.text = tr("RELIQUARY_COST") % int(relic.cost)
			buy.disabled = not Relics.can_buy(relic.id)
		buy.pressed.connect(_buy.bind(str(relic.id)))
		row.add_child(buy)
		_list.add_child(row)


func _buy(id: String) -> void:
	if Relics.buy(id):
		Audio.play(&"bell", -8.0)
		_fill()
		var next := _list.find_child("Buy_" + id, true, false) as Button
		if next != null:
			next.grab_focus()
