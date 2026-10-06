extends Node2D
## 1v1 duel (docs/MULTIPLAYER.md). Same body, same three hits, same roll — the
## only change is that the sword bites the other player. Rounds are short and
## the score sits between the two health bars: first to [constant ROUNDS_TO_WIN].
##
## The host referees: it owns the score and decides when a round is over, so a
## client cannot award itself a win. Each body is still driven by its own owner.

const ROUNDS_TO_WIN := 3
## Long enough to see who fell, short enough to want the next one.
const ROUND_BREAK := 2.8
## Weapons down while the banner counts you in.
const READY_TIME := 1.4
const ARENA_WIDTH := 960
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var scores := {}
var round_number := 0
var player: Player
var opponent: Player

var _started := false
var _finished := false
var _round_closing := false
var _scene_ready_peers := {}

@onready var players_root: Node2D = $Players
@onready var spawner: MultiplayerSpawner = $PlayerSpawner
@onready var spawns: Node2D = $Spawns
@onready var hud: DuelHud = $UI/DuelHud
@onready var touch_controls: Control = $UI/TouchControls


func _ready() -> void:
	Game.new_run()  # gifts and alignment play no part in a duel; start from clean stats
	Audio.music(&"arena")
	# Babylon at dusk breathes like every room (data/backdrops.json)
	BackdropLife.attach_picture($Parallax/Backdrop as Sprite2D, "arena")
	spawner.spawn_function = _make_player
	players_root.child_entered_tree.connect(_on_player_entered)
	# Settings decides, not this file: a player who turned the pad off in
	# Settings had it come back every time a run started (TouchPad._process
	# asked Settings, this line did not, and the two disagreed).
	touch_controls.visible = Settings.touch_enabled()
	hud.rematch.connect(_on_rematch)
	hud.to_menu.connect(_to_menu)
	if not Net.active:
		# No session: a practice yard, useful for tuning the arena on one machine.
		_spawn_player(1, 0)
		hud.name_yourself(Net.local_name)
		hud.banner("DUEL_PRACTICE", 3.0)
		return
	hud.name_yourself(Net.name_of(Net.my_id()))
	Net.closed.connect(_on_session_closed)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	if multiplayer.is_server():
		_scene_ready_peers[1] = true
		_check_everyone_loaded()
	else:
		_scene_loaded.rpc_id(1)


# ------------------------------------------------------------------ start ---

@rpc("any_peer", "call_remote", "reliable")
func _scene_loaded() -> void:
	if not multiplayer.is_server():
		return
	_scene_ready_peers[multiplayer.get_remote_sender_id()] = true
	_check_everyone_loaded()


func _check_everyone_loaded() -> void:
	if _started or not multiplayer.is_server():
		return
	for id in Net.peers:
		if not _scene_ready_peers.has(id):
			return
	_started = true
	scores = {}
	for id in Net.peer_ids():
		scores[id] = 0
		_spawn_player(id, Net.slot_of(id))
	_net_round.rpc(1, scores)


func _spawn_player(peer_id: int, slot: int) -> void:
	var data := {"peer": peer_id, "slot": slot}
	if Net.active:
		spawner.spawn(data)
	else:
		players_root.add_child(_make_player(data))


func _make_player(data: Dictionary) -> Node:
	var body: Player = PLAYER_SCENE.instantiate()
	body.name = "P%d" % int(data.peer)
	body.slot = int(data.slot)
	body.versus = true  # the one rule a duel adds
	body.set_multiplayer_authority(int(data.peer))
	body.attach_net_sync()
	return body


## Wait for the body's own _ready: its camera does not exist yet at the
## moment it enters the tree.
func _on_player_entered(node: Node) -> void:
	var body := node as Player
	if body != null:
		body.ready.connect(_on_player_ready.bind(body), CONNECT_ONE_SHOT)


func _on_player_ready(body: Player) -> void:
	if not Net.active or body.get_multiplayer_authority() == multiplayer.get_unique_id():
		player = body
		body.died.connect(_on_local_death)
		body.camera.limit_right = ARENA_WIDTH
		_place_local()
	else:
		opponent = body
		hud.track(body, Net.name_of(body.get_multiplayer_authority()))


func _spawn_point(slot: int) -> Vector2:
	var marker := spawns.get_child(slot % spawns.get_child_count()) as Marker2D
	return marker.global_position


func _place_local() -> void:
	if player == null:
		return
	player.revive(_spawn_point(player.slot), 1.0)
	player.facing = 1 if player.slot == 0 else -1
	player.camera.reset_smoothing()


# ------------------------------------------------------------------ rounds ---

@rpc("authority", "call_local", "reliable")
func _net_round(number: int, board: Dictionary) -> void:
	round_number = number
	scores = board
	_round_closing = false
	_refresh_score()
	_place_local()
	if player != null:
		player.controls_enabled = false
	hud.banner(tr("DUEL_ROUND") % number, READY_TIME)
	await get_tree().create_timer(READY_TIME).timeout
	if not is_inside_tree() or _finished:
		return
	if player != null:
		player.controls_enabled = true
	hud.banner("DUEL_FIGHT", 0.8)


func _on_local_death(_body: Player) -> void:
	if not Net.active:
		hud.banner("DUEL_PRACTICE", 2.0)
		_place_local()
		return
	_report_death.rpc_id(1)


## Only the host settles a round, and only once per round.
@rpc("any_peer", "call_local", "reliable")
func _report_death() -> void:
	if not multiplayer.is_server() or _finished or _round_closing:
		return
	var loser := multiplayer.get_remote_sender_id()
	if loser == 0:
		loser = 1
	var winner := loser
	for id in scores:
		if id != loser:
			winner = id
	if winner == loser:
		return  # no opponent left to award it to
	_round_closing = true
	scores[winner] = int(scores.get(winner, 0)) + 1
	_net_round_result.rpc(winner, scores)
	await get_tree().create_timer(ROUND_BREAK).timeout
	if not is_inside_tree() or _finished:
		return
	if int(scores[winner]) >= ROUNDS_TO_WIN:
		_net_match_result.rpc(winner, scores)
	else:
		_net_round.rpc(round_number + 1, scores)


@rpc("authority", "call_local", "reliable")
func _net_round_result(winner: int, board: Dictionary) -> void:
	scores = board
	_refresh_score()
	hud.banner("DUEL_ROUND_WON" if winner == multiplayer.get_unique_id() else "DUEL_ROUND_LOST", ROUND_BREAK)
	if player != null:
		player.controls_enabled = false


@rpc("authority", "call_local", "reliable")
func _net_match_result(winner: int, board: Dictionary) -> void:
	_finished = true
	scores = board
	_refresh_score()
	if player != null:
		player.controls_enabled = false
	hud.show_result(winner == multiplayer.get_unique_id(), _my_score(), _their_score(), _may_rematch())


## Whoever would press Start in the lobby gets to ask for another one — which
## on a dedicated host is a player, not the referee.
func _may_rematch() -> bool:
	if Net.dedicated:
		return Net.my_id() == Net.chooser_id()
	return multiplayer.is_server()


func _refresh_score() -> void:
	hud.set_score(_my_score(), _their_score())


func _my_score() -> int:
	return int(scores.get(Net.my_id(), 0))


func _their_score() -> int:
	var total := 0
	for id in scores:
		if id != Net.my_id():
			total += int(scores[id])
	return total


# ------------------------------------------------------------------- exits ---

func _on_rematch() -> void:
	if not Net.active:
		return
	if multiplayer.is_server():
		_net_rematch.rpc()
	else:
		_ask_rematch.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _ask_rematch() -> void:
	if multiplayer.is_server() and _finished:
		_net_rematch.rpc()


@rpc("authority", "call_local", "reliable")
func _net_rematch() -> void:
	_finished = false
	_round_closing = false
	hud.result.visible = false
	hud.banner("")
	if multiplayer.is_server():
		for id in scores:
			scores[id] = 0
		_net_round.rpc(1, scores)


func _on_peer_left(id: int) -> void:
	scores.erase(id)
	var body := players_root.get_node_or_null("P%d" % id)
	if body != null:
		body.queue_free()  # their body leaves with them
	opponent = null
	hud.track(null, "")
	if multiplayer.is_server() and not _finished and _started:
		_net_match_result.rpc(Net.my_id(), scores)  # walkover


func _on_session_closed(_reason: String) -> void:
	if is_inside_tree():
		Curtain.change_scene(MENU_SCENE)


func _to_menu() -> void:
	Curtain.change_scene(MENU_SCENE, false, func() -> void:
		get_tree().paused = false
		Net.leave())
