extends CharacterBody2D
class_name Player
## Elian, the Unborn. Side-view platformer body in the spirit of Dead Cells:
## snappy run, jump + one air jump, coyote time, jump buffer, variable jump
## height, a roll with i-frames, a 3-hit sword combo, a block that parries
## when it is timed, three healing charges.
## Every tunable number lives in [member stats] so gifts can modify it.
## Numbers: docs/BALANCE.md.
##
## Online (docs/MULTIPLAYER.md): one body per peer. The peer that owns a body
## is the only one that reads input for it and the only one that decides what
## it takes; everyone else receives its pose. A hit from anywhere therefore
## travels to the owner through [method take_damage].

const BASE_STATS := {
	"max_hp": 100.0,
	"speed": 150.0,
	"acceleration": 1800.0,
	"friction": 750.0,          # letting go of the stick: a short slide, not a stop
	"slide_friction": 1400.0,   # bleeding off the roll's speed after it ends
	"jump_velocity": 320.0,
	"gravity": 1100.0,
	"max_jumps": 2,
	"attack_damage": 10.0,
	"attack_cooldown": 0.8,     # 1.25 swings per second
	"attack_scale": 1.0,
	"crit_chance": 0.05,
	"crit_multiplier": 1.75,
	"backstab_multiplier": 2.5,  # a sword on a body that never saw it coming
	"dash_speed": 400.0,        # "dash" == roll; ~2.5 body lengths in dash_time
	"dash_time": 0.30,          # = i-frames
	"dash_cooldown": 2.2,
	"armor": 0.0,
	"lifesteal": 0.0,
	"extra_lives": 0,
	"heal_charges": 3,
	# Gift mechanics. All zero by default: a body with no gifts behaves exactly
	# as it did before any of them existed (docs/DATA_FORMATS.md).
	"thorns": 0.0,          # fraction of a blow taken sent straight back
	"execute": 0.0,         # extra damage to an enemy already on its knees
	"kill_heal": 0.0,       # health a kill is worth
	"clear_heal": 0.0,      # health a cleared room is worth
	"dash_damage": 0.0,     # what the roll does to whatever it passes through
	"wave_damage": 0.0,     # the finisher's arc, as a fraction of attack_damage
	"guard": 0,             # blows absorbed outright, refilled each room
	"essence_bonus": 0.0,   # extra essence from every kill
	# Item mechanics (data/items): interactions, not bigger numbers. Zero = absent.
	"heal_burst": 0.0,          # the flask also scorches every enemy within HEAL_BURST_RADIUS for this much
	"parry_stun": 0.0,          # a parry also stops every enemy within PARRY_STUN_RADIUS for this long
	"chest_heal": 0.0,          # health an opened chest is worth
	"backstab_refresh": 0.0,    # 1 = a backstab gives the roll back at once
	"clean_clear_charge": 0.0,  # 1 = a room cleared without a wound refills one flask
	"wrath_after_hit": 0.0,     # after a wound, the next swing inside WRATH_TIME is worth this much more
	"desperate_crit_heal": 0.0, # under a third of the bar, each critical blow heals this much
}
## Where the item mechanics above reach.
const HEAL_BURST_RADIUS := 72.0
const PARRY_STUN_RADIUS := 90.0
const WRATH_TIME := 2.0
const DESPERATE_SHARE := 0.33
const COMBO_MULTIPLIERS := [1.0, 1.1, 1.6]  # 10 · 11 · 16
## A chain is meant to be chainable: the first two swings recover in a fraction
## of [code]attack_cooldown[/code], only the finisher costs the full swing. With
## one flat cooldown the window below was never actually reachable.
const COMBO_RECOVERY := [0.45, 0.45, 1.0]
## How long the chain stays open after a swing. Comfortably longer than the
## fast recovery, so a chain is a rhythm and not a frame-perfect input.
const COMBO_WINDOW := 1.0
## How long each swing owns the body (frames / fps of the strip), by animation.
const SWING_TIME := {"attack": 0.25, "attack2": 0.27, "attack3": 0.31, "thrust": 0.25, "rising": 0.25, "dash_strike": 0.25}
## The chain's three swings, in order.
const SWING_ANIMATIONS := ["attack", "attack2", "attack3"]
## The special moves (docs/TECHNIQUES.md). Lunge: back, then forward, then
## attack, each within LUNGE_WINDOW; a short rush that runs the sword through
## everything in the way. Cleave: attack held CHARGE_AFTER past a swing starts
## a charge (slow feet, the blade drawn back); let go after CHARGE_FULL and it
## comes down hard and stops what it lands on. Sweep: down + attack on the
## ground, a low cut that takes the legs from under a walker.
const LUNGE_WINDOW := 0.3
const LUNGE_SPEED := 360.0
const LUNGE_TIME := 0.18
const LUNGE_MULTIPLIER := 1.6
const CHARGE_AFTER := 0.3
const CHARGE_FULL := 0.6
const CHARGE_SPEED := 0.35
## ×3 on one blow after ~0.9 s of charge: ~19 damage a second against the
## chain's ~22 (docs/BALANCE_PROBE.md, "The moves") — worth the wait, never
## worth doing instead of fighting.
const CLEAVE_MULTIPLIER := 3.0
const CLEAVE_STAGGER := 0.6
const SWEEP_MULTIPLIER := 0.8
const SWEEP_STAGGER := 0.9
const TECHNIQUE_TIME := {"lunge": 0.3, "cleave": 0.35, "sweep": 0.3}
## Landing faster than this earns the crouch.
const HARD_LANDING := 300.0
## A blow worth this much of the bar throws the body off its feet (visually).
const KNOCKBACK_FRACTION := 0.2
## Block and parry (docs/BALANCE.md; not the ward gift, which is stats.guard).
## Holding the button is the safe, boring answer: a blow from the front still
## lands, for a third of what it was worth. The first moments of a *fresh*
## block are the parry: nothing lands, the swing is thrown back and the body
## that swung is left open. Timing is rewarded, mashing is not — the window only
## opens on a new press, and only once the last block has been down a moment.
const PARRY_WINDOW := 0.22
const BLOCK_REDUCTION := 0.65
const BLOCK_SPEED := 0.35
const BLOCK_RECOVERY := 0.35
const PARRY_PUSH := 90.0
const BLOCK_PUSH := 40.0
const HEAL_AMOUNT := 35.0
const HEAL_TIME := 1.0
## A short counterattack window after a real wound. Only sword hits against
## living enemies reclaim health; potions and passive healing cannot farm it.
const RALLY_TIME := 2.4
const RALLY_DAMAGE_SHARE := 0.35
const RALLY_HIT_SHARE := 0.4
const RALLY_MAX_HP_SHARE := 0.15
## A landed blow must not become several wounds just because two attack
## hitboxes overlap on the same frame. Hazards and scripted damage bypass it.
const HURT_GRACE_TIME := 0.24
## The riposte the roll earns. A real enemy blow that the i-frames swallowed
## leaves the blade hot: the next sword hit that actually lands on something
## alive is worth a little more. One charge per roll, one swing to spend it,
## and it never stacks — dodging is meant to be answered, not farmed.
const DODGE_COUNTER_TIME := 2.0
const DODGE_COUNTER_BONUS := 0.2
## Cold steel, the colour the ward and the block already use.
const DODGE_COUNTER_TINT := Color(0.8, 0.9, 1.0)
## Ground covered between two footsteps, in pixels.
const STEP_DISTANCE := 34.0
const COYOTE_TIME := 0.1
const JUMP_BUFFER := 0.12
const JUMP_CUT_VELOCITY := -110.0
## Down + jump on a ledge: how long the ledge layer (5) is ignored while dropping through.
const DROP_THROUGH_TIME := 0.18
const LEDGE_LAYER := 16
const STEP_HEIGHT := 12.0
const MANTLE_RISE := 104.0
const MANTLE_TIME := 0.22

## --- ground slam ---
## Down in the air drops him like a stone onto whatever is beneath. It is free
## — no cooldown, no gift — because what it costs is height and the moment he
## spends planted afterwards, and because a move with a meter on it stops
## being one you reach for without thinking.
const SLAM_SPEED := 760.0
## Below this there is no room to build the fall, and slamming out of a hop
## would turn a mistimed jump into an attack nobody meant to make.
const SLAM_MIN_HEIGHT := 26.0
const SLAM_RADIUS := 38.0
## Of attack_damage. Less than a sword because it lands on everything at once
## and costs no swing; the knockdown is the point, not the number.
const SLAM_DAMAGE_SHARE := 0.9
## He cannot steer while falling, and is briefly planted where he lands.
const SLAM_RECOVERY := 0.22

## --- wall grab ---
## Pressed into a wall in mid-air he catches it and slides instead of falling.
## Not a climb: gravity still wins, only slowly, and only while the stick is
## held into the wall.
const WALL_SLIDE_SPEED := 72.0
## A push off the wall, away and up. It costs the air jump it hands back, so a
## wall is a second chance rather than unlimited height.
const WALL_JUMP_PUSH := 230.0
const WALL_JUMP_RISE := 0.92  # of jump_velocity
## Long enough for the push to carry him clear before the stick can steer back
## into the wall and stick to it again.
const WALL_JUMP_TURN_LOCK := 0.16

## An enemy this close to the rolling body is caught by a cutting roll.
const DASH_REACH := 22.0
## The arc a finisher throws when a gift gives it one.
const WAVE_SCENE := preload("res://scenes/fx/projectile.tscn")
const WAVE_SPEED := 260.0
## Enemy bodies are not solid to the player. Sword hitboxes and attack/contact
## areas remain on their own layers, so a chase cannot shove an idle hero.
## Slot 1 wears a colder cloth so the two of you never lose each other.
const SLOT_TINTS := [Color.WHITE, Color(0.72, 0.84, 1.05)]
## What the other peer needs to draw this body. The rest is local theatre.
const NET_PROPERTIES := [".:position", ".:facing", ".:hp", ".:net_anim", ".:slot", ".:skin"]

signal died(player: Player)

## The cloak he wears (data/skins). Our own body takes it from Settings; the
## other player's arrives with its synchronizer and dyes their body here.
var skin := "":
	set(value):
		if value == skin:
			return
		skin = value
		if is_node_ready():
			_dress()

var stats: Dictionary = BASE_STATS.duplicate()
var hp: float
var facing := 1  # -1 left, 1 right
var heal_charges := 3
## Item state: a wound this room (clean_clear_charge), the wrath window (wrath_after_hit).
var _wounded_this_room := false
var _wrath_left := 0.0
var controls_enabled := true
## Which of the two seats this body is. Drives spawn point and tint.
var slot := 0
## Duels only: the sword also bites other players.
var versus := false
## Replicated body animation, so a remote body is not just a sliding sprite.
var net_anim := "idle":
	set(value):
		net_anim = value
		if not _is_mine() and body != null and body.sprite_frames.has_animation(value):
			body.play(value)

var _jumps_left := 0
var _coyote := 0.0
var _jump_buffer := 0.0
var _drop_left := 0.0
var _turn_lock_left := 0.0
var _mantle_left := 0.0
var _mantle_start := Vector2.ZERO
var _mantle_end := Vector2.ZERO
var _was_on_floor := false
## Falling on purpose: set on the way down, spent on landing.
var _slamming := false
var _slam_recovery := 0.0
## Which way the wall he is holding lies (-1 left of him, 1 right), 0 for none.
var _wall_side := 0
## The soft light the hero carries and the blob under the feet (Fx.light / Fx.shadow).
var _light: GlowLight
## The path the soul leans towards shows on the body (never as numbers): motes
## of its colour and a tint on the carried light. See _update_aura.
const LIGHT_COLOR := Color(1.0, 0.93, 0.8)
const AURA := {
	"grace": [Color(1.0, 0.88, 0.5), Vector2(0, -26)],       # gold, rising
	"temptation": [Color(0.85, 0.12, 0.15), Vector2(0, 14)],  # embers of blood, sinking
	"will": [Color(0.72, 0.7, 0.68), Vector2(8, -6)],         # ash, drifting
}
## The three marks, in the order assets/shaders/alignment_marks.gdshader
## expects them.
const MARK_MODE := {"grace": 0, "temptation": 1, "will": 2}
const MARKS_SHADER := preload("res://assets/shaders/alignment_marks.gdshader")
var _aura: CPUParticles2D
var _shadow: Sprite2D
var _step_left := 0.0
## Blows the ward still has in it, refilled at the start of every room.
var _guard_left := 0
## Whoever this roll has already cut, so one roll is one hit per body.
var _dash_hit := {}
var _dash_left := 0.0
## How long the counter the last roll earned is still worth something.
var _dodge_counter_left := 0.0
## This roll has already earned its counter: a second blow swallowed by the
## same i-frames is not a second charge.
var _dodge_counted := false
var _hurt_grace_left := 0.0
## Sword out. Sheathed until somebody notices us or we swing; the draw is a
## beat of theatre when the first enemy in a room wakes up.
var _armed := false
var _arm_check := 0.0
## A one-shot animation (draw, hurt, land, knockback) owns the body this long.
var _scripted_left := 0.0
var _fall_speed := 0.0
var _dash_cd := 0.0
var _attack_cd := 0.0
var _attack_cd_total := 0.0
var _attack_anim_left := 0.0
var _combo := 0
## Special-move input: a tap opens the lunge window, a tap the other way
## inside it arms the lunge. _tap_facing is the first tap's direction.
var _back_tap_left := 0.0
var _tap_facing := 1
var _lunge_armed_left := 0.0
var _lunge_left := 0.0
## How long attack has been held, and the charge it became.
var _attack_held := 0.0
var _charging := false
var _charge_time := 0.0
var _charge_ready := false
var _combo_timer := 0.0
var _healing_left := 0.0
var _rally_left := 0.0
var _rally_pool := 0.0
var _blocking := false
## The button on the previous tick. Freshness is tracked here rather than with
## is_action_just_pressed, which belongs to render frames and can be missed by
## (or seen twice by) the physics tick that decides the parry.
var _block_was_down := false
var _parry_left := 0.0
var _block_cd := 0.0
var _dead := false
## The active skill a gift gave (AbilitySystem, effect "skill"): its spec, see
## docs/DATA_FORMATS.md. Empty = none yet. One at a time; a new one replaces it.
var skill: Dictionary = {}
var _skill_cd := 0.0
## Where the body last stood on firm ground for a moment: lava puts it back here.
var _safe_position := Vector2.ZERO
var _safe_time := 0.0
var _burn_left := 0.0
## A fall beyond the room bounds ends the night immediately, even with an
## extra-life gift: there is nowhere to revive inside the void.
var fell_outside_room := false
var _tag: Label
var _tag_bar: ColorRect

@onready var body: AnimatedSprite2D = $Body
@onready var hitbox: Area2D = $Hitbox
@onready var hitbox_collision: CollisionShape2D = $Hitbox/Collision
@onready var slash: AnimatedSprite2D = $Hitbox/Slash
@onready var camera: Camera2D = $Camera


## Called by whoever spawns us, after setting our authority and *before* we
## enter the tree: a synchronizer that learns its authority any later is too
## late for the spawner to give it a network id.
func attach_net_sync() -> void:
	if Net.active and not has_node("NetSync"):
		Net.attach_sync(self, NET_PROPERTIES)


func _ready() -> void:
	hp = stats.max_hp
	# a vial of wrath may take a flask away before the night starts (data/vials)
	stats.heal_charges = maxf(1.0, float(stats.heal_charges) + float(Vials.rule("flasks")))
	heal_charges = int(stats.heal_charges)
	_emit_hp()
	hitbox_collision.shape = hitbox_collision.shape.duplicate()  # per-player reach, not shared scene data
	slash.animation_finished.connect(func() -> void: slash.visible = false)
	EventBus.boss_died.connect(func() -> void: heal_charges = int(stats.heal_charges); _emit_hp())
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.room_cleared.connect(_on_room_cleared)
	EventBus.room_started.connect(func(_index: int) -> void:
		_guard_left = int(stats.guard)
		_armed = false
		_rally_pool = 0.0
		_rally_left = 0.0
		_hurt_grace_left = 0.0
		_wounded_this_room = false)
	body.modulate = SLOT_TINTS[slot % SLOT_TINTS.size()]
	if _is_mine():
		skin = Skins.worn(Settings.skin)
		Settings.changed.connect(func() -> void: skin = Skins.worn(Settings.skin))
	_dress()
	_light = Fx.light(self, Vector2(0, -12), LIGHT_COLOR, 110.0, 0.55, 0.0, 0.06)
	EventBus.alignment_changed.connect(func(_alignment: Dictionary) -> void: _update_aura())
	EventBus.run_restored.connect(_update_aura)
	_update_aura.call_deferred()  # a habit (Profile.habit) shows from the first frame of the night
	_shadow = Fx.shadow(self, Vector2(0, 14), 22.0, 0.8)
	# The painted rooms are deliberately larger than a screen. A slightly closer
	# camera stops a 1280x720 level reading as one small diorama on wide displays.
	camera.zoom = Vector2(1.14, 1.14)
	if versus:
		hitbox.collision_mask |= 2  # layer 2 = other players
	if Net.active:
		_setup_net()


## True when this body is ours to drive: single player, or our seat in a session.
func _is_mine() -> bool:
	return not Net.active or is_multiplayer_authority()


func _setup_net() -> void:
	var mine := _is_mine()
	camera.enabled = mine
	if mine:
		camera.make_current()
	# A body we do not own is posed by the synchronizer, never simulated here:
	# two peers running the same physics would fight over the same position.
	set_physics_process(mine)
	if not mine:
		_add_tag()


## A name and a slim health bar over the other player's head.
func _add_tag() -> void:
	_tag = Label.new()
	_tag.text = Net.name_of(get_multiplayer_authority())
	_tag.add_theme_font_size_override("font_size", 6)
	_tag.add_theme_color_override("font_color", SLOT_TINTS[slot % SLOT_TINTS.size()])
	_tag.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_tag.add_theme_constant_override("shadow_offset_x", 1)
	_tag.add_theme_constant_override("shadow_offset_y", 1)
	_tag.position = Vector2(-20, -44)
	_tag.size = Vector2(40, 8)
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_tag)
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.5)
	back.position = Vector2(-11, -32)
	back.size = Vector2(22, 2)
	add_child(back)
	_tag_bar = ColorRect.new()
	_tag_bar.color = Color(0.85, 0.35, 0.35)
	_tag_bar.position = Vector2(-11, -32)
	_tag_bar.size = Vector2(22, 2)
	add_child(_tag_bar)


## Called by AbilitySystem after stats change.
func refresh_stats() -> void:
	# A ward taken mid-room is worth something now, not at the next door.
	_guard_left = maxi(_guard_left, int(stats.guard))
	hp = minf(hp, stats.max_hp)
	hitbox.scale = Vector2(facing, 1) * stats.attack_scale
	_emit_hp()


func _process(delta: float) -> void:
	if _tag_bar != null:
		_tag_bar.size.x = 22.0 * clampf(hp / stats.max_hp, 0.0, 1.0)
		body.flip_h = facing < 0
	_update_camera(delta)


## The framing breathes with the player instead of pinning them dead-centre.
## Horizontal anticipation reveals the next landing; vertical anticipation
## gives tall rooms their depth without exposing the whole painted panel.
func _update_camera(delta: float) -> void:
	if not camera.enabled:
		return
	var speed_ratio := clampf(absf(velocity.x) / maxf(1.0, stats.speed), 0.0, 1.5)
	var target_x := float(facing) * lerpf(18.0, 54.0, speed_ratio / 1.5)
	var target_y := -30.0 + clampf(velocity.y * 0.055, -22.0, 28.0)
	if is_on_floor() and absf(velocity.x) < 8.0:
		target_x *= 0.45
	camera.position = camera.position.lerp(Vector2(target_x, target_y), 1.0 - exp(-delta * 3.5))


func _physics_process(delta: float) -> void:
	if _dead:
		velocity.x = 0.0
		velocity.y += stats.gravity * delta
		move_and_slide()
		return
	if _mantle_left > 0.0:
		_mantle_left = maxf(0.0, _mantle_left - delta)
		var progress: float = 1.0 - _mantle_left / MANTLE_TIME
		global_position = _mantle_start.lerp(_mantle_end, smoothstep(0.0, 1.0, progress))
		velocity = Vector2.ZERO
		if _mantle_left <= 0.0:
			_jumps_left = 0
			_play("idle")
		_check_room_bounds()
		return
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_attack_anim_left = maxf(0.0, _attack_anim_left - delta)
	_combo_timer = maxf(0.0, _combo_timer - delta)
	_scripted_left = maxf(0.0, _scripted_left - delta)
	_block_cd = maxf(0.0, _block_cd - delta)
	_tick_rally(delta)
	_hurt_grace_left = maxf(0.0, _hurt_grace_left - delta)
	_wrath_left = maxf(0.0, _wrath_left - delta)
	_dodge_counter_left = maxf(0.0, _dodge_counter_left - delta)
	_turn_lock_left = maxf(0.0, _turn_lock_left - delta)
	_parry_left = maxf(0.0, _parry_left - delta)
	if _combo_timer <= 0.0:
		_combo = 0
	_arm_check -= delta
	# Not while a scripted pose owns the body (lying in the grave, waking): an
	# enemy that happens to be awake would make him stand and draw first.
	if not _armed and _arm_check <= 0.0 and controls_enabled:
		_arm_check = 0.25
		_check_for_hunters()

	var dir := Input.get_axis("move_left", "move_right") if controls_enabled and _healing_left <= 0.0 else 0.0
	if absf(dir) > 0.2 and _turn_lock_left <= 0.0:
		facing = 1 if dir > 0.0 else -1
		body.flip_h = facing < 0
		hitbox.scale.x = facing * stats.attack_scale
	else:
		dir = 0.0

	# --- vertical ---
	var on_floor := is_on_floor()
	_skill_cd = maxf(0.0, _skill_cd - delta)
	if controls_enabled and not skill.is_empty() and _skill_cd <= 0.0 and Input.is_action_just_pressed("skill"):
		_cast_skill()
	_burn_left = maxf(0.0, _burn_left - delta)
	if on_floor and _burn_left <= 0.0:
		_safe_time += delta
		if _safe_time > 0.25:
			_safe_position = global_position
	else:
		_safe_time = 0.0
	if on_floor:
		if not _was_on_floor:
			if _slamming:
				_land_slam()
			else:
				Audio.play(&"land", -12.0)
				Fx.dust(global_position + Vector2(0, 14), Vector2.UP, 8)
				var landing_strength := clampf(_fall_speed / maxf(HARD_LANDING, 1.0), 0.25, 1.35)
				EventBus.world_impulse.emit(global_position, Vector2(0, 1), landing_strength, &"land")
				if _fall_speed > HARD_LANDING and _attack_anim_left <= 0.0:
					_one_shot("land", 0.25)
		_jumps_left = int(stats.max_jumps)
		_coyote = COYOTE_TIME
		_wall_side = 0
	else:
		_coyote -= delta
		if _was_on_floor and _coyote <= 0.0:
			_jumps_left = mini(_jumps_left, int(stats.max_jumps) - 1)  # walked off a ledge: no free jump
		velocity.y += stats.gravity * delta
	_fall_speed = velocity.y
	_was_on_floor = on_floor
	_shadow.visible = on_floor

	_slam_recovery = maxf(0.0, _slam_recovery - delta)
	# Holding into a wall in mid-air catches it. Checked before the jump, so
	# the jump below can read _wall_side and push off instead of going up.
	_update_wall_grab(on_floor, dir, delta)
	if _slamming:
		velocity.x = 0.0
		velocity.y = SLAM_SPEED
		dir = 0.0

	_drop_left -= delta
	if _drop_left <= 0.0 and not (collision_mask & LEDGE_LAYER):
		collision_mask |= LEDGE_LAYER
	if controls_enabled and _healing_left <= 0.0:
		_jump_buffer = JUMP_BUFFER if Input.is_action_just_pressed("jump") else _jump_buffer - delta
		# Down in the air, with room below: fall on it. Down on the ground is
		# still the drop-through, and down while rolling is nothing at all.
		if not on_floor and not _slamming and _dash_left <= 0.0 and _mantle_left <= 0.0 \
				and Input.is_action_just_pressed("move_down") and _room_to_slam():
			_start_slam()
		elif _jump_buffer > 0.0 and _wall_side != 0 and not on_floor:
			_wall_jump()
		elif _jump_buffer > 0.0 and on_floor and Input.is_action_pressed("move_down") and _on_ledge():
			_drop_through()
		elif _jump_buffer > 0.0 and _jumps_left > 0 and _dash_left <= 0.0:
			velocity.y = -stats.jump_velocity
			Audio.play(&"jump", -8.0)
			EventBus.world_impulse.emit(global_position, Vector2(0, -1), 0.45, &"jump")
			if _attack_anim_left <= 0.0:
				_one_shot("jump", 0.3)  # restarts on the air jump too
			_jumps_left -= 1
			_jump_buffer = 0.0
			_coyote = 0.0
		elif Input.is_action_just_pressed("jump") and not on_floor and _jumps_left <= 0 \
				and _dash_left <= 0.0 and _try_mantle():
			_jump_buffer = 0.0
			return
		if Input.is_action_just_released("jump") and velocity.y < JUMP_CUT_VELOCITY:
			velocity.y = JUMP_CUT_VELOCITY  # short hop

	# --- block ---
	# A body committed to a slam, or still picking itself up from one, is not
	# raising a guard.
	var block_down := controls_enabled and Input.is_action_pressed("block")
	var wants_block := block_down and _healing_left <= 0.0 and _dash_left <= 0.0 and _attack_anim_left <= 0.0 \
			and not _slamming and _slam_recovery <= 0.0
	if wants_block and not _blocking:
		_raise_block(not _block_was_down)
	elif not wants_block and _blocking:
		_lower_block()
	_block_was_down = block_down

	# --- horizontal ---
	if _dash_left > 0.0:
		_dash_left -= delta
		velocity.x = facing * stats.dash_speed
		if on_floor:
			velocity.y = 0.0
		_dash_hits()
	elif _lunge_left > 0.0:
		_lunge_left -= delta
		velocity.x = facing * LUNGE_SPEED
	elif _slamming:
		pass  # the fall owns the body; velocity was set above
	else:
		var top_speed: float = stats.speed * (BLOCK_SPEED if _blocking else 1.0)
		if _slam_recovery > 0.0:
			top_speed = 0.0  # planted where he landed, for a moment
		elif _charging:
			top_speed *= CHARGE_SPEED
		velocity.x = move_toward(velocity.x, dir * top_speed, _horizontal_rate(dir, on_floor) * delta)
		if controls_enabled and _healing_left <= 0.0 and _slam_recovery <= 0.0 \
				and Input.is_action_just_pressed("dash") and _dash_cd <= 0.0:
			_roll()

	if controls_enabled and _healing_left <= 0.0 and not _slamming and _slam_recovery <= 0.0:
		_read_technique_input(delta, on_floor)
		if Input.is_action_just_pressed("attack") and _attack_cd <= 0.0 and not _charging:
			if _blocking:
				_lower_block()  # the riposte: straight out of the block into the swing
			var technique := _technique_for_press(on_floor)
			if technique != "":
				_technique(technique)
			else:
				_attack()
		elif Input.is_action_just_pressed("heal") and heal_charges > 0 and on_floor and hp < stats.max_hp \
				and not _blocking:
			_start_heal()

	if _healing_left > 0.0:
		_healing_left -= delta
		if _healing_left <= 0.0:
			heal_charges -= 1
			heal(HEAL_AMOUNT)
			if stats.heal_burst > 0.0:
				_heal_burst()
			Fx.puff(global_position + Vector2(0, -10), 0.9, Color(0.9, 1.0, 0.7))
			Fx.sparkle(global_position + Vector2(0, 4), Color(0.75, 1.0, 0.7), 16, 10.0)
			Fx.flash(global_position + Vector2(0, -12), Color(0.7, 1.0, 0.75), 90.0, 0.5)
			body.modulate = SLOT_TINTS[slot % SLOT_TINTS.size()]

	var before_move := global_position
	move_and_slide()
	if on_floor and dir != 0.0 and is_on_wall() and _dash_left <= 0.0:
		_try_step_up(before_move, dir)
	_check_room_bounds()
	if _dead:
		return
	_animate(on_floor)
	_footsteps(on_floor, delta)


## A low broken stone should be a step, not a wall. The raised pose must have
## room for the full body and a floor below it, so this cannot climb cliffs.
func _try_step_up(before_move: Vector2, direction: float) -> void:
	for height in [4.0, 8.0, STEP_HEIGHT]:
		var lift := Vector2(0.0, -height)
		var raised := global_transform
		raised.origin = before_move + lift
		if test_move(global_transform, lift) or test_move(raised, Vector2(signf(direction) * 5.0, 0.0)):
			continue
		var across := raised
		across.origin.x += signf(direction) * 5.0
		if not test_move(across, Vector2(0.0, height + 3.0)):
			continue
		global_position = across.origin
		velocity.y = 0.0
		return


## Third Space press near the lip of a platform pulls the hero onto it.
## It is a short, checked mantle, never a general-purpose third air jump.
func _try_mantle() -> bool:
	var space := get_world_2d().direct_space_state
	for distance in [18.0, 26.0, 34.0]:
		var x: float = global_position.x + facing * distance
		var ray := PhysicsRayQueryParameters2D.create(
			Vector2(x, global_position.y - MANTLE_RISE - 15.0),
			Vector2(x, global_position.y - 8.0), 1 | LEDGE_LAYER, [get_rid()])
		var hit: Dictionary = space.intersect_ray(ray)
		if hit.is_empty() or (hit.normal as Vector2).y > -0.7:
			continue
		var rise: float = global_position.y + 15.0 - (hit.position as Vector2).y
		if rise < 15.0 or rise > MANTLE_RISE:
			continue
		var landing := Vector2(x, (hit.position as Vector2).y - 16.0)
		var clearance := PhysicsShapeQueryParameters2D.new()
		clearance.shape = ($Collision as CollisionShape2D).shape
		clearance.transform = global_transform
		clearance.transform.origin = landing
		clearance.collision_mask = 1
		clearance.exclude = [get_rid()]
		if not space.intersect_shape(clearance, 1).is_empty():
			continue
		_mantle_start = global_position
		_mantle_end = landing
		_mantle_left = MANTLE_TIME
		velocity = Vector2.ZERO
		_play("climb")
		Audio.play(&"jump", -12.0)
		return true
	return false


func _check_room_bounds() -> void:
	var current_room := get_tree().get_first_node_in_group("room") as Room
	if current_room == null:
		return
	var in_room := current_room.to_local(global_position)
	var bottom_limit := current_room.void_kill_y if current_room.void_kill_y >= 0.0 else float(current_room.height) + 24.0
	if in_room.y <= bottom_limit \
			and in_room.x >= -64.0 and in_room.x <= float(current_room.width) + 64.0:
		return
	fell_outside_room = true
	hp = 0.0
	_emit_hp()
	_go_down()
	if Net.active:
		_net_down.rpc()
	died.emit(self)
	if _is_mine():
		EventBus.player_died.emit()


## A step every so many pixels of ground actually covered, so the rhythm
## follows the run instead of a timer that keeps ticking while the body is
## standing still against a wall. Only our own body: two sets of boots in a
## co-op room is noise.
## How fast velocity.x closes on what the stick asks for. Pushing (or turning
## round) is snappy; letting go slides a little on stone, and the roll's extra
## speed drains rather than snapping back to a jog.
func _horizontal_rate(dir: float, on_floor: bool) -> float:
	var same_way := dir != 0.0 and signf(dir) == signf(velocity.x)
	if absf(velocity.x) > stats.speed + 1.0 and (same_way or dir == 0.0):
		return stats.slide_friction
	if dir == 0.0:
		return stats.friction if on_floor else stats.friction * 0.6
	return stats.acceleration


func _footsteps(on_floor: bool, delta: float) -> void:
	if not _is_mine() or not on_floor or _dead or _dash_left > 0.0 or absf(velocity.x) < 20.0:
		_step_left = 0.0
		return
	_step_left -= absf(velocity.x) * delta
	if _step_left <= 0.0:
		_step_left = STEP_DISTANCE
		Audio.play(&"step", -4.0)
		Fx.dust(global_position + Vector2(-facing * 4.0, 14), Vector2(-facing, -0.6), 3, Color(0.6, 0.55, 0.5, 0.5))


func _animate(on_floor: bool) -> void:
	if _attack_anim_left > 0.0 or _scripted_left > 0.0:
		return  # the swing (or a one-shot: draw, hurt, land) owns the body until it lands
	if _charging:
		return  # the drawn-back blade, glowing, until it is let go
	if not controls_enabled:
		return  # a scripted animation (waking up) owns the body
	if _healing_left > 0.0:
		return  # the flask animation owns the body until the heal completes
	if _blocking:
		if body.animation != "guard":
			_play("guard")  # raise, then hold on the braced frame
		return
	if _dash_left > 0.0:
		if body.animation != "roll":
			_play("roll")
	elif _slamming:
		if body.animation != "fall":
			_play("fall")  # no slam frames yet; the plunge reads as a hard fall
	elif _wall_side != 0:
		if body.animation != "climb":
			_play("climb")  # the nearest thing to a body against a wall
	elif not on_floor:
		if velocity.y < 0.0 and _inside_ledge():
			_play("climb")  # pulling up through a jump-through ledge
		elif velocity.y < 0.0:
			if body.animation != "jump":
				_play("jump")
		else:
			_play("fall")
	elif absf(velocity.x) > stats.speed * 0.55:
		_play("run")
	elif absf(velocity.x) > 10.0:
		_play("walk")
	else:
		_play("idle" if _armed else "rest")


func _play(animation: String) -> void:
	body.play(animation)
	net_anim = animation


## A one-shot the body finishes before anything else gets to pose it.
func _one_shot(animation: String, seconds: float) -> void:
	_play(animation)
	_scripted_left = seconds


## A cutscene posing the body: it holds the pose until [method release_body].
func play_scripted(animation: String) -> void:
	_one_shot(animation, 60.0)


func release_body() -> void:
	_scripted_left = 0.0


## Somebody in the room is hunting us: the sword comes out. Standing still, it
## is the drawing animation; on the move, it is simply out.
func _check_for_hunters() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy != null and enemy.aware and not enemy.is_dead():
			_arm(true)
			return


func _arm(with_draw: bool) -> void:
	if _armed:
		return
	_armed = true
	if with_draw and is_on_floor() and absf(velocity.x) < 10.0 and _attack_anim_left <= 0.0 and _dash_left <= 0.0:
		_one_shot("draw", 0.55)
		Audio.play(&"draw", -7.0)


## A rest point: whole again, every flask full, nothing left to recover.
func rest() -> void:
	# under the fourth vial an altar gives back only part of the bar (data/vials)
	hp = minf(stats.max_hp, maxf(hp, hp + stats.max_hp * float(Vials.rule("rest_heal"))))
	heal_charges = int(stats.heal_charges)
	_rally_pool = 0.0
	_rally_left = 0.0
	_emit_hp()


## The censer (item "heal_burst"): the flask's warmth goes out as a scorch.
func _heal_burst() -> void:
	Fx.flash(global_position + Vector2(0, -10), Color(1.0, 0.7, 0.35), HEAL_BURST_RADIUS, 0.5, 1.2)
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy != null and not enemy.is_dead() and enemy.global_position.distance_to(global_position) <= HEAL_BURST_RADIUS:
			enemy.take_damage(stats.heal_burst, self)


func heal(amount: float) -> void:
	var restored := minf(maxf(0.0, amount), stats.max_hp - hp)
	hp += restored
	# Flask, gifts and life-steal fill the same missing health; they must not
	# leave a second, invisible recovery pool behind.
	_rally_pool = maxf(0.0, _rally_pool - restored)
	_emit_hp()


func recoverable_hp() -> float:
	return _rally_pool if _rally_left > 0.0 and not _dead else 0.0


func _tick_rally(delta: float) -> void:
	if _rally_left <= 0.0:
		return
	_rally_left = maxf(0.0, _rally_left - delta)
	if _rally_left <= 0.0:
		_rally_pool = 0.0


func _recover_from_strike(damage: float) -> void:
	if _dead or _rally_left <= 0.0 or _rally_pool <= 0.0:
		return
	var restored := minf(minf(_rally_pool, maxf(0.0, damage) * RALLY_HIT_SHARE), stats.max_hp - hp)
	if restored <= 0.0:
		return
	hp += restored
	_rally_pool -= restored
	_emit_hp()


## The one door damage comes through, wherever it was dealt. A body is only
## ever hurt by the peer that owns it, so a remote hit is forwarded first.
## Lava (Hazard): it burns through a roll and a raised sword alike, throws the
## body up, and puts it back on the last floor it stood on. Only the owner of
## the body acts; the copies on other peers follow its position.
func burn(amount: float, danger := Rect2()) -> void:
	if not _is_mine() or _dead or _burn_left > 0.0:
		return
	_burn_left = 1.0
	_dash_left = 0.0
	_blocking = false
	_apply_damage(amount, null, {"from_x": global_position.x - facing * 40.0})
	Fx.ash(global_position + Vector2(0, -6), Color(1.0, 0.5, 0.2), 18, 60.0, 8.0)
	Fx.flash(global_position, Color(1.0, 0.5, 0.2), 90.0, 0.4)
	if _dead:
		return
	velocity = Vector2(0, -280)
	await get_tree().create_timer(0.35).timeout
	if not is_inside_tree() or _dead:
		return
	var back := _safe_position
	if back == Vector2.ZERO or danger.has_point(back):
		# never stood anywhere safe in this room: the entrance is
		var current_room := get_tree().get_first_node_in_group("room") as Room
		if current_room != null:
			back = current_room.player_spawn.global_position
	global_position = back
	_safe_position = back
	velocity = Vector2.ZERO
	Fx.puff(global_position + Vector2(0, -10), 0.8, Color(0.9, 0.85, 0.8))


func take_damage(amount: float, source: Node = null, info: Dictionary = {}) -> void:
	if Net.active and not is_multiplayer_authority():
		var owner_id := get_multiplayer_authority()
		if multiplayer.get_peers().has(owner_id):
			var path: NodePath = source.get_path() if source != null and source.is_inside_tree() else NodePath()
			_net_damage.rpc_id(owner_id, amount, _attacker_x(source, info), path)
		return  # a body whose owner has left takes nothing; the run frees it
	_apply_damage(amount, source, info)


## The source is named rather than passed: a replicated enemy has the same path
## on every peer, so a block here still knows which way the blow came from and
## a parry here can still answer the body that swung over there.
@rpc("any_peer", "call_remote", "reliable")
func _net_damage(amount: float, from_x: float, source_path: NodePath) -> void:
	var source: Node = null if source_path.is_empty() else get_node_or_null(source_path)
	# A projectile can already have burst before this RPC arrives. Its nonempty
	# path still identifies combat damage, even if there is no node to resolve.
	_apply_damage(amount, source, {"from_x": from_x, "combat_hit": not source_path.is_empty()})


func _apply_damage(amount: float, source: Node = null, info: Dictionary = {}) -> void:
	if _dead:
		return
	if _dash_left > 0.0:  # rolling grants i-frames
		# Only a real enemy attack earns the answer, once per roll. Hazards,
		# furniture and a teammate's tests cannot charge it for free.
		if amount > 0.0 and source is Enemy and not _dodge_counted:
			_dodge_counted = true
			_dodge_counter_left = DODGE_COUNTER_TIME
			Fx.sparkle(global_position + Vector2(0, -12), DODGE_COUNTER_TINT, 6, 8.0)
		return
	var from_x := _attacker_x(source, info)
	var combat_hit := not source is Hazard and (source != null or bool(info.get("combat_hit", false)))
	var blocked := _blocking and _faces(from_x)
	if blocked and _parry_left > 0.0:
		_parry(source, from_x)
		return
	if _hurt_grace_left > 0.0 and combat_hit:
		return
	# The present backstab still lands, but the next blow should not catch an
	# oblivious back. Briefly keep the hit reaction facing its actual source.
	if (source is Node2D or info.has("from_x")) and absf(from_x - global_position.x) >= 4.0:
		facing = 1 if from_x > global_position.x else -1
		body.flip_h = facing < 0
		hitbox.scale.x = facing * stats.attack_scale
		_turn_lock_left = 0.18
	if _guard_left > 0:
		# The ward takes this one whole. It is worth a beat of its own, or the
		# player never learns that the gift did anything.
		_guard_left -= 1
		Fx.puff(global_position + Vector2(0, -10), 1.0, Color(0.8, 0.9, 1.0))
		Juice.shake(2.0)
		Audio.play(&"hit_crit", -6.0)
		return
	amount *= 1.0 - clampf(stats.armor, 0.0, 0.5)
	if blocked:
		amount *= 1.0 - BLOCK_REDUCTION
		velocity.x = signf(global_position.x - from_x) * BLOCK_PUSH
	if stats.thorns > 0.0 and source != null and source != self and source.has_method("take_damage"):
		source.take_damage(amount * stats.thorns, self)
	hp -= amount
	if amount > 0.0 and not blocked:
		_wounded_this_room = true
		if _charging:
			_cancel_charge()  # a wound breaks the charge; the blade was not ready
		if stats.wrath_after_hit > 0.0:
			_wrath_left = WRATH_TIME
	if amount > 0.0 and not blocked and combat_hit:
		_hurt_grace_left = HURT_GRACE_TIME
	if amount > 0.0 and hp > 0.0:
		_rally_pool = minf(minf(_rally_pool + amount * RALLY_DAMAGE_SHARE, stats.max_hp * RALLY_MAX_HP_SHARE), stats.max_hp - hp)
		_rally_left = RALLY_TIME
	if _healing_left > 0.0:
		_healing_left = 0.0  # the channel breaks; the charge is kept
		body.modulate = SLOT_TINTS[slot % SLOT_TINTS.size()]
	_arm(false)
	if blocked:
		# The blade held: no flinch, the pose stays up for the next one.
		_block_fx(amount, from_x)
		if Net.active:
			_net_block_fx.rpc(amount, from_x)
	else:
		_hit_fx(amount)
		if _attack_anim_left <= 0.0 and _dash_left <= 0.0:
			if amount >= stats.max_hp * KNOCKBACK_FRACTION:
				_one_shot("knockback", 0.5)
			else:
				_one_shot("hurt", 0.25)
		Audio.play(&"player_hurt")
		if Net.active:
			_net_hit_fx.rpc(amount)
	if hp <= 0.0:
		if stats.extra_lives > 0:
			stats.extra_lives -= 1
			hp = stats.max_hp * 0.5
			_rally_pool = 0.0
			_rally_left = 0.0
		else:
			hp = 0.0
			_dead = true
			_rally_pool = 0.0
			_rally_left = 0.0
			_emit_hp()
			_go_down()
			if Net.active:
				_net_down.rpc()
			died.emit(self)
			if _is_mine():
				EventBus.player_died.emit()
			return
	_emit_hp()


func _go_down() -> void:
	_dead = true
	_hurt_grace_left = 0.0
	_dodge_counter_left = 0.0
	_dodge_counted = false
	_healing_left = 0.0
	_slamming = false
	_slam_recovery = 0.0
	_wall_side = 0
	Audio.play(&"player_death", 0.0, 0.0)
	_play("death")
	body.modulate = Color(0.6, 0.55, 0.55)
	if _light != null:
		create_tween().tween_method(_light.set_base_energy, 0.55, 0.12, 1.2)


@rpc("authority", "call_remote", "reliable")
func _net_down() -> void:
	_go_down()


@rpc("authority", "call_remote", "reliable")
func _net_up() -> void:
	_dead = false
	_rally_pool = 0.0
	_rally_left = 0.0
	body.modulate = SLOT_TINTS[slot % SLOT_TINTS.size()]
	_play("idle")


func _hit_fx(amount: float) -> void:
	Fx.damage_number(global_position, amount, Color(1.0, 0.45, 0.4))
	_flash(Color(1.0, 0.35, 0.35))
	Fx.flash(global_position + Vector2(0, -10), Color(1.0, 0.4, 0.35), 70.0, 0.2)
	if _is_mine():
		Juice.shake(4.0)
		Juice.hit_stop(0.06)
		EventBus.player_hurt.emit(amount / maxf(stats.max_hp, 1.0))


@rpc("authority", "call_remote", "unreliable")
func _net_hit_fx(amount: float) -> void:
	_hit_fx(amount)


func is_dead() -> bool:
	return _dead


## Teleports must not carry a climb's old coordinates, a disabled ledge mask,
## or a hazard's return point into the next room. Health and gifts stay intact.
func place_in_room(at: Vector2) -> void:
	global_position = at
	velocity = Vector2.ZERO
	_mantle_left = 0.0
	_mantle_start = at
	_mantle_end = at
	_drop_left = 0.0
	collision_mask |= LEDGE_LAYER
	_jump_buffer = 0.0
	_coyote = 0.0
	_was_on_floor = false
	_jumps_left = int(stats.max_jumps)
	_wall_side = 0
	_slamming = false
	_slam_recovery = 0.0
	_dash_left = 0.0
	_safe_position = at
	_safe_time = 0.0
	_scripted_left = 0.0


## Back on your feet: between rooms in co-op, between rounds in a duel.
func revive(at: Vector2, fraction := 1.0) -> void:
	place_in_room(at)
	_dead = false
	_rally_pool = 0.0
	_rally_left = 0.0
	fell_outside_room = false
	_healing_left = 0.0
	_slamming = false
	_slam_recovery = 0.0
	_wall_side = 0
	_dash_left = 0.0
	_hurt_grace_left = 0.0
	_dodge_counter_left = 0.0
	_dodge_counted = false
	_blocking = false
	_parry_left = 0.0
	hp = stats.max_hp * clampf(fraction, 0.05, 1.0)
	heal_charges = int(stats.heal_charges)
	controls_enabled = true
	body.modulate = SLOT_TINTS[slot % SLOT_TINTS.size()]
	_play("idle")
	_emit_hp()
	if _light != null:
		_light.set_base_energy(0.55)
	if Net.active and is_multiplayer_authority():
		_net_up.rpc()
	if _is_mine():
		EventBus.player_waking.emit(0.7)
	Fx.puff(at + Vector2(0, -8), 1.1, Color(0.95, 0.9, 0.7))


## Intro: break through the grave and get to our feet while the angel talks.
## Before the first frame is seen: the body lies in the grave, held on the
## first frame of "wake". Called the moment the run spawns it, so the curtain
## opens on a corpse rather than on a hero standing who then lies down to get up.
func lie_down() -> void:
	controls_enabled = false
	if body.sprite_frames.has_animation("wake"):
		_play("wake")
		body.pause()
		body.frame = 0


func wake_up() -> void:
	controls_enabled = false
	if body.sprite_frames.has_animation("wake"):
		_play("wake")
		body.frame = 0
		Fx.dust(global_position + Vector2(0, 14), Vector2.UP, 12, Color(0.38, 0.3, 0.26, 0.8))
		if _is_mine():
			var frames: float = body.sprite_frames.get_frame_count("wake")
			EventBus.player_waking.emit(frames / body.sprite_frames.get_animation_speed("wake") + 0.3)
		await body.animation_finished
		if is_inside_tree():
			Fx.dust(global_position + Vector2(0, 14), Vector2.UP, 8, Color(0.4, 0.34, 0.3, 0.7))
	else:
		await get_tree().create_timer(1.2).timeout
	if is_inside_tree() and not Game.cutscene:  # a scene that started meanwhile keeps the hands
		controls_enabled = true


## Passing up through a ledge (layer 5): the one-way shape reports no
## collision, so the body is looked up in the space directly.
func _inside_ledge() -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = ($Collision as CollisionShape2D).shape
	query.transform = global_transform
	query.collision_mask = LEDGE_LAYER
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


## Standing on a jump-through ledge (layer 5) rather than solid ground.
func _on_ledge() -> bool:
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is CollisionObject2D and (collider as CollisionObject2D).collision_layer & LEDGE_LAYER:
			return true
	return false


## Down + jump: let go of the ledge and fall through it.
func _drop_through() -> void:
	collision_mask &= ~LEDGE_LAYER
	_drop_left = DROP_THROUGH_TIME
	_jump_buffer = 0.0
	_coyote = 0.0
	velocity.y = maxf(velocity.y, 40.0)
	global_position.y += 2.0


func _roll() -> void:
	if _blocking:
		_lower_block()
	Audio.play(&"dash", -4.0)
	_scripted_left = 0.0
	_dash_hit.clear()
	_dodge_counter_left = 0.0
	_dodge_counted = false
	_dash_left = stats.dash_time
	_dash_cd = stats.dash_cooldown
	# Enemy body collision is always non-solid; the roll still grants i-frames and
	# can cut through enemies when a gift grants dash damage.
	Fx.puff(global_position + Vector2(-facing * 6.0, 6.0), 0.5, Color(1, 1, 1, 0.7))
	Fx.dust(global_position + Vector2(-facing * 6.0, 14), Vector2(-facing, -0.4), 6)
	EventBus.world_impulse.emit(global_position, Vector2(facing, -0.15), 1.0, &"dash")
	body.modulate.a = 0.6
	get_tree().create_timer(stats.dash_time).timeout.connect(func() -> void: body.modulate.a = 1.0)


# ------------------------------------------------------------ ground slam ---

## Is there anything under him worth falling onto? Without this, tapping down
## at the top of a hop reads as a slam and lands as a fizzle — worse, it eats
## the input somebody meant as a drop-through a frame before they touched down.
func _room_to_slam() -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position, global_position + Vector2(0.0, SLAM_MIN_HEIGHT + 14.0))
	query.exclude = [get_rid()]
	# The world only. A jump-through ledge is not a floor to slam onto, and
	# enemies are not solid to walk on.
	query.collision_mask = 1
	return space.intersect_ray(query).is_empty()


func _start_slam() -> void:
	EventBus.technique_performed.emit("slam")
	if _blocking:
		_lower_block()
	_slamming = true
	_scripted_left = 0.0
	_attack_anim_left = 0.0
	velocity = Vector2(0.0, SLAM_SPEED)
	Audio.play(&"dash", -6.0, 0.7)
	Fx.puff(global_position, 0.5, Color(1.0, 0.95, 0.85, 0.7))
	_play("fall")


## He arrives. Everything standing close enough is knocked down and away from
## him, the floor kicks, and he is planted for a beat — the price of a move
## that costs nothing else.
func _land_slam() -> void:
	_slamming = false
	_slam_recovery = SLAM_RECOVERY
	velocity = Vector2.ZERO
	Audio.play(&"land", -2.0, 0.6)
	Fx.dust(global_position + Vector2(0, 14), Vector2.UP, 22)
	Fx.puff(global_position + Vector2(0, 10), 1.3, Color(0.95, 0.9, 0.8))
	Juice.shake(7.0)
	EventBus.world_impulse.emit(global_position, Vector2(0, 1), 1.6, &"land")
	_one_shot("land", SLAM_RECOVERY)
	if not _is_mine():
		return  # the hit is the owner's to deal; the rest is for everyone to see
	var damage: float = stats.attack_damage * SLAM_DAMAGE_SHARE
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		if enemy == null or not enemy.has_method("take_damage"):
			continue
		var offset := enemy.global_position - global_position
		# A flat reach: something directly overhead is not under the landing.
		if absf(offset.x) > SLAM_RADIUS or offset.y < -24.0 or offset.y > 30.0:
			continue
		enemy.take_damage(damage, self, {"knockback": 1.6})
		Fx.puff(enemy.global_position + Vector2(0, -8), 0.7, Color(0.95, 0.9, 0.8))


# -------------------------------------------------------------- wall grab ---

## Catch a wall in mid-air by holding the stick into it. Sets _wall_side so the
## jump can push off, and slows the fall while it is held. Letting go, landing,
## or the wall ending drops him out of it.
func _update_wall_grab(on_floor: bool, dir: float, delta: float) -> void:
	if on_floor or _slamming or _dash_left > 0.0 or _mantle_left > 0.0 \
			or not controls_enabled or _healing_left > 0.0 or _dead:
		_wall_side = 0
		return
	var side := 0
	if is_on_wall():
		var normal := get_wall_normal()
		if absf(normal.x) > 0.7:
			side = -signi(int(signf(normal.x)))  # the wall is opposite its normal
	# Held into it, not merely touching it: brushing a wall on the way past
	# should not stick.
	if side == 0 or absf(dir) < 0.2 or signf(dir) != float(side):
		_wall_side = 0
		return
	_wall_side = side
	facing = side
	body.flip_h = facing < 0
	hitbox.scale.x = facing * stats.attack_scale
	if velocity.y > 0.0:
		velocity.y = minf(velocity.y, WALL_SLIDE_SPEED)
		if int(Time.get_ticks_msec() / 90) % 2 == 0:
			Fx.dust(global_position + Vector2(side * 7.0, 6.0), Vector2(-side, -0.2), 1)


func _wall_jump() -> void:
	EventBus.technique_performed.emit("wall_jump")
	var away := -_wall_side
	velocity = Vector2(away * WALL_JUMP_PUSH, -stats.jump_velocity * WALL_JUMP_RISE)
	facing = away
	body.flip_h = facing < 0
	hitbox.scale.x = facing * stats.attack_scale
	# Steering is locked briefly so the stick, still held into the wall, does
	# not pull him straight back onto it.
	_turn_lock_left = WALL_JUMP_TURN_LOCK
	_wall_side = 0
	_jump_buffer = 0.0
	_coyote = 0.0
	# The wall gives the air jump back rather than adding to it: two walls are
	# a route, not a ladder.
	_jumps_left = maxi(_jumps_left, 1)
	_jumps_left -= 1
	Audio.play(&"jump", -6.0, 0.9)
	Fx.dust(global_position + Vector2(-away * 7.0, 8.0), Vector2(-away, -0.5), 6)
	EventBus.world_impulse.emit(global_position, Vector2(away, -0.6), 0.6, &"jump")
	if _attack_anim_left <= 0.0:
		_one_shot("jump", 0.3)


## A cutting roll catches whatever it passes through, once per roll: rolling
## back and forth over one body must not be better than using the sword.
func _dash_hits() -> void:
	if stats.dash_damage <= 0.0:
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		if enemy == null or _dash_hit.has(enemy) or not enemy.has_method("take_damage"):
			continue
		if enemy.global_position.distance_to(global_position) > DASH_REACH:
			continue
		_dash_hit[enemy] = true
		enemy.take_damage(stats.dash_damage, self, {"knockback": 1.2})
		Fx.puff(enemy.global_position + Vector2(0, -8), 0.6, Color(0.85, 0.95, 1.0))


## The third swing of the chain throws its arc across the room. It is the
## player's own bolt, so it bites enemies and breaks on walls instead.
func _throw_wave() -> void:
	var wave := WAVE_SCENE.instantiate()
	wave.damage = stats.attack_damage * stats.wave_damage
	wave.speed = WAVE_SPEED
	wave.direction = Vector2(facing, 0.0)
	wave.tint = Color(1.0, 0.93, 0.72)
	wave.visual_style = "blade"
	wave.friendly = true
	get_parent().add_child(wave)
	wave.global_position = global_position + Vector2(facing * 12.0, -12.0)


## Health a kill is worth. Only our own body collects, and only while it is
## still standing.
func _on_enemy_died(_id: StringName, _at: Vector2) -> void:
	if not _is_mine() or _dead or stats.kill_heal <= 0.0 or hp >= stats.max_hp:
		return
	heal(stats.kill_heal)
	Fx.puff(global_position + Vector2(0, -12), 0.5, Color(0.8, 1.0, 0.75))


func _on_room_cleared(index: int) -> void:
	_dodge_counter_left = 0.0
	_dodge_counted = false
	if _is_mine() and not _dead and not _wounded_this_room:
		EventBus.player_unscathed.emit(index)
	if _is_mine() and not _dead and stats.clean_clear_charge > 0.0 and not _wounded_this_room \
			and heal_charges < int(stats.heal_charges):
		heal_charges += 1
		_emit_hp()
		Fx.sparkle(global_position + Vector2(0, -12), Color(0.75, 1.0, 0.7), 10, 10.0)
	if not _is_mine() or _dead or stats.clear_heal <= 0.0:
		return
	heal(stats.clear_heal)
	Fx.puff(global_position + Vector2(0, -10), 0.9, Color(0.9, 1.0, 0.8))


## [param fresh]: the button went down this frame. A block raised because the
## button was still held after a swing or a roll is a block, never a parry.
func _raise_block(fresh: bool) -> void:
	_blocking = true
	_parry_left = PARRY_WINDOW if fresh and _block_cd <= 0.0 else 0.0
	_scripted_left = 0.0
	_armed = true


func _lower_block() -> void:
	_blocking = false
	_parry_left = 0.0
	_block_cd = BLOCK_RECOVERY


## Where a blow came from, along the floor. A remote hit brings it along
## ([code]info.from_x[/code]); a blow with no body behind it came from behind,
## because a blade can only be raised against what it can see.
func _attacker_x(source: Node, info: Dictionary) -> float:
	if info.has("from_x"):
		return float(info.from_x)
	if source is Node2D:
		return (source as Node2D).global_position.x
	return global_position.x - facing * 10.0


func _faces(from_x: float) -> bool:
	var dx := from_x - global_position.x
	return absf(dx) < 4.0 or signf(dx) == float(facing)


## A clean parry: nothing lands and the blow goes back where it came from — a
## bolt turns round, a swing leaves its owner open (Enemy.parried). A parry
## re-arms at once, so a string of blows can be answered blow by blow.
func _parry(source: Node, from_x: float) -> void:
	_parry_left = 0.0
	_block_cd = 0.0
	velocity.x = signf(global_position.x - from_x) * PARRY_PUSH
	_parry_fx(from_x)
	if Net.active:
		_net_parry_fx.rpc(from_x)
	EventBus.player_parried.emit()
	if source != null and source.has_method("reflect"):
		source.reflect(self)
	elif source != null and source.has_method("parried"):
		source.parried(self)
	if stats.parry_stun > 0.0:
		for node in get_tree().get_nodes_in_group("enemies"):
			var enemy := node as Enemy
			if enemy != null and not enemy.is_dead() and enemy.global_position.distance_to(global_position) <= PARRY_STUN_RADIUS:
				enemy.stagger(stats.parry_stun)
		Fx.flash(global_position + Vector2(0, -12), Color(0.95, 0.9, 0.7), PARRY_STUN_RADIUS, 0.4)


## Steel on steel: the block held, the blow is a thud and a few cold sparks.
func _block_fx(amount: float, from_x: float) -> void:
	var toward := signf(from_x - global_position.x)
	if toward == 0.0:
		toward = float(facing)
	var at := global_position + Vector2(toward * 10.0, -12.0)
	Fx.damage_number(global_position, amount, Color(0.72, 0.8, 0.95))
	Fx.impact(at, Vector2(-toward, -0.4), Color(0.85, 0.9, 1.0), 6)
	_flash(Color(0.8, 0.88, 1.1))
	Audio.play(&"block")
	if _is_mine():
		Juice.shake(2.0)
		Juice.hit_stop(0.03)


@rpc("authority", "call_remote", "unreliable")
func _net_block_fx(amount: float, from_x: float) -> void:
	_block_fx(amount, from_x)


## The parry: a white crack of light where the blades met, the arc of the
## deflection, and a stop in time long enough to feel it.
func _parry_fx(from_x: float) -> void:
	var toward := signf(from_x - global_position.x)
	if toward == 0.0:
		toward = float(facing)
	var at := global_position + Vector2(toward * 12.0, -12.0)
	Fx.impact(at, Vector2(toward, -0.3), Color(1.0, 0.96, 0.85), 16)
	Fx.sparkle(at, Color(0.85, 0.92, 1.0), 12, 8.0)
	Fx.flash(at, Color(0.85, 0.92, 1.0), 110.0, 0.3, 1.8)
	slash.visible = true
	slash.flip_v = false
	slash.scale = Vector2.ONE * 1.15
	slash.speed_scale = 1.3
	slash.play("white")
	_flash(Color(1.4, 1.45, 1.6))
	Audio.play(&"parry")
	EventBus.world_impulse.emit(at, Vector2(-toward, -0.2), 1.35, &"parry")
	if _is_mine():
		Juice.hit_stop(0.14, 0.02)
		Juice.shake(5.0)


@rpc("authority", "call_remote", "unreliable")
func _net_parry_fx(from_x: float) -> void:
	_parry_fx(from_x)


func _start_heal() -> void:
	Audio.play(&"heal", -4.0, 0.0)
	_healing_left = HEAL_TIME
	velocity.x = 0.0
	_play("heal" if body.sprite_frames.has_animation("heal") else "idle")
	body.modulate = Color(0.85, 1.0, 0.8)


func _attack() -> void:
	# Up + attack is an intentional anti-air slash. It trades the horizontal
	# three-hit chain for a taller, narrower hit area above the player's head.
	var aim_up := _dash_left <= 0.0 and Input.is_action_pressed("move_up")
	var hit_index := 0 if aim_up else _combo
	_attack_cd = stats.attack_cooldown * (0.65 if aim_up else COMBO_RECOVERY[hit_index])
	_attack_cd_total = _attack_cd
	_combo = 0 if aim_up else (_combo + 1) % COMBO_MULTIPLIERS.size()
	_combo_timer = 0.0 if aim_up else COMBO_WINDOW
	_armed = true
	_scripted_left = 0.0
	hitbox_collision.position = Vector2(8, -38) if aim_up else Vector2(24, -4)
	(hitbox_collision.shape as RectangleShape2D).size = Vector2(36, 60) if aim_up else Vector2(30, 30)
	# The same three blows, drawn for where the body is: out of a roll, in the
	# air, or into the back of somebody who has not turned round yet.
	var animation: String = SWING_ANIMATIONS[hit_index]
	if _dash_left > 0.0:
		animation = "dash_strike"
	elif aim_up:
		animation = "rising"
	elif not is_on_floor():
		animation = "rising"
	elif hit_index == 0 and _sneak_target_ahead():
		animation = "thrust"
	_play(animation)
	Audio.play(&"swing", -2.0 if hit_index == 2 else -5.0)
	_attack_anim_left = float(SWING_TIME[animation])
	var arc := "white" if aim_up else _arc_for(hit_index)
	_swing_fx(hit_index, arc)
	EventBus.world_impulse.emit(
		global_position + (Vector2(0, -28) if aim_up else Vector2(facing * 12.0, -10.0)),
		Vector2.UP if aim_up else Vector2(facing, -0.15), 0.45 + hit_index * 0.2, &"attack")
	if Net.active:
		_net_swing.rpc(hit_index, arc)
	if animation != SWING_ANIMATIONS[hit_index] and animation != "thrust":
		EventBus.technique_performed.emit(animation)  # rising, dash_strike
	await _land_hits(COMBO_MULTIPLIERS[hit_index], 2.0 if hit_index == 2 else 1.0, hit_index == 2)


## Everything a swing does once it is in the air: the hitbox (already placed
## and sized by the caller) opens for two physics ticks, and each body in it
## takes [param multiplier] of a blow, pushed by [param knockback]; a [param
## heavy] one lands like the chain's finisher, and [param stagger] seconds
## stop what it was doing (the cleave, the sweep). The chain and the special
## moves share it, so every gift and item that reads a hit reads theirs too.
func _land_hits(multiplier: float, knockback: float, heavy: bool, stagger := 0.0) -> void:
	hitbox.monitoring = true
	# Area2D needs a physics tick to register overlaps after monitoring is enabled.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var hit_something := false
	var hit_crit := false
	# Bodies are the enemies; areas are the breakable props (scripts/props/prop.gd).
	var targets: Array[Node2D] = []
	targets.assign(hitbox.get_overlapping_bodies())
	for area in hitbox.get_overlapping_areas():
		targets.append(area)
	for target in targets:
		if target == self or not target.has_method("take_damage"):
			continue
		var live_enemy: bool = target is Enemy and not (target as Enemy).is_dead()
		var damage: float = stats.attack_damage * multiplier
		var counter_hit := live_enemy and _dodge_counter_left > 0.0
		if counter_hit:
			damage *= 1.0 + DODGE_COUNTER_BONUS
			_dodge_counter_left = 0.0
		var crit: bool = randf() < stats.crit_chance
		if crit:
			damage *= stats.crit_multiplier
		if live_enemy and _wrath_left > 0.0:
			damage *= 1.0 + stats.wrath_after_hit
			_wrath_left = 0.0  # one swing answers one wound
		if live_enemy and stats.backstab_refresh > 0.0 and (target as Enemy).is_unaware():
			_dash_cd = 0.0
		if live_enemy and crit and stats.desperate_crit_heal > 0.0 and hp < stats.max_hp * DESPERATE_SHARE:
			heal(stats.desperate_crit_heal)
		# "sneak" is what the blow is worth on an enemy that has not noticed us;
		# the enemy (the host, online) knows whether it has and applies it.
		target.take_damage(damage, self, {"crit": crit, "knockback": knockback,
			"sneak": stats.backstab_multiplier, "execute": stats.execute})
		if live_enemy and stagger > 0.0:
			(target as Enemy).stagger(stagger)
		if live_enemy:
			_recover_from_strike(damage)
			if counter_hit:
				Fx.sparkle(target.global_position + Vector2(0, -12), DODGE_COUNTER_TINT, 9, 14.0)
		hit_something = true
		hit_crit = hit_crit or crit
		# Steel on flesh is not steel on plate: the body decides what the blow
		# sounds like, and a barrel that has no opinion gets the generic one.
		if target.has_method("impact_sound"):
			Audio.play_at(target.impact_sound(), target.global_position, -1.0 if crit else -4.0)
		else:
			Audio.play_at(&"hit", target.global_position)
		if stats.lifesteal > 0.0:
			heal(damage * stats.lifesteal)
	if heavy and stats.wave_damage > 0.0:
		_throw_wave()
	if hit_something:
		Juice.hit_stop(0.06 if heavy else 0.04)
		Juice.shake(2.5 if heavy else 1.5)
		if hit_crit:
			Audio.play(&"hit_crit", -7.0)  # the bright ring over whatever it landed on
	hitbox.monitoring = false
	hitbox_collision.position = Vector2(24, -4)
	(hitbox_collision.shape as RectangleShape2D).size = Vector2(30, 30)


# ------------------------------------------------------------ special moves ---

## Reads the taps and the held button the moves are made of. Only our own
## body, only with the controls ours (the caller checks both).
func _read_technique_input(delta: float, on_floor: bool) -> void:
	_back_tap_left = maxf(0.0, _back_tap_left - delta)
	_lunge_armed_left = maxf(0.0, _lunge_armed_left - delta)
	var right := Input.is_action_just_pressed("move_right")
	var left := Input.is_action_just_pressed("move_left")
	if right or left:
		# Two taps the opposite ways: the first is "back", the second "forward",
		# and the lunge goes where the second one points. The facing is not
		# asked: by the time this runs the first tap has already turned him.
		var tap := 1 if right else -1
		if _back_tap_left > 0.0 and tap == -_tap_facing:
			_lunge_armed_left = LUNGE_WINDOW  # back, forward: the lunge waits for the blow
			_back_tap_left = 0.0
		else:
			_tap_facing = tap
			_back_tap_left = LUNGE_WINDOW
	# the charge: attack still held after the swing it started
	if Input.is_action_pressed("attack") and not _blocking and _dash_left <= 0.0:
		_attack_held += delta
	else:
		if _charging:
			_release_charge()
		_attack_held = 0.0
	if not _charging and _attack_held >= CHARGE_AFTER and on_floor and _attack_anim_left <= 0.0 \
			and _lunge_left <= 0.0:
		_charging = true
		_charge_time = 0.0
		_charge_ready = false
		_play("charge")
	if _charging:
		if not on_floor or _dash_left > 0.0 or _healing_left > 0.0:
			_cancel_charge()
			return
		_charge_time += delta
		if not _charge_ready and _charge_time >= CHARGE_FULL:
			_charge_ready = true  # the ping: let go now and it lands
			Fx.flash(global_position + Vector2(0, -16), Color(1.0, 0.84, 0.47), 50.0, 0.25, 1.4)
			Fx.sparkle(global_position + Vector2(-facing * 6.0, -24.0), Color(1.0, 0.86, 0.5), 8, 6.0)
			Audio.play(&"draw", -4.0, 1.3)


## Which special move a fresh attack press makes, or "" for the chain.
func _technique_for_press(on_floor: bool) -> String:
	if not on_floor or _dash_left > 0.0:
		return ""
	if _lunge_armed_left > 0.0:
		return "lunge"
	if Input.is_action_pressed("move_down"):
		return "sweep"
	return ""


func _release_charge() -> void:
	var ready := _charge_ready
	_cancel_charge()
	if ready and _attack_cd <= 0.0:
		_technique("cleave")


func _cancel_charge() -> void:
	_charging = false
	_charge_ready = false
	_charge_time = 0.0
	_attack_held = 0.0


## A special move: its pose, its reach, and then the same hit as any swing
## (_land_hits), so gifts, items, crits and backstabs all apply to it.
func _technique(id: String) -> void:
	_armed = true
	_scripted_left = 0.0
	_combo = 0
	_combo_timer = 0.0
	_lunge_armed_left = 0.0
	_back_tap_left = 0.0
	var reach := Vector2(30, 30)
	var at := Vector2(24, -4)
	var multiplier := 1.0
	var knockback := 1.0
	var stagger := 0.0
	var heavy := false
	match id:
		"lunge":
			_attack_cd = stats.attack_cooldown * 0.9
			_lunge_left = LUNGE_TIME
			reach = Vector2(68, 26)
			at = Vector2(34, -6)
			multiplier = LUNGE_MULTIPLIER
			knockback = 1.6
			Fx.dust(global_position + Vector2(-facing * 8.0, 12.0), Vector2(-facing, -0.3), 6)
			Audio.play(&"dash", -6.0)
		"cleave":
			_attack_cd = stats.attack_cooldown * 1.2
			reach = Vector2(56, 44)
			at = Vector2(30, -8)
			multiplier = CLEAVE_MULTIPLIER
			knockback = 2.6
			stagger = CLEAVE_STAGGER
			heavy = true
			Juice.shake(4.5)
			Fx.ring(global_position + Vector2(facing * 30.0, 10.0), 34.0, Color(1.0, 0.78, 0.4), 0.3)
			Fx.debris(global_position + Vector2(facing * 30.0, 12.0), Color(0.55, 0.48, 0.42), 8)
		"sweep":
			_attack_cd = stats.attack_cooldown * 0.8
			reach = Vector2(48, 14)
			at = Vector2(22, 8)
			multiplier = SWEEP_MULTIPLIER
			knockback = 0.6
			stagger = SWEEP_STAGGER
			Fx.dust(global_position + Vector2(facing * 18.0, 12.0), Vector2(facing, -0.2), 8)
	_attack_cd_total = _attack_cd
	hitbox_collision.position = at
	(hitbox_collision.shape as RectangleShape2D).size = reach
	_play(id)
	_attack_anim_left = float(TECHNIQUE_TIME[id])
	Audio.play(&"swing", -2.0 if heavy else -4.0, 0.85 if heavy else 1.0)
	EventBus.world_impulse.emit(global_position + Vector2(facing * 14.0, -6.0), Vector2(facing, -0.1),
		0.9 if heavy else 0.6, &"attack")
	if _is_mine():
		EventBus.technique_performed.emit(id)
	await _land_hits(multiplier, knockback, heavy, stagger)


## An enemy in front of the sword that has not noticed us: the first blow of
## the chain is a stab in the back. Only the pose is decided here; whether it
## counts is the enemy's call (Enemy._apply_damage), replicated as `aware`.
func _sneak_target_ahead() -> bool:
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.aware or enemy.is_dead():
			continue
		var d := enemy.global_position - global_position
		if d.x * facing > 0.0 and absf(d.x) <= 40.0 * stats.attack_scale and absf(d.y) <= 24.0:
			return true
	return false


## The arc the sword leaves on top of the drawn swing: the finisher's is heavy
## and slow; the first two are coloured by the path the run leans towards
## (docs/GDD.md — the build shows on the blade before it shows anywhere else)
## and plain white means nothing extra at all.
func _arc_for(hit_index: int) -> String:
	if hit_index == 2:
		return "heavy"
	match Game.dominant_path():
		"grace":
			return "gold"
		"temptation":
			return "red"
	return "white"


## Each step of the chain has to look like a different swing, or the combo is
## invisible to the player: the second comes back the other way, the finisher
## is wider and slower.
func _swing_fx(hit_index: int, arc: String) -> void:
	if arc == "white":
		return  # the plain arc is drawn into the swing itself; only colour and weight are added
	slash.visible = true
	slash.flip_v = hit_index == 1
	slash.scale = Vector2.ONE * [1.0, 1.1, 1.3][hit_index]
	slash.speed_scale = 0.85 if hit_index == 2 else 1.0
	slash.play(arc if slash.sprite_frames.has_animation(arc) else "white")


@rpc("authority", "call_remote", "unreliable")
func _net_swing(hit_index: int, arc: String) -> void:
	_swing_fx(hit_index, arc)


func _flash(color: Color) -> void:
	body.modulate = color
	create_tween().tween_property(body, "modulate", SLOT_TINTS[slot % SLOT_TINTS.size()], 0.15)


## 0 while recharging, 1 the moment the move is back. The HUD reads these every
## frame instead of us firing a signal per tick.
## A lean needs a lead: a tie or a step ahead shows nothing, two steps a faint
## trail, six a thick one. Only our own body — the alignment is ours.
## How strongly a habit of nights marks the body while this night is level.
const HABIT_MARK := 0.18


func _update_aura() -> void:
	if not _is_mine() or not is_inside_tree():
		return
	var path := Game.dominant_path()
	var lead := Game.lead()
	if lead < 2:
		if _aura != null:
			_aura.emitting = false
		if _light != null:
			_light.color = LIGHT_COLOR
		Audio.alignment_layer("", 0.0)
		# A habit of several nights stays on the body faintly before this
		# night has leaned anywhere: the world has noticed (docs/CORE_LOOP.md).
		var habit := Profile.habit() if not Net.active else ""
		_mark_body(habit, HABIT_MARK if habit != "" else 0.0)
		return
	var strength := clampf((lead - 1) / 5.0, 0.2, 1.0)
	# The same lean, for the ears: a layer under the room's music that thickens
	# as the counters separate. Audio ignores a call that changes nothing.
	Audio.alignment_layer(path, strength)
	# ...and on the body itself, under whatever frame is showing.
	_mark_body(path, strength)
	var look: Array = AURA[path]
	if _aura == null:
		_aura = Fx.trail(self, look[0], 16, 1.4)
		_aura.position = Vector2(0, -14)
		_aura.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		_aura.emission_sphere_radius = 9.0
	_aura.emitting = true
	_aura.color = Color(look[0], 0.35 + 0.55 * strength)
	_aura.amount = 4 + int(14 * strength)
	_aura.gravity = look[1]
	if _light != null:
		_light.color = LIGHT_COLOR.lerp(look[0], 0.25 + 0.4 * strength)


## What the lean has done to the body: light along his edge for grace, veins
## under the skin for temptation, ash settling on him for will. It reads the
## sprite's own alpha rather than a painted mask, so it costs no art and holds
## through every animation. At a lead below 2 the shader is left bound with
## strength 0, which is a no-op — cheaper than swapping the material about.
func _mark_body(path: String, strength: float) -> void:
	if body == null:
		return
	if strength <= 0.0:
		if body.material is ShaderMaterial:
			(body.material as ShaderMaterial).set_shader_parameter("strength", 0.0)
		return
	var shader_material := _marks_material()
	shader_material.set_shader_parameter("mode", MARK_MODE.get(path, 2))
	shader_material.set_shader_parameter("strength", strength)
	shader_material.set_shader_parameter("tint", (AURA[path] as Array)[0])


func _marks_material() -> ShaderMaterial:
	if not (body.material is ShaderMaterial):
		var material := ShaderMaterial.new()
		material.shader = MARKS_SHADER
		body.material = material
	return body.material as ShaderMaterial


## Dyes the body in [member skin]. The same shader carries the marks, so the
## cloak and the lean are one material and neither undoes the other.
func _dress() -> void:
	if body == null:
		return
	var spec: Dictionary = Skins.spec(skin)
	var cloak: Dictionary = spec.get("cloak", {})
	var dyed := not cloak.is_empty() or spec.has("armor")
	if not dyed and not (body.material is ShaderMaterial):
		return
	var material := _marks_material()
	material.set_shader_parameter("skin_on", dyed)
	material.set_shader_parameter("cloak_hue", float(cloak.get("hue", 0.0)))
	material.set_shader_parameter("cloak_saturation", float(cloak.get("saturation", 1.0)))
	material.set_shader_parameter("cloak_value", float(cloak.get("value", 1.0)))
	material.set_shader_parameter("armor_tint", Color(str(spec.get("armor", "#ffffff"))))


func skill_ready_ratio() -> float:
	if skill.is_empty():
		return 0.0
	return clampf(1.0 - _skill_cd / maxf(float(skill.get("cooldown", 8.0)), 0.001), 0.0, 1.0)


## The three kinds of skill. Damage goes through each enemy's take_damage, so a
## guest's skill is judged by the host like a swing; the show is played here
## and sent to the others.
func _cast_skill() -> void:
	_skill_cd = float(skill.get("cooldown", 8.0))
	_arm(false)
	# grows with the sword: gifts that sharpen the blade sharpen the skill too
	var damage: float = float(skill.get("damage", 20.0)) * float(stats.attack_damage) / float(BASE_STATS.attack_damage)
	match skill.get("kind", ""):
		"nova":
			var radius := float(skill.get("radius", 70.0))
			for enemy in get_tree().get_nodes_in_group("enemies"):
				var body_hit := enemy as Node2D
				if body_hit != null and not body_hit.call("is_dead") \
						and body_hit.global_position.distance_to(global_position) <= radius:
					body_hit.take_damage(damage, self, {"knockback": 1.6})
			heal(float(skill.get("heal", 0.0)))
		"bolt":
			var bolt := WAVE_SCENE.instantiate()
			bolt.damage = damage
			bolt.speed = float(skill.get("speed", 300.0))
			bolt.direction = Vector2(facing, 0.0)
			bolt.tint = Color(skill.get("color", "#ffffff"))
			bolt.visual_style = "sacred"
			bolt.friendly = true
			bolt.scale = Vector2.ONE * 1.6
			get_parent().add_child(bolt)
			bolt.global_position = global_position + Vector2(facing * 14.0, -12.0)
		"drain":
			var target := _skill_target(float(skill.get("range", 110.0)))
			if target != null:
				target.take_damage(damage, self, {"knockback": 0.6})
				heal(damage * float(skill.get("drain", 0.5)))
	_skill_fx(str(skill.get("kind", "")), str(skill.get("color", "#ffffff")), float(skill.get("radius", 70.0)))
	if Net.active:
		_net_skill_fx.rpc(str(skill.get("kind", "")), str(skill.get("color", "#ffffff")), float(skill.get("radius", 70.0)))


## The nearest living enemy in front, within reach.
func _skill_target(reach: float) -> Node2D:
	var best: Node2D = null
	var best_d := reach
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var candidate := enemy as Node2D
		if candidate == null or candidate.call("is_dead"):
			continue
		var d := candidate.global_position - global_position
		if signf(d.x) != float(facing) and absf(d.x) > 8.0 or absf(d.y) > 48.0 or d.length() > best_d:
			continue
		best_d = d.length()
		best = candidate
	return best


func _skill_fx(kind: String, color_hex: String, radius: float) -> void:
	var tint := Color(color_hex)
	match kind:
		"nova":
			Fx.flash(global_position + Vector2(0, -10), tint, radius * 2.2, 0.5, 1.6)
			Fx.sparkle(global_position + Vector2(0, 6), tint, 26, radius * 0.6)
			Fx.puff(global_position + Vector2(0, -10), radius / 30.0, tint)
			Juice.shake(3.5)
			Audio.play(&"beam", -8.0, 1.3)
		"bolt":
			Fx.flash(global_position + Vector2(facing * 14.0, -12.0), tint, 70.0, 0.3)
			Juice.shake(2.0)
			Audio.play(&"swing", -2.0, 0.7)
		"drain":
			Fx.flash(global_position + Vector2(facing * 40.0, -12.0), tint, 90.0, 0.4, 1.3)
			Fx.ash(global_position + Vector2(facing * 50.0, -12.0), tint, 20, 50.0, 18.0)
			Juice.shake(2.5)
			Audio.play(&"hit_crit", -6.0, 0.8)
	_play("attack")


@rpc("authority", "call_remote", "unreliable")
func _net_skill_fx(kind: String, color_hex: String, radius: float) -> void:
	_skill_fx(kind, color_hex, radius)


func dash_ready_ratio() -> float:
	if _dash_cd <= 0.0:
		return 1.0
	return clampf(1.0 - _dash_cd / maxf(stats.dash_cooldown, 0.001), 0.0, 1.0)


func attack_ready_ratio() -> float:
	if _attack_cd <= 0.0:
		return 1.0
	return clampf(1.0 - _attack_cd / maxf(_attack_cd_total, 0.001), 0.0, 1.0)


func is_blocking() -> bool:
	return _blocking


## Full when a fresh press would parry. Empty while a block is up past its
## window, refilling over BLOCK_RECOVERY once it is let go of: the meter is how
## the player learns that mashing the button does not parry.
func block_ready_ratio() -> float:
	if _blocking:
		return 1.0 if _parry_left > 0.0 else 0.0
	if _block_cd <= 0.0:
		return 1.0
	return clampf(1.0 - _block_cd / BLOCK_RECOVERY, 0.0, 1.0)


## Which swing of the chain comes next (0-2), and whether the chain is still open.
func combo_step() -> int:
	return _combo


func combo_open() -> bool:
	return _combo > 0 and _combo_timer > 0.0


## Only our own body drives the HUD; the other player's bar lives over their head.
func _emit_hp() -> void:
	if not _is_mine():
		return
	EventBus.player_hp_changed.emit(hp, stats.max_hp)
	EventBus.heal_charges_changed.emit(heal_charges, int(stats.heal_charges))
