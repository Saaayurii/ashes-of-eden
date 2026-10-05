extends Node
class_name PracticeDrills
## The practice yard's drills (docs/PRACTICE.md): what stands across from the
## hero and why. `interact` (E / the touch pad's talk button) changes it.
##   spar  — the foe the yard was opened for, already fighting (the straw man
##           from the main menu);
##   guard — a foe that swings at him with a slow, readable wind-up: hold the
##           guard into the blow to block it, raise it as it lands to parry;
##   volley — a foe that shoots: raise the guard as a bolt arrives and it
##           flies back at its owner, or roll through it;
##   stalk — a foe pacing its patch that has not seen him: come at its back.
##           Once it knows he is there it is put back, unaware, a little later.
## Blocks, parries and backstabs are counted for the yard's list (MoveList),
## and the parries in a row since the last wound, with the best such run.
## Solo only, as the yard is; nothing here is saved.

const DRILLS := ["spar", "guard", "volley", "stalk"]
const NAMES := {"spar": "DRILL_SPAR", "guard": "DRILL_GUARD", "volley": "DRILL_VOLLEY", "stalk": "DRILL_STALK"}
const HINTS := {"spar": "", "guard": "DRILL_GUARD_HINT", "volley": "DRILL_VOLLEY_HINT", "stalk": "DRILL_STALK_HINT"}
## Who stands in for a foe that cannot do the drill (the straw man, a boss,
## one that is always aware): the fallen guard winds up slowest of the walkers.
const GUARD_FOE := "fallen_guard"
const STALK_FOE := "cultist"
## The zealot's bolt is slow to start and quickens: time to read it.
const VOLLEY_FOE := "zealot"
## Seconds a stalked foe stays aware before it is put back unaware.
const STALK_RESET := 1.6
## Where along the yard's floor (room-local x) a stalked foe may be set down:
## the one farthest from the hero, facing away from him.
const STALK_SPOTS := [300.0, 480.0, 660.0, 840.0]

signal changed

var drill := "spar"
var tally := {"blocked": 0, "parried": 0, "backstab": 0, "streak": 0, "best": 0}

var _run: Node
var _foe: Enemy
var _aware_for := 0.0


func _init(run: Node) -> void:
	_run = run
	name = "PracticeDrills"


func _ready() -> void:
	EventBus.player_blocked.connect(func() -> void: _count("blocked"))
	EventBus.player_parried.connect(_on_parried)
	EventBus.player_hurt.connect(func(_fraction: float) -> void:
		if tally.streak > 0:
			tally.streak = 0
			changed.emit())
	EventBus.technique_performed.connect(func(id: String) -> void:
		if id == "backstab":
			_count("backstab"))


## The enemy id the current drill puts in the yard.
func foe_id() -> String:
	var own := Game.practice
	var spec: Dictionary = Data.enemies.get(own, {})
	var behaviour := str(spec.get("behaviour", "walker"))
	var plain: bool = not spec.is_empty() and not spec.get("boss", false) and behaviour not in ["dummy", "seal"]
	match drill:
		"guard":
			return own if plain else GUARD_FOE
		"volley":
			return own if plain and _shoots(spec) else VOLLEY_FOE
		"stalk":
			return own if plain and not spec.get("aware", false) else STALK_FOE
	return own


## The next drill, the old foe cleared away and the new one standing.
func next() -> void:
	drill = DRILLS[(DRILLS.find(drill) + 1) % DRILLS.size()]
	_clear()
	spawn()
	changed.emit()


func spawn() -> void:
	var room: Room = _run.room
	if room == null or (is_instance_valid(_foe) and not _foe.is_dead()):
		return  # one foe at a time: a respawn due may find a new drill's standing
	var id := foe_id()
	var spec: Dictionary = Data.enemies.get(id, {})
	var flying: bool = spec.get("behaviour", "walker") in ["flyer", "boss_ophanim"]
	var gate := room.player_spawn.global_position
	var at := gate + Vector2(room.width * 0.45, -70.0 if flying else -8.0)
	if drill != "stalk":
		_foe = room.spawn_enemy(id, at, true)
		return
	var hero := _hero()
	var hero_x := hero.global_position.x if hero != null else gate.x
	var best := at.x
	for spot in STALK_SPOTS:
		var x := room.global_position.x + float(spot)
		if absf(x - hero_x) > absf(best - hero_x):
			best = x
	at.x = best
	_foe = room.spawn_enemy(id, at, false)
	_foe.facing = 1 if at.x > hero_x else -1  # its back to him
	_aware_for = 0.0


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("interact") and not Game.cutscene:
		next()
		return
	if drill != "stalk" or not is_instance_valid(_foe) or _foe.is_dead():
		return
	if _foe.is_unaware():
		_aware_for = 0.0
		return
	_aware_for += delta
	if _aware_for >= STALK_RESET:
		# seen, or struck: it forgets him and paces again, somewhere else
		Fx.puff(_foe.global_position + Vector2(0, -10), 1.0, Color(0.7, 0.68, 0.75))
		_clear()
		spawn()


## Every living foe off the floor. Not a death: the room's count is given back
## by hand, and the run's respawn (Run._practice_again) is not woken.
func _clear() -> void:
	var room: Room = _run.room
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Enemy:
			if not (node as Enemy).is_dead() and room != null:
				room.alive = maxi(0, room.alive - 1)
			node.remove_from_group("enemies")
			node.queue_free()
	_foe = null


func _hero() -> Player:
	for node in get_tree().get_nodes_in_group("player"):
		if node.is_multiplayer_authority():
			return node as Player
	return null


static func _shoots(spec: Dictionary) -> bool:
	for attack in spec.get("attacks", []) + ([spec.attack] if spec.has("attack") else []):
		if str(attack.get("type", "")) == "ranged":
			return true
	return false


func _on_parried() -> void:
	tally.streak += 1
	tally.best = maxi(tally.best, tally.streak)
	_count("parried")


func _count(what: String) -> void:
	tally[what] += 1
	changed.emit()
