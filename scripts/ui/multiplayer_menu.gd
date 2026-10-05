extends Control
## Host or join a session for two (docs/MULTIPLAYER.md, docs/RELAY.md).
## Everything here is a thin face on the [Net] autoload: this screen never
## touches the peer itself. Three ways in: the host's code (any network, any
## device), a game heard on this Wi-Fi (LanBeacon), or an address typed by hand.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const LAN_REFRESH := 0.5
const MODE_KEYS := {Net.Mode.COOP: "MP_MODE_COOP", Net.Mode.PVP: "MP_MODE_PVP"}

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
@onready var lan: Control = %Lan
@onready var lan_list: VBoxContainer = %LanList
@onready var invite_row: Control = %InviteRow
@onready var code_label: Label = %Code
@onready var copy_button: Button = %Copy

var _beacon := LanBeacon.new()
var _lan_clock := 0.0
## "ip:port" of every game listed, to rebuild the list only when it changes
var _lan_shown := ""


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
	Net.invite_changed.connect(_refresh_invite)
	Net.failed.connect(_on_failed)
	Net.closed.connect(_on_failed)
	copy_button.pressed.connect(_on_copy)
	_beacon.listen()
	tree_exiting.connect(_beacon.close)
	_refresh()
	host_button.grab_focus()


func _process(delta: float) -> void:
	_lan_clock -= delta
	if _lan_clock > 0.0:
		return
	_lan_clock = LAN_REFRESH
	_refresh_lan()


func _on_host() -> void:
	Net.local_name = player_name.text.strip_edges()
	if Net.host(mode.get_selected_id() as Net.Mode, _port()) == OK:
		_refresh()
		_refresh_invite()


func _on_join() -> void:
	if address.text.strip_edges().is_empty():
		status.text = "NET_ERR_ADDRESS"
		return
	_join(address.text, _port())


func _join(where: String, port_number: int) -> void:
	Net.local_name = player_name.text.strip_edges()
	if Net.join(where, port_number) == OK:
		status.text = "MP_STATUS_CONNECTING"
		_refresh()


func _on_copy() -> void:
	if Net.invite_code.is_empty():
		return
	DisplayServer.clipboard_set(RelayProtocol.pretty_code(Net.invite_code))
	status.text = "MP_COPIED"


## The host's code, or why there is none, and the addresses a friend on the
## same network can use either way.
func _refresh_invite() -> void:
	invite_row.visible = Net.hosting and not Net.relay_url().is_empty()
	if not Net.hosting:
		return
	var local := tr("MP_STATUS_HOSTING") % _own_addresses() if Net.listening_locally else ""
	match Net.online:
		Net.Online.READY:
			code_label.text = RelayProtocol.pretty_code(Net.invite_code)
			status.text = local
		Net.Online.WAITING:
			code_label.text = "…"
			status.text = "MP_CODE_WAIT"
		Net.Online.FAILED:
			code_label.text = "—"
			status.text = "MP_CODE_NONE"
		_:
			status.text = ("%s\n%s" % [tr("MP_CODE_OFF"), local]) if not local.is_empty() else ""
	copy_button.disabled = Net.invite_code.is_empty()


## Games heard on this Wi-Fi, one button each; nothing at all in a browser,
## or while we are in a session ourselves.
func _refresh_lan() -> void:
	var games: Array = _beacon.games() if not Net.active else []
	var keys: PackedStringArray = []
	for game in games:
		keys.append("%s:%d:%s:%s" % [game.ip, game.port, game.code, game.name])
	var shown := ",".join(keys)
	lan.visible = not games.is_empty()
	if shown == _lan_shown:
		return
	_lan_shown = shown
	for child in lan_list.get_children():
		child.queue_free()
	for game in games:
		var button := Button.new()
		button.text = tr("MP_LAN_GAME") % [game.name, tr(MODE_KEYS.get(int(game.mode), "MP_MODE_COOP"))]
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		# Straight to the host on the same network when it listens here;
		# through its code otherwise.
		if int(game.port) > 0:
			button.pressed.connect(_join.bind(str(game.ip), int(game.port)))
		else:
			button.pressed.connect(_join.bind(str(game.code), Net.DEFAULT_PORT))
		lan_list.add_child(button)


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
