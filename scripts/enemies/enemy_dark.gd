extends RefCounted
class_name EnemyDark
## What chapter IV's enemies do with the dark (docs/CHAPTER4.md §2, §6, §9),
## kept here so enemy.gd only calls in:
##   "dark_adapted": true   in a room dark ≥ 0.5 it is 15 % quicker and never
##                          steps into a bought lamp's light: it waits at the edge
##   "steals": N            a blow that lands on a body takes N essence off the
##                          shared bar; its death gives back all it took
##   "darkness_phase": {at_hp, dark, relight_price, windup, caption}
##                          a boss puts the room out once, on the host, after a
##                          wind-up like any other (the palm raised, `windup` s)
## None of it touches a wind-up: the dark never shortens what the player reads.

const ADAPTED_SPEED := 1.15
const PHASE_DEFAULTS := {"at_hp": 0.5, "dark": 0.85, "relight_price": 2.0, "windup": 1.4,
	"caption": "", "animation": "special", "color": "#fff0b0"}


## Its speed in this room: a body at home in the dark is quicker in it.
static func speed_factor(enemy: Enemy) -> float:
	if enemy.stats.get("dark_adapted", false) and Darkness.adapted_room(enemy.get_tree()):
		return ADAPTED_SPEED
	return 1.0


## A dark-adapted body's step this frame, kept out of bought light: a move
## that would carry it deeper into a lamp's light is stopped (it may always
## step out of one that was lit over it).
static func keep_out_of_light(enemy: Enemy, velocity: Vector2, delta: float) -> Vector2:
	if not enemy.stats.get("dark_adapted", false) or not Darkness.adapted_room(enemy.get_tree()):
		return velocity
	var here := enemy.global_position
	var next := here + velocity * maxf(delta, 1.0 / 30.0) * 4.0
	for node in enemy.get_tree().get_nodes_in_group("lamp_light"):
		var light := node as GlowLight
		if light == null or not light.visible or light.energy < Darkness.LIT_ENERGY:
			continue
		var reach := light.radius * Darkness.LIT_SHARE
		var to_next := light.global_position.distance_to(next)
		if to_next <= reach and to_next < light.global_position.distance_to(here):
			if enemy.stats.get("behaviour", "walker") == "flyer":
				return Vector2.ZERO
			return Vector2(0.0, velocity.y)
	return velocity


## A blow from [param source] landed on [param body] (our own): a thief takes
## its share of the bar. The bar is the host's, so a guest asks it.
static func steal(source: Node, body: Node) -> void:
	var enemy := source as Enemy
	if enemy == null or Game.practice != "":
		return
	var amount := float(enemy.stats.get("steals", 0))
	if amount <= 0.0:
		return
	Fx.sparkle(body.global_position + Vector2(0, -14), Color("#ffd870"), 6, 8.0)
	if Net.active and not enemy.multiplayer.is_server():
		enemy._net_stole.rpc_id(1, amount)
		return
	take(enemy, amount)


## The host takes [param amount] off the bar and the thief keeps it.
static func take(enemy: Enemy, amount: float) -> void:
	var taken := minf(amount, Game.essence)
	if taken <= 0.0:
		return
	Game.set_essence(Game.essence - taken, Game.level)
	enemy.set_meta("stolen", float(enemy.get_meta("stolen", 0.0)) + taken)


## The thief is down (host): all it took comes back, glinting where it fell.
static func give_back(enemy: Enemy) -> void:
	var stolen := float(enemy.get_meta("stolen", 0.0))
	if stolen <= 0.0:
		return
	enemy.set_meta("stolen", 0.0)
	Game.add_essence(stolen / maxf(0.01, float(Vials.rule("essence")) * (1.0 + Game.essence_bonus)))
	Fx.sparkle(enemy.global_position + Vector2(0, -8), Color("#ffd870"), 14, 14.0)


## The boss's douse, filled in: what darkness_phase says, defaults beneath.
static func phase(enemy: Enemy) -> Dictionary:
	var spec: Dictionary = PHASE_DEFAULTS.duplicate()
	spec.merge(enemy.stats.get("darkness_phase", {}), true)
	return spec


## Whether the boss should put the room out now (host): once, at its threshold.
static func douse_due(enemy: Enemy, fraction: float) -> bool:
	if not enemy.stats.has("darkness_phase") or enemy.get_meta("doused", false):
		return false
	return fraction <= float(phase(enemy).at_hp)


## The douse as an attack the state machine can wind up and strike.
static func douse_attack(enemy: Enemy) -> Dictionary:
	enemy.set_meta("doused", true)
	var spec := phase(enemy)
	return {"type": "douse", "windup": float(spec.windup), "animation": str(spec.animation),
		"color": str(spec.color), "cooldown": 1.2, "recover": 0.6}


## On every peer: stage 0, the palm is up and the lamps dim over the wind-up;
## stage 1, they are out and the room sinks.
static func douse(enemy: Enemy, stage: int) -> void:
	var dark := Darkness.of(enemy.get_tree())
	var spec := phase(enemy)
	enemy.set_meta("doused", true)
	if stage == 0:
		for node in enemy.get_tree().get_nodes_in_group("lamp_light"):
			var light := node as GlowLight
			if light != null:
				light.create_tween().tween_method(light.set_base_energy, light.energy, 0.35, float(spec.windup))
		return
	if dark != null:
		dark.douse_all(float(spec.dark), float(spec.relight_price))
	var caption := str(spec.caption)
	if caption != "" and Data.dialogues.has(caption):
		var box := enemy.get_tree().get_first_node_in_group("dialogue_box")
		if box != null:
			box.play(caption)
