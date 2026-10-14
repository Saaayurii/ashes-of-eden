extends Node2D
class_name Tether
## Chains (docs/CHAPTER6.md §2, §9): an enemy with "tether" in its JSON is held
## to an anchor and goes no further than the chain's length.
##   tether        {"length": px, "anchor": [x, y]?, "strain": s?}: the anchor is
##                 that point (room pixels), else the nearest `chain` ring prop
##                 within ANCHOR_SNAP of the spawn, else the spawn itself.
##   freed         what the abbot's keys make of it (Enemy.loose): multipliers
##                 {"speed", "damage", "cooldown"}, or {"leaves": true} — it goes
##                 up the river and does not fight.
##   bound_phases  the Four Bound (one body, four pillars): {"anchors": {room:
##                 [[x, y] ×4]}, "lengths" [4], "at_hp" [3], "tints" [4],
##                 "speakers" [4], "swap": s}. Each quarter of health the one
##                 awake is pulled to its pillar and the next stands, on a longer
##                 chain; the other three hang at their pillars, drawn by every peer.
##
## The host holds the body (hold, after move_and_slide) and decides when it
## strains; every peer draws the chain from the replicated position and the
## enemy's synced `tethered` / `taut` / `bound_phase`. Strain is the window:
## a body hanging on its chain does not strike (only a ranged attack may).

const ANCHOR_SNAP := 48.0
const IRON := Color("#5a5a62")
const GLINT := Color("#cfd6e6")
const POINTS := 8
## After a strain, the body stands at its chain's end this long before it pulls again.
const STRAIN_REST := 1.0
const DEFAULT_STRAIN := 0.6

var enemy: Enemy
var anchor := Vector2.ZERO
var length := 130.0
var strain_time := DEFAULT_STRAIN
## The ring it hangs from, if one stands at the anchor (a Prop of kind "chain").
var ring: Node2D
var _strain_left := 0.0
var _rest_left := 0.0
var _swap_left := 0.0
var _wind := 0.0
var _wind_time := 0.0
var _was_taut := false
var _line: Line2D
var _glint: Line2D
## The three at their pillars (bound_phases), drawn by every peer.
var _bound: Array = []
var _shown_phase := -1
## The anchor is found a frame late: the room's rings may come up after the body.
var _anchored := false


## What a chained body replicates beyond the usual (Enemy.attach_net_sync,
## called before stats are read, so it asks the data by id).
static func synced(enemy_id: String) -> Array:
	var spec: Dictionary = Data.enemies.get(enemy_id, {})
	if not spec.has("tether") and not spec.has("bound_phases"):
		return []
	return [".:tethered", ".:taut", ".:bound_phase"]


## Gives [param body] its chain if its data asks for one. Called from Enemy._ready.
static func attach(body: Enemy) -> Tether:
	if not body.stats.has("tether") and not body.stats.has("bound_phases"):
		return null
	var tether := Tether.new()
	tether.name = "Tether"
	tether.enemy = body
	body.add_child(tether)
	return tether


func _ready() -> void:
	top_level = true
	z_index = enemy.z_index
	var spec: Dictionary = enemy.stats.get("tether", {})
	length = float(spec.get("length", 130.0)) * float(Vials.rule("tether_length"))
	strain_time = float(spec.get("strain", DEFAULT_STRAIN))
	anchor = enemy.global_position
	_line = _chain_line(2.0, IRON)
	_glint = _chain_line(1.0, GLINT)
	_glint.default_color.a = 0.35
	_line.visible = false
	_glint.visible = false
	_find_anchor.call_deferred()


func _find_anchor() -> void:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return
	var spec: Dictionary = enemy.stats.get("tether", {})
	var room := _room()
	anchor = enemy._home
	if spec.get("anchor") is Array and room != null:
		anchor = room.to_global(Vector2(float(spec.anchor[0]), float(spec.anchor[1])))
	else:
		ring = _nearest_ring()
		if ring != null:
			anchor = ring.global_position + Vector2(0, -ChainRing.RING_HEIGHT)
			ring.set_meta("chained", enemy)
	_anchored = true
	if enemy.stats.has("bound_phases"):
		_apply_phase(enemy.bound_phase)
	_redraw()


func _chain_line(width: float, color: Color) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.texture_mode = Line2D.LINE_TEXTURE_NONE
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(line)
	return line


func _room() -> Node2D:
	return enemy.get_tree().get_first_node_in_group("room") as Node2D if enemy.is_inside_tree() else null


func _nearest_ring() -> Node2D:
	var best: Node2D = null
	var best_d := ANCHOR_SNAP
	for node in enemy.get_tree().get_nodes_in_group("chain_rings"):
		var prop := node as Node2D
		if prop.has_meta("chained") and is_instance_valid(prop.get_meta("chained")) and prop.get_meta("chained") != enemy:
			continue
		var d := prop.global_position.distance_to(enemy._home)
		if d <= best_d:
			best_d = d
			best = prop
	return best


## Still held: not loosed by the keys, not dead.
func holds() -> bool:
	return enemy.tethered and not enemy.is_dead()


## Hanging on the chain: no blows until it lets go. Every peer reads the synced flag.
func is_taut() -> bool:
	return holds() and enemy.taut


## Host: in the middle of the pillar change (bound_phases).
func swapping() -> bool:
	return _swap_left > 0.0


## How far from the anchor the body may stand, across: a walker keeps its floor,
## so a ring above it shortens the reach by the drop.
func _reach(dy: float) -> float:
	return maxf(8.0, sqrt(maxf(0.0, length * length - dy * dy)))


## Host, after move_and_slide: the body back onto the chain's circle, its
## outward speed taken away. Returns true when the chain had to stop it.
func hold(delta: float) -> bool:
	_strain_left = maxf(0.0, _strain_left - delta)
	_rest_left = maxf(0.0, _rest_left - delta)
	if _swap_left > 0.0:
		_swap_left -= delta
		if _swap_left <= 0.0:
			_end_swap()
		return false  # pulled to the next pillar: the tween has the body
	if not holds() or not _anchored:
		enemy.taut = false
		return false
	var stopped := false
	var d := enemy.global_position - anchor
	if enemy._is_flying():
		if d.length() > length:
			var out := d.normalized()
			enemy.global_position = anchor + out * length
			var speed_out := enemy.velocity.dot(out)
			if speed_out > 0.0:
				enemy.velocity -= out * speed_out
			stopped = true
	else:
		var reach := _reach(d.y)
		if absf(d.x) > reach:
			enemy.global_position.x = anchor.x + signf(d.x) * reach
			if enemy.velocity.x * signf(d.x) > 0.0:
				enemy.velocity.x = 0.0
			stopped = true
	enemy.taut = _strain_left > 0.0
	return stopped


## Host, every CHASE tick: does the body hang on its chain now? It strains when
## it stands at the end and the one it hunts is beyond the chain and its reach.
func restrains(to_target: Vector2, reach: float) -> bool:
	if not holds() or not _anchored or swapping():
		return false
	if _strain_left > 0.0:
		return true
	if _rest_left > 0.0:
		return false
	var target := enemy.global_position + to_target
	var from_anchor := target - anchor
	var far: bool
	if enemy._is_flying():
		far = from_anchor.length() > length + reach
	else:
		far = absf(from_anchor.x) > _reach(enemy.global_position.y - anchor.y) + reach
	var d := enemy.global_position - anchor
	var at_end := d.length() >= length - 4.0 if enemy._is_flying() \
		else absf(d.x) >= _reach(d.y) - 4.0
	if far and at_end and signf(from_anchor.x) == signf(d.x):
		strain()
		return true
	return false


## Host: hang on the chain for [param seconds] (its own strain time by default).
func strain(seconds := -1.0) -> void:
	_strain_left = strain_time if seconds < 0.0 else seconds
	_rest_left = _strain_left + STRAIN_REST
	enemy.taut = true


## Host: a lunge reached the chain's end — it snaps short and the body hangs.
func snap() -> void:
	strain()
	_snap_fx()
	if Net.active and enemy.is_inside_tree():
		enemy._net_tether_fx.rpc(&"snap")


## Every peer: the lunge's wind-up pulls the chain straight and bright.
func wind(seconds: float) -> void:
	_wind_time = maxf(0.05, seconds)
	_wind = _wind_time


func _snap_fx() -> void:
	_sound(&"chain_snap", &"block", -4.0)
	Juice.shake(2.0)
	Fx.sparkle(enemy.global_position + Vector2(0, -8), GLINT, 6, 8.0)


func play_fx(kind: StringName) -> void:
	match kind:
		&"snap":
			_snap_fx()


func _sound(clip: StringName, fallback: StringName, volume_db := -6.0) -> void:
	if Audio.has_clip(clip):
		Audio.play_at(clip, enemy.global_position, volume_db)
	elif fallback != &"":
		Audio.play_at(fallback, enemy.global_position, volume_db - 4.0)


func _process(delta: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	_wind = maxf(0.0, _wind - delta)
	var taut := is_taut()
	if taut != _was_taut:
		_was_taut = taut
		if taut:
			_sound(&"chain_strain", &"block", -8.0)
			enemy.strain_pose()
	if not _anchored:
		return
	if enemy.stats.has("bound_phases") and enemy.bound_phase != _shown_phase:
		_show_phase(enemy.bound_phase)
	if enemy.is_dead() and not _bound.is_empty():
		for node in _bound:
			var fade := (node as Node2D).create_tween()
			fade.tween_property(node, "modulate:a", 0.0, 1.2)
			fade.tween_callback(node.queue_free)
		_bound.clear()
	_redraw()


## The chain from the ring to the waist: it sags while there is slack and
## pulls straight (and lighter) when taut or in a lunge's wind-up.
func _redraw() -> void:
	var held := holds()
	_line.visible = held
	_glint.visible = held
	if not held:
		return
	var waist := enemy.global_position + Vector2(0, -8)
	var span := waist - anchor
	var slack := clampf(1.0 - span.length() / maxf(1.0, length), 0.0, 1.0)
	var pull := 1.0 if is_taut() else (_wind / _wind_time if _wind_time > 0.0 else 0.0)
	var sag := slack * minf(length, 80.0) * 0.45 * (1.0 - pull)
	var lowest := maxf(anchor.y, waist.y)
	_line.clear_points()
	_glint.clear_points()
	for i in POINTS:
		var t := float(i) / float(POINTS - 1)
		var p := anchor.lerp(waist, t)
		p.y = minf(p.y + sin(PI * t) * sag, lowest)
		_line.add_point(p)
		_glint.add_point(p + Vector2(0, -1))
	var bright := lerpf(0.0, 0.6, pull)
	_line.default_color = IRON.lerp(GLINT, bright)
	_glint.default_color.a = 0.35 + 0.5 * pull


# ------------------------------------------------------------ bound phases ---

func _phases() -> Dictionary:
	return enemy.stats.get("bound_phases", {})


## The four pillars' feet in this room (room pixels → world), or about the body.
func pillars() -> Array:
	var spec := _phases()
	var room := _room()
	var key := RoomLayers.look_key(room, spec.get("anchors", {})) if room != null else ""
	var points: Array = spec.get("anchors", {}).get(key, [])
	var out := []
	if points.size() >= 4 and room != null:
		for p in points:
			out.append(room.to_global(Vector2(float(p[0]), float(p[1]))))
		return out
	for dx in [-300.0, -100.0, 100.0, 300.0]:
		out.append(enemy._home + Vector2(dx, 0.0))
	return out


## Every peer: the anchor, chain and tint of [param phase]; the other three at their pillars.
func _apply_phase(phase: int) -> void:
	var spec := _phases()
	var lengths: Array = spec.get("lengths", [170, 250, 330, 460])
	var all := pillars()
	phase = clampi(phase, 0, 3)
	anchor = all[phase]
	length = float(lengths[mini(phase, lengths.size() - 1)]) * float(Vials.rule("tether_length"))
	var tints: Array = spec.get("tints", [])
	if phase < tints.size():
		enemy.sprite.self_modulate = Color(str(tints[phase]))
	_shown_phase = phase
	_lay_the_others(phase, all)


func _show_phase(phase: int) -> void:
	_apply_phase(phase)
	Fx.flash(enemy.global_position + Vector2(0, -16), Color("#cfe6ff"), 160.0, 0.8, 1.2)
	if Audio.has_clip(&"boss_ophanim"):
		Audio.play(&"boss_ophanim", -6.0)


## The three not awake: sprites of the same frames at their pillars, straining
## on short taut chains. No collider, no harm — cosmetic on every peer.
func _lay_the_others(phase: int, all: Array) -> void:
	for node in _bound:
		node.queue_free()
	_bound.clear()
	var frames: SpriteFrames = enemy.sprite.sprite_frames
	var tints: Array = _phases().get("tints", [])
	for i in all.size():
		if i == phase:
			continue
		var holder := Node2D.new()
		holder.position = all[i]
		add_child(holder)
		var chain := _chain_line(2.0, IRON)
		chain.reparent(holder, false)
		chain.add_point(Vector2.ZERO)
		chain.add_point(Vector2(0, -8) + Vector2((-1.0 if i < 2 else 1.0) * 14.0, 0))
		if frames != null:
			var body := AnimatedSprite2D.new()
			body.sprite_frames = frames
			body.position = enemy.sprite.position + Vector2((-1.0 if i < 2 else 1.0) * 14.0, 0)
			body.scale = enemy.sprite.scale
			body.offset = enemy.sprite.offset
			body.flip_h = i >= 2
			var pose := "special" if frames.has_animation("special") else "idle"
			if frames.has_animation(pose):
				frames.set_animation_loop(pose, true)
				body.play(pose)
			body.modulate = Color(str(tints[i])) if i < tints.size() else Color.WHITE
			body.modulate.a = 0.8
			holder.add_child(body)
		_bound.append(holder)


## Host, from Enemy._apply_damage after the blow: the next pillar's turn when
## health falls under a threshold; while the change runs, the blow lands but
## health does not pass the next threshold. Returns the health to keep.
func floor_hp(hp: float, max_hp: float) -> float:
	var spec := _phases()
	if spec.is_empty():
		return hp
	var at_hp: Array = spec.get("at_hp", [0.75, 0.5, 0.25])
	var phase := enemy.bound_phase
	if _swap_left <= 0.0 and phase < at_hp.size() and hp <= max_hp * float(at_hp[phase]):
		_begin_swap(phase + 1)
		phase += 1
	if _swap_left > 0.0:
		var floor_at := max_hp * float(at_hp[phase]) if phase < at_hp.size() else 1.0
		return maxf(hp, floor_at)
	return hp


func _begin_swap(phase: int) -> void:
	var swap := float(_phases().get("swap", 1.6))
	_swap_left = swap
	_strain_left = 0.0
	enemy.taut = false
	enemy.bound_phase = phase
	enemy.begin_bound_swap(swap)
	var goal: Vector2 = pillars()[clampi(phase, 0, 3)]
	var pull := enemy.create_tween()
	pull.tween_property(enemy, "global_position:x", goal.x, swap * 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_show_phase(phase)


func _end_swap() -> void:
	_swap_left = 0.0
	enemy.end_bound_swap()
