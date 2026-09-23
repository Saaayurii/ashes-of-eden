extends Control
## Host or join a session for two (docs/MULTIPLAYER.md). Everything here is a
## thin face on the [Net] autoload: this screen never touches the peer itself.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

@onready var player_name: LineEdit = %PlayerName
@onready var mode: OptionButton = %Mode
@onready var address: LineEdit = %Address
@onready var port: LineEdit = %Port
@onready var host_button: Button = %Host
@onready var join_button: Button = %Join
@onready var setup_panel: Control = %Setup
@onready var lobby_panel: Control = %Lobby
@onready var roster: Label = %Roster
@onready var ready_button: CheckButton = %Ready
@onready var start_button: Button = %Start
@onready var leave_button: Button = %Leave
@onready var status: Label = %Status
@onready var back_button: Button = %Back


func _ready() -> void:
	Net.leave()  # coming back from a match: never keep a stale peer around
	player_name.text = Net.local_name
	mode.add_item(tr("MP_MODE_COOP"), Net.Mode.COOP)
	mode.add_item(tr("MP_MODE_PVP"), Net.Mode.PVP)
	mode.select(0)
	port.text = str(Net.DEFAULT_PORT)
	host_button.pressed.connect(_on_host)
	join_button.pressed.connect(_on_join)
	ready_button.toggled.connect(Net.set_ready)
	start_button.pressed.connect(Net.request_start)
	leave_button.pressed.connect(_on_leave)
	back_button.pressed.connect(_on_back)
	Net.lobby_changed.connect(_refresh)
	Net.failed.connect(_on_failed)
	Net.closed.connect(_on_failed)
	_refresh()
	host_button.grab_focus()


func _on_host() -> void:
	Net.local_name = player_name.text.strip_edges()
	if Net.host(mode.get_selected_id() as Net.Mode, _port()) == OK:
		status.text = tr("MP_STATUS_HOSTING") % _own_addresses()
		_refresh()


func _on_join() -> void:
	Net.local_name = player_name.text.strip_edges()
	if address.text.strip_edges().is_empty():
		status.text = "NET_ERR_ADDRESS"
		return
	if Net.join(address.text, _port()) == OK:
		status.text = "MP_STATUS_CONNECTING"
		_refresh()


func _on_leave() -> void:
	Net.leave()
	status.text = ""
	_refresh()


func _on_back() -> void:
	Curtain.change_scene(MENU_SCENE, false, Net.leave)


func _on_failed(reason_key: String) -> void:
	status.text = reason_key
	ready_button.set_pressed_no_signal(false)
	_refresh()


func _port() -> int:
	var value := int(port.text)
	return value if value > 0 and value < 65536 else Net.DEFAULT_PORT


func _refresh() -> void:
	setup_panel.visible = not Net.active
	lobby_panel.visible = Net.active
	if not Net.active:
		return
	mode.select(int(Net.mode))
	var lines: PackedStringArray = []
	for id in Net.peer_ids():
		var mark := "●" if Net.peers[id].ready else "○"
		var who: String = Net.name_of(id)
		if id == Net.my_id():
			who += " (%s)" % tr("MP_YOU")
		lines.append("%s  %s" % [mark, who])
	while lines.size() < Net.MAX_PLAYERS:
		lines.append("○  %s" % tr("MP_EMPTY_SEAT"))
	roster.text = "\n".join(lines)
	start_button.visible = Net.hosting
	start_button.disabled = not Net.everyone_ready()
	if not Net.hosting and status.text == "MP_STATUS_CONNECTING":
		status.text = "MP_STATUS_LOBBY"


## The addresses a friend on the same network can type into "Join".
func _own_addresses() -> String:
	var found: PackedStringArray = []
	for ip in IP.get_local_addresses():
		if ip.contains(":") or ip.begins_with("127.") or ip.begins_with("169.254."):
			continue
		found.append(ip)
	return ", ".join(found) if not found.is_empty() else "localhost"
