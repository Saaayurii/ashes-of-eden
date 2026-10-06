extends Node
## Online session for two: co-op through the story, or a 1v1 duel.
##
## The transport is WebSocket on purpose. It is the only Godot peer that works
## on every target we ship — desktop, mobile *and* Web — so one host can serve
## a browser, a phone and a laptop at the same time. ENet would be smoother but
## silently drops the Web build, and crossplay is the point. See docs/MULTIPLAYER.md.
##
## Authority: the host simulates the world (rooms, enemies, score); every player
## body is simulated by whoever owns it and mirrored to the others. Damage is
## always applied by the owner of the body that takes it (see Player.take_damage).
##
## Three ways in, all on the same screen (docs/RELAY.md): a code through the
## relay (anywhere, behind any router, from a browser too — what people use
## ZeroTier or Radmin for, without either), a game heard on the same Wi-Fi
## (LanBeacon), or an address typed by hand. A host offers the first two at once
## (HostPeer).

signal lobby_changed
signal match_started(mode: int)
signal failed(reason_key: String)
signal closed(reason_key: String)
## The host's room code arrived, or went away with the relay.
signal invite_changed
## A match ended because the wire did (host gone, relay gone, silence past
## LINK_TIMEOUT). NetOverlay says so; the scene is already on its way to the menu.
signal connection_lost(reason_key: String)
## The other player left a match we are still in (the host carries on).
signal partner_left(peer_name: String)

enum Mode {COOP, PVP}

const DEFAULT_PORT := 8910
## Two players. The whole feature is "play this with a friend", not a lobby simulator.
const MAX_PLAYERS := 2
const CONNECT_TIMEOUT := 12.0
const MODE_SCENES := {
	Mode.COOP: "res://scenes/run/run.tscn",
	Mode.PVP: "res://scenes/pvp/arena.tscn",
}
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
## Where the relay lives (docs/RELAY.md); "" until one is deployed, and then
## only the Wi-Fi and the typed address are offered. --relay-url= overrides it.
const RELAY_SETTING := "ashes/network/relay_url"
const BEACON_INTERVAL := 1.0
const SYNC_GROUP := &"net_sync"
const RELAY_RETRY := 4.0
## The link is measured with a ping a second each way (link_ms, link_silence).
const PING_INTERVAL := 1.0
## Silence this long reads as an unstable link (NetOverlay shows it) ...
const LINK_STALL := 2.5
## ... and this long as a dead one: a guest gives up on the host, a host lets
## the silent guest go. A WebSocket can take far longer to notice by itself.
const LINK_TIMEOUT := 15.0

enum Online {OFF, WAITING, READY, FAILED}

## A session exists (hosting or connected). False = plain single player.
var active := false
var hosting := false
## Headless host that only referees: it holds no player of its own.
var dedicated := false
var mode: Mode = Mode.COOP
var in_match := false
## peer id -> {"name": String, "ready": bool, "slot": int}
var peers: Dictionary = {}
var local_name := ""
var last_error := ""
## The host's room code on the relay ("" while there is none) and where that stands.
var invite_code := ""
var online: Online = Online.OFF
## Whether a friend on this network can reach us directly (the local server is up).
var listening_locally := false

var _connect_timer: SceneTreeTimer
var _relay: RelayPeer
var _beacon: LanBeacon
var _beacon_clock := 0.0
var _beacon_port := DEFAULT_PORT
var _retry_clock := 0.0
## The room code this host held last, asked for again after a reconnect.
var _last_code := ""
## peer id -> smoothed round trip in ms, and when we last heard from it
var _rtt := {}
var _heard := {}
var _ping_clock := 0.0
## Where we joined last ({where, port}) and, after a co-op match the wire
## ended under us, what our body carried (Saves.capture), so "Rejoin" puts
## the same Elian back into the same night. Survives leave() on purpose.
var rejoin_target := {}
var rejoin_snapshot := {}
var rejoin_offered := false
## While a match runs on this host, replicated nodes are shown only to the
## peers in it (attach_sync's filter). One who comes in later sees nothing
## until it has built the match scene (reveal_to) — the replication layer
## sends spawns the moment a peer connects, before any signal of ours runs,
## and spawns that reach a menu are lost. Static so the filter can be.
static var _gated := false
static var _shown := {}


func _ready() -> void:
	local_name = _default_name()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if active:
		_measure(delta)
	if not hosting:
		return
	# The relay can drop a host's room (a restart, a lost connection) while the
	# local game stands: the code goes, a friend on the Wi-Fi can still come,
	# and the room is asked for again every few seconds until it is back.
	if _relay != null and online != Online.FAILED \
			and _relay.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		online = Online.FAILED
		invite_code = ""
		_retry_clock = RELAY_RETRY
		invite_changed.emit()
	if online == Online.FAILED and not in_match and multiplayer.multiplayer_peer is HostPeer:
		_retry_clock -= delta
		if _retry_clock <= 0.0:
			_retry_clock = RELAY_RETRY
			_open_room(multiplayer.multiplayer_peer)
	if _beacon != null and not in_match:
		_beacon_clock -= delta
		if _beacon_clock <= 0.0:
			_beacon_clock = BEACON_INTERVAL
			_beacon.announce(local_name, int(mode), _beacon_port, invite_code)


# ------------------------------------------------------------------ link ---

## The peers whose link we watch: a guest watches the host, a host its guests.
func _watched() -> Array:
	if not active:
		return []
	if not multiplayer.is_server():
		return [1]
	var ids: Array = []
	for id in multiplayer.get_peers():
		ids.append(id)
	return ids


func _measure(delta: float) -> void:
	var now := Time.get_ticks_msec()
	var connected := multiplayer.multiplayer_peer != null \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	if not connected or (not multiplayer.is_server() and multiplayer.get_unique_id() <= 1):
		return
	_ping_clock -= delta
	var send := _ping_clock <= 0.0
	if send:
		_ping_clock = PING_INTERVAL
	for id in _watched():
		if not _heard.has(id):
			_heard[id] = now  # the clock starts when we first look
		if send:
			_ping.rpc_id(id, now)
		if now - int(_heard[id]) > LINK_TIMEOUT * 1000.0:
			if multiplayer.is_server():
				multiplayer.multiplayer_peer.disconnect_peer(id)
				_heard.erase(id)
			else:
				_lost("NET_ERR_TIMEOUT")
				return


## The round trip to whoever we watch, in ms (the worst of them for a host),
## or -1 before the first answer.
func link_ms() -> int:
	var worst := -1
	for id in _watched():
		if _rtt.has(id):
			worst = maxi(worst, int(round(float(_rtt[id]))))
	return worst


## The round trip to one peer in ms, -1 before its first answer (the lobby
## shows it beside each name; a guest knows only its own to the host).
func peer_ms(peer_id: int) -> int:
	return int(round(float(_rtt[peer_id]))) if _rtt.has(peer_id) else -1


## Seconds since the quietest watched peer was last heard; 0 when all is well.
func link_silence() -> float:
	var now := Time.get_ticks_msec()
	var worst := 0.0
	for id in _watched():
		if _heard.has(id):
			worst = maxf(worst, (now - int(_heard[id])) / 1000.0)
	return worst


## Who the quiet one is, for "waiting for …".
func quiet_name() -> String:
	var now := Time.get_ticks_msec()
	var quiet := 1
	var longest := -1
	for id in _watched():
		var silent := now - int(_heard.get(id, now))
		if silent > longest:
			longest = silent
			quiet = id
	return name_of(quiet)


@rpc("any_peer", "call_remote", "unreliable")
func _ping(sent: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	_heard[from] = Time.get_ticks_msec()
	_pong.rpc_id(from, sent)


@rpc("any_peer", "call_remote", "unreliable")
func _pong(sent: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	var now := Time.get_ticks_msec()
	_heard[from] = now
	var sample := float(now - sent)
	_rtt[from] = sample if not _rtt.has(from) else lerpf(float(_rtt[from]), sample, 0.3)


## The wire is gone under a match or a lobby: drop the session and tell
## whoever listens why, the overlay included when a match was running.
func _lost(reason_key: String) -> void:
	var playing := in_match
	# a guest whose co-op night went down can walk back into it
	rejoin_offered = playing and not hosting and mode == Mode.COOP \
		and reason_key != "NET_ERR_VERSION" and not rejoin_target.is_empty()
	last_error = reason_key
	leave()
	closed.emit(reason_key)
	if playing:
		connection_lost.emit(reason_key)


## Asks the relay for a room and hangs it on the host's wires, in place of a
## dead one. Asks for the old code back, so a friend who has it still gets in.
func _open_room(merged: HostPeer) -> void:
	if _relay != null:
		merged.remove(_relay)
	var wanted := _last_code if not _last_code.is_empty() else _wanted_code()
	_relay = RelayPeer.new()
	if _relay.open_host(relay_url(), wanted) != OK:
		_relay = null
		online = Online.FAILED
		_retry_clock = RELAY_RETRY
		return
	merged.add(_relay)
	online = Online.WAITING
	_relay.code_assigned.connect(_on_code_assigned)


func _on_code_assigned(code: String) -> void:
	invite_code = code
	_last_code = code
	online = Online.READY
	invite_changed.emit()


# ---------------------------------------------------------------- session ---

func host(session_mode: Mode, port := DEFAULT_PORT, headless := false) -> Error:
	leave()
	var merged := HostPeer.new()
	# A browser cannot listen; everywhere else a friend on the same network
	# connects straight in, with no relay in between.
	if not OS.has_feature("web"):
		var local := WebSocketMultiplayerPeer.new()
		if local.create_server(port) == OK:
			merged.add(local)
			listening_locally = true
	if not headless and not relay_url().is_empty():
		_open_room(merged)
	if merged.children.is_empty():
		last_error = "NET_ERR_PORT"
		failed.emit(last_error)
		return ERR_CANT_CREATE
	multiplayer.multiplayer_peer = merged
	active = true
	hosting = true
	dedicated = headless
	mode = session_mode
	peers = {}
	if not dedicated:
		peers[1] = {"name": local_name, "ready": true, "slot": 0}
	if LanBeacon.supported() and listening_locally:
		_beacon = LanBeacon.new()
		_beacon_port = port
	lobby_changed.emit()
	invite_changed.emit()
	return OK


## [param address] is either a bare host ("192.168.1.5", "play.example.com")
## or a full URL ("wss://play.example.com/game") for a TLS host behind a proxy,
## which is what a browser needs when the page itself is served over HTTPS.
func join(address: String, port := DEFAULT_PORT) -> Error:
	leave()
	# what our body carried belongs to the night we lost, not to another host's
	if rejoin_target.get("where", "") != address.strip_edges() or int(rejoin_target.get("port", port)) != port:
		rejoin_snapshot = {}
	rejoin_target = {"where": address.strip_edges(), "port": port}
	var peer: MultiplayerPeer
	if is_code(address):
		if relay_url().is_empty():
			last_error = "NET_ERR_NO_RELAY"
			failed.emit(last_error)
			return ERR_UNCONFIGURED
		_relay = RelayPeer.new()
		if _relay.open_join(relay_url(), address) != OK:
			last_error = _relay.error_key
			_relay = null
			failed.emit(last_error)
			return ERR_CANT_CONNECT
		peer = _relay
	else:
		var direct := WebSocketMultiplayerPeer.new()
		var err := direct.create_client(url_for(address, port))
		if err != OK:
			last_error = "NET_ERR_ADDRESS"
			failed.emit(last_error)
			return err
		peer = direct
	multiplayer.multiplayer_peer = peer
	active = true
	hosting = false
	dedicated = false
	peers = {}
	lobby_changed.emit()
	_connect_timer = get_tree().create_timer(CONNECT_TIMEOUT, true, false, true)
	_connect_timer.timeout.connect(_on_connect_timeout)
	return OK


## A room code rather than an address: six letters from the code alphabet,
## nothing that could be a host name with a dot or a port.
static func is_code(text: String) -> bool:
	return not text.contains(".") and not text.contains(":") \
		and not RelayProtocol.normalize_code(text).is_empty()


## The relay to use: the command line first (tests, a private relay), then the
## project setting a release ships with.
static func relay_url() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--relay-url="):
			return arg.trim_prefix("--relay-url=")
	return str(ProjectSettings.get_setting(RELAY_SETTING, ""))


## A code the host asks the relay for (--relay-code=, for the test stand);
## the relay hands out a random one when it is taken or absent.
static func _wanted_code() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--relay-code="):
			return arg.trim_prefix("--relay-code=")
	return ""


static func url_for(address: String, port := DEFAULT_PORT) -> String:
	var trimmed := address.strip_edges()
	if trimmed.contains("://"):
		return trimmed
	if trimmed.contains("]"):  # bracketed IPv6, e.g. [::1]
		return "ws://%s:%d" % [trimmed, port]
	if trimmed.count(":") == 1:
		return "ws://%s" % trimmed
	return "ws://%s:%d" % [trimmed, port]


func leave() -> void:
	_cancel_timeout()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	active = false
	hosting = false
	dedicated = false
	in_match = false
	peers = {}
	_relay = null
	_beacon = null
	invite_code = ""
	_last_code = ""
	_rtt.clear()
	_heard.clear()
	_gated = false
	_shown.clear()
	online = Online.OFF
	listening_locally = false
	lobby_changed.emit()
	invite_changed.emit()


# ------------------------------------------------------------------ lobby ---

func set_ready(value: bool) -> void:
	if not active:
		return
	if multiplayer.is_server():
		_apply_ready(my_id(), value)  # an RPC to yourself is not a thing
	else:
		_set_ready.rpc_id(1, value)


## The host starts the match once everyone is in. Clients ask; the host decides.
func request_start() -> void:
	if not active:
		return
	if is_server():
		_try_start()
	else:
		_request_start.rpc_id(1)


func player_count() -> int:
	return peers.size()


func needed_players() -> int:
	return 2 if mode == Mode.PVP else 1


func everyone_ready() -> bool:
	if peers.size() < needed_players():
		return false
	for id in peers:
		if not peers[id].ready:
			return false
	return true


## Slot 0 / 1: which spawn point and which colour a player gets.
func slot_of(peer_id: int) -> int:
	return int(peers.get(peer_id, {}).get("slot", 0))


func name_of(peer_id: int) -> String:
	return str(peers.get(peer_id, {}).get("name", "?"))


## Who answers a story choice for both players: the host when it plays, else
## the first player who joined. One voice keeps the run's alignment coherent.
func chooser_id() -> int:
	var ids := peer_ids()
	if ids.has(1):
		return 1
	return int(ids[0]) if not ids.is_empty() else 1


func peer_ids() -> Array:
	var ids: Array = peers.keys()
	ids.sort()
	return ids


# ------------------------------------------------------------------ utils ---

## True when we may take authoritative decisions: single player, or the host.
func is_server() -> bool:
	return not active or multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if active else 1


func match_scene() -> String:
	return MODE_SCENES[mode]


## Pausing the tree is a single-player luxury: in a session it would freeze the
## synchronizers and desync everyone, so online we simply never pause.
func set_paused(paused: bool) -> void:
	if active:
		return
	get_tree().paused = paused


## A MultiplayerSynchronizer built in code, so the same properties are mirrored
## whether the node came out of a spawner or was placed by hand. [param props]
## are replication paths relative to [param node], e.g. ".:position".
static func attach_sync(node: Node, props: Array, interval := 0.0) -> MultiplayerSynchronizer:
	var config := SceneReplicationConfig.new()
	for prop in props:
		var path := NodePath(prop)
		config.add_property(path)
		config.property_set_spawn(path, true)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "NetSync"
	sync.replication_config = config
	sync.replication_interval = interval
	sync.delta_interval = interval
	sync.add_visibility_filter(_shown_to)
	sync.add_to_group(SYNC_GROUP)
	node.add_child(sync)
	sync.set_multiplayer_authority(node.get_multiplayer_authority())
	return sync


static func _shown_to(peer: int) -> bool:
	return not _gated or _shown.has(peer)


# --------------------------------------------------------------- late join ---

## A co-op night has room for whoever comes in after it started: a friend
## arriving late, or one whose wire went down coming back. The host lets them
## in hidden, tells them which scene to build, and shows them the world once
## it is built (Run._admit_late calls reveal_to).
func _can_take_late() -> bool:
	return in_match and mode == Mode.COOP and peers.size() < MAX_PLAYERS


## The late peer has built the match scene: everything replicated becomes
## visible to it now, which sends it every body and enemy as they stand.
func reveal_to(peer_id: int) -> void:
	_shown[peer_id] = true
	for sync in get_tree().get_nodes_in_group(SYNC_GROUP):
		(sync as MultiplayerSynchronizer).update_visibility(peer_id)


func is_late(peer_id: int) -> bool:
	return _gated and not _shown.has(peer_id)


@rpc("authority", "call_remote", "reliable")
func _join_running(session_mode: int) -> void:
	mode = session_mode as Mode
	in_match = true
	match_started.emit(int(mode))
	Curtain.change_scene(match_scene(), true)


## "Rejoin" after a lost co-op match: the same place, the same way in.
func can_rejoin() -> bool:
	return rejoin_offered and not rejoin_target.is_empty() and not active


func rejoin() -> Error:
	rejoin_offered = false
	return join(str(rejoin_target.where), int(rejoin_target.port))


# --------------------------------------------------------------- internals ---

func _on_peer_connected(id: int) -> void:
	if not is_server():
		return
	if _can_take_late():
		peers[id] = {"name": "…", "ready": true, "slot": _free_slot()}
		_push_lobby()
		return
	if peers.size() >= MAX_PLAYERS or in_match:
		_kicked.rpc_id(id, "NET_ERR_FULL")
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	peers[id] = {"name": "…", "ready": false, "slot": _free_slot()}
	_push_lobby()


func _on_peer_disconnected(id: int) -> void:
	_rtt.erase(id)
	_heard.erase(id)
	_shown.erase(id)
	if not is_server():
		return
	if in_match and peers.has(id):
		partner_left.emit(name_of(id))
	peers.erase(id)
	_push_lobby()


func _on_connected() -> void:
	_cancel_timeout()
	_hello.rpc_id(1, local_name, game_version())


func _on_connection_failed() -> void:
	_cancel_timeout()
	last_error = "NET_ERR_CONNECT"
	if _relay != null:
		last_error = _relay.error_key if not _relay.error_key.is_empty() else "NET_ERR_RELAY"
	leave()
	failed.emit(last_error)


func _on_server_disconnected() -> void:
	var reason := "NET_ERR_HOST_LEFT"
	if _relay != null and not _relay.error_key.is_empty():
		reason = _relay.error_key
	_lost(reason)


func _on_connect_timeout() -> void:
	if not active or multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_on_connection_failed()


func _cancel_timeout() -> void:
	if _connect_timer != null and _connect_timer.timeout.is_connected(_on_connect_timeout):
		_connect_timer.timeout.disconnect(_on_connect_timeout)
	_connect_timer = null


func _free_slot() -> int:
	var used := []
	for id in peers:
		used.append(peers[id].slot)
	for slot in MAX_PLAYERS:
		if not used.has(slot):
			return slot
	return 0


func _push_lobby() -> void:
	_lobby.rpc(peers, int(mode))
	lobby_changed.emit()


func _try_start() -> void:
	if in_match or not everyone_ready():
		return
	_begin.rpc(int(mode))


## Two builds of the game would desync on the first room, so a guest on
## another version is sent away with a reason instead.
static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


@rpc("any_peer", "reliable")
func _hello(peer_name: String, version := "") -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id):
		return
	if version != game_version():
		_kicked.rpc_id(id, "NET_ERR_VERSION")
		peers.erase(id)
		_push_lobby()
		return
	peers[id].name = peer_name.strip_edges().left(16)
	_push_lobby()
	if in_match and is_late(id):
		_join_running.rpc_id(id, int(mode))


@rpc("any_peer", "reliable")
func _set_ready(value: bool) -> void:
	if is_server():
		_apply_ready(multiplayer.get_remote_sender_id(), value)


func _apply_ready(id: int, value: bool) -> void:
	if not peers.has(id):
		return
	peers[id].ready = value
	_push_lobby()
	if dedicated:
		_try_start()  # nobody to press Start: the referee starts when the room is full


@rpc("any_peer", "reliable")
func _request_start() -> void:
	if is_server():
		_try_start()


@rpc("authority", "call_remote", "reliable")
func _lobby(roster: Dictionary, session_mode: int) -> void:
	peers = roster
	mode = session_mode as Mode
	lobby_changed.emit()


@rpc("authority", "call_local", "reliable")
func _begin(session_mode: int) -> void:
	mode = session_mode as Mode
	in_match = true
	rejoin_snapshot = {}  # a fresh night: nothing to carry back into it
	if multiplayer.is_server():
		_gated = true
		_shown.clear()
		for id in multiplayer.get_peers():
			_shown[id] = true
	match_started.emit(int(mode))
	# A night draws its own chapter card out of the black and opens the curtain
	# itself; a duel has no such thing, so the arena is simply revealed.
	Curtain.change_scene(match_scene(), mode == Mode.COOP)


@rpc("authority", "call_remote", "reliable")
func _kicked(reason_key: String) -> void:
	last_error = reason_key
	leave()
	failed.emit(reason_key)


func _default_name() -> String:
	var who := OS.get_environment("USER")
	if who.is_empty():
		who = OS.get_environment("USERNAME")
	if who.is_empty():
		who = "Elian"
	return who.left(16)


# ----------------------------------------------------------------- headless ---

## Dedicated referee mode, for when both players are in a browser (a browser
## cannot listen for connections, so somebody has to):
##   godot --headless -- --server --port=8910 --mode=coop
## or the relay that rooms by code go through (docs/RELAY.md):
##   godot --headless -- --relay --port=8920
## Returns true when the command line asked for it and the host is up.
func start_from_cli() -> bool:
	var args := {}
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if not arg.begins_with("--"):
			continue
		var pair := arg.substr(2).split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else "true"
	if args.has("relay"):
		var relay_port := int(args.get("port", RelayProtocol.DEFAULT_PORT))
		var relay := RelayServer.new()
		relay.name = "Relay"
		get_tree().root.add_child.call_deferred(relay)
		if relay.listen(relay_port) != OK:
			printerr("[Relay] could not listen on port %d" % relay_port)
			get_tree().quit(1)
			return true
		print("[Relay] listening on ws://0.0.0.0:%d (protocol %d)" % [relay_port, RelayProtocol.VERSION])
		return true
	if not args.has("server"):
		return false
	var port := int(args.get("port", DEFAULT_PORT))
	var session_mode: Mode = Mode.PVP if str(args.get("mode", "coop")) == "pvp" else Mode.COOP
	if host(session_mode, port, true) != OK:
		printerr("[Net] could not listen on port %d" % port)
		get_tree().quit(1)
		return true
	print("[Net] dedicated %s server listening on ws://0.0.0.0:%d" % [
		"pvp" if session_mode == Mode.PVP else "coop", port])
	return true
