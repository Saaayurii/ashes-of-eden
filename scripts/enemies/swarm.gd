extends RefCounted
class_name Swarm
## Behaviour "swarm" (docs/CHAPTER5.md §9): the locusts of the pit. One spawn
## marker lets out a cloud — base + floor(Game.surfeit × per_surfeit) + the
## omen's "swarm", never past max — and the cloud is many ordinary enemies
## (group `enemies`, each on the minimap and in the bestiary) bound by one key
## in their meta. Not boids: the cloud's goal is a point on a ring above the
## hero, like a flyer's, and every member is sprung to its own slot about that
## point with a little noise. At most dive_slots of a cloud wind up or dive at
## once; each dive is a lunge after a wind-up that lifts it SWARM_RISE px (the
## enemy's own WINDUP/STRIKE, so the telegraph and the RPCs are the usual
## ones). One sees him, the cloud wakes. The host simulates; the clients see
## the synced bodies. Locusts never touch the garden: Foliage skips them.

const KEY := &"swarm_cloud"
const DEFAULTS := {"base": 4, "per_surfeit": 0.5, "max": 12, "spacing": 18.0, "dive_slots": 2}
## How far a locust climbs over the cloud during its wind-up, px.
const SWARM_RISE := 20.0
## How far a summoned locust looks for a cloud to join, px.
const ADOPT_RADIUS := 240.0

static var _members := {}  # key -> [physics frame, Array[Enemy]]


static func is_swarm(enemy_id: String) -> bool:
	return str(Data.enemies.get(enemy_id, {}).get("behaviour", "")) == "swarm"


## The enemy's "swarm" block over the defaults.
static func spec(enemy_id: String) -> Dictionary:
	var out := DEFAULTS.duplicate()
	var own = Data.enemies.get(enemy_id, {}).get("swarm", {})
	if own is Dictionary:
		out.merge(own, true)
	return out


## How many a marker lets out tonight. [param per_surfeit] < 0 = the enemy's
## own; a room may set its own on the marker (`swarm_per_surfeit`).
static func size_for(enemy_id: String, per_surfeit := -1.0) -> int:
	var own := spec(enemy_id)
	var per := per_surfeit if per_surfeit >= 0.0 else float(own.per_surfeit)
	var count := int(own.base) + int(floor(float(Game.surfeit) * per)) + int(Vials.rule("swarm"))
	return clampi(count, 1, int(own.max))


## Host, Room.populate: the cloud a marker stands for. Returns its bodies.
static func release(room: Room, spawn: EnemySpawn) -> Array:
	var bodies: Array = []
	var count := size_for(spawn.enemy_id, float(spawn.get_meta("swarm_per_surfeit", -1.0)))
	var spacing := float(spec(spawn.enemy_id).spacing)
	for i in count:
		var body := room.spawn_enemy(spawn.enemy_id, spawn.global_position + slot(i, count, spacing))
		if body != null:
			join(body, spawn)
			bodies.append(body)
	return bodies


## A body raised again for [param spawn] (a rest) belongs to its cloud.
static func join(body: Node, spawn: Node) -> void:
	if body != null and is_swarm(str(body.get("enemy_id"))):
		body.set_meta(KEY, "swarm:%d" % spawn.get_instance_id())


## A place in a cloud of [param count]: a sunflower disc, so any count is round.
static func slot(index: int, count: int, spacing: float) -> Vector2:
	if count <= 1:
		return Vector2.ZERO
	var r := spacing * 0.75 * sqrt(float(index) + 0.5)
	var a := float(index) * 2.39996
	return Vector2(cos(a) * r, sin(a) * r * 0.6)


## Which cloud a body flies with. A summoned locust (Swarm.adopt) joins the
## nearest cloud about, or begins one.
static func cloud(body: Enemy) -> String:
	if body.has_meta(KEY):
		return str(body.get_meta(KEY))
	return adopt(body)


static func adopt(body: Enemy) -> String:
	var best := ""
	var best_d := ADOPT_RADIUS
	for node in body.get_tree().get_nodes_in_group("enemies"):
		var other := node as Enemy
		if other == null or other == body or other.is_dead() or not other.has_meta(KEY) \
				or other.enemy_id != body.enemy_id:
			continue
		var d := other.global_position.distance_to(body.global_position)
		if d < best_d:
			best_d = d
			best = str(other.get_meta(KEY))
	if best == "":
		best = "swarm:%d" % body.get_instance_id()
	body.set_meta(KEY, best)
	return best


## The living members of [param body]'s cloud, counted once a physics frame.
static func members(body: Enemy) -> Array:
	var key := cloud(body)
	var frame := Engine.get_physics_frames()
	var hit = _members.get(key)
	if hit != null and int(hit[0]) == frame and body.get_tree() != null:
		return hit[1]
	var list: Array = []
	for node in body.get_tree().get_nodes_in_group("enemies"):
		var other := node as Enemy
		if other != null and not other.is_dead() and other.has_meta(KEY) and str(other.get_meta(KEY)) == key:
			list.append(other)
	if _members.size() > 64:
		_members.clear()
	_members[key] = [frame, list]
	return list


static func centre(list: Array) -> Vector2:
	if list.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for other in list:
		sum += (other as Node2D).global_position
	return sum / list.size()


## Where this member wants to be: its slot about the cloud's goal, wobbling.
static func _home_in(body: Enemy, goal: Vector2) -> Vector2:
	var list := members(body)
	var index := maxi(0, list.find(body))
	var phase := float(body.get_instance_id() % 997)
	var t := float(Time.get_ticks_msec()) / 1000.0
	var wobble := Vector2(sin(t * 2.3 + phase), cos(t * 1.9 + phase * 0.7)) * 6.0
	return goal + slot(index, list.size(), float(spec(body.enemy_id).spacing)) + wobble


static func _toward(body: Enemy, desired: Vector2, speed: float) -> Vector2:
	var to := desired - body.global_position
	if to.length() < 1.0:
		return Vector2.ZERO
	return to.normalized() * minf(speed, to.length() * 3.0)


## CHASE: the cloud hangs on a ring above the hero, on the side it came from.
static func chase(body: Enemy, to_target: Vector2, _delta: float) -> Vector2:
	var list := members(body)
	var mid := centre(list)
	var hero := body.global_position + to_target
	var side := signf(mid.x - hero.x)
	if side == 0.0:
		side = 1.0
	var ring := maxf(60.0, float(body.stats.get("hover_distance", 70.0)))
	var goal := hero + Vector2(side * ring, -46.0)
	return _toward(body, _home_in(body, goal), float(body.stats.get("speed", 120)) * body._liquid_drag())


## WINDUP lifts it over the cloud; RECOVER takes it back to its place.
static func hold(body: Enemy) -> Vector2:
	if body.state == Enemy.State.WINDUP:
		return Vector2(0.0, -SWARM_RISE / maxf(0.3, float(body._attack.get("windup", 0.6))))
	if body.state == Enemy.State.RECOVER and body._target != null and is_instance_valid(body._target):
		return chase(body, body._target.global_position - body.global_position, 0.0) * 0.6
	return Vector2.ZERO


## PATROL: the whole cloud drifts about where it was let out, as one.
static func patrol(body: Enemy, _delta: float) -> void:
	var key := cloud(body)
	var seed := float(hash(key) % 1000)
	var t := float(Time.get_ticks_msec()) / 1000.0
	var radius := float(body.stats.get("patrol", {}).get("radius", 40.0))
	var drift := Vector2(sin(t * 0.4 + seed) * radius, sin(t * 0.9 + seed) * 10.0)
	var list := members(body)
	var home := Vector2.ZERO
	for other in list:
		home += (other as Enemy)._home
	home = home / maxf(1.0, list.size()) if not list.is_empty() else body._home
	body.velocity = _toward(body, _home_in(body, home + drift), float(body.stats.get("speed", 120)) * 0.45) + body._knockback
	if absf(body.velocity.x) > 4.0:
		body.facing = 1 if body.velocity.x > 0.0 else -1
	body._play("idle")


## May this member begin a dive now? Never more than dive_slots of a cloud.
static func may_strike(body: Enemy) -> bool:
	if str(body.stats.get("behaviour", "")) != "swarm":
		return true
	var busy := 0
	for other in members(body):
		var e := other as Enemy
		if e != body and (e.state == Enemy.State.WINDUP or e.state == Enemy.State.STRIKE):
			busy += 1
	return busy < int(spec(body.enemy_id).dive_slots)


## One saw him: the whole cloud knows.
static func wake(body: Enemy, who: Player) -> void:
	if str(body.stats.get("behaviour", "")) != "swarm":
		return
	for other in members(body):
		var e := other as Enemy
		if e != body and e.is_unaware():
			e._notice(who, false)


## Foliage asks: does this body leave the garden be? (Rev. 9:4)
static func spares(node: Node) -> bool:
	var e := node as Enemy
	return e != null and str(e.stats.get("behaviour", "")) == "swarm"
