extends MultiplayerPeerExtension
class_name HostPeer
## The host's side of a session, listening on more than one wire at once: the
## local WebSocket server (a friend on the same Wi-Fi, found by LanBeacon or
## typed as an address) and a room on the relay (a friend anywhere, by code).
## SceneMultiplayer sees one server with one set of peers; each packet goes out
## through whichever wire its peer came in on.

var children: Array[MultiplayerPeer] = []
## peer id -> the child it lives on
var _home := {}
## child -> the two bound callables it was connected with, to undo them
var _listeners := {}
## [from, channel, mode, packet]
var _inbox: Array = []
var _target := 0
var _channel := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _refusing := false
var _open := true


func add(child: MultiplayerPeer) -> void:
	children.append(child)
	var heard := [_on_child_connected.bind(child), _on_child_disconnected.bind(child)]
	_listeners[child] = heard
	child.peer_connected.connect(heard[0])
	child.peer_disconnected.connect(heard[1])


## A wire that went down (the relay restarted) is taken out before its
## replacement is added; whoever was on it has already been dropped.
func remove(child: MultiplayerPeer) -> void:
	if not children.has(child):
		return
	children.erase(child)
	var heard: Array = _listeners.get(child, [])
	_listeners.erase(child)
	if heard.size() == 2:
		child.peer_connected.disconnect(heard[0])
		child.peer_disconnected.disconnect(heard[1])
	child.close()
	for id in _home.keys():
		if _home[id] == child:
			_home.erase(id)
			peer_disconnected.emit(id)


func _on_child_connected(id: int, child: MultiplayerPeer) -> void:
	# Ids are random 31-bit numbers from two sources; a clash is a one in a
	# billion, and the newcomer is the one sent away.
	if _home.has(id):
		child.disconnect_peer(id, true)
		return
	_home[id] = child
	peer_connected.emit(id)


func _on_child_disconnected(id: int, child: MultiplayerPeer) -> void:
	if _home.get(id) == child:
		_home.erase(id)
		peer_disconnected.emit(id)


func _poll() -> void:
	for child in children:
		child.poll()
		while child.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED \
				and child.get_available_packet_count() > 0:
			var from := child.get_packet_peer()
			var channel := child.get_packet_channel()
			var mode := child.get_packet_mode()
			_inbox.append([from, channel, mode, child.get_packet()])


func _put_packet_script(buffer: PackedByteArray) -> Error:
	var result := OK
	for child in children:
		if child.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			continue
		var target := _target
		if _target > 0:
			if _home.get(_target) != child:
				continue
		elif _target < 0 and _home.get(-_target) != child:
			target = 0  # the excluded peer is not on this wire
		if target == 0 and not _home.values().has(child):
			continue  # nobody on this wire to hear a broadcast
		child.set_transfer_channel(_channel)
		child.set_transfer_mode(_mode)
		child.set_target_peer(target)
		var err := child.put_packet(buffer)
		if err != OK:
			result = err
	return result


func _get_packet_script() -> PackedByteArray:
	return _inbox.pop_front()[3] if not _inbox.is_empty() else PackedByteArray()


func _get_available_packet_count() -> int:
	return _inbox.size()


func _get_packet_peer() -> int:
	return int(_inbox[0][0]) if not _inbox.is_empty() else 0


func _get_packet_channel() -> int:
	return int(_inbox[0][1]) if not _inbox.is_empty() else 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return _inbox[0][2] if not _inbox.is_empty() else MultiplayerPeer.TRANSFER_MODE_RELIABLE


func _get_max_packet_size() -> int:
	return 1 << 16


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
	return true


func _is_server_relay_supported() -> bool:
	return true


func _get_unique_id() -> int:
	return 1


## A host is up while any of its wires is: losing the relay leaves the local
## game standing, and the other way round.
func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	if not _open:
		return MultiplayerPeer.CONNECTION_DISCONNECTED
	for child in children:
		if child.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			return MultiplayerPeer.CONNECTION_CONNECTED
	for child in children:
		if child.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
			return MultiplayerPeer.CONNECTION_CONNECTING
	return MultiplayerPeer.CONNECTION_DISCONNECTED


func _set_refuse_new_connections(enable: bool) -> void:
	_refusing = enable
	for child in children:
		child.refuse_new_connections = enable


func _is_refusing_new_connections() -> bool:
	return _refusing


func _disconnect_peer(peer: int, force: bool) -> void:
	var child: MultiplayerPeer = _home.get(peer)
	if child != null:
		child.disconnect_peer(peer, force)


func _close() -> void:
	_open = false
	for child in children:
		child.close()
	_home.clear()
	_inbox.clear()
