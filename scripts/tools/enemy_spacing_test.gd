extends SceneTree
## Enemies fight at a distance, not glued to the hero (docs/ENEMY_AI.md),
## measured against a hero who stands still and cannot die:
##   - a walker strikes, then gives ground: most of the time it is out of reach;
##   - three of a kind on one side queue up instead of stacking on one spot;
##   - flyers never park on the body; they close in only to strike;
##   - an enemy with several moves changes them, never one three times running.
##   godot --headless --path . -s scripts/tools/enemy_spacing_test.gd

const HERO_AT := Vector2(600, 225)
const FLOOR_Y := 240.0

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _run() -> void:
	var net = root.get_node("Net")
	var was_dedicated: bool = net.dedicated
	net.dedicated = true  # no bestiary or profile writes from this
	seed(20260929)
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(1400, 20)
	floor_shape.shape = rectangle
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	floor_body.global_position = Vector2(600, FLOOR_Y + 10)
	var hero = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(hero)
	hero.global_position = HERO_AT
	hero.controls_enabled = false
	hero.stats.max_hp = 1e9
	hero.hp = 1e9

	await _walker(hero)
	await _queue(hero)
	await _flyers(hero)
	await _variety(hero)

	print("ENEMY SPACING TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	hero.queue_free()
	floor_body.queue_free()
	await process_frame
	net.dedicated = was_dedicated
	quit(0 if failures == 0 else 1)


func _spawn(id: String, at: Vector2):
	var enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	enemy.enemy_id = id
	enemy.start_aware = true
	root.add_child(enemy)
	enemy.global_position = at
	enemy.attack_rng.seed = hash(id + str(at))
	return enemy


func _clear(enemies: Array) -> void:
	for enemy in enemies:
		enemy.queue_free()
	await physics_frame


func _hold_hero(hero) -> void:
	hero.hp = 1e9
	hero.global_position.x = HERO_AT.x  # a hit may shove him; the test measures the enemy
	hero.velocity.x = 0.0


## One melee walker for ten seconds: out of reach more than in it, and it backs
## off after its blows rather than standing in the hero's face.
func _walker(hero) -> void:
	var guard = _spawn("fallen_guard", HERO_AT + Vector2(160, 4))
	var reach: float = guard._melee_reach()
	var close := 0
	var frames := 600
	var strikes := 0
	var backed_off := false
	var was: int = guard.state
	var struck_at := -1
	for frame in frames:
		await physics_frame
		_hold_hero(hero)
		var gap: float = absf(guard.global_position.x - hero.global_position.x)
		if gap < reach * 0.8:
			close += 1
		if guard.state == guard.State.WINDUP and was != guard.State.WINDUP:
			strikes += 1
			struck_at = frame
		if struck_at >= 0 and frame - struck_at < 90 and gap > reach + 12.0:
			backed_off = true
		was = guard.state
	_check(strikes >= 3, "the walker keeps attacking (%d wind-ups in 10 s)" % strikes)
	_check(float(close) / frames < 0.4, "and is in the hero's face %d%% of the time, not glued" % (100 * close / frames))
	_check(backed_off, "it gives ground after a blow")
	await _clear([guard])


## Three cultists from one side: a queue, not a stack.
func _queue(hero) -> void:
	var crowd := []
	for i in 3:
		crowd.append(_spawn("cultist", HERO_AT + Vector2(140 + i * 6, 4)))
	var stacked := 0
	var crushing := 0
	var spread_sum := 0.0
	var frames := 600
	for frame in frames:
		await physics_frame
		_hold_hero(hero)
		var xs: Array = []
		var within := 0
		for body in crowd:
			xs.append(body.global_position.x)
			if absf(body.global_position.x - hero.global_position.x) < 30.0:
				within += 1
		xs.sort()
		var tightest := 1e9
		for i in xs.size() - 1:
			tightest = minf(tightest, xs[i + 1] - xs[i])
		if tightest < 8.0:
			stacked += 1
		if within >= 3:
			crushing += 1
		if frame >= 180:
			spread_sum += xs.back() - xs.front()
	_check(float(stacked) / frames < 0.2, "the three stand apart (%d%% of frames stacked)" % (100 * stacked / frames))
	_check(crushing == 0, "never all three in the hero's face at once (%d frames)" % crushing)
	_check(spread_sum / (frames - 180) > 30.0, "they form a queue (%.0f px from first to last)" % (spread_sum / (frames - 180)))
	await _clear(crowd)


## Two shades and a raven: nobody parks on the hero's body.
func _flyers(hero) -> void:
	var flock := [_spawn("shade", HERO_AT + Vector2(-120, -60)), _spawn("shade", HERO_AT + Vector2(130, -70)),
		_spawn("raven", HERO_AT + Vector2(100, -90))]
	var parked := 0
	var longest := 0
	var run := {}
	var frames := 600
	var chest: Vector2
	for frame in frames:
		await physics_frame
		_hold_hero(hero)
		chest = hero.global_position + Vector2(0, -12)
		for body in flock:
			var inside: bool = body.global_position.distance_to(chest) < 22.0 \
				and not (body.state in [body.State.WINDUP, body.State.STRIKE])
			run[body] = run.get(body, 0) + 1 if inside else 0
			longest = maxi(longest, run[body])
			if inside:
				parked += 1
	_check(float(parked) / (frames * flock.size()) < 0.08,
		"flyers sit on the body %d%% of the time outside a strike" % (100 * parked / (frames * flock.size())))
	_check(longest < 30, "and never for long (longest %d frames)" % longest)
	var apart := 1e9
	for i in flock.size():
		for j in range(i + 1, flock.size()):
			apart = minf(apart, flock[i].global_position.distance_to(flock[j].global_position))
	_check(apart > 12.0, "the flock is not one blob (closest pair %.0f px)" % apart)
	await _clear(flock)


## Three moves: it changes them, and never uses one three times running.
func _variety(hero) -> void:
	var villager = _spawn("possessed_villager", HERO_AT + Vector2(90, 4))
	var used := []
	var was: int = villager.state
	for frame in 1500:
		await physics_frame
		_hold_hero(hero)
		if villager.state == villager.State.WINDUP and was != villager.State.WINDUP:
			used.append(villager._last_attack)
		was = villager.state
	var distinct := {}
	var looped := false
	for i in used.size():
		distinct[used[i]] = true
		if i >= 2 and used[i] == used[i - 1] and used[i] == used[i - 2]:
			looped = true
	_check(distinct.size() >= 2, "it changes attacks (%s)" % [used])
	_check(not looped, "never the same one three times running")
	await _clear([villager])
