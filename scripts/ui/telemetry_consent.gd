extends Control
class_name TelemetryConsent
## The one question about telemetry (scripts/autoload/telemetry.gd), over the
## main menu on the first launch of a build that has a server to send to:
## what is sent, what is not, yes or no. Either answer is kept
## (Settings.telemetry_asked) and the switch stays in Settings; Escape is a
## no. Focus starts on "No": saying yes takes a deliberate press.

signal closed

const GOLD := Color(0.95, 0.83, 0.5)

var _yes: Button
var _no: Button


## Whether the menu should show it now.
static func wanted() -> bool:
	return Telemetry.can_ask() and not Settings.telemetry_asked


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.04, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(380, 0)
	column.add_theme_constant_override("separation", 8)
	center.add_child(column)
	var title := Label.new()
	title.text = "TELEMETRY_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_font_size_override("font_size", 16)
	column.add_child(title)
	var body := Label.new()
	body.name = "Body"
	body.text = "TELEMETRY_BODY"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(380, 0)
	body.add_theme_font_size_override("font_size", roundi(10 * Settings.text_scale()))
	column.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	_yes = Button.new()
	_yes.name = "Yes"
	_yes.text = "TELEMETRY_YES"
	_yes.pressed.connect(answer.bind(true))
	row.add_child(_yes)
	_no = Button.new()
	_no.name = "No"
	_no.text = "TELEMETRY_NO"
	_no.pressed.connect(answer.bind(false))
	row.add_child(_no)


func open() -> void:
	visible = true
	_no.grab_focus()


func answer(yes: bool) -> void:
	Settings.set_telemetry(yes)
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		answer(false)
