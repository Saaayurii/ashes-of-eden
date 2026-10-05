extends SceneTree
## The relay and what talks to it, in one process (docs/RELAY.md):
##   - codes: read back the way a player types them, refused when they are not one;
##   - a host gets the code it asked for, or a fresh one when it is taken;
##   - a guest with a wrong code, a full room or another protocol is told why;
##   - packets go host -> one guest, host -> all but one, guest -> host;
##   - a kick and a guest leaving reach the host; the host leaving ends the room;
##   - HostPeer: a friend on the Wi-Fi and a friend through the relay in the
##     same game, each answered on the wire they came in on;
##   - LanBeacon: a host's shout is heard and read, a stranger's is not.
## The real game over the relay is tools/net_test.sh coop-relay.
##   godot --headless -s scripts/tools/relay_test.gd

const PORT := 8925
const LOCAL_PORT := 8926
const URL := "ws://127.0.0.1:%d" % PORT

var failures := 0
var RelayServer = load("res://scripts/net/relay_server.gd")
var RelayPeer = load("res://scripts/net/relay_peer.gd")
var HostPeer = load("res://scripts/net/host_peer.gd")
var LanBeacon = load("res://scripts/net/lan_beacon.gd")
var Protocol = load("res://scripts/net/relay_protocol.gd")
var relay
var _polled: Array = []


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


## Polls every peer under test (the relay polls itself in _process) until
## [param done] holds or two seconds pass.
func _until(done: Callable, seconds := 2.0) -> bool:
	var left := seconds
	while left > 0.0:
		for peer in _polled:
			peer.poll()
		if done.call():
			return true
		await process_frame
		left -= 1.0 / 60.0
	return done.call()


func _packets(peer) -> Array:
	var got: Array = []
	peer.poll()
	while peer.get_available_packet_count() > 0:
		var from: int = peer.get_packet_peer()
		got.append([from, peer.get_packet()])
	return got


func _host(code := ""):
	var peer = RelayPeer.new()
	peer.open_host(URL, code)
	_polled.append(peer)
	await _until(func() -> bool: return peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTING)
	return peer


func _guest(code: String):
	var peer = RelayPeer.new()
	peer.open_join(URL, code)
	_polled.append(peer)
	await _until(func() -> bool: return peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTING)
	return peer


func _run() -> void:
	_codes()
	relay = RelayServer.new()
	root.add_child(relay)
	_check(relay.listen(PORT) == OK, "the relay listens on %d" % PORT)

	# a host asks for a code and gets it
	var host = await _host("ace-234")
	var joined := []
	var left := []
	host.peer_connected.connect(func(id: int) -> void: joined.append(id))
	host.peer_disconnected.connect(func(id: int) -> void: left.append(id))
	_check(host.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and host.code == "ACE234",
		"a host opens room ACE234 (%s)" % host.code)
	_check(host.get_unique_id() == 1 and host._is_server(), "  and is peer 1, the server")
	var second_host = await _host("ACE234")
	_check(second_host.code.length() == 6 and second_host.code != "ACE234", "a taken code gives another (%s)" % second_host.code)

	# wrong code, then the right one typed loosely
	var lost = await _guest("ZZZ-ZZZ")
	_check(lost.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED and lost.error_key == "NET_ERR_NO_ROOM",
		"a code nobody holds is refused as such (%s)" % lost.error_key)
	var guest = await _guest(" ace 234 ")
	_check(guest.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and guest.get_unique_id() > 1,
		"a guest joins by code, spaces and case forgiven (id %d)" % guest.get_unique_id())
	await _until(func() -> bool: return joined.size() == 1)
	_check(joined == [guest.get_unique_id()], "  and the host hears it arrive")

	# guest -> host
	guest.put_packet(PackedByteArray([1, 2, 3]))
	var at_host := []
	await _until(func() -> bool:
		at_host.append_array(_packets(host))
		return not at_host.is_empty())
	_check(at_host.size() == 1 and at_host[0][0] == guest.get_unique_id() and at_host[0][1] == PackedByteArray([1, 2, 3]),
		"a guest's packet reaches the host, signed with the guest's id")

	# host -> everyone but one
	var other = await _guest("ACE234")
	await _until(func() -> bool: return joined.size() == 2)
	host.set_target_peer(-guest.get_unique_id())
	host.put_packet(PackedByteArray([9]))
	var at_other := []
	await _until(func() -> bool:
		at_other.append_array(_packets(other))
		return not at_other.is_empty())
	await _until(func() -> bool: return false, 0.2)
	_check(at_other.size() == 1 and at_other[0][0] == 1 and _packets(guest).is_empty(),
		"the host's \"all but one\" skips the one")
	host.set_target_peer(guest.get_unique_id())
	host.put_packet(PackedByteArray([7]))
	var at_guest := []
	await _until(func() -> bool:
		at_guest.append_array(_packets(guest))
		return not at_guest.is_empty())
	_check(at_guest.size() == 1 and at_guest[0][1] == PackedByteArray([7]) and _packets(other).is_empty(),
		"and a packet for one goes to that one only")

	# full room
	var third = await _guest("ACE234")
	var fourth = await _guest("ACE234")
	_check(third.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED \
		and fourth.error_key == "NET_ERR_FULL", "a full room turns the next away (%s)" % fourth.error_key)

	# kick, leave
	await _until(func() -> bool: return joined.size() == 3)
	host.disconnect_peer(third.get_unique_id())
	await _until(func() -> bool: return third.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED \
		and left.has(third.get_unique_id()))
	_check(third.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED and left.has(third.get_unique_id()),
		"a kicked guest is cut off, and the host hears it go")
	other.close()
	await _until(func() -> bool: return left.has(other.get_unique_id()))
	_check(left.has(other.get_unique_id()), "a guest that leaves is heard leaving")

	# another protocol
	var stranger := WebSocketPeer.new()
	stranger.connect_to_url(URL)
	var said := []
	await _until(func() -> bool:
		stranger.poll()
		if stranger.get_ready_state() == WebSocketPeer.STATE_OPEN and said.is_empty():
			said.append(true)
			stranger.send(PackedByteArray([Protocol.HELLO_JOIN, Protocol.VERSION + 1]) + "ACE234".to_ascii_buffer())
		while stranger.get_available_packet_count() > 0:
			said.append(stranger.get_packet())
		return said.size() > 1)
	_check(said.size() > 1 and said[1] == Protocol.error(Protocol.Reason.VERSION), "another protocol version is refused")

	# the host leaves: the room ends for whoever is left
	var guest_saw_host_go := []
	guest.peer_disconnected.connect(func(id: int) -> void: guest_saw_host_go.append(id))
	var rooms_before: int = relay.room_count()
	host.close()
	await _until(func() -> bool: return guest.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED)
	_check(guest_saw_host_go == [1] and guest.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED,
		"the host leaving ends the room for its guest")
	await _until(func() -> bool: return relay.room_count() == rooms_before - 1)
	_check(relay.room_count() == rooms_before - 1, "  and the relay forgets the room")
	second_host.close()

	await _merged()
	_beacon()

	relay.stop()
	print("RELAY TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)


func _codes() -> void:
	_check(Protocol.normalize_code("ace-234") == "ACE234", "a code is read whatever its case and dash")
	_check(Protocol.normalize_code("ACE23") == "" and Protocol.normalize_code("ACE2345") == "", "  and only at six characters")
	_check(Protocol.normalize_code("AC0234") == "" and Protocol.normalize_code("ACB234") == "",
		"  and never with a character it leaves out to be read aloud")
	_check(Protocol.pretty_code("ACE234") == "ACE-234", "a code is shown in two halves")
	var net = root.get_node("Net")
	_check(net.is_code("ace-234") and not net.is_code("192.168.1.5") and not net.is_code("localhost") \
		and not net.is_code("play.example.com") and not net.is_code("ACE234:8910"), "Join tells a code from an address")


## A host on two wires at once: the Wi-Fi friend dials straight in, the other
## comes through the relay, and each hears only what is meant for them.
func _merged() -> void:
	var local := WebSocketMultiplayerPeer.new()
	_check(local.create_server(LOCAL_PORT) == OK, "the host listens locally on %d" % LOCAL_PORT)
	var online = RelayPeer.new()
	online.open_host(URL, "")
	var merged = HostPeer.new()
	merged.add(local)
	merged.add(online)
	var arrived := []
	merged.peer_connected.connect(func(id: int) -> void: arrived.append(id))
	_polled.append(merged)
	await _until(func() -> bool: return online.code.length() == 6)
	var near := WebSocketMultiplayerPeer.new()
	near.create_client("ws://127.0.0.1:%d" % LOCAL_PORT)
	_polled.append(near)
	var far = await _guest(online.code)
	await _until(func() -> bool: return arrived.size() == 2 \
		and near.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)
	_check(arrived.size() == 2 and arrived.has(far.get_unique_id()) and arrived.has(near.get_unique_id()),
		"one host, a friend on the Wi-Fi and a friend by code (%s)" % [arrived])
	merged.set_target_peer(far.get_unique_id())
	merged.put_packet(PackedByteArray([5]))
	var at_far := []
	await _until(func() -> bool:
		at_far.append_array(_packets(far))
		return not at_far.is_empty())
	_check(at_far.size() == 1 and _packets(near).is_empty(), "a packet for the far one goes through the relay only")
	merged.set_target_peer(0)
	merged.put_packet(PackedByteArray([6]))
	var both := [[], []]
	await _until(func() -> bool:
		both[0].append_array(_packets(near))
		both[1].append_array(_packets(far))
		return not both[0].is_empty() and not both[1].is_empty())
	_check(both[0].size() == 1 and both[1].size() == 1, "a broadcast reaches both, once each")
	near.put_packet(PackedByteArray([8]))
	far.put_packet(PackedByteArray([4]))
	var heard := []
	await _until(func() -> bool:
		merged.poll()
		while merged.get_available_packet_count() > 0:
			heard.append([merged.get_packet_peer(), merged.get_packet()[0]])
		return heard.size() == 2)
	_check(heard.has([near.get_unique_id(), 8]) and heard.has([far.get_unique_id(), 4]),
		"the host hears both, each signed as itself")
	merged.close()
	near.close()


func _beacon() -> void:
	var said: PackedByteArray = LanBeacon.message("Roman", 1, 8910, "ACE234")
	var game: Dictionary = LanBeacon.parse(said, "192.168.1.5")
	_check(game.get("name") == "Roman" and game.get("port") == 8910 and game.get("code") == "ACE234" \
		and game.get("ip") == "192.168.1.5", "a host's shout reads back as its game")
	_check(LanBeacon.parse("hello".to_utf8_buffer(), "1.2.3.4").is_empty() \
		and LanBeacon.parse(JSON.stringify({"g": "other-game", "v": 1, "p": 1}).to_utf8_buffer(), "1.2.3.4").is_empty(),
		"  and anything else on the network is ignored")
	var ear = LanBeacon.new()
	if not ear.listen():
		print("  skip the broadcast port is taken on this machine")
		return
	var mouth := PacketPeerUDP.new()
	mouth.set_dest_address("127.0.0.1", LanBeacon.PORT)
	mouth.put_packet(said)
	var games := []
	var waited := 0
	while games.is_empty() and waited < 60:
		OS.delay_msec(10)
		games = ear.games()
		waited += 1
	_check(games.size() == 1 and games[0].name == "Roman", "the screen lists a game it hears")
	ear.close()
