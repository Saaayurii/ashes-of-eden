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

signal lobby_changed
signal match_started(mode: int)
signal failed(reason_key: String)
signal closed(reason_key: String)

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

var _connect_timer: SceneTreeTimer


func _ready() -> void:
	local_name = _default_name()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ---------------------------------------------------------------- session ---

func host(session_mode: Mode, port := DEFAULT_PORT, headless := false) -> Error:
	leave()
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		last_error = "NET_ERR_PORT"
		failed.emit(last_error)
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	hosting = true
	dedicated = headless
	mode = session_mode
	peers = {}
	if not dedicated:
		peers[1] = {"name": local_name, "ready": true, "slot": 0}
	lobby_changed.emit()
	return OK


## [param address] is either a bare host ("192.168.1.5", "play.example.com")
## or a full URL ("wss://play.example.com/game") for a TLS host behind a proxy,
## which is what a browser needs when the page itself is served over HTTPS.
func join(address: String, port := DEFAULT_PORT) -> Error:
	leave()
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url_for(address, port))
	if err != OK:
		last_error = "NET_ERR_ADDRESS"
		failed.emit(last_error)
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	hosting = false
	dedicated = false
	peers = {}
	lobby_changed.emit()
	_connect_timer = get_tree().create_timer(CONNECT_TIMEOUT, true, false, true)
	_connect_timer.timeout.connect(_on_connect_timeout)
	return OK


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
	lobby_changed.emit()


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
	node.add_child(sync)
	sync.set_multiplayer_authority(node.get_multiplayer_authority())
	return sync


# --------------------------------------------------------------- internals ---

func _on_peer_connected(id: int) -> void:
	if not is_server():
		return
	if peers.size() >= MAX_PLAYERS or in_match:
		_kicked.rpc_id(id, "NET_ERR_FULL")
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	peers[id] = {"name": "…", "ready": false, "slot": _free_slot()}
	_push_lobby()


func _on_peer_disconnected(id: int) -> void:
	if not is_server():
		return
	peers.erase(id)
	_push_lobby()


func _on_connected() -> void:
	_cancel_timeout()
	_hello.rpc_id(1, local_name)


func _on_connection_failed() -> void:
	_cancel_timeout()
	last_error = "NET_ERR_CONNECT"
	leave()
	failed.emit(last_error)


func _on_server_disconnected() -> void:
	last_error = "NET_ERR_HOST_LEFT"
	leave()
	closed.emit(last_error)


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


@rpc("any_peer", "reliable")
func _hello(peer_name: String) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id):
		return
	peers[id].name = peer_name.strip_edges().left(16)
	_push_lobby()


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
## Returns true when the command line asked for it and the host is up.
func start_from_cli() -> bool:
	var args := {}
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if not arg.begins_with("--"):
			continue
		var pair := arg.substr(2).split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else "true"
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
