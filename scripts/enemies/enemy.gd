extends CharacterBody2D
class_name Enemy
## Generic data-driven enemy. Everything comes from res://data/enemies/*.json
## (see docs/DATA_FORMATS.md):
##   behaviour  walker | flyer | boss_ophanim | caster (a walker that backs
##              away from a player closer than "keep_away", never off a ledge)
##              | seal (hangs where it was put and does nothing but break)
##   seal_phase {"at_hp", "seal", "points": {room: [[x, y], ...]}, "exposed",
##              "exposed_bonus", "sealed_cooldown"}: at that share of its
##              health the boss closes its eyes. Nothing hurts it; one seal
##              appears at each of the room's points, and the boss hangs out of
##              reach and only uses the attacks marked "sealed": true, slower
##              ("sealed_only": true keeps one for this phase alone).
##              When the last seal breaks it opens its eyes, drops low and takes
##              "exposed_bonus" more from every blow for "exposed" seconds,
##              without attacking — the damage phase. Once per fight.
##   attacks    optional telegraphed attacks: [{"type": "melee" | "ranged" | "lunge" | "beam" | "nova", "windup", ...}]
##              (a single "attack" object is accepted too). One is picked by weight among those in range,
##              with a strong penalty for repeating while another is available.
##   sprite     one strip, or {"cell", "fps", "animations": {idle, walk, attack, hurt, death}}
##   sight      {"range", "height", "behind"}: how far ahead it looks (a cone in
##              front of its face, cut by walls and floors) and the radius behind
##              its back it can still feel you in.
##   patrol     {"radius", "speed", "pause"}: how it idles around its spawn until
##              it notices somebody.
##   aware      true = awake from frame one (bosses always are).
##   shield     a share (≤ 0.8) of every blow from the side it faces that its
##              shield turns, while it is not swinging: from its wind-up to the
##              end of the recovery after its blow it is open, and a backstab
##              or a riposte goes round the shield anyway.
##   on_death   {"type": "explode", "radius", "damage", "delay"} — the corpse
##              bursts; {"type": "split", "into": id, "count"} — it comes apart
##              into that many of another kind, already awake.
## The telegraph is the whole point: a wind-up the player can read and roll through.
##
## Nobody is born hostile: an enemy patrols its patch until it sees a player
## (or is touched, hit, or shouted at by a neighbour), pauses one readable beat
## with a "!" and only then hunts. A sword landing on an unaware body is a
## backstab: a guaranteed crit at Player.stats.backstab_multiplier.
##
## Online (docs/MULTIPLAYER.md): enemies are simulated by the host only. Clients
## receive the pose through a synchronizer and the theatre — telegraph, swing,
## beam, death — through RPCs, so both players read the same wind-up.

enum State { PATROL, ALERT, CHASE, WINDUP, STRIKE, RECOVER, DEAD }

const PROJECTILE_SCENE := preload("res://scenes/fx/projectile.tscn")
static var RETARGET_INTERVAL: float = 0.4
## A swing the player parried leaves its owner open this long (data can say
## otherwise: "parry_opening"); a boss gets its feet back in half the time. The
## first blow landed in that window is a riposte, worth half as much again.
static var PARRY_OPENING: float = 0.9
static var RIPOSTE_MULTIPLIER: float = 1.5
## The beat between "!" and the first step towards you.
static var ALERT_TIME: float = 0.4
## An enemy that wakes up shouts; sleepers this close wake with it.
## An enemy at or under this share of its health can be executed outright.
static var EXECUTE_BELOW: float = 0.3
static var SHOUT_RADIUS: float = 90.0
## A hit that stops a body (a flinch, a broken wind-up) also keeps the next
## wind-up back this long after it is on its feet: hurt, a beat, then the
## telegraph, never a swing that grows straight out of the flinch.
static var HIT_ATTACK_DELAY: float = 0.25
## Occasional repeats keep two-move enemies from becoming a strict metronome.
static var REPEAT_ATTACK_WEIGHT: float = 0.18
## Physics layers a look or a step is stopped by: world (1) and ledges (5).
const SOLID_MASK := 1 | 16
## Per behaviour: sight range, sight height, feel-behind radius.
static var SIGHT_DEFAULTS: Dictionary = {
	"walker": [210.0, 70.0, 40.0],
	"flyer": [260.0, 150.0, 48.0],
}
static var PATROL_DEFAULTS: Dictionary = {"radius": 110.0, "speed": 0.45, "pause": [0.8, 2.4]}
## Spacing (docs/ENEMY_AI.md). How many walkers on one side of a player may
## step in to strike at once; the rest wait, each further back by CROWD_STEP.
static var ATTACKERS_PER_SIDE: int = 2
static var CROWD_STEP: float = 22.0
## A flyer hovers at least this far from the player it hunts, and is pushed off
## anyone's body inside PERSONAL_SPACE unless it is mid-attack.
static var FLYER_MIN_GAP: float = 48.0
static var PERSONAL_SPACE: float = 36.0
static var FLOCK_SPACE: float = 30.0
## How far behind its slot a walker waits, rolled once per body [min, max].
static var BAND_DEPTH: Array = [26.0, 52.0]

## How enemies fight is data too (docs/ENEMY_AI.md, docs/GAME_PACKS.md): the
## "enemy_ai" section of data/hero.json, by the lower-case names of the static
## vars above; Data.reload lays it on through apply_ai (from Player.apply_hero).
## One enemy can take its own with "ai": {...} in its JSON, read by _ai.
const AI_KEYS := ["retarget_interval", "parry_opening", "riposte_multiplier", "alert_time",
	"execute_below", "shout_radius", "hit_attack_delay", "repeat_attack_weight", "sight_defaults",
	"patrol_defaults", "attackers_per_side", "crowd_step", "flyer_min_gap", "personal_space",
	"flock_space", "peck_patience", "band_depth"]
## The script's own numbers, taken before the first apply_ai.
static var _ai_defaults: Dictionary = {}

@export var enemy_id: String = "possessed_villager"
## What this elite rose with (data/affixes), "" for none: chosen by the host
## at spawn (Run._spawn_enemy) and carried in the spawn data, so every peer
## builds the same body.
var affix := ""
## Set by the spawner for reinforcements: they arrive already fighting.
@export var start_aware := false

var stats: Dictionary = {}
var hp: float
var state := State.PATROL
## Replicated so a client's minimap can tell a sleeper from a hunter.
var aware := false
var facing := 1:
	set(value):
		facing = value
		if sprite != null:
			sprite.flip_h = value < 0
		if attack_area != null:
			attack_area.scale.x = value

var _max_hp: float
## The last blow's side and weight, for the way a death bleeds (Gore.death).
var _last_away := 1.0
## The pool it wades in (Hazard.liquid_touch), how deep, and when it last said so.
var _liquid: Hazard = null
var _liquid_depth := 0.0
var _liquid_frame := -10
var _last_violent := false
var _last_move := ""
var _attacks: Array = []
var _attack: Dictionary = {}  # the one being performed
## Index in _attacks of the last wind-up begun. Repeats are less likely when
## another move is in range, but never impossible. Host-only choice.
var _last_attack := -1
## How many times in a row _last_attack has been chosen: a third time is
## refused while anything else is in range.
var _repeats := 0
## Its own dice for the choice, so a test can seed it.
var attack_rng := RandomNumberGenerator.new()
var _telegraph_tween: Tween
var _strike_wait := false
## A shield-bearer between its wind-up and the next time it walks: open.
var _guard_down := false
var _strike_frame := 0
var _strike_aim := Vector2.ZERO
var _beam_lines: Array[Line2D] = []
var _beam_hit := {}  # player -> already burned this beam
var _contact_cd := 0.0
var _attack_cd := 0.0
var _open_left := 0.0  # parried: the riposte window (see PARRY_OPENING)
var _state_left := 0.0
var _knockback := Vector2.ZERO
## What it hunts: a player, or a body of a hostile side (Faction, chapter III).
var _target: Node2D
var _retarget := 0.0
var _bob := randf() * TAU
var _hover_side := 1.0 if randf() < 0.5 else -1.0
var _hover_timer := 0.0
## A short tactical retreat after a melee strike, then a fresh approach.
var _disengage_left := 0.0
var _retreat_distance := 38.0
var _retreat_speed := 0.7
## Flyers alternate near and far per instance; the phase changes only in
## CHASE, never in the middle of a telegraphed attack.
var _fly_phase := 0
var _fly_phase_left := 0.0
var _lunge_dir := Vector2.ZERO
## Between blows a walker keeps a distance it picks now and then inside its
## band (_pace_goal); _band_depth is how deep this one's band is.
var _pace_goal := 0.0
var _pace_left := 0.0
var _band_depth := 36.0
## How many of its kind stand between it and its target on its side (walkers)
## or hunt the same player (flyers). Recounted with the target.
var _crowd_rank := 0
## How long a flyer has been on its attack run without striking: past
## PECK_PATIENCE it gives the run up and pulls out (never hang on the body).
var _peck_time := 0.0
static var PECK_PATIENCE: float = 0.35
var _summoned := false
var _home := Vector2.ZERO  # where it was spawned; the patrol is around this
var _patrol_goal := Vector2.ZERO
var _patrol_wait := 0.0
var _has_anim := {}
## An animation the studio's sandbox asks it to show instead of fighting ("" = fight).
var showcase := ""
## What the body's scale springs back to after a hit punch.
var _visual_scale := Vector2.ONE
var _simulated := true  # false on a client: the host drives this body
## Optional glow from data ("light": colour, radius, energy): spirits, relics, the boss.
var _light: GlowLight
var _shadow: Sprite2D
## The seal phase (see "seal_phase" above): eyes closed, warded, waiting on its seals.
var _sealed := false
var _seal_done := false
## The damage phase after the seals break: open, low, not attacking.
var _exposed_left := 0.0
## A hex (the Hex of Ashes skill): every blow it takes is worth _hex_bonus
## more while _hex_left runs. Decided by the host, like damage.
var _hex_left := 0.0
var _hex_bonus := 0.0
## A training dummy's quiet time left before it is whole again.
var _dummy_rest := 0.0
var _ward: Line2D
## Two armies (scripts/enemies/faction.gd): spared = its side spares the hero
## tonight and he has not struck it (replicated, for the minimap and the nod);
## holds_door = it keeps the room's door shut (Room); felled_by_soldier = the
## last blow on it came from another body, not a player.
var spared := false
var holds_door := true
## Wormwood's water has risen ("flood"): once a fight.
var _flooded := false
var felled_by_soldier := false
var _turned := false
var _nod_at := -10000

@onready var body: ColorRect = $Body
@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hp_bar: ColorRect = $HpBar
@onready var contact_area: Area2D = $ContactArea
@onready var attack_area: Area2D = $AttackArea
@onready var attack_shape: CollisionShape2D = $AttackArea/Shape
## Whatever is drawn: the sprite when data provides one, the rectangle otherwise.
@onready var visual: CanvasItem = body


## Same contract as Player.attach_net_sync: the run calls this on a fresh
## enemy, before it enters the tree.
func attach_net_sync() -> void:
	if Net.active and not has_node("NetSync"):
		Net.attach_sync(self, [".:position", ".:facing", ".:aware", ".:spared"])


## Lays the "enemy_ai" numbers over the script's own (a key it does not know is
## skipped; the validator names it). A second call starts from the defaults.
static func apply_ai(doc: Dictionary) -> void:
	var script: GDScript = load("res://scripts/enemies/enemy.gd")
	if _ai_defaults.is_empty():
		_ai_defaults = enemy_ai()
	for key: String in AI_KEYS:
		var value = _ai_defaults[key]
		var given = doc.get(key)
		if given != null and typeof(given) == typeof(value) or (given is int and value is float) \
				or (given is float and value is int):
			value = given
		if _ai_defaults[key] is float:
			value = float(value)
		elif _ai_defaults[key] is int:
			value = int(value)
		script.set(key.to_upper(), value.duplicate(true) if value is Array or value is Dictionary else value)


## How enemies fight as it stands, by data name.
static func enemy_ai() -> Dictionary:
	var script: GDScript = load("res://scripts/enemies/enemy.gd")
	var out := {}
	for key: String in AI_KEYS:
		var value = script.get(key.to_upper())
		out[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	return out


## One of the AI numbers for this body: its own "ai" in the JSON, else the game's.
func _ai(key: String) -> Variant:
	var own = stats.get("ai", {})
	if own is Dictionary and own.has(key):
		return own[key]
	return get(key.to_upper())


func _ready() -> void:
	sprite.frame_changed.connect(_attack_frame_changed)
	stats = Data.enemies.get(enemy_id, {}).duplicate(true)  # scaled per instance below
	if stats.is_empty():
		push_error("Unknown enemy id: %s" % enemy_id)
	Profile.record_seen(enemy_id)
	# Walkers need a floor (gravity, is_on_floor, ledge checks); flyers must not
	# snap to one. The scene file cannot know which we are, so decide here.
	motion_mode = MOTION_MODE_FLOATING if _is_flying() else MOTION_MODE_GROUNDED
	floor_snap_length = 0.0 if _is_flying() else 4.0
	# Difficulty mode × time scaling (docs/BALANCE.md), applied once at spawn.
	stats.hp = float(stats.get("hp", 20)) * Game.enemy_hp_multiplier()
	var damage_scale := Game.enemy_damage_multiplier()
	stats.damage = float(stats.get("damage", 0)) * damage_scale
	for attack in stats.get("attacks", []) + ([stats.attack] if stats.has("attack") else []):
		attack.damage = float(attack.get("damage", 0)) * damage_scale
	_apply_affix()
	_max_hp = stats.hp
	hp = _max_hp
	_attacks = stats.get("attacks", [])
	if stats.has("attack"):
		_attacks = [stats.attack]
	attack_rng.randomize()
	_attack_cd = randf_range(0.3, 1.0)  # not everyone swings on frame one
	_retreat_distance = randf_range(28.0, 48.0)
	_retreat_speed = randf_range(0.55, 0.8)
	var band: Array = _ai("band_depth")
	_band_depth = randf_range(float(band[0]), float(band[1]))
	_fly_phase = randi() % 2
	_fly_phase_left = randf_range(0.9, 1.7)
	var size := float(stats.get("size", 12))
	body.size = Vector2.ONE * size
	body.position = -body.size / 2.0
	body.color = Color(stats.get("color", "#b03030"))
	body.pivot_offset = body.size / 2.0
	hp_bar.visible = false
	attack_area.monitoring = false
	for attack in _attacks:
		if attack.get("type", "") == "melee":
			var reach := float(attack.get("reach", 30))
			(attack_shape.shape as RectangleShape2D).size = Vector2(reach, 24)
			attack_shape.position = Vector2(reach / 2.0 + 2.0, -6)
	if stats.has("sprite"):
		_setup_sprite(stats.sprite)
	_visual_scale = visual.get("scale")
	if stats.has("light"):
		var spec: Dictionary = stats.light
		_light = Fx.light(self, Vector2(0, -10), Color(spec.get("color", stats.get("color", "#ffffff"))),
			float(spec.get("radius", 50)), float(spec.get("energy", 0.7)), float(spec.get("flicker", 0.0)), 0.15)
	_mark_elite()
	_show_affix()
	if not _is_flying():
		_shadow = Fx.shadow(self, Vector2(0, 11), size * 1.6, 0.7)
	if _is_flying():
		collision_mask &= ~16  # ledges are for walkers; a flyer passes through them
	_home = global_position
	_patrol_wait = randf_range(0.2, 1.2)
	# one that waits (chapter II) is never awake until struck, a boss included
	aware = start_aware or (not waits() and (bool(stats.get("aware", false)) or bool(stats.get("boss", false))))
	state = State.CHASE if aware else State.PATROL
	if Faction.of(self) != "":
		Faction.soldiers += 1
		tree_exiting.connect(func() -> void: Faction.soldiers -= 1)
	spared = Faction.spares(Faction.of(self))
	holds_door = Room.holds_door(enemy_id) and not spared
	if Net.active:
		_simulated = multiplayer.is_server()
		set_physics_process(_simulated)
	if _simulated and stats.get("boss", false):
		EventBus.boss_hp_changed.emit(stats.get("name", ""), hp, _max_hp)


## An elite reads as one before it swings: a low ember glow under it and a
## mote rising off it now and then (tags "elite", never a boss — a boss has
## its own bar). Same on every peer: it is drawn from the data.
const ELITE_EMBER := Color(0.95, 0.38, 0.28)


func _mark_elite() -> void:
	if not stats.get("tags", []).has("elite") or stats.get("boss", false):
		return
	var glow := Fx.light(self, Vector2(0, 4), ELITE_EMBER, 38.0, 0.75, 0.3, 0.2)
	if glow != null:
		glow.name = "EliteMark"
	var motes := Timer.new()
	motes.name = "EliteMotes"
	motes.wait_time = 0.5
	motes.autostart = true
	motes.timeout.connect(func() -> void:
		if state != State.DEAD and visible and is_inside_tree():
			Fx.ash(global_position + Vector2(randf_range(-6.0, 6.0), -4.0), ELITE_EMBER * Color(1, 1, 1, 0.8), 3, 18.0, 6.0))
	add_child(motes)


## An affix changes the numbers, never the wind-ups: hp, damage, speed and
## the rest between blows are multiplied, armour added (capped like any armour).
func _apply_affix() -> void:
	var spec: Dictionary = Data.affixes.get(affix, {})
	if spec.is_empty():
		affix = ""
		return
	var mods: Dictionary = spec.get("mods", {})
	stats.hp = float(stats.hp) * float(mods.get("hp", 1.0))
	stats.speed = float(stats.get("speed", 50)) * float(mods.get("speed", 1.0))
	stats.armor = minf(0.5, float(stats.get("armor", 0.0)) + float(mods.get("armor", 0.0)))
	var damage := float(mods.get("damage", 1.0))
	var cooldown := float(mods.get("cooldown", 1.0))
	stats.damage = float(stats.damage) * damage
	for attack in stats.get("attacks", []) + ([stats.attack] if stats.has("attack") else []):
		attack.damage = float(attack.get("damage", 0)) * damage
		attack.cooldown = float(attack.get("cooldown", 1.5)) * cooldown


## The affix's name over the elite's head, in its colour.
func _show_affix() -> void:
	if affix == "":
		return
	var label := Label.new()
	label.name = "Affix"
	label.text = tr(str(Data.affixes[affix].get("name", affix)))
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", Color(str(Data.affixes[affix].get("color", "#ffffff"))))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(80, 10)
	label.position = Vector2(-40, -float(stats.get("size", 12)) - 30.0)
	label.z_index = 6
	# the room's night (Ambient, a CanvasModulate) darkens everything in the
	# world; the name is a word to read, so it is lifted back to its own colour
	var night := get_tree().get_first_node_in_group("ambient") as CanvasModulate
	if night != null and night.visible:
		var c := night.color
		label.self_modulate = Color(minf(4.0, 1.0 / maxf(c.r, 0.25)), minf(4.0, 1.0 / maxf(c.g, 0.25)),
			minf(4.0, 1.0 / maxf(c.b, 0.25)))
	add_child(label)


## A pool holds this walker this frame (Hazard): how deep, 0..1. Flyers pass over.
func liquid_touch(liquid: Hazard, depth: float) -> void:
	_liquid = liquid
	_liquid_depth = depth
	_liquid_frame = Engine.get_physics_frames()


func _liquid_now() -> float:
	if _liquid == null or not is_instance_valid(_liquid) or Engine.get_physics_frames() - _liquid_frame > 2:
		_liquid = null
		return 0.0
	return _liquid_depth


## Its pace in a pool: the kind's enemy.drag, by how deep it stands.
func _liquid_drag() -> float:
	if _liquid_now() <= 0.0:
		return 1.0
	return lerpf(1.0, float(_liquid.spec.get("enemy", {}).get("drag", 1.0)), _liquid_depth)


## A walker's gravity, held up and slowed in a pool like the hero's.
func _fall(delta: float) -> void:
	var depth := _liquid_now()
	if depth <= 0.0:
		velocity.y += 1100.0 * delta
		return
	var body_spec: Dictionary = _liquid.spec.get("body", {})
	velocity.y += 1100.0 * delta * lerpf(1.0, float(body_spec.get("buoyancy", 1.0)), depth)
	var sink := float(body_spec.get("sink_speed", INF))
	if depth > 0.35 and velocity.y > sink:
		velocity.y = move_toward(velocity.y, sink, 2400.0 * delta)


## What a pool of blood gives back (Hazard, host only): the bar follows.
func liquid_heal(amount: float) -> void:
	if state == State.DEAD or hp >= _max_hp:
		return
	hp = minf(_max_hp, hp + amount)
	hp_bar.size.x = 14.0 * clampf(hp / _max_hp, 0.0, 1.0)
	Fx.sparkle(global_position + Vector2(0, -10), Color(0.8, 0.15, 0.2), 3, 8.0)


func _is_flying() -> bool:
	return stats.get("behaviour", "walker") in ["flyer", "boss_ophanim", "seal"]


func is_dead() -> bool:
	return state == State.DEAD


func _fell_out_of_room() -> bool:
	var rooms := get_tree().get_nodes_in_group("room")
	if rooms.is_empty():
		return false
	# During a transition the old room may still be queued for deletion. The
	# newest one owns enemies spawned for the current section.
	var current_room := rooms.back() as Room
	if current_room == null:
		return false
	var here := current_room.to_local(global_position)
	var bottom := current_room.void_kill_y if current_room.void_kill_y >= 0.0 else float(current_room.height) + 24.0
	return here.y > bottom or here.x < -96.0 or here.x > float(current_room.width) + 96.0


## True while it has not noticed anybody: a sword landing now is a backstab.
func is_unaware() -> bool:
	return state == State.PATROL or state == State.ALERT


## "waits" in the JSON (docs/CHAPTER2.md): it sees nobody, feels no touch and
## hears no shout — only a blow wakes it — and it never holds the door
## (Room.holds_door). The city where nobody fights is made of these.
func waits() -> bool:
	return bool(stats.get("waits", false))


func _setup_sprite(spec: Dictionary) -> void:
	# "like": another creature's strips and cell (a cult caller is a cultist in
	# another robe); "tint" colours the drawing, not the telegraph flashes.
	if spec.has("like"):
		var borrowed: Dictionary = Data.enemies.get(str(spec.like), {}).get("sprite", {}).duplicate(true)
		for key in spec:
			if key != "like":
				borrowed[key] = spec[key]
		spec = borrowed
	var frames := SpriteFrames.new()
	var cell := Vector2i(int(spec.get("frame_w", 24)), int(spec.get("frame_h", 28)))
	if spec.has("cell"):
		cell = Vector2i(int(spec.cell[0]), int(spec.cell[1]))
	var fps := float(spec.get("fps", 6))
	if spec.has("animations"):
		for anim in spec.animations:
			var loop: bool = anim in ["idle", "walk", "special"]
			if Fx.add_strip(frames, spec.animations[anim], cell, fps, anim, loop):
				_has_anim[anim] = true
	elif spec.has("path"):
		if Fx.add_strip(frames, spec.path, cell, fps, "idle", true):
			_has_anim["idle"] = true
	if _has_anim.is_empty():
		return
	sprite.sprite_frames = frames
	var art_scale := float(spec.get("scale", 1.0))
	sprite.scale = Vector2.ONE * art_scale
	# The collision box is 22 px tall around the origin, so its sole is at +11; the
	# strips keep one transparent row under the feet. Anything less than +12 here
	# and the whole bestiary hovers a few pixels above the ground.
	sprite.position.y = -cell.y * art_scale / 2.0 + 12.0
	# a flyer's strip padded above and below for a big spell keeps its body
	# where it was (tools/art/build_bestiary_assets.py writes the padding)
	sprite.position.y += float(spec.get("pad_y", 0)) * art_scale
	if spec.has("tint"):
		sprite.self_modulate = Color(str(spec.tint))
	sprite.play("idle")
	sprite.frame = randi() % maxi(1, frames.get_frame_count("idle"))  # desync the crowd
	# particles on its actions (data/action_fx.json): anchors measured on this body —
	# the sole 11 px under the origin, the head near the top of the drawn cell
	var top := 12.0 - cell.y * art_scale + float(spec.get("pad_y", 0)) * art_scale
	ActionFx.attach(self, sprite, enemy_id, {"feet": Vector2(0, 11), "body": Vector2(0, (top + 11.0) * 0.5),
		"head": Vector2(0, top + 6.0), "hand": Vector2(12, -14), "back": Vector2(-6, 4)})
	sprite.visible = true
	body.visible = false
	visual = sprite


var studio_debug := false


func _physics_process(delta: float) -> void:
	if studio_debug:
		queue_redraw()
	if state == State.DEAD:
		return
	_time_fight(delta)
	# A walker can be knocked into a shaft and a flyer can drift past a side
	# boundary. Both must use the normal death path: Room.alive owns the exit.
	if _fell_out_of_room():
		if Net.active:
			_net_die.rpc()
		_die()
		return
	if showcase != "":
		# the studio's sandbox shows one animation (StudioLive): it stands and plays it
		# over and over, the death included, so the artist can look at every frame
		if _is_flying():
			velocity = Vector2.ZERO
		else:
			_hold(delta)
			move_and_slide()
		if _has_anim.has(showcase) and (sprite.animation != showcase or not sprite.is_playing()):
			sprite.play(showcase)
			sprite.frame = 0
		return
	if stats.get("behaviour", "walker") == "seal":
		# it hangs where it was set; a blow only plays its crack
		velocity = Vector2.ZERO
		if not sprite.is_playing():
			_play("idle")
		return
	if stats.get("behaviour", "walker") == "dummy":
		# the practice yard's straw man: it stands, rocks when struck, and
		# fills up again once left alone (_apply_damage keeps it standing)
		_hold(delta)
		_knockback = _knockback.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		_dummy_rest -= delta
		if _dummy_rest <= 0.0 and hp < _max_hp:
			hp = _max_hp
			hp_bar.visible = false
		if not sprite.is_playing():
			_play("idle")
		return
	_exposed_left = maxf(0.0, _exposed_left - delta)
	_hex_left = maxf(0.0, _hex_left - delta)
	if Game.cutscene:
		# A scene is playing: everybody holds where they stand (walkers keep
		# their gravity, a flyer hangs still so the scene can place it).
		if _is_flying():
			velocity = Vector2.ZERO
		else:
			_hold(delta)
			move_and_slide()
		return
	_contact_cd = maxf(0.0, _contact_cd - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_disengage_left = maxf(0.0, _disengage_left - delta)
	_open_left = maxf(0.0, _open_left - delta)
	_state_left -= delta
	if state == State.PATROL:
		_patrol(delta)
		_knockback = _knockback.move_toward(Vector2.ZERO, 700.0 * delta)
		move_and_slide()
		var seen: Node2D = null if waits() else _spot_player()
		if seen != null:
			_notice(seen)
		return
	if state == State.ALERT:
		_hold(delta)
		move_and_slide()
		if _state_left <= 0.0:
			_set_state(State.CHASE, 0.0)
		return
	_retarget -= delta
	if _target == null or not is_instance_valid(_target) or _target.call("is_dead") or _retarget <= 0.0 \
			or not _hostile_to(_target):
		_retarget = float(_ai("retarget_interval"))
		_acquire_target()
		_crowd_rank = _count_crowd()
	if _target == null:
		if Faction.of(self) != "" and state == State.CHASE:
			_set_state(State.PATROL, 0.0)  # a soldier with nobody left to fight goes back to its watch
		return

	var to_target := _target.global_position - global_position
	match state:
		State.CHASE:
			_chase(to_target, delta)
			if _attack_cd <= 0.0:
				var choice := _choose_attack(to_target)
				if choice >= 0:
					_repeats = _repeats + 1 if choice == _last_attack else 0
					_last_attack = choice
					_attack = _attacks[choice]
					_begin_windup(to_target)
		State.WINDUP:
			_hold(delta)
			if _state_left <= 0.0:
				_strike(to_target)
		State.STRIKE:
			if _strike_wait:
				_hold(delta)
				move_and_slide()
				return
			if _attack.get("type") == "lunge":
				velocity = _lunge_dir * float(_attack.get("lunge_speed", 400))
			else:
				_hold(delta)
			if _attack.get("type") == "beam":
				_beam_tick()
			if _state_left <= 0.0:
				_clear_beam()
				if Net.active:
					_net_clear_beam.rpc()
				# Let a real seven-frame attack finish across recovery instead of
				# snapping back to idle after the hit frame.
				var recover := maxf(float(_attack.get("recover", 0.35)), _attack_animation_remaining())
				_set_state(State.RECOVER, recover)
		State.RECOVER:
			_hold(delta)
			if _state_left <= 0.0:
				_set_state(State.CHASE, 0.0)
	_knockback = _knockback.move_toward(Vector2.ZERO, 700.0 * delta)
	move_and_slide()

	# Only a telegraphed lunge hurts by bodily contact. Walkers and flyers
	# otherwise use their attack hitboxes: simply closing distance must not
	# become an invisible attack, or add a second hit to a melee swing.
	var contact_damage := 0.0
	if state == State.STRIKE and _attack.get("type") == "lunge":
		contact_damage = float(_attack.get("damage", stats.get("damage", 5)))
	if contact_damage > 0.0 and _contact_cd <= 0.0:
		for touched in contact_area.get_overlapping_bodies():
			if touched is Player and not touched.is_dead() and _hostile_to(touched):
				_contact_cd = float(stats.get("attack_interval", 0.8))
				touched.take_damage(contact_damage, self)
		# a lunge into a hostile soldier (Faction): the bodies collide, so touching is near
		for other in _hostile_bodies():
			if _contact_cd > 0.0:
				break
			var touch := (float(stats.get("size", 12)) + float(other.stats.get("size", 12))) * 0.5 + 8.0
			if not other.is_dead() and global_position.distance_to(other.global_position) <= touch:
				_contact_cd = float(stats.get("attack_interval", 0.8))
				other.take_damage(contact_damage * Faction.damage_between(), self)


## The nearest player still on their feet. In co-op both of you are fair game.
## A soldier (Faction) also hunts the bodies of a hostile side within its
## aggro range that it can see, and passes over a player its side spares.
func _acquire_target() -> void:
	var best: Node2D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("player"):
		var candidate := node as Player
		if candidate == null or candidate.is_dead() or not _hostile_to(candidate):
			continue
		var distance := candidate.global_position.distance_squared_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	if Faction.soldiers > 0:
		var aggro := float(stats.get("aggro_range", 380))
		for node in get_tree().get_nodes_in_group("enemies"):
			var other := node as Enemy
			if other == null or other == self or not _hostile_to(other):
				continue
			var distance := other.global_position.distance_squared_to(global_position)
			if distance < best_distance and distance <= aggro * aggro and (other == _target or _can_see(other)):
				best_distance = distance
				best = other
	_target = best


## Whether it fights [param other]: a player unless its side spares him, a body
## of a hostile side (Faction.hostile); never a boss, and a boss only the players.
func _hostile_to(other: Node) -> bool:
	if other == null or not is_instance_valid(other) or other.call("is_dead"):
		return false
	if other is Player:
		return not spared
	if Faction.soldiers <= 0 or not other is Enemy or other == self:
		return false
	if stats.get("boss", false) or (other as Enemy).stats.get("boss", false):
		return false
	return Faction.hostile(Faction.of(self), Faction.of(other))


## Whether it can see [param who] from where it stands (Faction.break_truce asks
## which comrades saw the blow).
func sees(who: Node2D) -> bool:
	return _can_see(who)


## The hero struck it while its side spared him (Faction.break_truce, host): it
## hunts him for the rest of the room and keeps the door shut again.
func turn_on_hero() -> void:
	if not spared or is_dead():
		return
	spared = false
	_turned = true
	_retarget = 0.0
	if not holds_door and Room.holds_door(enemy_id):
		holds_door = true
		EventBus.enemy_holds_changed.emit(self, true)
	_turn_fx()
	if Net.active:
		_net_turn_fx.rpc()


## A side was chosen (Faction.flag_set): whether it spares the hero now, on the
## host, unless he has already broken the truce with it.
func refresh_spared() -> void:
	if not _simulated or is_dead() or _turned:
		return
	var now := Faction.spares(Faction.of(self))
	if now == spared:
		return
	spared = now
	var holds := Room.holds_door(enemy_id) and not spared
	if holds != holds_door:
		holds_door = holds
		EventBus.enemy_holds_changed.emit(self, holds)
	if spared and _target is Player:
		_target = null
		_retarget = 0.0


func _turn_fx() -> void:
	Fx.popup(global_position + Vector2(0, -28), "!", Faction.color(Faction.of(self)), 12)
	visual.modulate = Color(1.8, 1.2, 1.0)
	create_tween().tween_property(visual, "modulate", Color.WHITE, 0.3)


@rpc("authority", "call_remote", "reliable")
func _net_turn_fx() -> void:
	_turn_fx()


## A spared soldier that sees the hero lowers its weapon for a beat: a dim mark
## of its side's colour over the head, no "!" (docs/CHAPTER3.md §9).
func _nod() -> void:
	_play("idle")
	var dim := Faction.color(Faction.of(self)).darkened(0.35)
	dim.a = 0.6
	Fx.popup(global_position + Vector2(0, -26), "·", dim, 10)


@rpc("authority", "call_remote", "unreliable")
func _net_nod() -> void:
	_nod()


# ------------------------------------------------------------- awareness ---

## Idle around the spawn point: walkers pace their ledge and turn at its edge,
## flyers drift between points in the air. Nothing here hurts anybody.
func _patrol(delta: float) -> void:
	var spec: Dictionary = stats.get("patrol", {})
	var radius := float(spec.get("radius", PATROL_DEFAULTS.radius))
	var speed := float(stats.get("speed", 50)) * float(spec.get("speed", PATROL_DEFAULTS.speed)) * _liquid_drag()
	var pause: Array = spec.get("pause", PATROL_DEFAULTS.pause)
	if _is_flying():
		_bob += delta * 2.0
		if _patrol_wait > 0.0:
			_patrol_wait -= delta
			velocity = Vector2.ZERO
			if _patrol_wait <= 0.0:
				_patrol_goal = _home + Vector2(randf_range(-radius, radius), randf_range(-radius * 0.5, radius * 0.5))
		else:
			var to_goal := _patrol_goal - global_position
			if to_goal.length() < 6.0 or get_slide_collision_count() > 0:
				_patrol_wait = randf_range(float(pause[0]), float(pause[1]))
				velocity = Vector2.ZERO
			else:
				velocity = to_goal.normalized() * speed
				if absf(to_goal.x) > 4.0:
					facing = 1 if to_goal.x > 0.0 else -1
		velocity.y += sin(_bob) * 10.0
		velocity += _knockback
		_play("walk" if velocity.length() > 6.0 else "idle")
		return
	_fall(delta)
	velocity.x = _knockback.x
	if _patrol_wait > 0.0:
		_patrol_wait -= delta
		if _patrol_wait <= 0.0:
			# Walk the other way from where we stand, somewhere inside the patch.
			var side := -signf(global_position.x - _home.x)
			if side == 0.0:
				side = 1.0 if randf() < 0.5 else -1.0
			_patrol_goal = Vector2(_home.x + side * randf_range(radius * 0.4, radius), _home.y)
			facing = 1 if _patrol_goal.x > global_position.x else -1
		_play("idle")
		return
	var dx := _patrol_goal.x - global_position.x
	if absf(dx) < 4.0 or _blocked_ahead():
		_patrol_wait = randf_range(float(pause[0]), float(pause[1]))
		_play("idle")
		return
	facing = 1 if dx > 0.0 else -1
	velocity.x += facing * speed
	_play("walk")


## A wall in the face, or no floor under the next step.
## A wall or a drop in the direction a caster is backing into.
func _ledge_behind(direction: float) -> bool:
	var saved := facing
	facing = 1 if direction > 0.0 else -1
	var blocked := _blocked_ahead()
	facing = saved
	return blocked


func _blocked_ahead() -> bool:
	var space := get_world_2d().direct_space_state
	var ahead := Vector2(facing * 10.0, 0.0)
	var wall := PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -4), global_position + ahead + Vector2(0, -4), 1)
	wall.exclude = [get_rid()]
	if not space.intersect_ray(wall).is_empty():
		return true
	var step := PhysicsRayQueryParameters2D.create(global_position + ahead + Vector2(0, 4), global_position + ahead + Vector2(0, 26), SOLID_MASK)
	step.exclude = [get_rid()]
	return space.intersect_ray(step).is_empty()


## The first player in sight: in the cone ahead with nothing solid between us,
## or close enough behind to be felt. Touching one counts as well.
func _spot_player() -> Node2D:
	for touched in contact_area.get_overlapping_bodies():
		if touched is Player and not touched.is_dead() and _hostile_to(touched):
			return touched
	for node in get_tree().get_nodes_in_group("player"):
		var candidate := node as Player
		if candidate == null or candidate.is_dead() or not _can_see(candidate):
			continue
		if _hostile_to(candidate):
			return candidate
		if spared and Time.get_ticks_msec() - _nod_at > 4000:
			_nod_at = Time.get_ticks_msec()
			_nod()
			if Net.active:
				_net_nod.rpc()
	if Faction.soldiers > 0:
		for node in get_tree().get_nodes_in_group("enemies"):
			var other := node as Enemy
			if other != null and _hostile_to(other) and _can_see(other):
				return other
	return null


func _can_see(who: Node2D) -> bool:
	var spec: Dictionary = stats.get("sight", {})
	var defaults: Array = SIGHT_DEFAULTS["flyer" if _is_flying() else "walker"]
	# an omen may thicken the dark (data/omens: "enemy_sight")
	var sight_range := float(spec.get("range", defaults[0])) * float(Vials.rule("enemy_sight"))
	var height := float(spec.get("height", defaults[1]))
	var behind := float(spec.get("behind", defaults[2]))
	var d := who.global_position - global_position
	if d.length() <= behind:
		return true
	if d.x * facing < 0.0 or absf(d.x) > sight_range or absf(d.y) > height:
		return false
	var eyes := global_position + Vector2(0, -10)
	var query := PhysicsRayQueryParameters2D.create(eyes, who.global_position + Vector2(0, -8), SOLID_MASK)
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## "!" — one readable beat, then the hunt. Sleepers nearby wake with us.
func _notice(who: Node2D, shout := true) -> void:
	if not is_unaware() or waits() or not _hostile_to(who):
		return
	_target = who
	aware = true
	_set_state(State.ALERT, float(_ai("alert_time")))
	if who is Player:
		# the gift Held Truce: the first blow waits at least this long
		_attack_cd = maxf(_attack_cd, float((who as Player).stats.get("truce_hold", 0.0)))
	var d := who.global_position - global_position
	if absf(d.x) > 4.0:
		facing = 1 if d.x > 0.0 else -1
	_alert_fx()
	if Net.active:
		_net_alert.rpc(facing)
	if shout:
		for node in get_tree().get_nodes_in_group("enemies"):
			var other := node as Enemy
			if other != null and other != self and other.is_unaware() \
					and other.global_position.distance_to(global_position) <= float(_ai("shout_radius")):
				other._notice(who, false)


## What the sword sounds like landing on this body: its own clips if the
## bestiary has them (<voice>_impact_1..3), otherwise the set for whatever it
## is made of ("material" in the JSON: flesh, cloth, mail, plate, bone,
## feather, spirit, gold), otherwise the generic blow. Asked for by whoever
## swung, so the hit is heard the moment it lands and not a round trip later.
func impact_sound() -> StringName:
	var own := StringName("%s_impact" % str(stats.get("voice", enemy_id)))
	if Audio.has_clip(own):
		return own
	var material := StringName("hit_%s" % str(stats.get("material", "flesh")))
	return material if Audio.has_clip(material) else &"hit"


## Every creature in the bestiary has its own voice: clips named
## <voice>_alert / _attack / _hurt / _death in assets/audio/sfx ("voice" in the
## enemy's data, its id by default). Where one is missing the generic cue plays.
func _voice(kind: String, fallback: StringName, volume_db := 0.0) -> void:
	var own := StringName("%s_%s" % [str(stats.get("voice", enemy_id)), kind])
	if Audio.has_clip(own):
		Audio.play_at(own, global_position, volume_db)
	elif fallback != &"":
		Audio.play_at(fallback, global_position, volume_db)


func _alert_fx() -> void:
	_play("idle")
	_voice("alert", &"", -6.0)
	Fx.popup(global_position + Vector2(0, -28), "!", Color(1.0, 0.85, 0.4), 12)
	visual.modulate = Color(1.6, 1.3, 1.0)
	create_tween().tween_property(visual, "modulate", Color.WHITE, 0.25)


@rpc("authority", "call_remote", "reliable")
func _net_alert(new_facing: int) -> void:
	facing = new_facing
	_alert_fx()


func _chase(to_target: Vector2, delta: float) -> void:
	var speed := float(stats.get("speed", 50)) * _liquid_drag()
	var aggro := float(stats.get("aggro_range", 380))
	var chase := Vector2.ZERO
	match stats.get("behaviour", "walker"):
		"flyer":
			_bob += delta * 3.0
			_fly_phase_left -= delta
			if _fly_phase_left <= 0.0:
				_fly_phase = 1 - _fly_phase
				_fly_phase_left = randf_range(1.0, 2.0)
			# It hovers on a ring around the player, out of the way of the sword
			# and never parked on the body: in, then out and higher, each flyer on
			# its own timing and a little further out than the one before it.
			var side := signf(to_target.x) if absf(to_target.x) > 4.0 else float(facing)
			var distance := maxf(float(_ai("flyer_min_gap")), float(stats.get("hover_distance", 60.0))) \
				+ (34.0 if _fly_phase == 1 else 0.0) + 16.0 * _crowd_rank
			var height := 34.0 + 18.0 * _fly_phase + 10.0 * _crowd_rank
			var pecking := false
			if _disengage_left > 0.0:
				distance += 60.0  # it struck: out and up before anything else
				height += 26.0
			elif _attack_cd <= 0.05:
				var reach := _melee_reach()
				if reach > 0.0:
					pecking = true  # an attack run, only with the blow ready: in to its beak's reach at head height
					distance = reach * 0.7
					height = 16.0
			if pecking:
				_peck_time += delta
				if _peck_time > float(_ai("peck_patience")):
					# the run came to nothing (another move was picked, or none):
					# out, rather than hanging over his head
					pecking = false
					_peck_time = 0.0
					_disengage_left = randf_range(0.6, 0.9)
					distance += 60.0
					height += 26.0
			else:
				_peck_time = 0.0
			var goal := _leashed(to_target - Vector2(side * distance, height))
			if goal.length() > 6.0:
				chase = goal.normalized() * minf(speed, goal.length() * 3.0)
			chase.y += sin(_bob) * 18.0
			if not pecking:
				chase += _personal_space(to_target) * speed * 2.0
			chase += _flock() * speed
			velocity = chase + _knockback
		"boss_ophanim":
			_bob += delta * 2.0
			_hover_timer -= delta
			if _hover_timer <= 0.0:
				_hover_side = -_hover_side
				_hover_timer = randf_range(2.5, 4.5)
			var hover := _target.global_position + Vector2(150.0 * _hover_side, -100.0)
			hover.y = clampf(hover.y, 70.0, 250.0)
			if _sealed:
				# high over the fight, out of a sword's reach: the seals are the way
				hover = _target.global_position + Vector2(120.0 * _hover_side, -190.0)
				hover.y = clampf(hover.y, 40.0, 250.0)
			elif _exposed_left > 0.0:
				# spent: it sinks to where a blade can reach it
				hover = _target.global_position + Vector2(70.0 * _hover_side, -38.0)
			var goal := hover - global_position
			if goal.length() > 8.0:
				chase = goal.normalized() * minf(speed, goal.length() * 3.0)
			chase.y += sin(_bob) * 20.0
			velocity = chase + _knockback
		_:
			_fall(delta)
			# The close stance is for a ready attack. During cooldown, hold just
			# outside melee range; after a strike, backstep before returning.
			var stop_at := float(stats.get("size", 12)) * 0.5 + 11.0
			var melee_range := 0.0
			for attack in _attacks:
				if attack.get("type") == "ranged":
					stop_at = maxf(stop_at, float(attack.get("range", 0)) * 0.6)
				elif attack.get("type") == "melee":
					melee_range = maxf(melee_range, float(attack.get("range", 30)))
			if stats.get("behaviour", "walker") == "caster":
				var preferred := maxf(stop_at, float(stats.get("keep_away", 90)))
				if _disengage_left > 0.0:
					preferred += _retreat_distance
				if absf(to_target.x) < preferred - 5.0:
					var away := -signf(to_target.x)
					if not _ledge_behind(away):
						chase.x = away * speed * _retreat_speed
				elif absf(to_target.x) > preferred + 12.0 and absf(to_target.x) < aggro:
					var toward := signf(to_target.x)
					if not _ledge_behind(toward):
						chase.x = toward * speed * 0.75
			elif _disengage_left > 0.0 and melee_range > 0.0 and not stats.get("boss", false):
				var retreat_dir := -signf(to_target.x)
				if absf(to_target.x) < stop_at + _retreat_distance and not _ledge_behind(retreat_dir):
					chase.x = retreat_dir * speed * _retreat_speed
			elif melee_range <= 0.0 or stats.get("boss", false):
				# a shooter holds its range; a boss simply comes on
				if absf(to_target.x) < aggro and absf(to_target.x) > stop_at:
					chase.x = signf(to_target.x) * speed
			elif _attack_cd <= 0.3 and _crowd_rank < int(_ai("attackers_per_side")):
				# a blow is ready and it is its turn: in to striking distance
				if absf(to_target.x) < aggro and absf(to_target.x) > stop_at:
					chase.x = signf(to_target.x) * speed
			else:
				chase.x = _keep_distance(to_target, melee_range, speed, aggro, delta)
			velocity.x = chase.x + _knockback.x
			velocity.y += _knockback.y
	if absf(to_target.x) > 4.0:
		facing = 1 if to_target.x > 0.0 else -1
	_play("walk" if chase.length() > 1.0 else "idle")


## Stand still (walkers keep gravity) while winding up / striking / recovering.
func _hold(delta: float) -> void:
	match stats.get("behaviour", "walker"):
		"flyer", "boss_ophanim":
			# _knockback already represents the full impulse; adding it to last
			# frame's velocity again made flyers accelerate away without bound.
			velocity = _knockback
			if state == State.RECOVER and _target != null and is_instance_valid(_target):
				# a lunge that ended on the player does not stay there
				velocity += _personal_space(_target.global_position - global_position) * 220.0
		_:
			velocity.x = _knockback.x
			_fall(delta)


## Between blows: a walker holds a distance just outside its reach, paced
## in and out now and then, further back for each of its kind ahead of it on
## this side (so a crowd forms a queue, not a stack). Returns the x speed.
func _keep_distance(to_target: Vector2, melee_range: float, speed: float, aggro: float, delta: float) -> float:
	var gap := absf(to_target.x)
	var toward := signf(to_target.x)
	var band_in := melee_range + 12.0 + float(_ai("crowd_step")) * _crowd_rank
	_pace_left -= delta
	if _pace_left <= 0.0 or _pace_goal < band_in or _pace_goal > band_in + _band_depth:
		_pace_left = randf_range(0.6, 1.4)
		_pace_goal = band_in + randf_range(0.0, _band_depth)
	if gap < _pace_goal - 6.0:
		if not _ledge_behind(-toward):
			return -toward * speed * 0.55  # a step back, still facing the player
	elif gap > _pace_goal + 6.0 and gap < aggro:
		return toward * speed * 0.7
	return 0.0


## How many of its kind are ahead of it: walkers between it and its target
## on the same side and level, or flyers hunting the same player.
func _count_crowd() -> int:
	if _target == null or stats.get("boss", false):
		return 0
	var flying := _is_flying()
	var side := signf(global_position.x - _target.global_position.x)
	var gap := absf(global_position.x - _target.global_position.x)
	var rank := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var other := node as Enemy
		if other == null or other == self or other.is_dead() or other.is_unaware() \
				or other._target != _target or other._is_flying() != flying or other.stats.get("boss", false):
			continue
		if flying:
			rank += 1 if other.get_instance_id() < get_instance_id() else 0
			continue
		if signf(other.global_position.x - _target.global_position.x) != side \
				or absf(other.global_position.y - global_position.y) > 40.0:
			continue
		var other_gap := absf(other.global_position.x - _target.global_position.x)
		if other_gap < gap or (other_gap == gap and other.get_instance_id() < get_instance_id()):
			rank += 1
	return rank


## The longest melee reach among its attacks, 0 without one.
func _melee_reach() -> float:
	var reach := 0.0
	for attack in _attacks:
		if attack.get("type") == "melee":
			reach = maxf(reach, float(attack.get("range", 30)))
	return reach


## A flyer inside a player's personal space is pushed off the body, harder
## the deeper it is: flying past is fine, parking on top is not.
func _personal_space(to_target: Vector2) -> Vector2:
	var chest := to_target + Vector2(0, -12)
	var depth := chest.length()
	var space := float(_ai("personal_space"))
	if depth >= space:
		return Vector2.ZERO
	var away := -chest.normalized() if depth > 0.5 else Vector2(-float(facing), -1.0).normalized()
	return away * (1.0 - depth / space)


## Flyers keep off one another, so a flock reads as several birds.
func _flock() -> Vector2:
	var push := Vector2.ZERO
	var space := float(_ai("flock_space"))
	for node in get_tree().get_nodes_in_group("enemies"):
		var other := node as Enemy
		if other == null or other == self or other.is_dead() or not other._is_flying():
			continue
		var apart := global_position - other.global_position
		if apart.length() < space:
			push += (apart.normalized() if apart.length() > 0.5 else Vector2.UP) * (1.0 - apart.length() / space)
	return push


## Weighted random among the attacks whose range and phase conditions hold.
## "from_hp": 0.66 makes an attack available only once hp is at or below 66 %;
## "until_hp": 0.66 retires it after that. Phases change behaviour, not HP.
## The last attack is less likely while another one is available; a single
## attack (or only one in range) repeats normally. Returns an index, -1 for none.
func _choose_attack(to_target: Vector2) -> int:
	if _exposed_left > 0.0:
		return -1  # the damage phase: open and not fighting back
	var candidates: Array[int] = []
	var fraction := hp / _max_hp
	for i in _attacks.size():
		var attack: Dictionary = _attacks[i]
		if fraction > float(attack.get("from_hp", 1.0)) or fraction <= float(attack.get("until_hp", 0.0)):
			continue
		if _sealed and not attack.get("sealed", false):
			continue
		if not _sealed and attack.get("sealed_only", false):
			continue
		if _in_attack_range(attack, to_target):
			candidates.append(i)
	if candidates.is_empty():
		return -1
	if candidates.size() > 1 and _repeats >= 1:
		candidates.erase(_last_attack)  # twice is a habit, three times a loop
	var total := 0.0
	var repeat := float(_ai("repeat_attack_weight"))
	for i in candidates:
		var weight := maxf(0.0, float(_attacks[i].get("weight", 1.0)))
		total += weight * (repeat if candidates.size() > 1 and i == _last_attack else 1.0)
	var roll := attack_rng.randf() * total
	for i in candidates:
		var weight := maxf(0.0, float(_attacks[i].get("weight", 1.0)))
		roll -= weight * (repeat if candidates.size() > 1 and i == _last_attack else 1.0)
		if roll <= 0.0:
			return i
	return candidates.back()


func _in_attack_range(attack: Dictionary, to_target: Vector2) -> bool:
	var range := float(attack.get("range", 30))
	match attack.get("type", "melee"):
		"melee":
			return absf(to_target.x) <= range and absf(to_target.y) <= 26.0
		"beam":
			# Only worth firing when the player is roughly on one of the two axes.
			return to_target.length() <= range and (absf(to_target.y) < 60.0 or absf(to_target.x) < 60.0)
		"nova":
			return to_target.length() <= float(attack.get("trigger_range", range))
		"summon":
			return to_target.length() <= range and _summons_near(attack) < int(attack.get("max_alive", 2))
		_:
			return to_target.length() <= range


func _begin_windup(to_target: Vector2) -> void:
	_set_state(State.WINDUP, float(_attack.get("windup", 0.5)))
	facing = 1 if to_target.x >= 0.0 else -1
	var beam: bool = _attack.get("type", "melee") == "beam"
	var length := float(_attack.get("length", 420))
	var thickness := float(_attack.get("thickness", 26))
	var color := str(_attack.get("color", "#ffe9a8"))
	_telegraph(_state_left, beam, length, thickness, color, str(_attack.get("animation", "attack")), str(_attack.get("telegraph_fx", "glow")))
	if Net.active:
		_net_telegraph.rpc(facing, _state_left, beam, length, thickness, color, str(_attack.get("animation", "attack")), str(_attack.get("telegraph_fx", "glow")))


## The telegraph: a bright pulse the player can read from across the room, and
## the breath before the swing for anyone looking the other way. Runs on every
## peer already, so the sound rides along without an RPC of its own.
func _telegraph(duration: float, beam := false, length := 420.0, thickness := 26.0, color := "#ffe9a8", animation := "attack", effect := "glow") -> void:
	_voice("attack", &"enemy_windup", -11.0)
	_play(animation, true)
	if effect == "none":
		if _telegraph_tween != null:
			_telegraph_tween.kill()
			_telegraph_tween = null
		visual.modulate = Color.WHITE
		return
	visual.modulate = Color(1.0, 0.85, 0.7)
	if _telegraph_tween != null:
		_telegraph_tween.kill()
	_telegraph_tween = create_tween()
	_telegraph_tween.tween_property(visual, "modulate", Color(2.2, 1.6, 1.2), duration * 0.8)
	_telegraph_tween.tween_property(visual, "modulate", Color.WHITE, 0.1)
	# The wind-up also brightens the room around the enemy: readable in the dark.
	Fx.flash(global_position + Vector2(0, -10), Color(color), 60.0, duration, 0.6)
	if beam:
		_show_beam(true, duration, length, thickness, color)


@rpc("authority", "call_remote", "reliable")
func _net_telegraph(new_facing: int, duration: float, beam: bool, length: float, thickness: float, color: String, animation := "attack", effect := "glow") -> void:
	facing = new_facing
	_telegraph(duration, beam, length, thickness, color, animation, effect)


## A wind-up that will not land (staggered, parried) stops looking like one:
## the glow stops building, the beam goes and the raised pose drops, so the
## player reads "broken" instead of waiting for a blow that never comes.
func _cancel_telegraph() -> void:
	if _telegraph_tween != null and _telegraph_tween.is_running():
		_telegraph_tween.kill()
		# Eased rather than snapped: a hit flash may be fading on the same colour.
		create_tween().tween_property(visual, "modulate", Color.WHITE, 0.12)
	_telegraph_tween = null
	_clear_beam()
	_play("idle")


@rpc("authority", "call_remote", "reliable")
func _net_cancel_telegraph() -> void:
	_cancel_telegraph()


## hit_frame is zero-based in data; the studio shows human frame numbers.
## Wait for the actual sprite frame, so speed changes and hit stop stay in sync.
func _strike(to_target: Vector2) -> void:
	var animation := str(_attack.get("animation", "attack"))
	_strike_frame = 0
	if _has_anim.has(animation):
		# Live sprite replacements can have fewer frames than the saved attack.
		_strike_frame = clampi(int(_attack.get("hit_frame", 0)), 0, sprite.sprite_frames.get_frame_count(animation) - 1)
	if _strike_frame > 0:
		_strike_aim = to_target
		_set_state(State.STRIKE, 0.0)
		_strike_wait = true
		# A timed attack is one impact, even when special is also an idle loop.
		sprite.sprite_frames.set_animation_loop(animation, false)
		_play(animation, true)
		sprite.play(animation)
		if Net.active:
			_net_attack_start.rpc(animation)
		return
	_resolve_strike(to_target)


func _attack_frame_changed() -> void:
	if Net.active and not multiplayer.is_server():
		return
	if _strike_wait and state == State.STRIKE and sprite.frame >= _strike_frame:
		_strike_wait = false
		_resolve_strike(_strike_aim)


@rpc("authority", "call_remote", "reliable")
func _net_attack_start(animation: String) -> void:
	if _has_anim.has(animation):
		sprite.sprite_frames.set_animation_loop(animation, false)
	_play(animation, true)
	sprite.play(animation)


func _resolve_strike(to_target: Vector2) -> void:
	if enemy_id == StudioLive.ID:
		StudioLive.report("УДАР", self)
	_attack_cd = float(_attack.get("cooldown", 1.5))
	if _sealed:
		_attack_cd *= float(stats.get("seal_phase", {}).get("sealed_cooldown", 1.6))
	if _attack.get("type") in ["melee", "lunge"] and not stats.get("boss", false):
		# Include the strike and recovery in the timer, leaving a visible
		# backstep once CHASE resumes without delaying the next ready attack.
		_disengage_left = minf(_attack_cd * 0.8,
			float(_attack.get("recover", 0.35)) + 0.18 + randf_range(0.55, 0.8))
	elif stats.get("behaviour", "walker") == "caster" and _attack.get("type") in ["ranged", "summon", "beam"]:
		_disengage_left = minf(_attack_cd * 0.7,
			float(_attack.get("recover", 0.35)) + 0.25 + randf_range(0.5, 0.75))
	var animation := str(_attack.get("animation", "attack"))
	var own_sfx := StringName(str(_attack.get("sfx", "")))
	if own_sfx != &"" and Audio.has_clip(own_sfx):
		Audio.play_at(own_sfx, global_position, -5.0)
	match _attack.get("type", "melee"):
		"melee":
			_set_state(State.STRIKE, 0.18)
			_play(animation)
			Audio.play(&"enemy_swing", -8.0)
			if Net.active:
				_net_strike.rpc("melee", animation)
			_melee_hit()
		"ranged":
			_set_state(State.STRIKE, 0.25)
			_play(animation)
			_fire_round(_attack, to_target)
			# a volley: the same round again volley_gap later, aimed anew
			for round_index in range(1, maxi(1, int(_attack.get("volley", 1)))):
				get_tree().create_timer(float(_attack.get("volley_gap", 0.25)) * round_index, false) \
					.timeout.connect(_fire_round.bind(_attack, Vector2.ZERO))
		"lunge":
			_set_state(State.STRIKE, float(_attack.get("lunge_time", 0.45)))
			_lunge_dir = (to_target + Vector2(0, -10)).normalized()
			_play(animation)
			_lunge_fx()
			if Net.active:
				_net_strike.rpc("lunge", animation)
		"beam":
			_set_state(State.STRIKE, float(_attack.get("duration", 0.45)))
			_play(animation)
			_beam_hit = {}
			_beam_fx(float(_attack.get("length", 420)), float(_attack.get("thickness", 26)),
				str(_attack.get("color", "#ffe9a8")))
			if Net.active:
				_net_beam.rpc(float(_attack.get("length", 420)), float(_attack.get("thickness", 26)),
					str(_attack.get("color", "#ffe9a8")))
		"summon":
			_set_state(State.STRIKE, 0.45)
			_play(animation)
			_call_up(_attack)
			if Net.active:
				_net_strike.rpc("summon", animation)
		"nova":
			_set_state(State.STRIKE, float(_attack.get("duration", 0.3)))
			_play(animation)
			_nova_fx(float(_attack.get("radius", 90)), str(_attack.get("color", "#b86cff")), str(_attack.get("impact_fx", "magic")))
			_nova_hit()
			if Net.active:
				_net_nova.rpc(float(_attack.get("radius", 90)), str(_attack.get("color", "#b86cff")), str(_attack.get("impact_fx", "magic")), animation)


func _lunge_fx() -> void:
	var animation := str(_attack.get("animation", "attack"))
	if not _attack.has("hit_frame") and _has_anim.has(animation) and sprite.sprite_frames.get_frame_count(animation) > 1:
		sprite.frame = 1
	Juice.shake(3.0)


func _beam_fx(length: float, thickness: float, color: String) -> void:
	var animation := str(_attack.get("animation", "attack"))
	if not _attack.has("hit_frame") and _has_anim.has(animation) and sprite.sprite_frames.get_frame_count(animation) > 1:
		sprite.frame = 1
	_show_beam(false, 0.0, length, thickness, color)
	Fx.flash(global_position, Color(color), 180.0, 0.5, 1.3)
	Audio.play(&"beam", -2.0)
	Juice.shake(5.0)
	Juice.hit_stop(0.05)


@rpc("authority", "call_remote", "reliable")
func _net_strike(kind: String, animation := "attack") -> void:
	_play(animation)
	Audio.play(&"enemy_swing", -8.0)
	if kind == "lunge":
		_lunge_fx()
	elif kind == "summon":
		_summon_fx()


@rpc("authority", "call_remote", "reliable")
func _net_beam(length: float, thickness: float, color: String) -> void:
	_beam_fx(length, thickness, color)


@rpc("authority", "call_remote", "reliable")
func _net_clear_beam() -> void:
	_clear_beam()
	_play("idle")


func _nova_fx(radius: float, color: String, effect := "magic") -> void:
	if effect == "dust":
		# The shock travels along the floor; no light or circular magic field.
		var ground := global_position + Vector2(0, 11)
		var tint := Color(color)
		tint.a = 0.65
		for i in range(7):
			var at := ground + Vector2(lerpf(-radius, radius, float(i) / 6.0), -2)
			Fx.puff(at, 0.45, tint)
			Fx.dust(at, Vector2.UP, 4, tint)
		Juice.shake(4.0)
		return
	if effect == "none":
		return
	Fx.flash(global_position + Vector2(0, -8), Color(color), radius, 0.45, 1.2)
	# the ring runs out to exactly where the blast hurts; the smoke stays small
	Fx.ring(global_position + Vector2(0, -8), radius, Color(color), 0.35)
	Fx.puff(global_position + Vector2(0, -8), 0.9, Color(color))
	Juice.shake(4.0)


func _nova_hit() -> void:
	var radius := float(_attack.get("radius", 90))
	for node in get_tree().get_nodes_in_group("player"):
		var victim := node as Player
		if victim != null and not victim.is_dead() and _hostile_to(victim) and victim.global_position.distance_to(global_position) <= radius:
			victim.take_damage(float(_attack.get("damage", 12)), self)
	for victim in _hostile_bodies():
		if victim.global_position.distance_to(global_position) <= radius:
			victim.take_damage(float(_attack.get("damage", 12)) * Faction.damage_between(), self)


## The bodies of hostile sides in the tree (none outside chapter III).
func _hostile_bodies() -> Array[Enemy]:
	var out: Array[Enemy] = []
	if Faction.soldiers <= 0:
		return out
	for node in get_tree().get_nodes_in_group("enemies"):
		var other := node as Enemy
		if other != null and _hostile_to(other):
			out.append(other)
	return out


@rpc("authority", "call_remote", "reliable")
func _net_nova(radius: float, color: String, effect := "magic", animation := "special") -> void:
	_play(animation)
	_nova_fx(radius, color, effect)


## One round of a ranged attack: projectiles fanned over spread, each at its
## own speed when the attack has a speed_jitter. aim is the vector to the target,
## or zero to look for it again (a volley's later rounds).
func _fire_round(attack: Dictionary, aim: Vector2) -> void:
	if is_dead() or not is_inside_tree():
		return
	if aim == Vector2.ZERO:
		var target := _target if _target != null and is_instance_valid(_target) and _hostile_to(_target) else _nearest_player()
		if target == null:
			return
		aim = target.global_position - global_position
	var direction := (aim + Vector2(0, -14)).normalized()
	var origin := global_position + Vector2(facing * 12.0, -14.0)
	var count := maxi(1, int(attack.get("projectiles", 1)))
	var spread := deg_to_rad(float(attack.get("spread", 0.0)))
	var jitter := float(attack.get("speed_jitter", 0.0))
	for i in count:
		var offset := 0.0 if count == 1 else lerpf(-spread * 0.5, spread * 0.5, float(i) / float(count - 1))
		var shot := direction.rotated(offset)
		var speed := float(attack.get("projectile_speed", 170)) * (1.0 + randf_range(-jitter, jitter))
		_spawn_projectile(origin, shot, false, attack, speed)
		if attack.has("mark_landing"):
			_mark_landing(origin, shot, speed, attack)
		if Net.active:
			_net_projectile.rpc(origin, shot, speed, str(attack.get("color", "#ffd27a")), _projectile_style(attack),
				str(attack.get("projectile_motion", "straight")), float(attack.get("motion_amount", 0.0)),
				float(attack.get("projectile_scale", 1.0)), float(attack.get("projectile_range", 0.0)))


func _nearest_player() -> Node2D:
	var best: Node2D = null
	var near := INF
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as Node2D
		if body != null and not body.call("is_dead") and body.global_position.distance_to(global_position) < near:
			near = body.global_position.distance_to(global_position)
			best = body
	return best


func _spawn_projectile(origin: Vector2, direction: Vector2, cosmetic: bool, attack: Dictionary = {},
		speed := -1.0) -> void:
	if attack.is_empty():
		attack = _attack
	Audio.play(&"projectile", -9.0)
	var projectile := PROJECTILE_SCENE.instantiate()
	projectile.damage = float(attack.get("damage", 10)) if not cosmetic else 0.0
	projectile.speed = speed if speed > 0.0 else float(attack.get("projectile_speed", 170))
	projectile.direction = direction
	projectile.tint = Color(attack.get("color", "#ffd27a"))
	projectile.visual_style = _projectile_style(attack)
	projectile.size = float(attack.get("projectile_scale", 1.0))
	projectile.motion = str(attack.get("projectile_motion", "straight"))
	projectile.motion_amount = float(attack.get("motion_amount", 0.0))
	projectile.max_distance = float(attack.get("projectile_range", 0.0))
	projectile.cosmetic = cosmetic
	projectile.shooter_id = enemy_id
	if Faction.soldiers > 0 and not cosmetic:
		projectile.shooter = self  # its bolt bites the bodies of a hostile side too (Faction)
	get_parent().add_child(projectile)
	projectile.global_position = origin
	_cast_flare(origin, projectile.tint)


## The spark at the hand as a bolt leaves it, on every peer.
func _cast_flare(origin: Vector2, tint: Color) -> void:
	Fx.flash(origin, tint, 26.0, 0.14, 0.9)
	Fx.impact(origin, Vector2(facing, 0), tint, 5)


## Motion is deterministic from launch parameters, so peers draw their own copy.
## Only the host's bolt bites.
@rpc("authority", "call_remote", "reliable")
func _net_projectile(origin: Vector2, direction: Vector2, speed: float, color: String,
		style: String, motion: String, motion_amount: float, size: float, distance := 0.0) -> void:
	var projectile := PROJECTILE_SCENE.instantiate()
	projectile.damage = 0.0
	projectile.speed = speed
	projectile.direction = direction
	projectile.tint = Color(color)
	projectile.visual_style = style
	projectile.size = size
	projectile.motion = motion
	projectile.motion_amount = motion_amount
	projectile.max_distance = distance
	projectile.cosmetic = true
	get_parent().add_child(projectile)
	projectile.global_position = origin
	_cast_flare(origin, projectile.tint)


func _projectile_style(attack: Dictionary = {}) -> String:
	if attack.is_empty():
		attack = _attack
	var explicit_style := str(attack.get("projectile_style", ""))
	if explicit_style != "" and Projectile.has_style(explicit_style):
		return explicit_style
	if enemy_id == "wraith":
		return "wraith"
	var tags: Array = stats.get("tags", [])
	if "cult" in tags or "fallen" in tags or "spirit" in tags or "possessed" in tags:
		return "umbral"
	return "sacred"


func _soul_affinity() -> String:
	var override := str(stats.get("soul_affinity", ""))
	if override in ["light", "dark"]:
		return override
	var tags: Array = stats.get("tags", [])
	for corrupted in ["possessed", "undead", "fallen", "spirit", "demon", "unclean"]:
		if corrupted in tags:
			return "dark"
	# Humans, angels and animals leave warm motes. A cultist is still human;
	# only actual corruption makes its soul-effect dark.
	return "light"


## Cross of light through the boss: thin while winding up, thick while firing.
func _show_beam(telegraph: bool, duration := 0.0, length := 420.0, thickness := 26.0, color_hex := "#ffe9a8") -> void:
	_clear_beam()
	var color := Color(color_hex)
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for axis in [Vector2.RIGHT, Vector2.DOWN]:
		# a wide soft halo under a hot core
		for layer in ([[2.0, 0.35]] if telegraph else [[thickness * 2.4, 0.25], [thickness, 0.95]]):
			var line := Line2D.new()
			line.points = PackedVector2Array([-axis * length, axis * length])
			line.width = layer[0]
			line.default_color = Color(color, layer[1])
			line.z_index = 3
			line.material = material
			add_child(line)
			_beam_lines.append(line)
	if telegraph:
		for line in _beam_lines:
			create_tween().tween_property(line, "width", 6.0, duration)


func _beam_tick() -> void:
	for line in _beam_lines:
		line.default_color.a = clampf(line.default_color.a * randf_range(0.8, 1.15), 0.15, 1.0)
	var half := float(_attack.get("thickness", 26)) / 2.0 + 6.0
	var length := float(_attack.get("length", 420))
	var victims: Array = []
	for node in get_tree().get_nodes_in_group("player"):
		if node is Player and _hostile_to(node):
			victims.append(node)
	victims.append_array(_hostile_bodies())
	for victim in victims:
		if victim.call("is_dead") or _beam_hit.has(victim):
			continue
		var d: Vector2 = victim.global_position - global_position
		if (absf(d.y - 10.0) < half and absf(d.x) < length) or (absf(d.x) < half and absf(d.y) < length):
			_beam_hit[victim] = true
			var share := 1.0 if victim is Player else Faction.damage_between()
			victim.take_damage(float(_attack.get("damage", 20)) * share, self)


func _clear_beam() -> void:
	for line in _beam_lines:
		line.queue_free()
	_beam_lines.clear()


func _melee_hit() -> void:
	# layer 3 (enemies) only while a side is in play: a blade between soldiers (Faction)
	attack_area.collision_mask = 2 | (4 if Faction.soldiers > 0 else 0)
	attack_area.monitoring = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree() or state == State.DEAD:
		return
	for body_hit in attack_area.get_overlapping_bodies():
		if body_hit is Player and not body_hit.is_dead() and _hostile_to(body_hit):
			body_hit.take_damage(float(_attack.get("damage", 10)), self)
		elif body_hit is Enemy and _hostile_to(body_hit):
			body_hit.take_damage(float(_attack.get("damage", 10)) * Faction.damage_between(), self)
	attack_area.monitoring = false


## The second frame of the swing, for the enemies that have one drawn.
func _hold_attack_frame() -> void:
	var animation := str(_attack.get("animation", "attack"))
	if not _attack.has("hit_frame") and _has_anim.has(animation) and sprite.sprite_frames.get_frame_count(animation) > 1:
		sprite.frame = 1


func _set_state(new_state: State, duration: float) -> void:
	if new_state != State.STRIKE:
		_strike_wait = false
	if new_state == State.WINDUP:
		_guard_down = true  # a shield-bearer swinging is a shield-bearer open
	elif new_state == State.CHASE:
		_guard_down = false
	state = new_state
	_state_left = duration


func _play(animation: String, hold_first_frame := false) -> void:
	if _sealed and animation in ["idle", "walk", "hurt"] and _has_anim.has("special"):
		animation = "special"  # eyes closed: the wheels turn in on themselves
	if not _has_anim.has(animation) or sprite.animation == animation and sprite.is_playing() and not hold_first_frame:
		return
	sprite.play(animation)
	if hold_first_frame:
		sprite.pause()
		sprite.frame = 0


func _attack_animation_remaining() -> float:
	if sprite.sprite_frames == null or not _has_anim.has(sprite.animation):
		return 0.0
	var count := sprite.sprite_frames.get_frame_count(sprite.animation)
	var fps := sprite.sprite_frames.get_animation_speed(sprite.animation)
	if count <= 1 or fps <= 0.0:
		return 0.0
	return maxf(0.0, float(count - sprite.frame - 1) / fps)


## The one door damage comes through. Enemies live on the host, so a client
## reports the hit and lets the host decide what it was worth.
func take_damage(amount: float, source: Node = null, info: Dictionary = {}) -> void:
	var from: Vector2 = source.global_position if source is Node2D else global_position
	var crit := bool(info.get("crit", false))
	var knockback := float(info.get("knockback", 1.0))
	var sneak := float(info.get("sneak", 1.0))
	var execute := float(info.get("execute", 0.0))
	var move := str(info.get("move", ""))
	if Net.active and not multiplayer.is_server():
		if multiplayer.get_peers().has(1):
			_net_hit.rpc_id(1, amount, from, crit, knockback, sneak, execute, move)
		return
	_apply_damage(amount, from, source != null, crit, knockback, sneak, execute, move, source is Enemy)


@rpc("any_peer", "call_remote", "reliable")
func _net_hit(amount: float, from: Vector2, crit: bool, knockback: float, sneak: float, execute := 0.0, move := "") -> void:
	_apply_damage(amount, from, true, crit, knockback, sneak, execute, move)


## [param sneak] is what the blow is worth on a body that never saw it coming;
## only the host knows whether this one did, so the multiplier is applied here.
## [param move] names the blow that landed (Gore.moves): how this body bleeds and tears.
## [param soldier]: the blow came from another body (Faction) — no backstab, no
## crit, no riposte, and nobody's numbers count it.
func _apply_damage(amount: float, from: Vector2, pushed: bool, crit: bool, knockback: float, sneak := 1.0,
		execute := 0.0, move := "", soldier := false) -> void:
	if state == State.DEAD:
		return
	felled_by_soldier = soldier
	if soldier:
		crit = false
		sneak = 1.0
		execute = 0.0
	elif spared:
		Faction.break_truce(self)  # he struck one who was sparing him
	if _sealed:
		# warded: the blade rings off, nothing gets through
		_warded_fx()
		if Net.active:
			_net_warded_fx.rpc()
		return
	if _exposed_left > 0.0:
		amount *= 1.0 + float(stats.get("seal_phase", {}).get("exposed_bonus", 0.5))
	if _hex_left > 0.0:
		amount *= 1.0 + _hex_bonus
	var backstab := is_unaware() and sneak > 1.0 and Player.can_move("backstab")
	if backstab:
		amount *= sneak
		crit = true
		EventBus.technique_performed.emit("backstab")
	# The execution: worth nothing on a healthy body, everything on a spent one.
	# Only this side knows how much is left, so the multiplier is applied here.
	if execute > 0.0 and hp <= _max_hp * EXECUTE_BELOW:
		amount *= 1.0 + execute
		crit = true
	var riposte := not soldier and _open_left > 0.0 and Player.can_move("riposte")
	if riposte:
		_open_left = 0.0  # one riposte per parry
		EventBus.technique_performed.emit("riposte")
		amount *= RIPOSTE_MULTIPLIER
		crit = true
	if _shield_holds(from, backstab or riposte):
		amount *= 1.0 - clampf(float(stats.get("shield", 0.0)), 0.0, 0.8)
		_shield_fx()
		if Net.active:
			_net_shield_fx.rpc()
	amount *= 1.0 - clampf(float(stats.get("armor", 0.0)), 0.0, 0.5)  # FinalDamage = Base × (1 − armor)
	hp -= amount
	if stats.get("behaviour", "walker") == "dummy":
		hp = maxf(hp, 1.0)  # straw does not die; it shows the number and stands again
		_dummy_rest = 2.0
	var phase: Dictionary = stats.get("seal_phase", {})
	var seal_now := not phase.is_empty() and not _seal_done and hp <= _max_hp * float(phase.get("at_hp", 0.5))
	if seal_now:
		# the threshold is a floor until the seals are broken: no blow skips the phase
		hp = _max_hp * float(phase.get("at_hp", 0.5))
	var away := signf(global_position.x - from.x)
	if away == 0.0:
		away = float(facing)
	_hit_fx(amount, crit, hp, away, backstab, move, soldier)
	if Net.active:
		_net_hit_fx.rpc(amount, crit, hp, _max_hp, away, backstab, move, soldier)
	if riposte:
		_riposte_fx()
		if Net.active:
			_net_riposte_fx.rpc()
	if is_unaware():
		if waits() and not soldier:
			Game.flags["waiter_struck"] = true  # somebody who was only waiting (read in chapter II)
		# Whoever it was, it is awake now; the nearest player is picked up on the next tick.
		aware = true
		_target = null
		_set_state(State.CHASE, 0.0)
	if pushed and not stats.get("boss", false):
		var push := 170.0 * knockback * (1.4 if crit else 1.0)
		if _is_flying():
			push = minf(push, 190.0)
		_knockback = Vector2(away * push, -35.0 if _is_flying() else -60.0)
		if state == State.WINDUP and randf() < float(stats.get("stagger_chance", 0.35)):
			_set_state(State.RECOVER, 0.4)  # interrupted the wind-up
			_attack_cd = maxf(_attack_cd, _state_left + float(_ai("hit_attack_delay")))
			_cancel_telegraph()
			if Net.active:
				_net_cancel_telegraph.rpc()
		elif state == State.CHASE:
			# Knocked out of its stride: while it is walking at you a hit has to
			# actually stop it, otherwise the body walks the push straight off
			# and the sword looks like it passed through. An attack already in
			# motion still plays out — that is what stagger_chance is for.
			_set_state(State.RECOVER, float(stats.get("flinch", 0.18)))
			_attack_cd = maxf(_attack_cd, _state_left + float(_ai("hit_attack_delay")))
			_play("idle")
			# and now and then it gives ground rather than trade blows
			if randf() < float(stats.get("hit_retreat", 0.35)):
				_disengage_left = maxf(_disengage_left, randf_range(0.4, 0.7))
	if hp > 0.0:
		_play("hurt")
	if seal_now:
		_enter_seal()
	if stats.get("boss", false) and not _summoned and stats.has("summons") \
			and hp <= _max_hp * float(stats.summons.get("at_hp", 0.5)):
		_summon()
	if stats.has("flood") and not _flooded and hp > 0.0 and hp <= _max_hp * float(stats.flood.get("at_hp", 0.5)):
		_flood(stats.flood)
	if hp <= 0.0:
		if Net.active:
			_net_die.rpc(felled_by_soldier)
		_die()


## Hexed for [param seconds]: every blow it takes lands [param bonus] harder.
## Decided by the host, like damage; the mark is drawn on every peer.
func hex(seconds: float, bonus: float) -> void:
	if Net.active and not multiplayer.is_server():
		if multiplayer.get_peers().has(1):
			_net_hex.rpc_id(1, seconds, bonus)
		return
	_apply_hex(seconds, bonus)


@rpc("any_peer", "call_remote", "reliable")
func _net_hex(seconds: float, bonus: float) -> void:
	_apply_hex(seconds, bonus)


func _apply_hex(seconds: float, bonus: float) -> void:
	if state == State.DEAD:
		return
	_hex_left = maxf(_hex_left, seconds)
	_hex_bonus = maxf(_hex_bonus if _hex_left > 0.0 else 0.0, bonus)
	_hex_mark(seconds)
	if Net.active:
		_net_hex_mark.rpc(seconds)


@rpc("authority", "call_remote", "reliable")
func _net_hex_mark(seconds: float) -> void:
	_hex_mark(seconds)


## Ash rising off the hexed body for as long as it lasts.
func _hex_mark(seconds: float) -> void:
	var ticks := int(ceil(seconds / 0.4))
	for i in ticks:
		if not is_inside_tree() or state == State.DEAD:
			return
		Fx.ash(global_position + Vector2(randf_range(-6, 6), -14), Color(0.7, 0.35, 0.85, 0.8), 3, 20.0, 6.0)
		await get_tree().create_timer(0.4).timeout


func is_hexed() -> bool:
	return _hex_left > 0.0


## Stopped where it stands for [param duration] (the cracked bell's parry, an
## item): the wind-up breaks off, as a flinch would. A boss shrugs it off in
## half the time. Decided by the host, like damage.
func stagger(duration: float) -> void:
	if Net.active and not multiplayer.is_server():
		if multiplayer.get_peers().has(1):
			_net_stagger.rpc_id(1, duration)
		return
	_apply_stagger(duration)


@rpc("any_peer", "call_remote", "reliable")
func _net_stagger(duration: float) -> void:
	_apply_stagger(duration)


func _apply_stagger(duration: float) -> void:
	if state == State.DEAD or stats.get("behaviour", "walker") == "seal" or _sealed:
		return
	if stats.get("boss", false):
		duration *= 0.5
	if state == State.WINDUP:
		_cancel_telegraph()
		if Net.active:
			_net_cancel_telegraph.rpc()
	_set_state(State.RECOVER, duration)
	_attack_cd = maxf(_attack_cd, duration + float(_ai("hit_attack_delay")))


## The player's block caught this swing on the beat (Player._parry): the blow is
## dead, the attack is abandoned and the body is open for a riposte. Enemies
## live on the host, so a client reports the parry and lets the host act on it.
func parried(by: Node2D) -> void:
	var from: Vector2 = by.global_position if by != null else global_position
	if Net.active and not multiplayer.is_server():
		if multiplayer.get_peers().has(1):
			_net_parried.rpc_id(1, from)
		return
	_apply_parry(from)


@rpc("any_peer", "call_remote", "reliable")
func _net_parried(from: Vector2) -> void:
	_apply_parry(from)


func _apply_parry(from: Vector2) -> void:
	if state == State.DEAD:
		return
	var boss: bool = stats.get("boss", false)
	var opening := float(stats.get("parry_opening", _ai("parry_opening"))) * (0.5 if boss else 1.0)
	_cancel_telegraph()
	if Net.active:
		_net_cancel_telegraph.rpc()
	_open_left = opening
	_attack_cd = maxf(_attack_cd, opening + 0.3)
	_set_state(State.RECOVER, opening)
	_play("idle")
	var away := signf(global_position.x - from.x)
	if away == 0.0:
		away = -float(facing)
	if not boss:
		_knockback = Vector2(away * 220.0, -80.0)
	_parried_fx(away)
	if Net.active:
		_net_parried_fx.rpc(away)


## Thrown off balance: rocked back, the colour knocked out of it, and a word so
## the player knows the next blow is worth more.
func _parried_fx(away: float) -> void:
	Fx.popup(global_position + Vector2(0, -36), tr("HUD_PARRY"), Color(0.8, 0.9, 1.0), 9)
	visual.modulate = Color(0.55, 0.65, 1.0)
	create_tween().tween_property(visual, "modulate", Color.WHITE, 0.5)
	Fx.impact(global_position + Vector2(away * -6.0, -12.0), Vector2(away, -0.5), Color(0.85, 0.92, 1.0), 10)


@rpc("authority", "call_remote", "unreliable")
func _net_parried_fx(away: float) -> void:
	_parried_fx(away)


## The blow that answers a parry: named, and given a beat of its own.
func _riposte_fx() -> void:
	Fx.popup(global_position + Vector2(0, -44), tr("HUD_RIPOSTE"), Color(1.0, 0.85, 0.4), 9)
	Juice.hit_stop(0.08, 0.05)
	Juice.shake(4.0)


@rpc("authority", "call_remote", "unreliable")
func _net_riposte_fx() -> void:
	_riposte_fx()


## What a hit looks like from the receiving end: a white blow-out, a squash that
## springs back, sparks thrown the way the blade was going, and the number.
## [param away] is -1 or 1: the direction the hit came from, pointing outwards.
func _hit_fx(amount: float, crit: bool, new_hp: float, away := 1.0, backstab := false, move := "", soldier := false) -> void:
	if not soldier:
		Game.note_dealt(amount)  # the night's numbers (every peer sees every blow); a soldier's blow is not ours
	Fx.damage_number(global_position, amount, Color(1.0, 0.8, 0.3) if crit else Color(1, 0.95, 0.8))
	if backstab:
		# The one hit that is meant to feel like a decision: name it and let it land.
		Fx.popup(global_position + Vector2(0, -36), tr("HUD_BACKSTAB"), Color(1.0, 0.7, 0.25), 9)
		Juice.hit_stop(0.1, 0.05)
		Juice.shake(4.0)
	# The drawn burst: steel sparks on every blow, blood on the ones that open something.
	Fx.hit(global_position + Vector2(away * -3.0, -10.0), "blood" if backstab or crit else "spark",
		0.8 if crit else 0.6, away > 0.0)
	hp_bar.visible = not stats.get("boss", false)
	hp_bar.size.x = 14.0 * clampf(new_hp / _max_hp, 0.0, 1.0)
	# the white of the blow; a third of it with flashes reduced (Settings.flashes)
	var white := 1.0 + 2.0 * Settings.flash_scale()
	visual.modulate = Color(white, white, white)
	create_tween().tween_property(visual, "modulate", Color.WHITE, 0.12)
	_voice("hurt", &"enemy_hurt", -12.0)
	_punch(crit)
	# Sparks fly off the side the blade came from, up and outwards.
	Fx.impact(global_position + Vector2(away * -7.0, -10.0), Vector2(away, -0.35),
		Color(1.0, 0.75, 0.35) if crit else Color(1, 0.9, 0.7), 13 if crit else 9)
	Fx.flash(global_position + Vector2(0, -10), Color(1.0, 0.8, 0.5), 50.0 if crit else 36.0, 0.18, 0.9)
	# blood thrown the way the blade went, by what it is made of (data/gore.json)
	_last_away = away
	_last_violent = crit or backstab
	_last_move = "thrust" if backstab and move in ["", "attack"] else move
	var share := amount / maxf(_max_hp, 1.0)
	Gore.hit(self, enemy_id, str(stats.get("material", "cloth")), global_position + Vector2(away * -4.0, -10.0),
		Vector2(away, -0.3), 1.0 + (0.6 if crit else 0.0) + (1.0 if backstab else 0.0) + share * 2.0, _last_move)
	if stats.get("boss", false):
		EventBus.boss_hp_changed.emit(stats.get("name", ""), maxf(new_hp, 0.0), _max_hp)


## Squash on the way in, spring back out. Set through the property name because
## a body is either a Node2D sprite or the fallback Control rectangle, and only
## the two of them (not CanvasItem) have a scale — both pivot on their centre.
func _punch(crit: bool) -> void:
	var squash := Vector2(1.3, 0.74) if crit else Vector2(1.18, 0.84)
	visual.set("scale", _visual_scale * squash)
	var tween := create_tween()
	tween.tween_property(visual, "scale", _visual_scale, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The host also sends its own max: difficulty is a per-player setting, so the
## numbers a client computed at spawn are not the numbers being fought.
@rpc("authority", "call_remote", "unreliable_ordered")
func _net_hit_fx(amount: float, crit: bool, new_hp: float, max_hp: float, away: float, backstab: bool, move := "", soldier := false) -> void:
	hp = new_hp
	_max_hp = maxf(max_hp, 1.0)
	_hit_fx(amount, crit, new_hp, away, backstab, move, soldier)


## Attack type "summon": after its wind-up, calls "count" of "id" out of the
## ground beside it, unless "max_alive" of them are already about. The run
## spawns them (replicated in a session).
func _call_up(attack: Dictionary) -> void:
	_summon_fx()
	var wanted := mini(int(attack.get("count", 1)), int(attack.get("max_alive", 2)) - _summons_near(attack))
	for i in wanted:
		var at := global_position + Vector2(randf_range(24.0, 60.0) * (1 if i % 2 == 0 else -1), -18.0)
		# "where": "liquid" — they rise out of the room's water instead (Wormwood)
		if str(attack.get("where", "")) == "liquid":
			var risen := _liquid_point()
			if risen != Vector2.INF:
				at = risen
		if attack.has("essence"):
			# what the risen pay is the summoner's to say ("essence": 0 — nothing)
			var room := _room()
			if room != null:
				var body := room.spawn_enemy(str(attack.get("id", "shade")), at, true)
				if body != null:
					body.stats.essence = float(attack.essence)
		else:
			EventBus.enemy_spawn_requested.emit(str(attack.get("id", "shade")), at)
		Fx.puff(at, 1.0, Color(attack.get("color", "#9966cc")))


## The room this body fights in (the newest, while an old one is being freed).
func _room() -> Room:
	var rooms := get_tree().get_nodes_in_group("room")
	return null if rooms.is_empty() else rooms.back() as Room


## A random point just over the surface of the room's water ("liquids": Hazard),
## Vector2.INF when the room has none.
func _liquid_point() -> Vector2:
	var pools := get_tree().get_nodes_in_group("liquids").filter(func(p) -> bool: return not (p as Hazard).burns())
	if pools.is_empty():
		return Vector2.INF
	var pool := pools[randi() % pools.size()] as Hazard
	var x := pool.global_position.x + randf_range(12.0, maxf(13.0, pool.size.x - 12.0))
	return Vector2(x, pool.surface_y(x) - 18.0)


## A flyer with an "anchor" (finished-room pixels) never goes further than its
## "leash" from it, and with "hover_floor" never lower than that many px over the
## floor or the water under it — a boss that keeps over its own spring (Wormwood;
## generic, for any flying boss). Takes and returns the move it wanted.
func _leashed(goal: Vector2) -> Vector2:
	if not stats.has("anchor") and not stats.has("hover_floor"):
		return goal
	var want := global_position + goal
	if stats.has("anchor"):
		var room := _room()
		var origin := room.global_position if room != null else Vector2.ZERO
		var anchor := origin + Vector2(float(stats.anchor[0]), float(stats.anchor[1]))
		var leash := float(stats.get("leash", 150.0))
		if want.distance_to(anchor) > leash:
			want = anchor + (want - anchor).limit_length(leash)
	if stats.has("hover_floor"):
		var ground := _ground_under(want.x)
		want.y = minf(want.y, ground - float(stats.hover_floor))
	return want - global_position


## The first floor (world or ledge) or water surface under [param x], looking
## down from this body; far below when there is none.
func _ground_under(x: float) -> float:
	var from := Vector2(x, global_position.y - 40.0)
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 1200), SOLID_MASK)
	query.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	var ground: float = (hit.position as Vector2).y if not hit.is_empty() else from.y + 1200.0
	for node in get_tree().get_nodes_in_group("liquids"):
		var pool := node as Hazard
		if pool != null and x >= pool.global_position.x and x <= pool.global_position.x + pool.size.x:
			ground = minf(ground, pool.surface_y(x))
	return ground


## "mark_landing" on an arcing bolt: where it will come down glows that many
## seconds before it does (Wormwood's embers). The curve is the projectile's own
## (motion "arc": y += amount·t·dt), stepped until it meets the world or water.
func _mark_landing(origin: Vector2, direction: Vector2, speed: float, attack: Dictionary) -> void:
	var amount := float(attack.get("motion_amount", 0.0))
	var step := 1.0 / 30.0
	var t := 0.0
	var at := origin
	var space := get_world_2d().direct_space_state
	while t < 4.0:
		t += step
		var next := origin + direction * speed * t + Vector2(0, amount * t * t * 0.5)
		var query := PhysicsRayQueryParameters2D.create(at, next, 1)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			at = hit.position
			break
		var wet := false
		for node in get_tree().get_nodes_in_group("liquids"):
			var pool := node as Hazard
			if pool != null and next.x >= pool.global_position.x and next.x <= pool.global_position.x + pool.size.x \
					and next.y >= pool.surface_y(next.x):
				wet = true
		at = next
		if wet:
			break
	if t >= 4.0:
		return
	var lead := float(attack.mark_landing)
	var color := str(attack.get("color", "#d8ecff"))
	_mark(at, maxf(0.0, t - lead), minf(lead, t), color)
	if Net.active:
		_net_mark.rpc(at, maxf(0.0, t - lead), minf(lead, t), color)


## The glow on the ground where a bolt will fall, from [param delay] for [param time].
func _mark(at: Vector2, delay: float, time: float, color: String) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay, false).timeout
	if not is_inside_tree():
		return
	Fx.flash(at + Vector2(0, -2), Color(color), 34.0, time, 0.8)
	Fx.ring(at + Vector2(0, -2), 18.0, Color(color), time)


@rpc("authority", "call_remote", "reliable")
func _net_mark(at: Vector2, delay: float, time: float, color: String) -> void:
	_mark(at, delay, time, color)


## "flood": {"at_hp", "liquid": the pool's node name, "rise", "warn", "time"} —
## at that share of its health the water of the named pool rises: a warning
## (bubbles all over it, a rumble, a shake) and then the surface lifts "rise" px
## over "time" s (Hazard.set_level). Once. Every peer raises its own pool.
func _flood(spec: Dictionary) -> void:
	_flooded = true
	_raise_water(str(spec.get("liquid", "")), float(spec.get("rise", 64)), float(spec.get("warn", 1.5)),
		float(spec.get("time", 3.0)))
	if Net.active:
		_net_flood.rpc(str(spec.get("liquid", "")), float(spec.get("rise", 64)), float(spec.get("warn", 1.5)),
			float(spec.get("time", 3.0)))


func _raise_water(pool_name: String, rise: float, warn: float, time: float) -> void:
	var room := _room()
	var pool := room.find_child(pool_name, true, false) as Hazard if room != null else null
	if pool == null:
		push_warning("%s: no pool named %s to flood" % [enemy_id, pool_name])
		return
	Juice.shake(5.0)
	Audio.play(&"summon", -4.0, 0.0)
	var bubbles := int(maxf(6.0, pool.size.x / 24.0))
	for i in bubbles:
		var x := pool.global_position.x + randf_range(0.0, pool.size.x)
		LiquidFx.bubble(pool.spec, Vector2(x, pool.surface_y(x)))
	await get_tree().create_timer(warn, false).timeout
	if is_instance_valid(pool):
		pool.set_level(rise, time)


@rpc("authority", "call_remote", "reliable")
func _net_flood(pool_name: String, rise: float, warn: float, time: float) -> void:
	_raise_water(pool_name, rise, warn, time)


func _summons_near(attack: Dictionary) -> int:
	var count := 0
	for other in get_tree().get_nodes_in_group("enemies"):
		var body := other as Enemy
		if body != null and body != self and not body.is_dead() and body.enemy_id == str(attack.get("id", "shade")) \
				and body.global_position.distance_to(global_position) < 320.0:
			count += 1
	return count


func _summon_fx() -> void:
	Audio.play(&"summon", -6.0, 0.0)
	Fx.flash(global_position + Vector2(0, -12), Color(0.65, 0.4, 1.0), 110.0, 0.5, 1.2)
	Fx.sparkle(global_position + Vector2(0, 8), Color(0.7, 0.5, 1.0), 16, 20.0)


func _summon() -> void:
	Audio.play(&"summon", -3.0, 0.0)
	_summoned = true
	for i in int(stats.summons.get("count", 2)):
		var offset := Vector2(randf_range(-60, 60), randf_range(-30, 10))
		# The run owns spawning: in a session it also has to be replicated.
		EventBus.enemy_spawn_requested.emit(str(stats.summons.get("id", "shade")), global_position + offset)
		Fx.puff(global_position + offset, 1.2, Color(0.6, 0.4, 0.7))


## The seal phase begins (host): the wind-up breaks off, the eyes close and a
## seal appears at each of the room's points. The run spawns them, so a
## session replicates them like any summons.
func _enter_seal() -> void:
	var phase: Dictionary = stats.seal_phase
	_seal_done = true
	_cancel_telegraph()
	if Net.active:
		_net_cancel_telegraph.rpc()
	_set_state(State.RECOVER, 1.0)
	_attack_cd = maxf(_attack_cd, 2.0)
	_show_sealed(true)
	if Net.active:
		_net_sealed.rpc(true, false)
	var room := get_tree().get_first_node_in_group("room") as Node2D
	var key := RoomLayers.look_key(room, phase.get("points", {})) if room != null else ""
	var points: Array = phase.get("points", {}).get(key, [])
	if points.is_empty():
		points = [[-140, 40], [0, -60], [140, 40]]  # an unlisted room: about the boss
		for i in points.size():
			points[i] = [global_position.x + points[i][0], global_position.y + points[i][1]]
	if not EventBus.enemy_died.is_connected(_on_seal_broken):
		EventBus.enemy_died.connect(_on_seal_broken)
	for point in points:
		var at := Vector2(float(point[0]), float(point[1]))
		if room != null and not phase.get("points", {}).get(key, []).is_empty():
			at = room.to_global(at)
		EventBus.enemy_spawn_requested.emit(str(phase.get("seal", "ophanim_seal")), at)
		Fx.flash(at, Color(1.0, 0.85, 0.5), 70.0, 0.6)


## Host: a seal died. The last one opens the eyes.
func _on_seal_broken(dead_id: StringName, _at: Vector2) -> void:
	if not _sealed or state == State.DEAD or str(dead_id) != str(stats.seal_phase.get("seal", "ophanim_seal")):
		return
	for other in get_tree().get_nodes_in_group("enemies"):
		var seal := other as Enemy
		if seal != null and seal != self and seal.enemy_id == str(dead_id) and not seal.is_dead():
			return
	EventBus.enemy_died.disconnect(_on_seal_broken)
	_exposed_left = float(stats.seal_phase.get("exposed", 6.0))
	_attack_cd = maxf(_attack_cd, _exposed_left)
	_show_sealed(false, true)
	if Net.active:
		_net_sealed.rpc(false, true)


## Every peer: how the phase looks. Closed, a ring of light turns round it;
## broken open, the ring bursts and the wheel sags.
func _show_sealed(on: bool, broken := false) -> void:
	_sealed = on
	if on:
		Audio.play(&"summon", -2.0, 0.0)
		if _ward == null:
			_ward = Line2D.new()
			_ward.name = "Ward"
			_ward.width = 2.0
			_ward.default_color = Color(1.0, 0.86, 0.45, 0.7)
			for i in 33:
				var a := TAU * i / 32.0
				_ward.add_point(Vector2(cos(a), sin(a)) * 50.0 + Vector2(0, -10))
			add_child(_ward)
			var spin := _ward.create_tween().set_loops()
			spin.tween_property(_ward, "rotation", TAU, 6.0).from(0.0)
		visual.modulate = Color(1.25, 1.1, 0.8)
		_play("special")
		Fx.flash(global_position + Vector2(0, -10), Color(1.0, 0.85, 0.5), 150.0, 0.8, 1.2)
		return
	if _ward != null:
		_ward.queue_free()
		_ward = null
	visual.modulate = Color.WHITE
	if broken:
		Audio.play(&"boss_ophanim", -2.0)
		Juice.shake(6.0)
		Juice.hit_stop(0.15, 0.08)
		Fx.flash(global_position + Vector2(0, -10), Color(1.0, 0.95, 0.8), 180.0, 0.9, 1.4)
		Fx.sparkle(global_position + Vector2(0, -10), Color(1.0, 0.85, 0.5), 28, 30.0)
		_play("hurt")


@rpc("authority", "call_remote", "reliable")
func _net_sealed(on: bool, broken: bool) -> void:
	_show_sealed(on, broken)


## A shield-bearer (data "shield") turns a blow that comes at its face while it
## is not swinging; from the wind-up to the end of its recovery it is open.
func _shield_holds(from: Vector2, round_it: bool) -> bool:
	if float(stats.get("shield", 0.0)) <= 0.0 or round_it or _guard_down:
		return false
	if state == State.WINDUP or state == State.STRIKE:
		return false
	var side := signf(from.x - global_position.x)
	return side == 0.0 or int(side) == facing


func _shield_fx() -> void:
	Audio.play_at(&"block", global_position, -2.0)
	Fx.impact(global_position + Vector2(facing * 8, -14), Vector2(-facing, 0), Color(1.0, 0.86, 0.6), 6)


@rpc("authority", "call_remote", "unreliable")
func _net_shield_fx() -> void:
	_shield_fx()


## A body that comes apart (on_death "split"): the run spawns the pieces awake
## beside it, and the room's door waits for them too.
func _split(spec: Dictionary) -> void:
	var count := clampi(int(spec.get("count", 2)), 1, 4)
	for i in count:
		var offset := Vector2((i - (count - 1) * 0.5) * 22.0, -10.0 - 6.0 * (i % 2))
		EventBus.enemy_spawn_requested.emit(str(spec.get("into", "shade")), global_position + offset)
	Fx.ring(global_position + Vector2(0, -8), 40.0, Color(stats.get("light", {}).get("color", "#9fe0ff")))


func _warded_fx() -> void:
	Audio.play_at(&"block", global_position, -4.0)
	Fx.sparkle(global_position + Vector2(0, -10), Color(1.0, 0.85, 0.5), 8, 16.0)
	if _ward != null:
		_ward.default_color = Color(1.0, 0.95, 0.75, 1.0)
		create_tween().tween_property(_ward, "default_color", Color(1.0, 0.86, 0.45, 0.7), 0.25)


@rpc("authority", "call_remote", "unreliable")
func _net_warded_fx() -> void:
	_warded_fx()


## The prop an elite leaves where it fell (data/props): a chest with a common
## item and some essence, the reward for the harder fight. Laid on every peer
## as each one sees the death (the way a secret wall leaves its cache), on the
## floor under the body — a flyer killed over a pit leaves nothing.
const ELITE_CACHE := "elite_cache"


func _leave_cache() -> void:
	var room := get_tree().get_first_node_in_group("room") as Node2D
	if room == null or not Data.props.has(ELITE_CACHE) or not is_inside_tree():
		return
	var query := PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -8), global_position + Vector2(0, 400), 1 | 16)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var cache: Prop = load("res://scenes/props/prop.tscn").instantiate()
	cache.name = "EliteCache"
	cache.prop_id = ELITE_CACHE
	room.add_child(cache)
	cache.global_position = hit.position as Vector2
	Fx.sparkle(cache.global_position + Vector2(0, -12), Color("#ffa060"), 14, 16.0)


## One of the chosen of the dead: an elite or a boss (the gift Trophy Hunter).
func is_chosen() -> bool:
	return stats.get("boss", false) or stats.get("tags", []).has("elite")


## A boss's fight, timed for its bestiary page (Profile.record_boss_time): from
## the first blow that lands on it to its fall, a cutscene not counted.
var fight_time := -1.0


func _time_fight(delta: float) -> void:
	if not stats.get("boss", false) or Game.cutscene:
		return
	if fight_time >= 0.0:
		fight_time += delta
	elif hp < _max_hp:
		fight_time = 0.0


## Counts as dead immediately; the body plays its death strip or an "ash" squash.
## On a client this is the mirror of the host's death: same theatre, no bookkeeping.
@rpc("authority", "call_remote", "reliable")
func _net_die(by_soldier := false) -> void:
	felled_by_soldier = by_soldier
	_die()


func _die() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	Faction.dying = self  # the listeners may ask whose kill it was (Faction.felled_by_soldier)
	EventBus.enemy_died.emit(StringName(enemy_id), global_position)
	Faction.dying = null
	if affix != "" and not felled_by_soldier:
		Profile.record_affix(enemy_id, affix)  # the bestiary page lists the affixes laid low
	var is_boss: bool = stats.get("boss", false)
	if _simulated and Game.practice == "":  # practice pays nothing
		# a body felled by another pays a share (Faction): not his victory
		Game.add_essence(float(stats.get("essence", 10)) * (Faction.essence_between() if felled_by_soldier else 1.0))
		if is_boss:
			Game.ash_earned += int(stats.get("ash", 10))
			if fight_time >= 0.0:
				Profile.record_boss_time(enemy_id, fight_time)
	if not is_boss and stats.get("tags", []).has("elite") and Game.practice == "" and not felled_by_soldier:
		_leave_cache.call_deferred()
	if _simulated:  # but a corpse that bursts still bursts: that is what is practised
		match stats.get("on_death", {}).get("type", ""):
			"explode":
				_explode(stats.on_death)
			"split":
				_split(stats.on_death)
	_voice("death", &"boss_death" if is_boss else &"enemy_death")
	Juice.shake(9.0 if is_boss else 2.5)
	if is_boss:
		Juice.hit_stop(0.25, 0.1)
		EventBus.boss_died.emit()
	set_physics_process(false)
	_clear_beam()
	collision_layer = 0
	collision_mask = 0
	contact_area.monitoring = false
	attack_area.monitoring = false
	hp_bar.visible = false
	# What it leaves is what it was made of (Fx.REMAINS): blood, rags, shards,
	# wisps, feathers, stars.
	var material := str(stats.get("material", "cloth"))
	var own := Color(stats.get("light", {}).get("color", stats.get("color", "#b0a0a0"))) \
		if material in ["spirit", "gold"] else Color(stats.get("color", "#b0a0a0"))
	Fx.remains(global_position + Vector2(0, -10), material, own, 2.5 if is_boss else 1.0)
	# blood, a pool under it, and — when data/gore.json allows — its own drawing
	# torn into pieces; a boss lingers whole for its last words
	var torn := Gore.death(self, enemy_id, material, null if is_boss else sprite,
		Vector2(_last_away, -0.2), _last_violent, _last_move)
	# Cosmetic essence has its own readable allegiance; the numeric reward above
	# is unchanged. Possession and undeath override a human origin.
	var dark := _soul_affinity() == "dark"
	var tint := Color(0.57, 0.37, 0.79) if dark else Color(1.0, 0.88, 0.61)
	Fx.essence_release(global_position + Vector2(0, -10), dark, 19 if is_boss else 9)
	Fx.flash(global_position + Vector2(0, -8), tint, 140.0 if is_boss else 60.0, 0.9 if is_boss else 0.4)
	if _shadow != null:
		_shadow.visible = false
	if _light != null:
		create_tween().tween_method(_light.set_base_energy, _light.energy, 0.0, 0.5)
	if is_boss and stats.get("lingers", true):
		# A boss is not a corpse: it dims and hangs where it fell, so the scene
		# that follows (its last words) has somebody to look at. The room takes
		# it away when it changes.
		if _has_anim.has("death"):
			sprite.play("death")
		create_tween().tween_property(visual, "modulate:a", 0.35, 1.2)
		return
	if torn:
		visual.visible = false
		await get_tree().create_timer(0.4).timeout
		if is_inside_tree():
			_leave()
		return
	if _has_anim.has("death"):
		sprite.play("death")
		await sprite.animation_finished
		if not is_inside_tree():
			return
		var tween := create_tween()
		tween.tween_property(visual, "modulate:a", 0.0, 0.35)
		tween.tween_callback(_leave)
	else:
		var tween := create_tween()
		tween.tween_property(visual, "scale", Vector2(1.7, 0.1), 0.12)
		tween.parallel().tween_property(visual, "modulate", Color(1, 1, 1, 0), 0.12)
		tween.tween_callback(_leave)


## Only the host removes the node: the spawner takes the corpse off the clients.
func _leave() -> void:
	if _simulated:
		queue_free()
	else:
		visible = false


## Elite mechanic: a blast around the corpse the player has to step away from.
func _explode(spec: Dictionary) -> void:
	var radius := float(spec.get("radius", 40))
	var damage := float(spec.get("damage", 12)) * Game.enemy_damage_multiplier()
	await get_tree().create_timer(float(spec.get("delay", 0.6))).timeout
	if not is_inside_tree():
		return
	Fx.puff(global_position, radius / 24.0, Color(1.0, 0.5, 0.3))
	Audio.play_at(&"explode", global_position)
	Juice.shake(4.0)
	for node in get_tree().get_nodes_in_group("player"):
		var victim := node as Player
		if victim != null and not victim.is_dead() and victim.global_position.distance_to(global_position) <= radius:
			victim.take_damage(damage, self)


## The sandbox uses the real windup, sprite frame gate and damage routines.
func studio_force_attack(index: int, target: Node2D) -> void:
	if enemy_id != StudioLive.ID or index < 0 or index >= _attacks.size() or target == null:
		return
	_cancel_telegraph()
	_strike_wait = false
	_clear_beam()
	showcase = ""
	_target = target
	_attack = _attacks[index]
	_begin_windup(target.global_position - global_position)
	StudioLive.report("ПОДГОТОВКА", self)


func _draw() -> void:
	if not studio_debug or _attack.is_empty():
		return
	var color := Color(1, 0.75, 0.2, 0.7) if state != State.STRIKE else Color(1, 0.2, 0.2, 0.8)
	draw_arc(Vector2.ZERO, float(_attack.get("range", 30)), 0, TAU, 64, Color(0.4, 0.7, 1, 0.45), 1)
	match _attack.get("type", "melee"):
		"nova":
			draw_arc(Vector2.ZERO, float(_attack.get("radius", 90)), 0, TAU, 64, color, 2)
		"melee":
			var shape := attack_shape.shape as RectangleShape2D
			draw_rect(Rect2(attack_area.position + Vector2(attack_shape.position.x * facing, attack_shape.position.y) - shape.size / 2, shape.size), color, false, 2)
		"beam":
			var length := float(_attack.get("length", 420))
			var thick := float(_attack.get("thickness", 26))
			var half := thick / 2 + 6
			draw_rect(Rect2(Vector2(-length, 10 - half), Vector2(length * 2, half * 2)), color, false, 2)
			draw_rect(Rect2(Vector2(-half, -length), Vector2(half * 2, length * 2)), color, false, 2)
