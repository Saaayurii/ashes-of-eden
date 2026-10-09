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
##   hang       {"lift", "range", "rope", "land"}: a walker that may wait on a noose
##              (a spawn marked "hanging"): untouchable up there, it drops when a
##              player comes within "range" and lies "land" seconds before it hunts.
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
const RETARGET_INTERVAL := 0.4
## A swing the player parried leaves its owner open this long (data can say
## otherwise: "parry_opening"); a boss gets its feet back in half the time. The
## first blow landed in that window is a riposte, worth half as much again.
const PARRY_OPENING := 0.9
const RIPOSTE_MULTIPLIER := 1.5
## The beat between "!" and the first step towards you.
const ALERT_TIME := 0.4
## An enemy that wakes up shouts; sleepers this close wake with it.
## An enemy at or under this share of its health can be executed outright.
const EXECUTE_BELOW := 0.3
const SHOUT_RADIUS := 90.0
## A hit that stops a body (a flinch, a broken wind-up) also keeps the next
## wind-up back this long after it is on its feet: hurt, a beat, then the
## telegraph, never a swing that grows straight out of the flinch.
const HIT_ATTACK_DELAY := 0.25
## Occasional repeats keep two-move enemies from becoming a strict metronome.
const REPEAT_ATTACK_WEIGHT := 0.18
## Physics layers a look or a step is stopped by: world (1) and ledges (5).
const SOLID_MASK := 1 | 16
## Per behaviour: sight range, sight height, feel-behind radius.
const SIGHT_DEFAULTS := {
	"walker": [210.0, 70.0, 40.0],
	"flyer": [260.0, 150.0, 48.0],
}
const PATROL_DEFAULTS := {"radius": 110.0, "speed": 0.45, "pause": [0.8, 2.4]}
## Spacing (docs/ENEMY_AI.md). How many walkers on one side of a player may
## step in to strike at once; the rest wait, each further back by CROWD_STEP.
const ATTACKERS_PER_SIDE := 2
const CROWD_STEP := 22.0
## A flyer hovers at least this far from the player it hunts, and is pushed off
## anyone's body inside PERSONAL_SPACE unless it is mid-attack.
const FLYER_MIN_GAP := 48.0
const PERSONAL_SPACE := 36.0
const FLOCK_SPACE := 30.0

@export var enemy_id: String = "possessed_villager"
## What this elite rose with (data/affixes), "" for none: chosen by the host
## at spawn (Run._spawn_enemy) and carried in the spawn data, so every peer
## builds the same body.
var affix := ""
## Set by the spawner for reinforcements: they arrive already fighting.
@export var start_aware := false
## Set by the spawn (EnemySpawn.hanging): it waits on a noose until a player
## comes near. Only a walker whose data has "hang" does; see _hang.
@export var start_hanging := false

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
var _beam_lines: Array[Line2D] = []
var _beam_hit := {}  # player -> already burned this beam
var _contact_cd := 0.0
var _attack_cd := 0.0
var _open_left := 0.0  # parried: the riposte window (see PARRY_OPENING)
var _state_left := 0.0
var _knockback := Vector2.ZERO
var _target: Player
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
const PECK_PATIENCE := 0.35
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
## Hanging ("hang" in the data: lift, range, rope, land). On the noose it is
## out of reach of every blow; a player within "range" (or a neighbour's shout)
## snaps the rope, it drops, and lies "land" seconds before it hunts — the
## beat to read, as any wind-up is.
const HANG_DEFAULTS := {"lift": 26.0, "range": 64.0, "rope": 150.0, "land": 0.6}
## How far up a rope looks for something to be tied to.
const HANG_TIE_REACH := 320.0
var _hanging := false
var _dropping := false
var _land_left := -1.0
var _rope: Line2D
var _sway_t := 0.0
var _sway_push := 0.0
var _hang_layer := 0
## The top of the drawn body in local pixels (the rope's knot), from _setup_sprite.
var _head_y := -16.0
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
		Net.attach_sync(self, [".:position", ".:facing", ".:aware"])


func _ready() -> void:
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
	_band_depth = randf_range(26.0, 52.0)
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
	aware = start_aware or bool(stats.get("aware", false)) or bool(stats.get("boss", false))
	state = State.CHASE if aware else State.PATROL
	set_process(false)  # only a client watching a hanging body needs it (_process)
	if Net.active:
		_simulated = multiplayer.is_server()
		set_physics_process(_simulated)
	if start_hanging and not aware and stats.has("hang") and not _is_flying():
		_hang()
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
			var loop: bool = anim in ["idle", "walk", "special", "hang"]
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
	_head_y = top + 3.0 * art_scale  # the strips keep a little air over the head
	ActionFx.attach(self, sprite, enemy_id, {"feet": Vector2(0, 11), "body": Vector2(0, (top + 11.0) * 0.5),
		"head": Vector2(0, top + 6.0), "hand": Vector2(12, -14), "back": Vector2(-6, 4)})
	sprite.visible = true
	body.visible = false
	visual = sprite


func _physics_process(delta: float) -> void:
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
	if _hanging:
		_hang_tick(delta)
		return
	if _dropping:
		_drop_tick(delta)
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
		var seen := _spot_player()
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
	if _target == null or not is_instance_valid(_target) or _target.is_dead() or _retarget <= 0.0:
		_retarget = RETARGET_INTERVAL
		_acquire_target()
		_crowd_rank = _count_crowd()
	if _target == null:
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
			if touched is Player and not touched.is_dead():
				_contact_cd = float(stats.get("attack_interval", 0.8))
				touched.take_damage(contact_damage, self)


## The nearest player still on their feet. In co-op both of you are fair game.
func _acquire_target() -> void:
	var best: Player = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("player"):
		var candidate := node as Player
		if candidate == null or candidate.is_dead():
			continue
		var distance := candidate.global_position.distance_squared_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	_target = best


# ------------------------------------------------------------- awareness ---

## Idle around the spawn point: walkers pace their ledge and turn at its edge,
## flyers drift between points in the air. Nothing here hurts anybody.
func _patrol(delta: float) -> void:
	var spec: Dictionary = stats.get("patrol", {})
	var radius := float(spec.get("radius", PATROL_DEFAULTS.radius))
	var speed := float(stats.get("speed", 50)) * float(spec.get("speed", PATROL_DEFAULTS.speed))
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
	velocity.y += 1100.0 * delta
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
func _spot_player() -> Player:
	for touched in contact_area.get_overlapping_bodies():
		if touched is Player and not touched.is_dead():
			return touched
	for node in get_tree().get_nodes_in_group("player"):
		var candidate := node as Player
		if candidate != null and not candidate.is_dead() and _can_see(candidate):
			return candidate
	return null


func _can_see(who: Player) -> bool:
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
func _notice(who: Player, shout := true) -> void:
	if _hanging:
		_snap(who)  # a shout, a touch: the rope goes
		return
	if not is_unaware():
		return
	_target = who
	aware = true
	_set_state(State.ALERT, ALERT_TIME)
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
					and other.global_position.distance_to(global_position) <= SHOUT_RADIUS:
				other._notice(who, false)


## What the sword sounds like landing on this body: its own clips if the
## bestiary has them (<voice>_impact_1..3), otherwise the set for whatever it
## is made of ("material" in the JSON: flesh, cloth, mail, plate, bone,
## feather, spirit, gold), otherwise the generic blow. Asked for by whoever
## swung, so the hit is heard the moment it lands and not a round trip later.
func impact_sound() -> StringName:
	if _hanging:
		return &"block"  # the blade glances off a body swinging out of reach
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


## On the noose over its spawn: the sole "lift" above the floor (a spawn
## stands 12 px over its floor, the sole is 11 under the origin), a rope from
## the knot up "rope" px, fading into the dark it is tied to.
func _hang() -> void:
	var spec := _hang_spec()
	_hanging = true
	# out of reach means out of reach: no sword, bolt or body finds it up there
	# (a swing that found it would still pay its on-hit gifts)
	_hang_layer = collision_layer
	collision_layer = 0
	global_position.y += 1.0 - spec.lift
	_home = global_position
	if _shadow != null:
		_shadow.position.y = 11.0 + spec.lift
	_rope = Line2D.new()
	_rope.name = "Rope"
	_rope.width = 2.0
	_rope.default_color = Color("#6b5434")
	_rope.texture_mode = Line2D.LINE_TEXTURE_NONE
	_rope.points = PackedVector2Array([Vector2(0, _head_y), Vector2(0, _head_y - spec.rope)])
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.55, Color.WHITE)
	_rope.gradient = fade
	_rope.z_index = -1
	add_child(_rope)
	_tie_rope.call_deferred()
	_play("hang" if _has_anim.has("hang") else "idle")
	if not _simulated:
		set_process(true)  # a client watches for the host's snap (aware), late peers too


## Tied to whatever stone or ledge is above it, if any is near enough; otherwise
## the rope fades into the dark (a painted branch, a beam we have no collider for).
func _tie_rope() -> void:
	if _rope == null or not is_inside_tree():
		return
	var knot := global_position + Vector2(0, _head_y)
	var query := PhysicsRayQueryParameters2D.create(knot, knot + Vector2(0, -HANG_TIE_REACH), SOLID_MASK)
	query.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	_rope.set_point_position(1, Vector2(0, to_local(hit.position).y))
	_rope.gradient = null  # tied: drawn all the way up


func _hang_spec() -> Dictionary:
	var spec: Dictionary = HANG_DEFAULTS.duplicate()
	for key in stats.get("hang", {}):
		spec[key] = float(stats.hang[key])
	return spec


## On the host: it sways, untouchable, until somebody walks under it.
func _hang_tick(delta: float) -> void:
	velocity = Vector2.ZERO
	_sway_t += delta
	_sway_push = move_toward(_sway_push, 0.0, delta * 1.5)
	var sway := roundf(sin(_sway_t * 1.7) * (0.6 + _sway_push * 2.5))
	sprite.position.x = sway
	_rope.set_point_position(0, Vector2(sway, _head_y))
	if Game.cutscene:
		return
	var spec := _hang_spec()
	for node in get_tree().get_nodes_in_group("player"):
		var who := node as Player
		if who == null or who.is_dead():
			continue
		var d := who.global_position - global_position
		if absf(d.x) <= spec.range and d.y > -40.0 and d.y < spec.lift + 60.0:
			_snap(who)
			return
	for touched in contact_area.get_overlapping_bodies():
		if touched is Player and not touched.is_dead():
			_snap(touched)
			return


## The rope gives: it drops, awake, facing whoever came.
func _snap(who: Player) -> void:
	if not _hanging:
		return
	_target = who
	var d := who.global_position.x - global_position.x
	if absf(d) > 4.0:
		facing = 1 if d > 0.0 else -1
	aware = true
	_dropping = true
	_land_left = -1.0
	_set_state(State.RECOVER, 0.0)  # not unaware any more: no backstab on the way down
	_snap_fx()
	if Net.active:
		_net_snap.rpc(facing)


func _snap_fx() -> void:
	if not _hanging:
		return
	_hanging = false
	collision_layer = _hang_layer
	set_process(false)
	sprite.position.x = 0.0
	var knot := global_position + Vector2(0, _head_y)
	Audio.play_at(&"prop_break", knot, -8.0)
	_voice("alert", &"", -6.0)
	Fx.debris(knot, Color("#6b5434"), 5)
	_play("fall" if _has_anim.has("fall") else "hurt")
	if _shadow != null:
		create_tween().tween_property(_shadow, "position:y", 11.0, 0.35)
	if _rope != null:
		# the cut end whips up into the dark it hung from
		var rope := _rope
		_rope = null
		var tween := rope.create_tween().set_parallel()
		tween.tween_property(rope, "position:y", -24.0, 0.4)
		tween.tween_property(rope, "modulate:a", 0.0, 0.4)
		tween.chain().tween_callback(rope.queue_free)


@rpc("authority", "call_remote", "reliable")
func _net_snap(new_facing: int) -> void:
	facing = new_facing
	_snap_fx()


## A client: the snap arrives as an rpc, or — a peer let in after it — as the
## replicated `aware` of a body that is still drawn on its rope.
func _process(_delta: float) -> void:
	if _hanging and aware and not _simulated:
		_snap_fx()


## Falling, then a beat on the ground before the hunt.
func _drop_tick(delta: float) -> void:
	_hold(delta)
	_knockback = _knockback.move_toward(Vector2.ZERO, 700.0 * delta)
	move_and_slide()
	if not is_on_floor():
		return
	if _land_left < 0.0:
		_land_left = _hang_spec().land
		Audio.play_at(&"land", global_position)
		Fx.dust(global_position + Vector2(0, 11), Vector2.UP, 9)
		_play("land" if _has_anim.has("land") else "idle")
	_land_left -= delta
	if _land_left <= 0.0:
		_dropping = false
		_set_state(State.CHASE, 0.0)


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
	var speed := float(stats.get("speed", 50))
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
			var distance := maxf(FLYER_MIN_GAP, float(stats.get("hover_distance", 60.0))) \
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
				if _peck_time > PECK_PATIENCE:
					# the run came to nothing (another move was picked, or none):
					# out, rather than hanging over his head
					pecking = false
					_peck_time = 0.0
					_disengage_left = randf_range(0.6, 0.9)
					distance += 60.0
					height += 26.0
			else:
				_peck_time = 0.0
			var goal := to_target - Vector2(side * distance, height)
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
			velocity.y += 1100.0 * delta
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
			elif _attack_cd <= 0.3 and _crowd_rank < ATTACKERS_PER_SIDE:
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
			velocity.y += 1100.0 * delta


## Between blows: a walker holds a distance just outside its reach, paced
## in and out now and then, further back for each of its kind ahead of it on
## this side (so a crowd forms a queue, not a stack). Returns the x speed.
func _keep_distance(to_target: Vector2, melee_range: float, speed: float, aggro: float, delta: float) -> float:
	var gap := absf(to_target.x)
	var toward := signf(to_target.x)
	var band_in := melee_range + 12.0 + CROWD_STEP * _crowd_rank
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
	if depth >= PERSONAL_SPACE:
		return Vector2.ZERO
	var away := -chest.normalized() if depth > 0.5 else Vector2(-float(facing), -1.0).normalized()
	return away * (1.0 - depth / PERSONAL_SPACE)


## Flyers keep off one another, so a flock reads as several birds.
func _flock() -> Vector2:
	var push := Vector2.ZERO
	for node in get_tree().get_nodes_in_group("enemies"):
		var other := node as Enemy
		if other == null or other == self or other.is_dead() or not other._is_flying():
			continue
		var apart := global_position - other.global_position
		if apart.length() < FLOCK_SPACE:
			push += (apart.normalized() if apart.length() > 0.5 else Vector2.UP) * (1.0 - apart.length() / FLOCK_SPACE)
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
	for i in candidates:
		var weight := maxf(0.0, float(_attacks[i].get("weight", 1.0)))
		total += weight * (REPEAT_ATTACK_WEIGHT if candidates.size() > 1 and i == _last_attack else 1.0)
	var roll := attack_rng.randf() * total
	for i in candidates:
		var weight := maxf(0.0, float(_attacks[i].get("weight", 1.0)))
		roll -= weight * (REPEAT_ATTACK_WEIGHT if candidates.size() > 1 and i == _last_attack else 1.0)
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
	_telegraph(_state_left, beam, length, thickness, color)
	if Net.active:
		_net_telegraph.rpc(facing, _state_left, beam, length, thickness, color)


## The telegraph: a bright pulse the player can read from across the room, and
## the breath before the swing for anyone looking the other way. Runs on every
## peer already, so the sound rides along without an RPC of its own.
func _telegraph(duration: float, beam := false, length := 420.0, thickness := 26.0, color := "#ffe9a8") -> void:
	_voice("attack", &"enemy_windup", -11.0)
	_play(str(_attack.get("animation", "attack")), true)
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
func _net_telegraph(new_facing: int, duration: float, beam: bool, length: float, thickness: float, color: String) -> void:
	facing = new_facing
	_telegraph(duration, beam, length, thickness, color)


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


func _strike(to_target: Vector2) -> void:
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
			_nova_fx(float(_attack.get("radius", 90)), str(_attack.get("color", "#b86cff")))
			_nova_hit()
			if Net.active:
				_net_nova.rpc(float(_attack.get("radius", 90)), str(_attack.get("color", "#b86cff")))


func _lunge_fx() -> void:
	var animation := str(_attack.get("animation", "attack"))
	if _has_anim.has(animation) and sprite.sprite_frames.get_frame_count(animation) > 1:
		sprite.frame = 1
	Juice.shake(3.0)


func _beam_fx(length: float, thickness: float, color: String) -> void:
	var animation := str(_attack.get("animation", "attack"))
	if _has_anim.has(animation) and sprite.sprite_frames.get_frame_count(animation) > 1:
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


func _nova_fx(radius: float, color: String) -> void:
	Fx.flash(global_position + Vector2(0, -8), Color(color), radius, 0.45, 1.2)
	# the ring runs out to exactly where the blast hurts; the smoke stays small
	Fx.ring(global_position + Vector2(0, -8), radius, Color(color), 0.35)
	Fx.puff(global_position + Vector2(0, -8), 0.9, Color(color))
	Juice.shake(4.0)


func _nova_hit() -> void:
	var radius := float(_attack.get("radius", 90))
	for node in get_tree().get_nodes_in_group("player"):
		var victim := node as Player
		if victim != null and not victim.is_dead() and victim.global_position.distance_to(global_position) <= radius:
			victim.take_damage(float(_attack.get("damage", 12)), self)


@rpc("authority", "call_remote", "reliable")
func _net_nova(radius: float, color: String) -> void:
	_nova_fx(radius, color)


## One round of a ranged attack: projectiles fanned over spread, each at its
## own speed when the attack has a speed_jitter. aim is the vector to the target,
## or zero to look for it again (a volley's later rounds).
func _fire_round(attack: Dictionary, aim: Vector2) -> void:
	if is_dead() or not is_inside_tree():
		return
	if aim == Vector2.ZERO:
		var target := _nearest_player()
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
		if Net.active:
			_net_projectile.rpc(origin, shot, speed, str(attack.get("color", "#ffd27a")), _projectile_style(attack),
				str(attack.get("projectile_motion", "straight")), float(attack.get("motion_amount", 0.0)),
				float(attack.get("projectile_scale", 1.0)))


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
	projectile.cosmetic = cosmetic
	projectile.shooter_id = enemy_id
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
		style: String, motion: String, motion_amount: float, size: float) -> void:
	var projectile := PROJECTILE_SCENE.instantiate()
	projectile.damage = 0.0
	projectile.speed = speed
	projectile.direction = direction
	projectile.tint = Color(color)
	projectile.visual_style = style
	projectile.size = size
	projectile.motion = motion
	projectile.motion_amount = motion_amount
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
	for node in get_tree().get_nodes_in_group("player"):
		var victim := node as Player
		if victim == null or victim.is_dead() or _beam_hit.has(victim):
			continue
		var d := victim.global_position - global_position
		if (absf(d.y - 10.0) < half and absf(d.x) < length) or (absf(d.x) < half and absf(d.y) < length):
			_beam_hit[victim] = true
			victim.take_damage(float(_attack.get("damage", 20)), self)


func _clear_beam() -> void:
	for line in _beam_lines:
		line.queue_free()
	_beam_lines.clear()


func _melee_hit() -> void:
	attack_area.monitoring = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree() or state == State.DEAD:
		return
	for body_hit in attack_area.get_overlapping_bodies():
		if body_hit is Player and not body_hit.is_dead():
			body_hit.take_damage(float(_attack.get("damage", 10)), self)
	attack_area.monitoring = false


## The second frame of the swing, for the enemies that have one drawn.
func _hold_attack_frame() -> void:
	var animation := str(_attack.get("animation", "attack"))
	if _has_anim.has(animation) and sprite.sprite_frames.get_frame_count(animation) > 1:
		sprite.frame = 1


func _set_state(new_state: State, duration: float) -> void:
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
	if Net.active and not multiplayer.is_server():
		if multiplayer.get_peers().has(1):
			_net_hit.rpc_id(1, amount, from, crit, knockback, sneak, execute)
		return
	_apply_damage(amount, from, source != null, crit, knockback, sneak, execute)


@rpc("any_peer", "call_remote", "reliable")
func _net_hit(amount: float, from: Vector2, crit: bool, knockback: float, sneak: float, execute := 0.0) -> void:
	_apply_damage(amount, from, true, crit, knockback, sneak, execute)


## [param sneak] is what the blow is worth on a body that never saw it coming;
## only the host knows whether this one did, so the multiplier is applied here.
func _apply_damage(amount: float, from: Vector2, pushed: bool, crit: bool, knockback: float, sneak := 1.0,
		execute := 0.0) -> void:
	if state == State.DEAD:
		return
	if _hanging:
		_sway_push = 1.0  # out of reach: the blow only sets it swinging
		return
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
	var backstab := is_unaware() and sneak > 1.0
	if backstab:
		amount *= sneak
		crit = true
		EventBus.technique_performed.emit("backstab")
	# The execution: worth nothing on a healthy body, everything on a spent one.
	# Only this side knows how much is left, so the multiplier is applied here.
	if execute > 0.0 and hp <= _max_hp * EXECUTE_BELOW:
		amount *= 1.0 + execute
		crit = true
	var riposte := _open_left > 0.0
	if riposte:
		_open_left = 0.0  # one riposte per parry
		EventBus.technique_performed.emit("riposte")
		amount *= RIPOSTE_MULTIPLIER
		crit = true
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
	_hit_fx(amount, crit, hp, away, backstab)
	if Net.active:
		_net_hit_fx.rpc(amount, crit, hp, _max_hp, away, backstab)
	if riposte:
		_riposte_fx()
		if Net.active:
			_net_riposte_fx.rpc()
	if is_unaware():
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
			_attack_cd = maxf(_attack_cd, _state_left + HIT_ATTACK_DELAY)
			_cancel_telegraph()
			if Net.active:
				_net_cancel_telegraph.rpc()
		elif state == State.CHASE:
			# Knocked out of its stride: while it is walking at you a hit has to
			# actually stop it, otherwise the body walks the push straight off
			# and the sword looks like it passed through. An attack already in
			# motion still plays out — that is what stagger_chance is for.
			_set_state(State.RECOVER, float(stats.get("flinch", 0.18)))
			_attack_cd = maxf(_attack_cd, _state_left + HIT_ATTACK_DELAY)
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
	if hp <= 0.0:
		if Net.active:
			_net_die.rpc()
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
	_attack_cd = maxf(_attack_cd, duration + HIT_ATTACK_DELAY)


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
	var opening := float(stats.get("parry_opening", PARRY_OPENING)) * (0.5 if boss else 1.0)
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
func _hit_fx(amount: float, crit: bool, new_hp: float, away := 1.0, backstab := false) -> void:
	Game.note_dealt(amount)  # the night's numbers (every peer sees every blow)
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
func _net_hit_fx(amount: float, crit: bool, new_hp: float, max_hp: float, away: float, backstab: bool) -> void:
	hp = new_hp
	_max_hp = maxf(max_hp, 1.0)
	_hit_fx(amount, crit, new_hp, away, backstab)


## Attack type "summon": after its wind-up, calls "count" of "id" out of the
## ground beside it, unless "max_alive" of them are already about. The run
## spawns them (replicated in a session).
func _call_up(attack: Dictionary) -> void:
	_summon_fx()
	var wanted := mini(int(attack.get("count", 1)), int(attack.get("max_alive", 2)) - _summons_near(attack))
	for i in wanted:
		var offset := Vector2(randf_range(24.0, 60.0) * (1 if i % 2 == 0 else -1), -18.0)
		EventBus.enemy_spawn_requested.emit(str(attack.get("id", "shade")), global_position + offset)
		Fx.puff(global_position + offset, 1.0, Color(0.6, 0.4, 0.8))


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
	var key := room.scene_file_path.get_file().get_basename() if room != null else ""
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
func _net_die() -> void:
	_die()


func _die() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	EventBus.enemy_died.emit(StringName(enemy_id), global_position)
	if affix != "":
		Profile.record_affix(enemy_id, affix)  # the bestiary page lists the affixes laid low
	var is_boss: bool = stats.get("boss", false)
	if _simulated and Game.practice == "":  # practice pays nothing
		Game.add_essence(float(stats.get("essence", 10)))
		if is_boss:
			Game.ash_earned += int(stats.get("ash", 10))
			if fight_time >= 0.0:
				Profile.record_boss_time(enemy_id, fight_time)
	if not is_boss and stats.get("tags", []).has("elite") and Game.practice == "":
		_leave_cache.call_deferred()
	if _simulated:  # but a corpse that bursts still bursts: that is what is practised
		match stats.get("on_death", {}).get("type", ""):
			"explode":
				_explode(stats.on_death)
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
