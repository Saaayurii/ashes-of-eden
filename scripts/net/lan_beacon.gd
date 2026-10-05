extends RefCounted
class_name LanBeacon
## Finding a game on the same Wi-Fi without typing anything: the host says
## "here I am" to the whole network once a second (a UDP broadcast), and the
## Play together screen lists whoever it hears. Nothing leaves the network.
##
## Not in a browser — a page cannot send or receive UDP — where the code is
## the way in. An Android phone hears broadcasts only with the multicast
## permission (export_presets.cfg) and the broadcast flag on its socket.

const PORT := 8912
const TAG := "ashes-of-eden"
const VERSION := 1
## A host that has been quiet this long has gone.
const STALE := 3.5

var _udp := PacketPeerUDP.new()
var _listening := false
## "ip:port" -> {ip, port, name, mode, code, seen}
var _heard := {}


static func supported() -> bool:
	return not OS.has_feature("web")


## What a host says. [param port] 0 when it is not listening locally (only on
## the relay), [param code] "" when it has no relay room.
static func message(host_name: String, mode: int, port: int, code: String) -> PackedByteArray:
	return JSON.stringify({"g": TAG, "v": VERSION, "n": host_name.left(16),
		"m": mode, "p": port, "c": code}).to_utf8_buffer()


## A heard message as a game, or {} when it is not one of ours.
static func parse(packet: PackedByteArray, ip: String) -> Dictionary:
	var json := JSON.new()  # not JSON.parse_string: a stranger's packet is not worth an error line
	if json.parse(packet.get_string_from_utf8()) != OK:
		return {}
	var data = json.data
	if not data is Dictionary or data.get("g") != TAG or int(data.get("v", 0)) != VERSION:
		return {}
	var port := int(data.get("p", 0))
	var code := RelayProtocol.normalize_code(str(data.get("c", "")))
	if (port <= 0 or port > 65535) and code.is_empty():
		return {}
	return {"ip": ip, "port": port, "name": str(data.get("n", "?")).left(16),
		"mode": int(data.get("m", 0)), "code": code}


## Host side: one shout to the network.
func announce(host_name: String, mode: int, port: int, code: String) -> void:
	if not supported():
		return
	_udp.set_broadcast_enabled(true)
	_udp.set_dest_address("255.255.255.255", PORT)
	_udp.put_packet(message(host_name, mode, port, code))


## Joining side: start hearing. False when the port is taken (another copy of
## the game on this machine is already listening) — then there is no list.
func listen() -> bool:
	if not supported():
		return false
	if _listening:
		return true
	_udp.set_broadcast_enabled(true)
	_listening = _udp.bind(PORT) == OK
	return _listening


## The games heard lately, freshest first.
func games() -> Array:
	if _listening:
		while _udp.get_available_packet_count() > 0:
			var packet := _udp.get_packet()
			var game := parse(packet, _udp.get_packet_ip())
			if not game.is_empty():
				game.seen = Time.get_ticks_msec()
				_heard["%s:%d" % [game.ip, game.port]] = game
	var now := Time.get_ticks_msec()
	var found: Array = []
	for key in _heard.keys():
		if now - int(_heard[key].seen) > STALE * 1000.0:
			_heard.erase(key)
		else:
			found.append(_heard[key])
	found.sort_custom(func(a, b) -> bool: return int(a.seen) > int(b.seen))
	return found


func close() -> void:
	_udp.close()
	_listening = false
	_heard.clear()
