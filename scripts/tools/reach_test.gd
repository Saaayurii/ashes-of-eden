extends SceneTree
## Every room, played by a bot with the hero's real body and physics:
##   godot --headless --fixed-fps 60 --path . -s scripts/tools/reach_test.gd [-- room_name]
## Add `props` after the room filter to require every prop surface too.
##
## The room's colliders (Geometry, Ledges, ramps) are its surfaces. From the
## entrance the bot tries hops to every surface in rough reach — run to the
## edge and jump once or twice, or walk off it — steering in the air like a
## player would, and records where it actually lands. A room passes when the
## door and every walker's footing were reached. tools/rooms/painted_rooms.py
## (check_reach) predicts the same on paper; this proves it in the engine.
## Exit code 1 when a room fails.

const FEET := 15.0          # body origin to the soles
const MAX_RISE := 110.0     # no surface higher than this is worth a try
const MAX_GAP := 230.0
const HOP_FRAMES := 200
const FLYERS := ["shade", "wraith", "raven", "ophanim"]
## (first jump frame, second jump frame or -1, walk off without jumping)
const STRATEGIES := [[0, 18], [0, 28], [0, -1], [0, 10], [-1, -1]]

var run
var player
var surfaces: Array = []  # [x0, y0, x1, y1]
var failures := 0
var _allow_mantle := false
var _hop_strategies: Array = STRATEGIES


func _init() -> void:
	call_deferred("_main")


func _main() -> void:
	var only := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		only = args[0]
	run = load("res://scenes/run/run.tscn").instantiate()
	root.add_child(run)
	current_scene = run
	for i in 4:
		await process_frame
	player = run.player
	# Failed exploratory hops are retried. They must not open the verdict and
	# pause every subsequent attempt, or write hundreds of QA deaths to Profile.
	var death_handler: Callable = run._on_local_death
	if player.died.is_connected(death_handler):
		player.died.disconnect(death_handler)
	for index in run.ROOMS.size():
		var path: String = run.ROOMS[index]
		if only != "" and not Array(only.split("|")).any(func(part: String) -> bool: return path.contains(part)):
			continue
		if not await _test_room(index, path):
			# The body carries state from the rooms before (an animation, a
			# lock); a room that failed gets one clean second look.
			print("       retrying with a fresh body")
			player.revive(player.global_position, 1.0)
			if not await _test_room(index, path):
				failures += 1
		var return_starts := {
			"village_night": Vector2(1480, 635), "graveyard_cross": Vector2(70, 635),
			"graveyard_arches": Vector2(1120, 574), "graveyard_tree": Vector2(920, 615),
			"swamp_moon": Vector2(1520, 534), "swamp_red": Vector2(80, 485),
			"swamp_crypt": Vector2(1100, 635), "catacombs_1": Vector2(1370, 623),
			"hell_gate": Vector2(1435, 618),
			"crypt_lava": Vector2(660, 655),
		}
		if args.has("reverse") and return_starts.has(path.get_file().get_basename()):
			var crypt_start: Vector2 = return_starts[path.get_file().get_basename()]
			if not await _test_room(index, path, crypt_start):
				failures += 1
	print("REACH TEST PASSED" if failures == 0 else "REACH TEST FAILED (%d rooms)" % failures)
	quit(1 if failures > 0 else 0)


# ------------------------------------------------------------------ room ---

## True when the door and every walker were reached.
func _test_room(index: int, path: String, from_crypt: Variant = null) -> bool:
	_allow_mantle = from_crypt != null and not OS.get_cmdline_user_args().has("no_mantle")
	_hop_strategies = STRATEGIES + ([[0, 18, 36], [0, 28, 46]] if _allow_mantle else [])
	# the load closes a curtain, builds the room and opens it (title cards too)
	await run._load_room(index)
	for i in 3:
		await physics_frame
	_quiet_room()
	for i in 3:
		await physics_frame
	surfaces = _collect_surfaces()
	var entrance := _surface_under(run.room.player_spawn.global_position, 60.0)
	var start := entrance if from_crypt == null else _surface_under(from_crypt, 60.0)
	var door := _surface_under(run.room.door.global_position, 80.0)
	var goals := {}  # surface -> what stands there
	if door >= 0:
		goals[door] = "door"
	if from_crypt != null and entrance >= 0:
		goals[entrance] = "return to entrance"
	for spawn in run.room.get_node("Spawns").get_children():
		if FLYERS.has(spawn.get("enemy_id")):
			continue
		var s := _surface_under(spawn.global_position, 40.0)
		if s >= 0:
			goals[s] = str(spawn.get("enemy_id"))
	if from_crypt != null or OS.get_cmdline_user_args().has("props"):
		for prop in run.room.get_node("Props").get_children():
			if prop is Area2D:
				var s := _surface_under(prop.global_position, 12.0)
				if s >= 0:
					goals[s] = str(prop.get("prop_id"))
	var name := path.get_file().get_basename()
	if OS.get_cmdline_user_args().has("all_surfaces"):
		for surface in surfaces.size():
			if not goals.has(surface):
				goals[surface] = "surface"
	if from_crypt != null:
		name += " (return from lower ledge)" if name == "hell_gate" else " (return from crypt)"
	if start < 0 or door < 0:
		print("  FAIL %s: entrance or door stands on nothing" % name)
		return false
	var reached := {start: true}
	var hops := 0
	# A hop that fails once may land on a second try (a body is never placed
	# quite the same way twice): passes repeat until one finds nothing new.
	for attempt in 3:
		var before := reached.size()
		var queue: Array = reached.keys()
		while not queue.is_empty():
			var a: int = queue.pop_front()
			for b in _candidates(a, reached):
				if reached.has(b):
					continue
				hops += 1
				var landed: int = await _try_hop(a, b)
				if landed >= 0 and not reached.has(landed):
					reached[landed] = true
					queue.append(landed)
		if reached.size() == before:
			break
	var missing: Array = []
	for s in goals:
		if not reached.has(s):
			missing.append("%s at %s" % [goals[s], _describe(s)])
	if missing.is_empty():
		print("  ok   %s: door and %d targets reachable (%d/%d surfaces, %d hops)" %
			[name, goals.size() - 1, reached.size(), surfaces.size(), hops])
	else:
		print("  FAIL %s: cannot reach %s (%d/%d surfaces)" % [name, ", ".join(missing), reached.size(), surfaces.size()])
	var lost: Array = []
	for i in surfaces.size():
		if not reached.has(i) and surfaces[i][2] - surfaces[i][0] >= 40.0:
			lost.append(_describe(i))
	if not lost.is_empty():
		print("       unreached: %s" % ", ".join(lost))
	return missing.is_empty()


## Nobody to fight, nobody to talk to, no door to walk through, no lava.
func _quiet_room() -> void:
	for node in get_nodes_in_group("enemies") + get_nodes_in_group("npc"):
		node.queue_free()
	run.room.door.set_deferred("monitoring", false)
	for child in run.room.get_children():
		if child is Area2D and child.has_method("danger_rect"):
			child.set_physics_process(false)
			child.set_deferred("monitoring", false)
	run.cutscene.abort()
	root.get_node("Game").cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")  # a blocking line pauses the tree
	paused = false
	player.controls_enabled = true
	player.release_body()


func _collect_surfaces() -> Array:
	var out: Array = []
	var width := float(run.room.width)
	for holder_name in ["Geometry", "Ledges"]:
		var holder = run.room.get_node_or_null(holder_name)
		if holder == null:
			continue
		for child in holder.get_children():
			if child is CollisionShape2D and child.shape is RectangleShape2D:
				var size: Vector2 = child.shape.size
				var top_left: Vector2 = child.global_position - size / 2.0
				if top_left.x + size.x <= 0.0 or top_left.x >= width or top_left.y < 0.0:
					continue  # the side walls and the lid
				out.append([top_left.x, top_left.y, top_left.x + size.x, top_left.y])
			elif child is CollisionPolygon2D and child.polygon.size() >= 2:
				var p0: Vector2 = child.to_global(child.polygon[0])
				# Stair polygons contain every tread in their first half. The
				# second point is only the end of the first tread, not the ramp end.
				var p1: Vector2 = child.to_global(child.polygon[int(child.polygon.size() / 2) - 1])
				out.append([minf(p0.x, p1.x), p0.y if p0.x < p1.x else p1.y, maxf(p0.x, p1.x), p1.y if p0.x < p1.x else p0.y])
	return out


func _y_at(s: int, x: float) -> float:
	var seg: Array = surfaces[s]
	if seg[2] - seg[0] < 0.5:
		return seg[1]
	return lerpf(seg[1], seg[3], clampf((x - seg[0]) / (seg[2] - seg[0]), 0.0, 1.0))


func _surface_under(point: Vector2, reach: float) -> int:
	var best := -1
	var best_y := INF
	for i in surfaces.size():
		var seg: Array = surfaces[i]
		if point.x < seg[0] - 6.0 or point.x > seg[2] + 6.0:
			continue
		var y: float = _y_at(i, point.x)
		if y >= point.y - 6.0 and y - point.y <= reach and y < best_y:
			best_y = y
			best = i
	return best


func _describe(s: int) -> String:
	var seg: Array = surfaces[s]
	return "(%d..%d, %d)" % [seg[0], seg[2], seg[1]]


## Surfaces worth a hop from a, nearest first.
func _candidates(a: int, reached: Dictionary) -> Array:
	var sa: Array = surfaces[a]
	var list: Array = []
	for b in surfaces.size():
		if b == a or reached.has(b):
			continue
		var sb: Array = surfaces[b]
		var gap: float = maxf(0.0, maxf(sb[0] - sa[2], sa[0] - sb[2]))
		var rise: float = minf(sa[1], sa[3]) - maxf(sb[1], sb[3])
		if rise > (190.0 if _allow_mantle else MAX_RISE) or gap > MAX_GAP:
			continue
		list.append([gap + maxf(rise, 0.0), b])
	list.sort_custom(func(p, q): return p[0] < q[0])
	return list.map(func(p): return p[1])


# ------------------------------------------------------------------- hop ---

## Tries to get from a to b; returns the surface the body actually came to
## rest on after leaving a (which may be neither), or -1.
## A try is (takeoff x, target x, strategy, drop through with down + jump).
func _try_hop(a: int, b: int) -> int:
	var sa: Array = surfaces[a]
	var sb: Array = surfaces[b]
	var b_mid: float = (sb[0] + sb[2]) / 2.0
	var overlap: bool = sb[0] < sa[2] - 4.0 and sb[2] > sa[0] + 4.0
	var below: bool = _y_at(b, clampf(b_mid, sa[0], sa[2])) > _y_at(a, clampf(b_mid, sa[0], sa[2])) + 4.0
	var tries: Array = []
	if overlap and below:
		# step off whichever edge of a still has b underneath, or drop through a
		for edge in [[sa[2] - 4.0, sa[2] + 16.0], [sa[0] + 4.0, sa[0] - 16.0]]:
			if edge[1] > sb[0] + 4.0 and edge[1] < sb[2] - 4.0:
				tries.append([edge[0], edge[1], [-1, -1], false])
				tries.append([edge[0], edge[1], [0, -1], false])
		var x: float = clampf(b_mid, sa[0] + 6.0, sa[2] - 6.0)
		tries.append([x, x, [0, -1], true])
	elif overlap:
		# b straight above part of a: jump through it from under its middle or an edge
		for x in [clampf(b_mid, sa[0] + 6.0, sa[2] - 6.0), clampf(sb[0] + 8.0, sa[0] + 6.0, sa[2] - 6.0),
				clampf(sb[2] - 8.0, sa[0] + 6.0, sa[2] - 6.0)]:
			for strategy in _hop_strategies:
				tries.append([x, clampf(x, sb[0] + 10.0, sb[2] - 10.0), strategy, false])
	else:
		var dir: float = 1.0 if b_mid > sa[2] else -1.0
		var edge: float = sa[2] - 4.0 if dir > 0.0 else sa[0] + 4.0
		for x in [edge, edge - dir * 20.0]:
			for strategy in _hop_strategies:
				tries.append([x, clampf(x, sb[0] + 10.0, sb[2] - 10.0), strategy, false])
	var fallback := -1
	for attempt in tries:
		var landed: int = await _hop(a, attempt[0], attempt[1], attempt[2], attempt[3])
		if landed == b:
			return b
		if landed >= 0 and landed != a and fallback < 0:
			fallback = landed
	return fallback


func _hop(a: int, takeoff_x: float, target_x: float, strategy: Array, drop: bool) -> int:
	var dir: float = signf(target_x - takeoff_x)
	var jump_at: int = strategy[0]
	var double_at: int = strategy[1]
	var mantle_at: int = strategy[2] if strategy.size() > 2 else -1
	_release()
	if player.is_dead():
		player.revive(player.global_position, 1.0)
	# Start clear of the one-way collision margin. A teleport directly
	# against it can preserve the previous hop's contact recovery.
	player.place_in_room(Vector2(takeoff_x, _y_at(a, takeoff_x) - FEET - 12.0))
	for i in 24:
		_resume_physics_qa()
		await physics_frame
	if not player.is_on_floor():
		return -1
	var airborne := 0
	for frame in HOP_FRAMES:
		_resume_physics_qa()
		await physics_frame
		var x: float = player.global_position.x
		var steer := dir
		if airborne > 0 or absf(x - takeoff_x) > absf(target_x - takeoff_x):
			steer = signf(target_x - x) if absf(target_x - x) > 3.0 else 0.0
		_hold("move_right", steer > 0.0)
		_hold("move_left", steer < 0.0)
		_hold("move_down", drop and frame < 20)
		_hold("jump", (jump_at >= 0 and frame >= jump_at and frame < jump_at + 14)
			or (double_at >= 0 and frame >= double_at and frame < double_at + 14)
			or (mantle_at >= 0 and frame >= mantle_at and frame < mantle_at + 14))
		if not player.is_on_floor():
			airborne += 1
		elif airborne > 2:
			_release()
			var feet: Vector2 = player.global_position + Vector2(0, FEET)
			return _surface_under(feet - Vector2(0, 4), 12.0)
		if player.global_position.y > float(run.room.height) + 40.0 or player.is_dead():
			break
	_release()
	return -1


func _resume_physics_qa() -> void:
	# Room interactions can show a blocking panel during an exploratory hop.
	# This test measures traversal, not that panel: physics_frame still fires
	# in a paused tree, otherwise later hops silently never move the hero.
	if paused:
		if run.dialogue.visible:
			run.dialogue.call("_on_skip")
		paused = false
		player.controls_enabled = true


func _hold(action: String, down: bool) -> void:
	if down and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not down and Input.is_action_pressed(action):
		Input.action_release(action)


func _release() -> void:
	for action in ["move_left", "move_right", "move_down", "jump"]:
		Input.action_release(action)
