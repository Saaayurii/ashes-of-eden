class_name Mirror
extends Node
## Reflections (docs/CHAPTER7.md §2 and §9): Elian in glass, in the Heavenly
## Hall. A body with "mirror" in its JSON fights with the chain of the weapon
## its quarry holds (Player.weapon → Weapons.chain), every step a melee blow in
## the hero's own pose, slower by "windup_scale" and never under MIN_WINDUP; it
## answers with the move he used last (Player.last_technique, COPIES); it may
## roll out from under his swing (no invulnerability: the blow that catches it
## mid-roll lands); and it may lie in the polished floor until he comes within
## "rise", then get up. Only "behaviour": "walker".
##
## The static functions are the rules (mirror_test reads them); one Mirror node
## is laid on each reflection by Enemy._ready, on every peer, and drives it on
## the host. The theatre of a roll and a rise goes through its own RPCs.

const MIN_WINDUP := 0.6
## After the last step of the chain the reflection stands open this long.
const RECOVER := 0.8
## Between two steps of the chain: a breath, not a window.
const STEP_GAP := 0.15
const ROLL_DISTANCE := 90.0
const ROLL_TIME := 0.35
const WAKE_TIME := 1.0
## The poses a hero's swing is drawn with: a quarry in one of these within
## reach is a swing the reflection may roll out from under.
const SWINGS := ["attack", "attack2", "attack3", "thrust", "rising", "dash_strike", "lunge", "cleave", "sweep"]
## The moves a reflection answers with, as one more attack each. Slam, wall
## jump, riposte and backstab are not copied: a floor-hit and a wall-kick are no
## blow, and the last two are his answers, not moves.
const COPIES := {
	"lunge": {"type": "lunge", "windup": 0.9, "range": 260, "lunge_speed": 380, "lunge_time": 0.45, "multiplier": 1.6, "animation": "lunge"},
	"cleave": {"type": "melee", "windup": 1.3, "multiplier": 1.6, "reach_scale": 1.0, "animation": "cleave", "heavy": true},
	"sweep": {"type": "melee", "windup": 0.9, "multiplier": 0.8, "reach_scale": 1.3, "height": 18, "lift": -14, "animation": "sweep"},
	"rising": {"type": "melee", "windup": 0.8, "multiplier": 1.0, "lift": 40, "height": 50, "animation": "rising"},
	"dash_strike": {"type": "lunge", "windup": 0.8, "range": 160, "lunge_speed": 380, "lunge_time": 0.35, "multiplier": 1.2, "animation": "dash_strike"},
}
const COPY_MODES := ["last_technique", "none"]

var enemy: Enemy
var spec: Dictionary = {}
## The moves remembered, newest last (at most copies_count).
var memory: Array[String] = []
var _built_weapon := ""
var _chain: Array = []
var _step := 0
var _away_left := 0.0
var _roll_cd := 0.0
var _roll_left := 0.0
var _roll_dir := 0.0
var _lying := false
var _wake_left := 0.0
var _layer := 0
var _seen_technique := ""


## The reach of a weapon step: the hitbox's far edge, in front of the body.
static func step_reach(weapon_id: String, step: Dictionary) -> float:
	var own := Player.action_spec(str(step.get("animation", "attack")))
	var weapon := Weapons.spec(weapon_id)
	var box: Array = step.get("hitbox", weapon.get("hitbox", own.get("hitbox", [30, 30])))
	var at: Array = step.get("offset", weapon.get("offset", own.get("offset", [24, -4])))
	return float(box[0]) * 0.5 + float(at[0])


## The hero's own time for a step: its wind plus its animation.
static func hero_time(step: Dictionary) -> float:
	var animation := str(step.get("animation", "attack"))
	var own := Player.action_spec(animation)
	var animation_time := float(step.get("animation_time", own.get("animation_time", Player.SWING_TIME.get(animation, 0.25))))
	return float(step.get("wind", own.get("wind", 0.0))) + animation_time


## One melee attack per step of [param weapon_id]'s chain, in order: the
## hero's pose, his wind-up × windup_scale (never under MIN_WINDUP), the
## reflection's damage × the step's multiplier, the weapon's reach. The last
## step leaves it open for RECOVER.
static func attacks_for(weapon_id: String, mirror: Dictionary, damage: float) -> Array:
	var scale := float(mirror.get("windup_scale", 1.6))
	var steps := Weapons.chain(weapon_id)
	var out: Array = []
	for i in steps.size():
		var step: Dictionary = steps[i]
		var own := Player.action_spec(str(step.get("animation", "attack")))
		var multiplier := float(step.get("multiplier", own.get("multiplier",
			Player.COMBO_MULTIPLIERS[mini(i, Player.COMBO_MULTIPLIERS.size() - 1)])))
		var reach := step_reach(weapon_id, step)
		var last := i == steps.size() - 1
		out.append({"type": "melee", "box": true, "chain": i, "animation": str(step.get("animation", "attack")),
			"windup": maxf(MIN_WINDUP, hero_time(step) * scale), "damage": damage * multiplier * Weapons.number(weapon_id, "damage", 1.0),
			"reach": reach, "range": reach * 0.85, "height": float((step.get("hitbox", Weapons.spec(weapon_id).get("hitbox", own.get("hitbox", [30, 30]))))[1]),
			"cooldown": RECOVER if last else STEP_GAP, "recover": RECOVER if last else STEP_GAP, "weight": 1})
	return out


## The attack a remembered move becomes, at this reflection's damage and reach.
static func copy_of(move: String, damage: float, reach: float) -> Dictionary:
	if not COPIES.has(move):
		return {}
	var attack: Dictionary = COPIES[move].duplicate(true)
	attack["damage"] = damage * float(attack.get("multiplier", 1.0))
	attack["copy"] = move
	attack["weight"] = 2
	attack["cooldown"] = RECOVER + 0.6
	attack["recover"] = RECOVER
	if attack.type == "melee":
		attack["box"] = true
		attack["reach"] = reach * float(attack.get("reach_scale", 1.0))
		attack["range"] = attack.reach * 0.85
		attack["telegraph_fx"] = "glow" if move == "cleave" else "none"
	return attack


## What a reflection remembers after [param move]: copyable moves only, the
## newest last, at most [param count], none twice.
static func remember(memory: Array[String], move: String, count: int) -> Array[String]:
	var out: Array[String] = memory.duplicate()
	if not COPIES.has(move) or count <= 0:
		return out
	out.erase(move)
	out.append(move)
	while out.size() > count:
		out.remove_at(0)
	return out


## Laid on a fresh enemy whose stats carry "mirror" (Enemy._ready, every peer).
static func attach(on: Enemy) -> Mirror:
	var mirror := Mirror.new()
	mirror.name = "Mirror"
	mirror.enemy = on
	mirror.spec = on.stats.get("mirror", {})
	on.add_child(mirror)
	mirror._lie_down_if_waiting()
	return mirror


func _lie_down_if_waiting() -> void:
	if float(spec.get("rise", 0)) <= 0.0 or enemy.aware:
		return
	_lying = true
	_layer = enemy.collision_layer
	enemy.collision_layer = 0
	enemy.visual.visible = false
	enemy.remove_from_group("enemies")


## The host's say, each physics tick before the enemy's own: true while the
## mirror holds the body (lying, getting up, rolling) and the enemy must not.
func tick(delta: float) -> bool:
	_roll_cd = maxf(0.0, _roll_cd - delta)
	if _lying:
		for node in get_tree().get_nodes_in_group("player"):
			var who := node as Player
			if who != null and not who.is_dead() and who.global_position.distance_to(enemy.global_position) <= float(spec.get("rise", 0)):
				rise()
				if Net.active:
					_net_rise.rpc()
				break
		enemy.velocity = Vector2.ZERO
		return true
	if _wake_left > 0.0:
		_wake_left -= delta
		enemy.velocity.x = 0.0
		enemy.move_and_slide()
		if _wake_left <= 0.0:
			enemy.aware = true
			enemy.state = Enemy.State.CHASE
		return true
	if _roll_left > 0.0:
		_roll_left -= delta
		enemy.velocity.x = _roll_dir * ROLL_DISTANCE / ROLL_TIME
		enemy.velocity.y += 900.0 * delta
		enemy.move_and_slide()
		return true
	_maybe_roll()
	return false


## Gets up off the floor: shown, solid, an enemy again, the waking pose, and
## aware once it has stood (WAKE_TIME). Every peer plays it.
func rise() -> void:
	if not _lying:
		return
	_lying = false
	enemy.collision_layer = _layer
	enemy.visual.visible = true
	enemy.add_to_group("enemies")
	enemy._play("wake")
	_wake_left = WAKE_TIME
	Fx.sparkle(enemy.global_position + Vector2(0, 6), Color("#fff0c8"), 8)
	Audio.play_at(&"enemy_alert", enemy.global_position, -6.0)


func is_lying() -> bool:
	return _lying


@rpc("authority", "call_remote", "reliable")
func _net_rise() -> void:
	rise()


## Out from under his swing: a quarry in a swing pose within its reach and
## facing it, by chance and not more often than the cooldown. No invulnerability.
func _maybe_roll() -> void:
	var roll = spec.get("roll")
	if not roll is Dictionary or _roll_cd > 0.0 or enemy.state != Enemy.State.CHASE:
		return
	var target: Player = enemy._target
	if target == null or not is_instance_valid(target) or not SWINGS.has(target.net_anim):
		return
	var to := enemy.global_position - target.global_position
	if absf(to.x) > 80.0 or absf(to.y) > 30.0 or signf(to.x) != float(target.facing):
		return
	_roll_cd = float(roll.get("cooldown", 3.5))
	if enemy.attack_rng.randf() >= float(roll.get("chance", 0.3)):
		return
	roll_away(signf(to.x) if to.x != 0.0 else 1.0)
	if Net.active:
		_net_roll.rpc(_roll_dir)


func roll_away(direction: float) -> void:
	_roll_dir = direction
	_roll_left = ROLL_TIME
	enemy.facing = int(direction)
	enemy._play("roll")
	Fx.dust(enemy.global_position + Vector2(0, 11), Vector2(direction, -0.3), 6)


func is_rolling() -> bool:
	return _roll_left > 0.0


@rpc("authority", "call_remote", "reliable")
func _net_roll(direction: float) -> void:
	roll_away(direction)


## Picks the next blow (instead of Enemy._choose_attack): the chain's next
## step while the quarry stays in reach, else the chain's first or a copied
## move by weight. Rebuilds the chain when the quarry changed weapons, never
## between two steps. Fills enemy._attacks; -1 for none.
func choose(to_target: Vector2, delta := 0.0) -> int:
	var target: Player = enemy._target
	if target == null:
		return -1
	if spec.get("copies", "last_technique") == "last_technique" and target.last_technique != _seen_technique:
		_seen_technique = target.last_technique
		memory = remember(memory, _seen_technique, int(spec.get("copies_count", 1)))
	if _step == 0 and str(target.weapon) != _built_weapon:
		_built_weapon = str(target.weapon)
		_chain = attacks_for(_built_weapon, spec, float(enemy.stats.get("damage", 10)))
	var attacks: Array = _chain.duplicate()
	var reach := float(_chain[0].reach) if not _chain.is_empty() else 54.0
	for move in memory:
		attacks.append(copy_of(move, float(enemy.stats.get("damage", 10)), reach))
	enemy._attacks = attacks
	if _step > 0:
		if enemy._in_attack_range(_chain[_step], to_target):
			var next := _step
			_step = (_step + 1) % _chain.size()
			_away_left = 0.0
			return next
		_away_left += delta + 0.05
		if _away_left < 1.0:
			return -1
		_step = 0
	var candidates: Array[int] = []
	if enemy._in_attack_range(attacks[0], to_target):
		candidates.append(0)
	for i in range(_chain.size(), attacks.size()):
		if enemy._in_attack_range(attacks[i], to_target):
			candidates.append(i)
	if candidates.is_empty():
		return -1
	var total := 0.0
	for i in candidates:
		total += float(attacks[i].get("weight", 1))
	var roll := enemy.attack_rng.randf() * total
	var picked: int = candidates.back()
	for i in candidates:
		roll -= float(attacks[i].get("weight", 1))
		if roll <= 0.0:
			picked = i
			break
	if picked == 0 and _chain.size() > 1:
		_step = 1
	return picked
