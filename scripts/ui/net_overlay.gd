extends CanvasLayer
## How the link to the other player is doing, over whatever scene is up
## (an autoload, so it outlives a match that ends because the wire did):
##   - three bars and the round trip in ms, top centre, while a session is on;
##   - "Connection unstable — waiting for …" once the other side has been
##     silent for Net.LINK_STALL, counting up until it answers or times out;
##   - "<name> left the game" when a guest walks out of a host's match;
##   - "Connection lost" and why, over the menu the match fell back to.
## Reads Net, never touches the peer. docs/RELAY.md.

const GOOD_MS := 100
const FAIR_MS := 200
const GOOD := Color(0.62, 0.86, 0.55)
const FAIR := Color(0.95, 0.78, 0.38)
const POOR := Color(0.92, 0.42, 0.36)
const DEAD := Color(0.55, 0.52, 0.56)
const INK := Color(0.04, 0.03, 0.05, 0.86)
const TOAST_TIME := 4.0

var link: Control
var link_label: Label
var banner: Label
var toast: Label
var lost_panel: PanelContainer
var lost_reason: Label
var _bars := 0
var _colour := DEAD
var _toast_left := 0.0
var rejoin_button: Button
## A Rejoin is under way: its failure comes back as the lost panel, not silence.
var _rejoining := false


func _ready() -> void:
	layer = 150  # over HUD and menus, under the Curtain's 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	Net.connection_lost.connect(_on_lost)
	Net.partner_left.connect(_on_partner_left)
	Net.failed.connect(_on_rejoin_failed)
	Net.match_started.connect(func(_mode: int) -> void: _rejoining = false)


func _build() -> void:
	link = Control.new()
	link.name = "Link"
	link.mouse_filter = Control.MOUSE_FILTER_IGNORE
	link.custom_minimum_size = Vector2(64, 12)
	link.set_anchors_preset(Control.PRESET_CENTER_TOP)
	link.position = Vector2(-32, 2)
	link.size = Vector2(64, 12)
	link.draw.connect(_draw_bars)
	add_child(link)
	link_label = Label.new()
	link_label.position = Vector2(18, -3)
	link_label.add_theme_font_size_override("font_size", 8)
	link_label.add_theme_color_override("font_outline_color", Color.BLACK)
	link_label.add_theme_constant_override("outline_size", 3)
	link.add_child(link_label)

	banner = _plate("Unstable")
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.position.y = 18
	toast = _plate("Toast")
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.position.y = 40

	lost_panel = PanelContainer.new()
	lost_panel.name = "Lost"
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.border_color = POOR
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	lost_panel.add_theme_stylebox_override("panel", style)
	lost_panel.set_anchors_preset(Control.PRESET_CENTER)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	lost_panel.add_child(column)
	var title := Label.new()
	title.text = "NET_LOST_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", POOR)
	column.add_child(title)
	lost_reason = Label.new()
	lost_reason.name = "Reason"
	lost_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lost_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lost_reason.custom_minimum_size = Vector2(240, 0)
	column.add_child(lost_reason)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	rejoin_button = Button.new()
	rejoin_button.name = "Rejoin"
	rejoin_button.text = "NET_REJOIN"
	rejoin_button.pressed.connect(_on_rejoin)
	buttons.add_child(rejoin_button)
	var ok := Button.new()
	ok.name = "Ok"
	ok.text = "NET_LOST_OK"
	ok.pressed.connect(func() -> void: lost_panel.visible = false)
	buttons.add_child(ok)
	lost_panel.visible = false
	add_child(lost_panel)


func _plate(node_name: String) -> Label:
	var plate := Label.new()
	plate.name = node_name
	plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.set_content_margin_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	plate.add_theme_stylebox_override("normal", style)
	plate.add_theme_font_size_override("font_size", 9)
	plate.visible = false
	add_child(plate)
	return plate


func _process(delta: float) -> void:
	var on := Net.active and not Net.dedicated and Net.player_count() > 1
	link.visible = on
	if on:
		var ms := Net.link_ms()
		var silent := Net.link_silence()
		var bars := 0
		var colour := DEAD
		if silent > Net.LINK_STALL or ms < 0:
			bars = 0
		elif ms < GOOD_MS:
			bars = 3
			colour = GOOD
		elif ms < FAIR_MS:
			bars = 2
			colour = FAIR
		else:
			bars = 1
			colour = POOR
		link_label.text = tr("NET_LINK_MS") % ms if ms >= 0 and bars > 0 else "…"
		link_label.add_theme_color_override("font_color", colour)
		if bars != _bars or colour != _colour:
			_bars = bars
			_colour = colour
			link.queue_redraw()
		banner.visible = silent > Net.LINK_STALL
		if banner.visible:
			banner.text = tr("NET_UNSTABLE") % [Net.quiet_name(), int(silent)]
			_centre(banner)
	else:
		banner.visible = false
	if _toast_left > 0.0:
		_toast_left -= delta
		toast.visible = _toast_left > 0.0
	_scale()


func _draw_bars() -> void:
	for i in 3:
		var height := 4.0 + i * 3.0
		var rect := Rect2(Vector2(i * 4.0, 11.0 - height), Vector2(3.0, height))
		link.draw_rect(rect, _colour if i < _bars else Color(_colour, 0.25))


## Text follows the reader's size setting (Settings.text_scale).
func _scale() -> void:
	var scale := Settings.text_scale() if Settings.has_method("text_scale") else 1.0
	for plate in [banner, toast]:
		plate.add_theme_font_size_override("font_size", int(round(9 * scale)))
	lost_reason.add_theme_font_size_override("font_size", int(round(10 * scale)))


func _centre(plate: Control) -> void:
	plate.reset_size()
	plate.position.x = (plate.get_parent_area_size().x - plate.size.x) / 2.0


func _on_partner_left(peer_name: String) -> void:
	toast.text = tr("NET_PARTNER_LEFT") % peer_name
	toast.visible = true
	_centre(toast)
	_toast_left = TOAST_TIME


## The match is over because the wire is. The run or the duel takes us back to
## the menu (Net.closed); this says why, instead of the menu appearing without
## a word.
func _on_lost(reason_key: String) -> void:
	banner.visible = false
	lost_reason.text = tr(reason_key)
	lost_panel.visible = true
	lost_panel.reset_size()
	lost_panel.position = (lost_panel.get_parent_area_size() - lost_panel.size) / 2.0
	rejoin_button.visible = Net.can_rejoin()
	var first: Button = rejoin_button if rejoin_button.visible else lost_panel.get_node("Column/Buttons/Ok")
	first.grab_focus.call_deferred()


## Back into the night the wire dropped us out of (Net.rejoin): the host takes
## us in late and our body comes back as it was (Run._admit_late).
func _on_rejoin() -> void:
	lost_panel.visible = false
	_rejoining = true
	toast.text = tr("NET_REJOINING")
	toast.visible = true
	_centre(toast)
	_toast_left = Net.CONNECT_TIMEOUT
	if Net.rejoin() != OK:
		_on_rejoin_failed(Net.last_error)


func _on_rejoin_failed(reason_key: String) -> void:
	if not _rejoining:
		return
	_rejoining = false
	_toast_left = 0.0
	Net.rejoin_offered = true  # the way back stays open for another try
	_on_lost(reason_key)
