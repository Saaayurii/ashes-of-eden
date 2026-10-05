extends Node
class_name RelayServer
## The relay (docs/RELAY.md): rooms by code, and a byte pump between the host
## of each room and its guests. It never reads a game packet, simulates
## nothing and keeps nothing on disk, so one small machine carries many rooms.
##
##   godot --headless -- --relay --port=8920
##
## Plain ws:// on its port; put it behind a TLS proxy (Caddy, nginx) for the
## wss:// a page served over https must use.

const HELLO_TIMEOUT := 10.0
const MAX_ROOMS := 512
const MAX_ROOMS_PER_ADDRESS := 4
## Net turns away a third player itself; this only stops a room being used as
## a broadcast hub.
const MAX_GUESTS := 3
const MAX_PACKET := 1 << 20
const BUFFER := 1 << 20
const HEARTBEAT := 15.0

## Kept for the test and the log line; nothing reads them to decide anything.
var rooms_opened := 0
var packets_relayed := 0

var _tcp := TCPServer.new()
var _rng := RandomNumberGenerator.new()
## socket id -> {ws, address, since, room, id}
var _sockets := {}
var _next_socket := 1
## code -> {host: socket id, guests: {peer id: socket id}}
var _rooms := {}
## Sockets told to go: still polled until the goodbye (and the reason before
## it) has left, which a socket nobody polls never does. [ws, deadline]
var _closing: Array = []


func listen(port := RelayProtocol.DEFAULT_PORT, bind := "*") -> Error:
	_rng.randomize()
	return _tcp.listen(port, bind)


func room_count() -> int:
	return _rooms.size()


func stop() -> void:
	for socket in _sockets.keys():
		_sockets[socket].ws.close()
	_sockets.clear()
	_closing.clear()
	_rooms.clear()
	_tcp.stop()


func _process(_delta: float) -> void:
	while _tcp.is_connection_available():
		var stream := _tcp.take_connection()
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = BUFFER
		ws.outbound_buffer_size = BUFFER
		ws.max_queued_packets = 4096
		ws.heartbeat_interval = HEARTBEAT
		if ws.accept_stream(stream) != OK:
			continue
		_sockets[_next_socket] = {"ws": ws, "address": stream.get_connected_host(),
			"since": Time.get_ticks_msec(), "room": "", "id": 0}
		_next_socket += 1
	var now := Time.get_ticks_msec()
	for i in range(_closing.size() - 1, -1, -1):
		var ws: WebSocketPeer = _closing[i][0]
		ws.poll()
		# Close only once the last frame (a refusal's reason) has left: a close
		# sent first overtakes it, and the player reads "could not reach".
		if not _closing[i][2] and (ws.get_current_outbound_buffered_amount() == 0 or now > int(_closing[i][1])):
			_closing[i][2] = true
			ws.close(1000)
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED or now > int(_closing[i][1]) + 2000:
			_closing.remove_at(i)
	for socket in _sockets.keys():
		if not _sockets.has(socket):
			continue  # closed while another socket's frames were handled
		var entry: Dictionary = _sockets[socket]
		var ws: WebSocketPeer = entry.ws
		ws.poll()
		var state := ws.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED:
			_forget(socket)
			continue
		if state != WebSocketPeer.STATE_OPEN:
			if now - int(entry.since) > HELLO_TIMEOUT * 1000.0:
				_hang_up(socket)
			continue
		while _sockets.has(socket) and ws.get_available_packet_count() > 0:
			_read(socket, ws.get_packet())
		if _sockets.has(socket) and str(entry.room).is_empty() \
				and now - int(entry.since) > HELLO_TIMEOUT * 1000.0:
			_refuse(socket, RelayProtocol.Reason.BAD)


func _read(socket: int, packet: PackedByteArray) -> void:
	var entry: Dictionary = _sockets[socket]
	if packet.is_empty() or packet.size() > MAX_PACKET:
		_refuse(socket, RelayProtocol.Reason.BAD)
		return
	var type := int(packet[0])
	if str(entry.room).is_empty():
		match type:
			RelayProtocol.HELLO_HOST, RelayProtocol.HELLO_JOIN:
				if packet.size() < 2 or int(packet[1]) != RelayProtocol.VERSION:
					_refuse(socket, RelayProtocol.Reason.VERSION)
				elif type == RelayProtocol.HELLO_HOST:
					_open_room(socket, packet.slice(2).get_string_from_ascii())
				else:
					_join_room(socket, packet.slice(2).get_string_from_ascii())
			_:
				_refuse(socket, RelayProtocol.Reason.BAD)
		return
	var room: Dictionary = _rooms.get(entry.room, {})
	if room.is_empty():
		return
	var payload := packet.slice(RelayProtocol.HEADER)
	match type:
		RelayProtocol.SEND:
			if int(entry.id) == 1:
				var target := RelayProtocol.peer_of(packet)
				var out := RelayProtocol.frame(RelayProtocol.DELIVER, 1, payload)
				for guest in room.guests:
					if target == 0 or target == guest or (target < 0 and -target != guest):
						_send(room.guests[guest], out)
			else:
				_send(room.host, RelayProtocol.frame(RelayProtocol.DELIVER, int(entry.id), payload))
		RelayProtocol.KICK:
			if int(entry.id) == 1:
				var guest := RelayProtocol.peer_of(packet)
				if room.guests.has(guest):
					_hang_up(room.guests[guest])
		_:
			_refuse(socket, RelayProtocol.Reason.BAD)


func _open_room(socket: int, wanted: String) -> void:
	var address := str(_sockets[socket].address)
	var mine := 0
	for code in _rooms:
		if str(_sockets[_rooms[code].host].address) == address:
			mine += 1
	if _rooms.size() >= MAX_ROOMS or mine >= MAX_ROOMS_PER_ADDRESS:
		_refuse(socket, RelayProtocol.Reason.BUSY)
		return
	var code := RelayProtocol.normalize_code(wanted)
	while code.is_empty() or _rooms.has(code):
		code = RelayProtocol.random_code(_rng)
	_rooms[code] = {"host": socket, "guests": {}}
	_sockets[socket].room = code
	_sockets[socket].id = 1
	rooms_opened += 1
	_send(socket, RelayProtocol.frame(RelayProtocol.WELCOME, 1, code.to_ascii_buffer()))
	print("[Relay] room %s opened (%d open)" % [code, _rooms.size()])


func _join_room(socket: int, code: String) -> void:
	code = RelayProtocol.normalize_code(code)
	if not _rooms.has(code):
		_refuse(socket, RelayProtocol.Reason.NO_ROOM)
		return
	var room: Dictionary = _rooms[code]
	if room.guests.size() >= MAX_GUESTS:
		_refuse(socket, RelayProtocol.Reason.FULL)
		return
	var id := 0
	while id < 2 or room.guests.has(id):
		id = _rng.randi_range(2, 0x7fffffff)
	room.guests[id] = socket
	_sockets[socket].room = code
	_sockets[socket].id = id
	_send(socket, RelayProtocol.frame(RelayProtocol.WELCOME, id, code.to_ascii_buffer()))
	_send(room.host, RelayProtocol.frame(RelayProtocol.PEER_IN, id))


func _send(socket: int, packet: PackedByteArray) -> void:
	if _sockets.has(socket):
		_sockets[socket].ws.send(packet)
		packets_relayed += 1


## Says why, then hangs up; the client reads the reason before the close.
func _refuse(socket: int, reason: int) -> void:
	_sockets[socket].ws.send(RelayProtocol.error(reason))
	_hang_up(socket)


func _hang_up(socket: int) -> void:
	if not _sockets.has(socket):
		return
	_closing.append([_sockets[socket].ws, Time.get_ticks_msec() + 3000, false])
	_forget(socket)


## A socket is gone: a guest leaves its room, a host takes its room with it.
func _forget(socket: int) -> void:
	if not _sockets.has(socket):
		return
	var entry: Dictionary = _sockets[socket]
	_sockets.erase(socket)
	var code := str(entry.room)
	if code.is_empty() or not _rooms.has(code):
		return
	var room: Dictionary = _rooms[code]
	if int(entry.id) == 1:
		_rooms.erase(code)
		for guest in room.guests:
			var other: int = room.guests[guest]
			if _sockets.has(other):
				_sockets[other].ws.send(RelayProtocol.frame(RelayProtocol.PEER_OUT, 1))
				_closing.append([_sockets[other].ws, Time.get_ticks_msec() + 3000, false])
				_sockets.erase(other)
		print("[Relay] room %s closed (%d open)" % [code, _rooms.size()])
	else:
		room.guests.erase(int(entry.id))
		_send(room.host, RelayProtocol.frame(RelayProtocol.PEER_OUT, int(entry.id)))
