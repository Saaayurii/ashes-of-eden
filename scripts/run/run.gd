extends Node2D
## One run = a chain of rooms (docs/CORE_LOOP.md). Clear the room, the door
## opens, walk through, pick a gift, next room. Death or the last door ends the run.
##
## Co-op (docs/MULTIPLAYER.md) changes who decides, not what happens: the host
## owns the room chain, the enemies and the shared essence bar; each player owns
## their own body and picks their own gifts. Solo, every "host" branch below is
## simply taken by the only peer there is, so the single-player run is unchanged.

## The painted panels of the first location, in order (tools/rooms/painted_rooms.py):
## the graveyard at night, down through the swamp into the catacombs and the
## crypts, the Knight of Ash over the lava, the Ophanim at the gate of the pit.
const ROOMS := [
	"res://scenes/rooms/village_night.tscn",
	"res://scenes/rooms/graveyard_cross.tscn",
	"res://scenes/rooms/graveyard_arches.tscn",
	"res://scenes/rooms/graveyard_tree.tscn",
	"res://scenes/rooms/swamp_moon.tscn",
	"res://scenes/rooms/swamp_red.tscn",
	"res://scenes/rooms/swamp_crypt.tscn",
	"res://scenes/rooms/catacombs_1.tscn",
	"res://scenes/rooms/catacombs_2.tscn",
	"res://scenes/rooms/catacombs_3.tscn",
	"res://scenes/rooms/crypt_threshold.tscn",
	"res://scenes/rooms/crypt_skulls.tscn",
	"res://scenes/rooms/preacher_nave.tscn",
	"res://scenes/rooms/church.tscn",
	"res://scenes/rooms/crypt_lava.tscn",
	"res://scenes/rooms/hell_gate.tscn",
]
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
## How often each rarity is offered, relative to the others (docs/BALANCE.md).
const RARITY_WEIGHT := {"common": 55.0, "rare": 30.0, "epic": 12.0, "legendary": 3.0}
## Ash for a room cleared without a wound, and for one where a boss stood.
## Chests pay 15, a boss 10–25: this is a tip for clean play, not a wage.
const UNSCATHED_ASH := 3
## The practice yard (docs/PRACTICE.md): not one of ROOMS, never saved, entered
## from the bestiary with Game.practice set. Its room_index is PRACTICE_INDEX.
const PRACTICE_ROOM := "res://scenes/rooms/practice_yard.tscn"
const PRACTICE_INDEX := -1
## A fallen sparring partner stands up again after this long.
const PRACTICE_RESPAWN := 1.4
const UNSCATHED_BOSS_ASH := 9
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
## Two bodies should not spawn inside each other.
const SLOT_OFFSET := 26.0
## Co-op forgiveness: whoever fell is back on their feet in the next room, hurt.
const REVIVE_FRACTION := 0.5

var room_index := -1
var room: Room
var kills := 0
var elapsed := 0.0
var _finished := false
var _pending_gifts := 0
var _picking := false
var _advancing := false
var _started := false
var _enemy_counter := 0
var _scene_ready_peers := {}
var _gift_pending := {}
var _dead_peers := {}
var _story_done := false
## The room our body was last placed in. NOT_PLACED, never -1: -1 is the
## practice yard's own index (PRACTICE_INDEX), and a yard that looked "already
## placed" left the hero at the world's origin, off the screen.
const NOT_PLACED := -1000
var _placed_for_room := NOT_PLACED
## The place (data/chapters) the last loaded room belonged to: the card is only
## shown when we walk into a new one.
var _chapter_id := ""
## Bumped by every _load_room, so the card of a room that was replaced while
## the curtain was still up does not talk over the room that replaced it.
var _load_token := 0
## Whether the curtain now closing is hiding a new place (a full card) or the
## next room of the one we are in. Decided when the curtain starts, used when
## it opens again.
var _pending_grand := false
## The run as it stood when this room was entered: what every save writes
## (see Saves). Solo only.
var checkpoint: Dictionary = {}

## Our own body. The other player's is in the same container, owned by them.
var player: Player

@onready var players_root: Node2D = $Players
@onready var entities: Node2D = $Entities
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var enemy_spawner: MultiplayerSpawner = $EnemySpawner
@onready var room_holder: Node2D = $RoomHolder
@onready var dialogue: DialogueBox = $UI/DialogueBox
@onready var cutscene: CutscenePlayer = $UI/Cutscene
## The curtain is an autoload (it outlives this scene); named here so the
## tool scripts can reach it through the run they are driving.
@onready var transition: CanvasLayer = Curtain
@onready var picker: AbilityPicker = $UI/AbilityPicker
@onready var touch_controls: Control = $UI/TouchControls
@onready var run_end: EndScreen = $UI/RunEnd


func _ready() -> void:
	Game.new_run()
	Game.vial = Vials.for_new_night()
	if Game.daily != "":
		# the night of the day: its own vial and its own deal, the same for all
		Game.vial = Daily.vial_of(Game.daily)
		_gift_rng.seed = Daily.seed_of(Game.daily)
	Game.omen = Omens.for_new_night()
	player_spawner.spawn_function = _make_player
	enemy_spawner.spawn_function = _make_enemy
	players_root.child_entered_tree.connect(_on_player_entered)
	# Settings decides, not this file: a player who turned the pad off in
	# Settings had it come back every time a run started (TouchPad._process
	# asked Settings, this line did not, and the two disagreed).
	touch_controls.visible = Settings.touch_enabled()
	# the slowed night (Settings.game_speed), for this run only: menus run at full speed
	Juice.set_base_scale(Settings.time_scale())
	Settings.changed.connect(_on_settings_changed)
	tree_exiting.connect(Juice.set_base_scale.bind(1.0))
	run_end.retry.connect(_restart)
	run_end.to_menu.connect(_to_menu)
	run_end.spar.connect(_spar)
	EventBus.enemy_died.connect(func(_id: StringName, _pos: Vector2) -> void: kills += 1)
	EventBus.level_up.connect(_on_level_up)
	EventBus.enemy_spawn_requested.connect(_on_spawn_requested)
	EventBus.player_rested.connect(_on_player_rested)
	EventBus.player_unscathed.connect(_on_unscathed)
	EventBus.blood_offered.connect(_on_blood_offered)
	# A record from a secret cache is read out over play, like a caption.
	EventBus.note_found.connect(func(note_id: String, _first: bool) -> void:
		dialogue.play(str(Data.notes.get(note_id, {}).get("dialogue", ""))))
	dialogue.answered_locally.connect(_on_local_answer)
	cutscene.story_hook = _cutscene_story
	# the moves taught where they are needed (MoveHints); the yard has its list
	if Game.practice == "":
		var hints := MoveHints.new()
		hints.name = "MoveHints"
		$UI.add_child(hints)
	var deeds := DeedToast.new()
	deeds.name = "DeedToast"
	$UI.add_child(deeds)
	Game.daily_best = false
	if Game.daily != "":
		deeds.say_text(tr("DAILY_START") % tr(str(Vials.spec(Game.vial).get("name", ""))))
	if not Net.active:
		var save := Saves.take_pending()
		_spawn_player(1, 0)
		var jump := _requested_room()
		if Game.practice != "":
			_go_to_room(PRACTICE_INDEX)
		elif jump >= 0:
			# Straight into a room to look at it: no prologue, no intro, no
			# save, hero on his feet — the shape _resume_from already has.
			# Said out loud: a mistyped name falls back to the first room, and
			# without this line that is indistinguishable from being ignored.
			print("run: opening at %s (%d of %d)" %
				[room_names()[jump], jump + 1, ROOMS.size()])
			_go_to_room(jump)
		elif save.is_empty():
			_go_to_room(0)
			_begin()
		else:
			_resume_from(save)
		return
	run_end.allow_retry(multiplayer.is_server())
	Net.closed.connect(_on_session_closed)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	if multiplayer.is_server():
		EventBus.essence_changed.connect(
			func(value: float, _needed: float, level: int) -> void: _net_essence.rpc(value, level))
		_scene_ready_peers[1] = true
		_check_everyone_loaded()
	else:
		# The host must not spawn anything into a scene we have not built yet.
		_scene_loaded.rpc_id(1)


func _process(delta: float) -> void:
	if not _finished:
		elapsed += delta
		Game.elapsed = elapsed


func _is_server() -> bool:
	return Net.is_server()


## Who sent the RPC we are handling. Zero means we sent it to ourselves.
func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


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
	for id in Net.peer_ids():
		_spawn_player(id, Net.slot_of(id))
	_go_to_room(0)
	_net_begin.rpc()


@rpc("authority", "call_local", "reliable")
func _net_begin() -> void:
	_begin()


func _begin() -> void:
	# He is already lying in the grave while the curtain is still up: waiting
	# for it with the body in its default pose showed him standing first.
	if player:
		player.lie_down()
	# The night opens on the chapter card; the angel speaks once we can see.
	while transition.active:
		await get_tree().process_frame
	if not is_inside_tree():
		return
	# Before the angel, Elian alone over a black screen: what he remembers of
	# the rope and the sentence, and where his own knowledge runs out. It holds
	# the controls he has not been given yet and hands them back; any button
	# skips it straight into the wake-up.
	#
	# In full the first night only. This is a roguelite: the fifth restart does
	# not want half a minute of monologue, and a scene worth skipping every time
	# is a scene nobody hears. Afterwards he says the first line and the last —
	# the rope, and that it did not end — which is the whole of it in five
	# seconds. Marked as heard before it plays, so quitting during it still
	# counts: a monologue you walked out on is one you do not want again.
	var heard: bool = Profile.data.get("prologue_seen", false)
	var opening_room := room
	if not heard:
		Profile.data.prologue_seen = true
		Profile.save()
	await cutscene.play("ch1_prologue_short" if heard else "ch1_prologue")
	if not is_inside_tree() or room != opening_room:
		return
	# The angel talks over the fight; hands stay on the controls from second one.
	dialogue.play("ch1_intro")
	# ...except for the first second and a half: Elian rises out of the grave.
	# The captions run over it (docs/CORE_LOOP.md).
	if player:
		player.wake_up()
	await _announce_unlocks()
	_announce_omen()


## Open straight into one room, for looking at it:
##
##     Godot --path . scenes/run/run.tscn -- room=hell_gate
##     Godot --path . scenes/run/run.tscn -- room=14
##
## A name is the scene's own (`ROOMS` holds the paths), an index is a position
## in `ROOMS`. Debug builds only — this is a way to reach a room while working
## on it, not a way to skip the game, and a release build ignores it.
##
## The hero arrives as he starts a night: level one, no gifts, full health.
## A late room is meant to be entered by somebody who earned their way there,
## so it will be harder this way than it is in play. That is the tool working,
## not the balance being wrong.
const ROOM_ARG := "room="


func _requested_room() -> int:
	if not OS.is_debug_build():
		return -1
	return room_from_args(OS.get_cmdline_user_args())


## Which room a command line asks for, or -1 for none. Separate from the
## engine so a test can hand it arguments.
static func room_from_args(args: PackedStringArray) -> int:
	for arg in args:
		if not arg.begins_with(ROOM_ARG):
			continue
		var want := arg.substr(ROOM_ARG.length()).strip_edges()
		if want.is_valid_int():
			return clampi(int(want), 0, ROOMS.size() - 1)
		var names := room_names()
		var found := names.find(want)
		if found >= 0:
			return found
		push_warning("run: no room called '%s'. Try one of: %s" % [want, ", ".join(names)])
	return -1


## The names `room=` accepts, in the order they are played.
static func room_names() -> PackedStringArray:
	var names := PackedStringArray()
	for path in ROOMS:
		names.append(String(path).get_file().get_basename())
	return names


## A saved night picks up at the entrance of the room it was saved in, with
## no wake-up and no intro: the hero is already on his feet.
func _resume_from(save: Dictionary) -> void:
	Saves.restore(save, player)
	var state: Dictionary = save.game_state
	kills = int(state.get("kills", 0))
	elapsed = float(state.get("elapsed", 0.0))
	_go_to_room(maxi(0, Saves.room_index(save.room)))


# ---------------------------------------------------------------- spawning ---

func _spawn_player(peer_id: int, slot: int) -> void:
	var data := {"peer": peer_id, "slot": slot}
	if Net.active:
		player_spawner.spawn(data)
	else:
		players_root.add_child(_make_player(data))


func _make_player(data: Dictionary) -> Node:
	var body: Player = PLAYER_SCENE.instantiate()
	body.name = "P%d" % int(data.peer)
	body.slot = int(data.slot)
	body.set_multiplayer_authority(int(data.peer))
	body.attach_net_sync()
	return body


## Wait for the body's own _ready: its camera and sprite do not exist yet
## at the moment it enters the tree.
func _on_player_entered(node: Node) -> void:
	var body := node as Player
	if body != null:
		body.ready.connect(_on_player_ready.bind(body), CONNECT_ONE_SHOT)


func _on_player_ready(body: Player) -> void:
	if Net.active and body.get_multiplayer_authority() != multiplayer.get_unique_id():
		return
	player = body
	# what the Ash bought (data/relics); a loaded save puts its own stats back over it.
	# Not in the night of the day: every player starts it the same.
	if Game.daily == "":
		Relics.apply(body)
	body.died.connect(_on_local_death)
	_place_local_player()


## Bosses asking for reinforcements come through here so a session replicates them.
func _on_spawn_requested(enemy_id: String, at: Vector2) -> void:
	if not _is_server() or room == null:
		return
	room.spawn_enemy(enemy_id, at, true)


func _spawn_enemy(enemy_id: String, at: Vector2, aware := false) -> Enemy:
	# under a vial of wrath a common one may rise as its elite (data/vials)
	var promote: Dictionary = Vials.rule("promote") if not Net.active else {}
	if promote.has(enemy_id) and randf() < float(Vials.rule("promote_chance")):
		enemy_id = str(promote[enemy_id])
	_enemy_counter += 1
	var data := {"n": _enemy_counter, "id": enemy_id, "pos": at, "aware": aware, "affix": roll_affix(enemy_id)}
	if Net.active:
		return enemy_spawner.spawn(data) as Enemy
	var enemy := _make_enemy(data)
	entities.add_child(enemy)
	return enemy as Enemy


## An elite rises with one affix (data/affixes), each the same odds; a common
## enemy, a boss, and anything in the practice yard rise with none.
static func roll_affix(enemy_id: String) -> String:
	var spec: Dictionary = Data.enemies.get(enemy_id, {})
	if Game.practice != "" or spec.get("boss", false) or not spec.get("tags", []).has("elite") or Data.affixes.is_empty():
		return ""
	var ids: Array = Data.affixes.keys()
	ids.sort()
	return str(ids[randi() % ids.size()])


func _make_enemy(data: Dictionary) -> Node:
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	enemy.name = "E%d" % int(data.n)
	enemy.enemy_id = str(data.id)
	enemy.position = data.pos
	enemy.start_aware = bool(data.get("aware", false))
	enemy.affix = str(data.get("affix", ""))
	enemy.attach_net_sync()
	return enemy


# ------------------------------------------------------------------ rooms ---

## Walking into the next room, in two halves. First every peer draws its
## curtain (scripts/autoload/curtain.gd); only when ours is black does the
## host call the swap, and the swap itself is still one synchronous rpc, as it
## always was. That ordering is not decoration: the host populates the new room
## the moment it has built it, and a peer that was still tearing the old room
## down would free those brand-new enemies as leftovers.
func _go_to_room(index: int) -> void:
	if Net.active:
		if not _is_server():
			return
		_net_cover.rpc(index)
	await _draw_curtain(index)
	if not is_inside_tree():
		return
	if Net.active:
		_net_load_room.rpc(index)
	else:
		_load_room(index)


## A guest is told to cover up; it builds nothing until the host says so.
@rpc("authority", "call_remote", "reliable")
func _net_cover(index: int) -> void:
	_draw_curtain(index)


## The scene a room index stands for: one of ROOMS, or the practice yard.
func _room_path(index: int) -> String:
	return PRACTICE_ROOM if index == PRACTICE_INDEX else ROOMS[index]


func _draw_curtain(index: int) -> void:
	var chapter := Data.chapter_for(_room_path(index))
	# A place we have not been in gets the full page; another room of the same
	# place gets the curtain and its name, and we walk on.
	_pending_grand = not chapter.is_empty() and str(chapter.id) != _chapter_id
	await transition.cover(chapter, _pending_grand, room == null)


@rpc("authority", "call_local", "reliable")
func _net_load_room(index: int) -> void:
	_load_room(index)


## The swap itself: synchronous, the same on every peer. The curtain is
## already down — snap it shut if a slower peer is still burning the old room.
func _load_room(index: int) -> void:
	_load_token += 1
	var token := _load_token
	transition.snap_closed()
	_build_room(index)
	var chapter := Data.chapter_for(_room_path(index))
	_chapter_id = str(chapter.get("id", ""))
	Game.place = _chapter_id
	_open_curtain(chapter, _pending_grand, token)


## Local and unhurried: the card, the curtain opening, and only then whatever
## the room wanted to say. A boss landing behind the black is a boss nobody
## saw land.
func _open_curtain(chapter: Dictionary, grand: bool, token: int) -> void:
	# A room with a scene of its own gets the brisk card: name the place and
	# hand over, instead of two held pauses back to back.
	await transition.reveal(chapter, grand, room != null and room.intro_cutscene != "")
	if token != _load_token or not is_inside_tree() or room == null:
		return
	if room.intro_dialogue != "":
		dialogue.play(room.intro_dialogue)
	if room.intro_cutscene != "":
		cutscene.play(room.intro_cutscene)


func _build_room(index: int) -> void:
	cutscene.abort()
	cutscene.clear()
	if room:
		if room.exited.is_connected(_on_room_exited):
			room.exited.disconnect(_on_room_exited)
		room.queue_free()
	# The spawner owns replicated enemy lifetimes. A guest freeing them here
	# races the host's despawn packets and rejects those packets as unknown IDs.
	# Their authoritative removal arrives under the closed curtain instead.
	if not Net.active or _is_server():
		for leftover in entities.get_children():
			leftover.queue_free()
	room_index = index
	_placed_for_room = NOT_PLACED
	_dead_peers.clear()
	Game.wave = Route.step(ROOMS, index) + 1 if index >= 0 else 0
	# the way walked tonight, for the map (ChapterMap): which side of a fork
	if index >= 0 and not Game.walked.has(ROOMS[index]):
		Game.walked.append(ROOMS[index])
	room = load(_room_path(index)).instantiate()
	room.name = "Room"  # the same node path on every peer
	room.authoritative = _is_server()
	room.spawn_hook = _spawn_enemy
	room_holder.add_child(room)
	if index >= 0 and index != PRACTICE_INDEX:
		LastFall.attach(room, ROOMS[index])  # last night's body, where it fell
	room.cleared.connect(_on_room_cleared)
	room.reopened.connect(_on_room_reopened)
	room.exited.connect(_on_room_exited)
	_place_local_player()
	if not Net.active and player != null and index != PRACTICE_INDEX and Game.daily == "":
		checkpoint = Saves.capture(ROOMS[index], kills, elapsed, player)
		Saves.write(Saves.AUTO, checkpoint)
	if _is_server():
		room.populate()
	if index == PRACTICE_INDEX:
		_practice_begin()
	EventBus.room_started.emit(room_index + 1)


## Our body starts the room at the spawn marker, one slot-width apart from the
## other player's, and gets up again if it fell in the room before.
func _place_local_player() -> void:
	if player == null or room == null or _placed_for_room == room_index:
		return
	_placed_for_room = room_index
	var at: Vector2 = room.player_spawn.global_position + Vector2(player.slot * SLOT_OFFSET, 0)
	if player.is_dead():
		player.revive(at, REVIVE_FRACTION)
	else:
		player.place_in_room(at)
	player.camera.limit_right = room.width
	player.camera.limit_bottom = room.height
	player.camera.reset_smoothing()


func _on_room_cleared() -> void:
	if room_index == PRACTICE_INDEX:
		_practice_again()
		return
	EventBus.room_cleared.emit(room_index + 1)
	if Net.active and multiplayer.is_server():
		_net_room_cleared.rpc()
	if room.outro_cutscene != "":
		cutscene.play(room.outro_cutscene)


## Our body cleared the room without a wound (docs/DEAD_CELLS_GAP_ANALYSIS.md):
## a little Ash, never a gift, more where a boss stood. Ash is the host's to
## count, so a client asks for it; each player earns their own.
func _on_unscathed(_index: int) -> void:
	if room == null:
		return
	var amount := UNSCATHED_ASH
	for pair in room._from_markers:
		if Data.enemies.get((pair[0] as EnemySpawn).enemy_id, {}).get("boss", false):
			amount = UNSCATHED_BOSS_ASH
	Game.unscathed += 1
	if _is_server() or not Net.active:
		Game.ash_earned += amount
	elif multiplayer.get_peers().has(1):
		_net_unscathed.rpc_id(1, amount)
	if player != null:
		Fx.popup(player.global_position + Vector2(0, -44), tr("UNSCATHED_POPUP") % amount, Color(0.85, 0.95, 1.0))
		Fx.sparkle(player.global_position + Vector2(0, -14), Color(0.8, 0.92, 1.0), 12, 10.0)


@rpc("any_peer", "call_remote", "reliable")
func _net_unscathed(amount: int) -> void:
	if _is_server():
		Game.ash_earned += clampi(amount, 0, UNSCATHED_BOSS_ASH)


## Cleared again after a rest: the way opens, and nothing else happens twice.
func _on_room_reopened() -> void:
	if room_index == PRACTICE_INDEX:
		_practice_again()
		return
	if Net.active and multiplayer.is_server():
		_net_door.rpc(true)


@rpc("authority", "call_remote", "reliable")
func _net_door(open: bool) -> void:
	if room:
		room.door.open = open


## Our body rested (scripts/rooms/rest_point.gd): the checkpoint remembers a
## whole body and full flasks — the room itself still restarts from its
## entrance — and the host raises the room's common dead.
func _on_player_rested(room_path: String) -> void:
	if not Net.active and not checkpoint.is_empty() and player != null:
		checkpoint.player.hp = player.stats.max_hp
		checkpoint.player.heal_charges = int(player.stats.heal_charges)
		checkpoint.game_state.rested = Game.rested.keys()
		Saves.write(Saves.AUTO, checkpoint)
	if _is_server():
		_raise_commons()
	elif multiplayer.get_peers().has(1):
		_net_rest_raise.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _net_rest_raise() -> void:
	if _is_server():
		_raise_commons()


func _raise_commons() -> void:
	if room == null:
		return
	if room.respawn_commons() > 0 and Net.active:
		_net_door.rpc(false)


## The host counts the corpses; the clients are told when the way is open.
@rpc("authority", "call_remote", "reliable")
func _net_room_cleared() -> void:
	if room:
		room.door.open = true
		if room.outro_cutscene != "":
			cutscene.play(room.outro_cutscene)
	EventBus.room_cleared.emit(room_index + 1)


func _on_room_exited() -> void:
	if _finished or _advancing or room_index == PRACTICE_INDEX:
		return
	if _is_server():
		_advance()
	else:
		_reached_door.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _reached_door() -> void:
	if multiplayer.is_server() and not _finished and not _advancing:
		_advance()


## Whether the door we just walked through closes a place (or the chapter).
func _door_grants_gift() -> bool:
	if room_index + 1 >= ROOMS.size():
		return true
	var here: Dictionary = Data.chapter_for(ROOMS[room_index])
	# the room this door actually leads to, forks included (either way of a
	# fork is in the same place, so the default one answers for both)
	var next: Dictionary = Data.chapter_for(ROOMS[Route.next_index(ROOMS, room_index)])
	return here.is_empty() or next.is_empty() or here.get("id") != next.get("id")


## Between two rooms: a gift for each player, then onwards. (The story beats
## are the rooms' own scenes now: data/cutscenes, intro_cutscene / outro_cutscene.)
func _advance() -> void:
	_advancing = true
	# We arrive here from the door's body_entered, i.e. mid physics flush. When
	# nothing below awaits (no story, the gift pool run dry) the next room would
	# be built inside that flush and its areas could not be configured.
	await get_tree().process_frame
	# A door gift only where a place ends (data/chapters): one per graveyard,
	# swamp, catacombs… not one per room. With a gift behind every door the
	# chapter handed out ~23 upgrades against the 10–14 docs/BALANCE.md asks
	# for (measured by scripts/tools/balance_probe.gd); essence levels fill the rest.
	if _door_grants_gift():
		if Net.active:
			_gift_pending = {}
			for id in Net.peers:
				_gift_pending[id] = true
			_net_gift_at_door.rpc()
			while not _gift_pending.is_empty() and not _finished:
				await get_tree().process_frame
		else:
			_pending_gifts += 1
			await _offer_gifts()
	while _picking:  # a level-up picker was already open; wait for the queue to drain
		await get_tree().process_frame
	if _finished or not is_inside_tree():
		_advancing = false
		return
	if room_index + 1 >= ROOMS.size():
		_end_run(true)
	else:
		var next := await _next_room()
		if _finished or not is_inside_tree():
			_advancing = false
			return
		await _go_to_room(next)
	# The previous room's door is only freed at the end of the frame. Keep the
	# transition guard up until then so its queued body_entered cannot skip the
	# new (possibly quiet) room before the player sees it.
	await get_tree().physics_frame
	_advancing = false


## Where the door leads. At a fork (data/forks) the way splits and the
## player picks (online, as any story choice: one voice for the group);
## skipped or unanswered, the first way. Out of either way, the fork's "then".
func _next_room() -> int:
	var fork := Route.fork_after(ROOMS[room_index])
	if fork.is_empty():
		return Route.next_index(ROOMS, room_index)
	var picked := [""]
	var on_choice := func(dialogue_id: String, choice_id: String) -> void:
		if dialogue_id == str(fork.dialogue):
			picked[0] = choice_id
	EventBus.choice_made.connect(on_choice)
	await _story(str(fork.dialogue))
	EventBus.choice_made.disconnect(on_choice)
	return Route.next_index(ROOMS, room_index, picked[0])


# ------------------------------------------------------------------ gifts ---

## The host counts the essence for everyone; the clients are told where the
## shared bar stands. No level_up here: the gift is announced by _net_gift_now,
## so both players are offered their card at the same moment.
@rpc("authority", "call_remote", "reliable")
func _net_essence(value: float, level: int) -> void:
	Game.set_essence(value, level)


## Essence bar filled: a gift right now, mid-fight.
func _on_level_up(_level: int) -> void:
	if _finished:
		return
	if Net.active:
		if multiplayer.is_server():
			_net_gift_now.rpc()
		return
	_pending_gifts += 1
	_offer_gifts()


@rpc("authority", "call_local", "reliable")
func _net_gift_now() -> void:
	if player == null:
		return
	_pending_gifts += 1
	_offer_gifts()


## The gift behind the door. The host waits for both players before moving on,
## so nobody is dragged into the next room while still reading their cards.
@rpc("authority", "call_local", "reliable")
func _net_gift_at_door() -> void:
	if player == null:
		return  # a dedicated host referees, it does not collect gifts
	_pending_gifts += 1
	await _offer_gifts()
	while _picking:
		await get_tree().process_frame
	_gift_taken.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _gift_taken() -> void:
	if multiplayer.is_server():
		_gift_pending.erase(_sender())


## The speed can change from the pause menu's settings, mid-night.
func _on_settings_changed() -> void:
	Juice.set_base_scale(Settings.time_scale())


## Gifts are offered one at a time; a level-up during a door gift just queues.
func _offer_gifts() -> void:
	if _picking:
		return
	_picking = true
	while _pending_gifts > 0 and not _finished:
		_pending_gifts -= 1
		var options := _roll_gifts()
		if options.is_empty():
			break
		var gift: Dictionary = await picker.pick(options, _roll_gifts)
		if gift.is_empty():
			_refuse_gift()
		else:
			AbilitySystem.apply(player, gift)
	_picking = false


## A blood altar was opened by our own body: a hand of gifts, and the price
## (Player.pay_blood) only if one is taken — turned down, the hand withdraws
## and nothing is paid. It waits its turn behind any hand already on the table.
func _on_blood_offered(body: Node, price: float) -> void:
	var hero := body as Player
	if hero == null or hero != player or _finished:
		return
	while _picking and is_inside_tree():
		await get_tree().process_frame
	if not is_inside_tree() or _finished:
		return
	_picking = true
	var options := _roll_gifts()
	if not options.is_empty():
		var gift: Dictionary = await picker.pick(options, _roll_gifts,
			tr("BLOOD_PRICE") % roundi(price * 100.0))
		EventBus.blood_settled.emit(not gift.is_empty())
		if gift.is_empty():
			Fx.popup(hero.global_position + Vector2(0, -40), tr("BLOOD_WITHDRAWN"), Color(0.85, 0.8, 0.8), 8)
		else:
			hero.pay_blood(price)
			Game.flags["blood_paid"] = true  # Matthew sees it on him (npc_matthew "blood")
			AbilitySystem.apply(hero, gift)
			if Game.practice == "":
				Profile.count("blood_paid")
	_picking = false
	if _pending_gifts > 0:
		_offer_gifts()  # a level-up while the altar's hand was open waited its turn


## The hand turned down: the body takes a breath instead of a gift
## (Player.refuse_gift), and the profile counts it for the Ascetic's deed.
func _refuse_gift() -> void:
	if player == null:
		return
	player.refuse_gift()
	EventBus.gift_refused.emit()
	if Game.practice == "":
		Profile.count("refusals")


## One gift per path, skipping gifts already taken this run and gifts this
## profile has not reached yet (see [method gift_locked]).
func _roll_gifts() -> Array[Dictionary]:
	var taken := Game.abilities.map(func(a: Dictionary) -> String: return a.id)
	var result: Array[Dictionary] = []
	for path in Game.PATHS:
		var pool := Data.abilities.values().filter(
			func(a: Dictionary) -> bool:
				return a.path == path and not taken.has(a.id) and not gift_locked(a)
		)
		var pick := _weighted_pick(pool)
		if not pick.is_empty():
			result.append(pick)
	return result


## Once the angel has had its say, tell the player what tonight opened up —
## if anything did. It waits for the intro rather than talking over it, and it
## is a caption like any other, so it yields to a real conversation and can be
## walked away from.
func _announce_unlocks() -> void:
	var unlocked := gifts_unlocked_tonight()
	if unlocked.is_empty():
		return
	var names: Array[String] = []
	for ability in unlocked:
		names.append(tr(str(ability.get("name", ""))))
	names.sort()
	while dialogue.is_open() and not _finished and is_inside_tree():
		await get_tree().process_frame
	if not is_inside_tree() or _finished:
		return
	await dialogue.announce(tr("UNLOCKED_TONIGHT") % ", ".join(names))


## The night's omen, said once over the opening (after any gift it unlocked).
func _announce_omen() -> void:
	var spec := Omens.spec(Game.omen)
	if spec.is_empty():
		return
	while dialogue.is_open() and not _finished and is_inside_tree():
		await get_tree().process_frame
	if not is_inside_tree() or _finished:
		return
	await dialogue.announce(tr("OMEN_START") % [tr(str(spec.get("name", ""))), tr(str(spec.get("description", "")))])


## A gift may name the night it starts appearing on (`"unlock_nights": 3` in
## data/abilities). Until the profile has finished that many runs it is not in
## the pool at all, so the fifth night still has a card in it the first one
## could not have shown — a reason to come back that is not a bigger number.
##
## Nothing is locked by default: a gift with no `unlock_nights` has always
## been available and still is. Locks are also ignored in a duel, where both
## players must be offered the same cards whatever they have played before.
static func gift_locked(ability: Dictionary) -> bool:
	var needs := int(ability.get("unlock_nights", 0))
	if needs <= 0 or Net.mode == Net.Mode.PVP or Game.daily != "" or Relics.early(str(ability.get("id", ""))):
		return false
	return int(Profile.data.get("nights", 0)) < needs


## What this night opened up, for the line the run shows on its first room.
## Only the gifts whose night is exactly this one: a list of everything ever
## unlocked would grow into wallpaper nobody reads.
static func gifts_unlocked_tonight() -> Array:
	var nights := int(Profile.data.get("nights", 0))
	if nights <= 0:
		return []
	return Data.abilities.values().filter(
		func(a: Dictionary) -> bool: return int(a.get("unlock_nights", 0)) == nights
	)


## Rarity decides how often a gift is offered at all, never how strong it is
## once it turns up (docs/BALANCE.md). The weights are relative, so a path
## whose commons have all been taken still offers its rare cards rather than
## going empty.
## The night of the day deals from the day's seed (Daily), so every player is
## offered the same cards in the same order for the same choices.
var _gift_rng := RandomNumberGenerator.new()


func _weighted_pick(pool: Array) -> Dictionary:
	var total := 0.0
	for ability in pool:
		total += float(RARITY_WEIGHT.get(ability.get("rarity", "common"), 55.0))
	if total <= 0.0:
		return {}
	var roll := (_gift_rng.randf() if Game.daily != "" else randf()) * total
	for ability in pool:
		roll -= float(RARITY_WEIGHT.get(ability.get("rarity", "common"), 55.0))
		if roll <= 0.0:
			return ability
	return pool.back()


# ------------------------------------------------------------------ story ---

## One voice answers for the group (docs/MULTIPLAYER.md): everyone sees the
## same dialogue, the chooser's buttons are the live ones, and their answer is
## replayed on the other screens so the run keeps one alignment.
func _story(dialogue_id: String) -> void:
	if not Net.active:
		await dialogue.play(dialogue_id)
		return
	_story_done = false
	_net_story.rpc(dialogue_id, Net.chooser_id())
	while is_inside_tree() and Net.active and not _story_done and not _finished:
		await get_tree().process_frame


## A choice inside a scene. Every peer plays the room's scene on its own, but
## only the host opens the conversation (one voice answers for the group); a
## guest waits for it to end, or for its own Skip, or gives up after a while
## if the host skipped the scene and no conversation is coming.
func _cutscene_story(dialogue_id: String) -> void:
	if not Net.active or multiplayer.is_server():
		await _story(dialogue_id)
		return
	var ended := [false]
	var on_end := func(id: String) -> void:
		if id == dialogue_id:
			ended[0] = true
	EventBus.dialogue_finished.connect(on_end)
	var waited := 0.0
	while is_inside_tree() and Net.active and not ended[0] and not _finished and waited < 45.0 and cutscene.playing != "" and not cutscene.skipping():
		await get_tree().process_frame
		if not is_inside_tree():
			break
		waited += get_process_delta_time()
	EventBus.dialogue_finished.disconnect(on_end)


@rpc("authority", "call_local", "reliable")
func _net_story(dialogue_id: String, chooser: int) -> void:
	dialogue.remote = multiplayer.get_unique_id() != chooser
	await dialogue.play(dialogue_id)
	if not is_inside_tree() or not Net.active:
		return
	dialogue.remote = false
	if multiplayer.get_unique_id() == chooser:
		_story_finished.rpc_id(1)


func _on_local_answer(choice_index: int) -> void:
	if Net.active and not dialogue.remote:
		_net_answer.rpc(choice_index)


@rpc("any_peer", "call_remote", "reliable")
func _net_answer(choice_index: int) -> void:
	dialogue.answer_remote(choice_index)


@rpc("any_peer", "call_local", "reliable")
func _story_finished() -> void:
	if Net.active and multiplayer.is_server():
		_story_done = true


# ------------------------------------------------------------------- death ---

func _on_local_death(_body: Player) -> void:
	if room_index == PRACTICE_INDEX:
		_practice_revive()
		return
	if not Net.active:
		_end_run(false)
	else:
		_report_death.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _report_death() -> void:
	if not multiplayer.is_server():
		return
	_dead_peers[_sender()] = true
	for id in Net.peers:
		if not _dead_peers.has(id):
			return  # somebody is still standing; the run goes on
	_end_run(false)


## Somebody closed the game. Their body has to go with them, or every enemy
## that touches it keeps talking to a peer that is not there any more.
func _on_peer_left(id: int) -> void:
	_gift_pending.erase(id)
	_dead_peers.erase(id)
	var body := players_root.get_node_or_null("P%d" % id)
	if body != null:
		body.queue_free()
	if not multiplayer.is_server() or _finished:
		return
	if Net.peers.is_empty():
		_end_run(false)  # nobody left to finish the night


func _on_session_closed(_reason: String) -> void:
	if is_inside_tree():
		Curtain.change_scene(MENU_SCENE)


# --------------------------------------------------------------------- end ---

func _end_run(won: bool) -> void:
	if _finished:
		return
	if Net.active and multiplayer.is_server():
		# Ash is minted by the bosses the host simulates, so it travels with the
		# verdict; otherwise a guest would walk away from a kill empty-handed.
		_net_end.rpc(won, room_index + 1, kills, elapsed, Game.ash_earned)
		return
	_show_end(won, room_index + 1, kills, elapsed, Game.ash_earned)


@rpc("authority", "call_local", "reliable")
func _net_end(won: bool, reached: int, total_kills: int, seconds: float, ash: int) -> void:
	_show_end(won, reached, total_kills, seconds, ash)


func _show_end(won: bool, reached: int, total_kills: int, seconds: float, ash: int) -> void:
	if _finished:
		return
	_finished = true
	kills = total_kills
	# a vial of wrath pays for itself (data/vials: "ash")
	ash = int(round(ash * Vials.ash_multiplier()))
	Game.ash_earned = ash
	# the area reached counts rooms walked, not the index in ROOMS: a fork
	# skipped one of its ways
	var place_index := clampi(reached - 1, 0, ROOMS.size() - 1)
	reached = Route.step(ROOMS, place_index) + 1
	if not Net.dedicated:  # a referee plays no night of its own
		# the body stays where it fell, for tomorrow night (LastFall); a dawn clears it
		if won:
			Profile.data.last_fall = {}
		elif player != null and room != null and room_index >= 0 and room_index < ROOMS.size():
			LastFall.remember(ROOMS[room_index], player.global_position - room.global_position, Game.slain_by)
		Profile.record_run(reached, total_kills, seconds, ash, won)
		if Game.daily != "":
			Game.daily_best = Daily.record(Game.daily, reached, seconds, won)
	$UI/PauseMenu.visible = false
	# A fall beyond the map is already off-screen: show the result at once.
	var end_delay := 0.0 if not won and player != null and player.fell_outside_room else (0.9 if not won else 0.4)
	if end_delay > 0.0:
		await get_tree().create_timer(end_delay).timeout
	if not is_inside_tree():
		return
	# The night goes out the same way a room does. Red ash for a death, gold
	# for the dawn; the verdict is already standing when the screen comes back.
	await transition.cover({"color": "#f2d98c" if won else "#8c1f24"}, true)
	if not is_inside_tree():
		return
	Net.set_paused(true)
	var last := Data.chapter_for(ROOMS[place_index])
	run_end.show_result(won, reached, total_kills, seconds, str(last.get("title", "")))
	await transition.reveal()


func _restart() -> void:
	if Net.active:
		if multiplayer.is_server():
			_net_restart.rpc()
		return
	_reload()


@rpc("authority", "call_local", "reliable")
func _net_restart() -> void:
	_reload()


## Another night, from the first room: keep_closed, because the run that comes
## up behind the black opens on its own chapter card.
func _reload() -> void:
	Curtain.change_scene("", true, func() -> void: get_tree().paused = false)


# --------------------------------------------------------------- practice ---

## The sparring partner stands where the yard wants it, already fighting: a
## flyer up in the air, a walker on the floor across from the hero. The door
## is not a way anywhere here; Escape → the pause menu is the way out.
func _practice_begin() -> void:
	room.door.visible = false
	room.door.open = false
	_practice_spawn()
	if $UI.get_node_or_null("MoveList") == null:
		var moves := MoveList.new()
		moves.name = "MoveList"
		$UI.add_child(moves)


func _practice_spawn() -> void:
	if room == null or not _is_server():
		return
	var spec: Dictionary = Data.enemies.get(Game.practice, {})
	var flying: bool = spec.get("behaviour", "walker") in ["flyer", "boss_ophanim"]
	var at: Vector2 = room.player_spawn.global_position + Vector2(room.width * 0.45, -70.0 if flying else -8.0)
	room.spawn_enemy(Game.practice, at, true)


## Down: the body clears away and another stands up. A boss lingering dimmed
## over its corpse (Enemy._die) is taken off first, or it would stay forever.
func _practice_again() -> void:
	await get_tree().create_timer(PRACTICE_RESPAWN).timeout
	if not is_inside_tree() or room == null or room_index != PRACTICE_INDEX:
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Enemy and (node as Enemy).is_dead():
			node.queue_free()
	room.door.open = false
	_practice_spawn()


## Practice has no death: the hero is back on his feet at the yard's gate.
func _practice_revive() -> void:
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree() or player == null or room_index != PRACTICE_INDEX:
		return
	player.revive(room.player_spawn.global_position, 1.0)
	player.camera.reset_smoothing()


## From the night's end straight into the yard against what killed him: the
## same run scene, the night over, the practice set (docs/PRACTICE.md).
func _spar(enemy_id: String) -> void:
	if Net.active or not Bestiary.can_practise(enemy_id):
		return
	Game.practice = enemy_id
	Game.daily = ""
	_reload()


func _to_menu() -> void:
	Game.practice = ""
	Curtain.change_scene(MENU_SCENE, false, func() -> void:
		get_tree().paused = false
		Net.leave())
