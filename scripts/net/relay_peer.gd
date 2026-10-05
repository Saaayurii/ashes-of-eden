extends MultiplayerPeerExtension
class_name RelayPeer
## A MultiplayerPeer whose wire is a room on the relay (RelayProtocol,
## docs/RELAY.md). To the SceneMultiplayer above it, it is an ordinary server
## or client: RPCs, spawners and synchronizers run over it unchanged. Both
## sides dial out, so it works behind any router, on mobile data, and from a
## browser tab — which cannot listen for a connection, but can host this way.

## The relay gave the host its room code (or a guest the code it joined).
signal code_assigned(code: String)

const BUFFER := 1 << 20
const QUEUED := 4096
## Keeps the socket alive through proxies that drop a quiet one (Caddy,
## Cloudflare and most load balancers give up somewhere past a minute).
const HEARTBEAT := 15.0

var code := ""
## Why the relay turned us away (a NET_ERR_* key), "" if it did not.
var error_key := ""

var _ws := WebSocketPeer.new()
var _hosting := false
var _id := 0
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _hello_sent := false
var _target := 0
var _channel := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _refusing := false
var _peers := {}
## [from, packet] in arrival order; the front is what get_packet_* describe.
var _inbox: Array = []


func open_host(url: String, wanted_code := "") -> Error:
	_hosting = true
	_id = 1
	code = RelayProtocol.normalize_code(wanted_code)
	return _open(url)


func open_join(url: String, room_code: String) -> Error:
	_hosting = false
	code = RelayProtocol.normalize_code(room_code)
	if code.is_empty():
		error_key = "NET_ERR_NO_ROOM"
		return ERR_INVALID_PARAMETER
	return _open(url)


func _open(url: String) -> Error:
	_ws.inbound_buffer_size = BUFFER
	_ws.outbound_buffer_size = BUFFER
	_ws.max_queued_packets = QUEUED
	_ws.heartbeat_interval = HEARTBEAT
	var err := _ws.connect_to_url(url)
	if err != OK:
		error_key = "NET_ERR_RELAY"
		return err
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	return OK


# ------------------------------------------------------------ the poll ---

func _poll() -> void:
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not _hello_sent:
		_hello_sent = true
		var kind := RelayProtocol.HELLO_HOST if _hosting else RelayProtocol.HELLO_JOIN
		_ws.send(RelayProtocol.hello(kind, code))
	# Read even while closing: a refusal arrives as the last frame before the
	# close, and dropping it would leave "could not reach" instead of "no such game".
	while _status != MultiplayerPeer.CONNECTION_DISCONNECTED and _ws.get_available_packet_count() > 0:
		_read(_ws.get_packet())
	if state == WebSocketPeer.STATE_CLOSED and _status != MultiplayerPeer.CONNECTION_DISCONNECTED:
		if _status == MultiplayerPeer.CONNECTION_CONNECTING and error_key.is_empty():
			error_key = "NET_ERR_RELAY"
		_drop()


func _read(packet: PackedByteArray) -> void:
	if packet.is_empty():
		return
	match packet[0]:
		RelayProtocol.DELIVER:
			if packet.size() > RelayProtocol.HEADER:
				_inbox.append([RelayProtocol.peer_of(packet), packet.slice(RelayProtocol.HEADER)])
		RelayProtocol.WELCOME:
			_id = RelayProtocol.peer_of(packet)
			code = packet.slice(RelayProtocol.HEADER).get_string_from_ascii()
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			code_assigned.emit(code)
			if not _hosting:
				_peers[1] = true
				peer_connected.emit(1)
		RelayProtocol.PEER_IN:
			var id := RelayProtocol.peer_of(packet)
			if _hosting and not _peers.has(id):
				if _refusing:
					_ws.send(RelayProtocol.frame(RelayProtocol.KICK, id))
					return
				_peers[id] = true
				peer_connected.emit(id)
		RelayProtocol.PEER_OUT:
			var id := RelayProtocol.peer_of(packet)
			if _peers.erase(id):
				peer_disconnected.emit(id)
			if id == 1 and not _hosting:
				_ws.close()
				_drop()
		RelayProtocol.ERROR:
			var reason := int(packet[1]) if packet.size() > 1 else RelayProtocol.Reason.BAD
			error_key = RelayProtocol.REASON_KEYS.get(reason, "NET_ERR_RELAY")
			_ws.close()
			_drop()


## The socket is gone: everyone we knew leaves with it.
func _drop() -> void:
	for id in _peers.keys():
		peer_disconnected.emit(id)
	_peers.clear()
	_inbox.clear()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED


# ----------------------------------------------------- MultiplayerPeer ---

func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	# A guest only ever talks to the host; the host relays between guests.
	var target := _target if _hosting else 1
	return _ws.send(RelayProtocol.frame(RelayProtocol.SEND, target, buffer))


func _get_packet_script() -> PackedByteArray:
	if _inbox.is_empty():
		return PackedByteArray()
	return _inbox.pop_front()[1]


func _get_available_packet_count() -> int:
	return _inbox.size()


func _get_packet_peer() -> int:
	return int(_inbox[0][0]) if not _inbox.is_empty() else 0


func _get_packet_channel() -> int:
	return 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return MultiplayerPeer.TRANSFER_MODE_RELIABLE  # a WebSocket is ordered and reliable


func _get_max_packet_size() -> int:
	return BUFFER - RelayProtocol.HEADER


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _set_target_peer(peer: int) -> void:
	_target = peer


func _is_server() -> bool:
	return _hosting


func _is_server_relay_supported() -> bool:
	return true


func _get_unique_id() -> int:
	return _id


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


func _set_refuse_new_connections(enable: bool) -> void:
	_refusing = enable


func _is_refusing_new_connections() -> bool:
	return _refusing


func _disconnect_peer(peer: int, _force: bool) -> void:
	if _hosting and _peers.has(peer):
		_ws.send(RelayProtocol.frame(RelayProtocol.KICK, peer))


func _close() -> void:
	_ws.close()
	_peers.clear()
	_inbox.clear()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
