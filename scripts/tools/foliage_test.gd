extends SceneTree
## Painted trees answer the hero (scripts/rooms/foliage.gd): every "tree" zone
## of a game room becomes a crown over its own sway zone; a litter lies under
## it from the start; a swing into a crown bends the painting (life_bend) and
## throws leaves that fall, land on a floor and stay there; the crown swings
## back and settles; a running body kicks the litter up, a gust lifts it, a
## body pushing through a crown tears leaves loose; and however hard the trees
## are beaten, no more than MAX_LEAVES are alive at once. Ravens sit on the
## crowns that ask for them, on the crown, leaning with it; a slow body leaves
## them be, a blow to their tree (and only theirs) or a body running at one
## sends them off out of the room, and they come back to the same branches.
##   godot --headless --path . -s scripts/tools/foliage_test.gd

const STEP := 1.0 / 60.0
const ROOM := "res://scenes/rooms/graveyard_tree.tscn"

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL ", message)


func _run() -> void:
	var life = load("res://scripts/rooms/backdrop_life.gd")
	var bus = root.get_node("/root/EventBus")
	var trees_seen := 0
	for path in load("res://scripts/data/data_doc.gd").doc("game.json").get("rooms", []):
		var room = load(path).instantiate()
		root.add_child(room)
		await process_frame
		var marked := 0
		for zone in life.rule(life.room_key(room)).get("zones", []):
			if zone.has("tree"):
				marked += 1
		var foliage = room.get_node_or_null("Foliage")
		var name: String = str(path).get_file().get_basename()
		if marked == 0:
			_check(foliage == null, "%s: no tree, yet a Foliage node" % name)
		else:
			_check(foliage != null and foliage.trees.size() == marked, "%s: %d tree zones, %s crowns" % [name, marked, foliage.trees.size() if foliage != null else 0])
			var painting = life.painting_of(room)
			var shapes: PackedVector4Array = (painting.material as ShaderMaterial).get_shader_parameter("life_shape")
			for crown in foliage.trees if foliage != null else []:
				_check(int(shapes[crown.zone].x) == 2, "%s: crown %d bends shader zone %d, which is not a sway zone" % [name, crown.zone, crown.zone])
				_check(crown.rect.intersects(Rect2(0, 0, room.width, room.height)), "%s: crown %s is off the room" % [name, crown.rect])
			trees_seen += marked
		room.queue_free()
		await process_frame
	_check(trees_seen >= 10, "only %d painted trees in the chapter" % trees_seen)

	var room = load(ROOM).instantiate()
	root.add_child(room)
	await process_frame
	await physics_frame
	await physics_frame
	await process_frame
	var foliage = room.get_node("Foliage")
	foliage.set_process(false)  # stepped by hand: the same seconds on every machine
	var litter: int = foliage.leaves.size()
	_check(litter > 10, "only %d old leaves under the crowns" % litter)
	_check(foliage.leaves.all(func(leaf): return leaf.lying), "the litter is not lying on the floor")

	# ravens sit on the crowns' branch tops, lean with them and leave when struck at
	var seated := 0
	var ravens: int = foliage.birds.size()
	for zone in life.rule(life.room_key(room)).get("zones", []):
		seated += mini(int(zone.get("birds", 0)), foliage.MAX_BIRDS)
	_check(foliage.birds.size() >= seated - 2 and foliage.birds.size() > 0, "%d ravens on branches, the zones ask for %d" % [foliage.birds.size(), seated])
	for bird in foliage.birds:
		_check(bird.state == foliage.PERCHED, "a raven is not sitting at the start")
		_check(bird.crown.rect.grow(1.0).has_point(bird.perch), "a raven sits at %s, off its crown %s" % [bird.perch, bird.crown.rect])
	var dead = foliage.trees[2]
	var flock: Array = foliage.birds.filter(func(bird): return bird.crown == dead)
	var others: Array = foliage.birds.filter(func(bird): return bird.crown != dead)
	_check(not flock.is_empty() and not others.is_empty(), "no ravens on the dead tree, or none elsewhere")
	var sitter = flock[0]
	sitter.crown.lean = 2.0
	foliage._update_bird(sitter, [], 0.0)
	_check(sitter.lift > 0.0 and is_equal_approx(sitter.position.x, sitter.perch.x + 2.0 * sitter.lift), "a raven does not lean with its crown")
	sitter.crown.lean = 0.0
	# a slow body under the branch is no threat
	var walker := Node2D.new()
	walker.add_to_group("enemies")
	room.add_child(walker)
	var reach: float = foliage.ravens().get("scare", 64.0)
	# somewhere inside the reach of one, but not within a third of it of any
	var spot: Vector2 = sitter.perch
	for turn in 16:
		var at: Vector2 = sitter.perch + Vector2.from_angle(TAU * turn / 16.0) * reach * 0.7
		if foliage.birds.all(func(bird): return bird.perch.distance_to(at) > reach * 0.45):
			spot = at
			break
	_check(spot != sitter.perch, "no spot near a raven that is not right beside one")
	walker.global_position = spot
	_step(foliage, STEP)
	for i in 30:
		walker.global_position.y += 0.5  # 30 px/s
		_step(foliage, STEP)
	_check(foliage.birds.all(func(bird): return bird.state == foliage.PERCHED), "a slow body %d px off scared the ravens" % int(reach * 0.7))
	walker.queue_free()
	await process_frame
	bus.world_impulse.emit(dead.rect.get_center(), Vector2(1, 0), 0.65, &"attack")
	_check(flock.all(func(bird): return bird.state == foliage.STARTLED), "a blow to the crown did not startle its ravens")
	_step(foliage, 0.6)
	_check(flock.all(func(bird): return bird.state == foliage.FLEEING and bird.position.y < bird.perch.y), "struck, the ravens did not take off")
	_check(others.all(func(bird): return bird.state == foliage.PERCHED), "a blow to one tree scattered the ravens of another")
	_step(foliage, foliage.FLIGHT)
	_check(flock.all(func(bird): return bird.state == foliage.GONE), "the ravens are still about %s s after the blow" % foliage.FLIGHT)
	_step(foliage, float(foliage.ravens().get("away", 20.0)) * 1.3 + 10.0)
	_check(flock.all(func(bird): return bird.state == foliage.PERCHED and bird.position.distance_to(bird.perch) < 3.0), "the ravens never came back to their branches")
	# a body running at one sends it off
	var fled = others[0]
	var rook := Node2D.new()
	rook.add_to_group("player")
	room.add_child(rook)
	rook.global_position = fled.perch + Vector2(-reach * 0.9, 0.0)
	_step(foliage, STEP)
	for i in 10:
		rook.global_position.x += 4.0  # 240 px/s
		_step(foliage, STEP)
	_check(fled.state != foliage.PERCHED, "a body running at a raven left it sitting")
	rook.queue_free()
	await process_frame

	# a swing into the oak's crown
	var oak = foliage.trees[1]
	var material := life.painting_of(room).material as ShaderMaterial
	bus.world_impulse.emit(oak.rect.get_center(), Vector2(1, -0.15), 0.65, &"attack")
	var thrown: Array = foliage.leaves.slice(litter)
	_check(thrown.size() >= 8, "a blow threw %d leaves" % thrown.size())
	_check(oak.speed > 0.0, "a blow to the right set the crown swinging %s" % oak.speed)
	_step(foliage, 0.2)
	var bend: PackedFloat32Array = material.get_shader_parameter("life_bend")
	_check(bend.size() == life.MAX_ZONES and bend[oak.zone] < -0.3, "the painting did not lean right: life_bend %s" % (bend[oak.zone] if bend.size() > oak.zone else bend))
	# it swings back past rest, then settles; the leaves come down onto a floor
	var crossed := false
	var landed := {}
	for i in 60 * 30:
		_step(foliage, STEP)
		crossed = crossed or oak.lean < -0.05
		for leaf in thrown:
			if leaf.lying and not landed.has(leaf):
				landed[leaf] = true
				var under: Dictionary = foliage._ray(leaf.position - Vector2(0, 3), leaf.position + Vector2(0, 4), foliage.WORLD_MASK | foliage.LEDGE_MASK)
				_check(not under.is_empty(), "a leaf came to rest on nothing at %s" % leaf.position)
	_check(crossed, "the crown never swung back past rest")
	_check(oak.lean == 0.0 and oak.speed == 0.0, "the crown has not settled: %s" % oak.lean)
	bend = material.get_shader_parameter("life_bend")
	_check(absf(bend[oak.zone]) < 0.01, "a settled crown still bends the painting %s" % bend[oak.zone])
	_check(landed.size() >= thrown.size() / 2, "only %d of %d struck leaves landed" % [landed.size(), thrown.size()])

	# a running body kicks the litter up
	var leaf = foliage.leaves.filter(func(each): return each.lying and each.life > 1e5)[0]
	var runner := Node2D.new()
	runner.add_to_group("player")
	room.add_child(runner)
	runner.global_position = leaf.position - Vector2(6, foliage.FEET)
	_step(foliage, STEP)
	runner.global_position.x += 4.0  # 240 px/s
	_step(foliage, STEP)
	_check(not leaf.lying and leaf.velocity.y < 0.0, "a runner went through the litter and left it lying")
	runner.queue_free()
	await process_frame

	# a heavy landing lifts the litter around it
	var lying = foliage.leaves.filter(func(each): return each.lying)
	var target = lying[0]
	bus.world_impulse.emit(target.position + Vector2(10, -4), Vector2(0, 1), 1.6, &"land")
	_check(not target.lying, "a landing beside a leaf left it lying")

	# a body pushing through the willow tears leaves loose and bends it
	var willow = foliage.trees[0]
	_step(foliage, 8.0)
	var before: int = foliage.leaves.size()
	var bat := Node2D.new()
	bat.add_to_group("enemies")
	room.add_child(bat)
	bat.global_position = willow.rect.get_center()
	_step(foliage, STEP)
	for i in 30:
		bat.global_position.x += 3.0  # 180 px/s
		_step(foliage, STEP)
	_check(foliage.leaves.size() > before, "a body through the crown tore nothing loose")
	_check(willow.lean > 0.05, "a body through the crown did not push it its way: %s" % willow.lean)
	bat.queue_free()
	await process_frame

	# a blade through a falling leaf parts it in two
	_step(foliage, 12.0)
	var falling = foliage._spawn(willow, willow.rect.get_center(), Vector2.ZERO)
	falling.shape = 0  # a leaf
	var count: int = foliage.leaves.size()
	bus.world_impulse.emit(falling.position + Vector2(-6, 0), Vector2(1, 0), 0.5, &"jump")
	_check(not falling.cut, "a jump cut a leaf")
	bus.world_impulse.emit(falling.position + Vector2(-6, 0), Vector2(1, 0), 0.65, &"attack")
	var halves = foliage.leaves.filter(func(each): return each.cut)
	_check(falling.cut and halves.size() >= 2, "a swing through a falling leaf left it whole")
	_check(halves.size() < 2 or halves[0].velocity.distance_to(halves[1].velocity) > 30.0, "the halves of a cut leaf fly together")

	# however hard the trees are beaten
	for i in 40:
		bus.world_impulse.emit(oak.rect.get_center(), Vector2(-1, 0), 0.85, &"attack")
		_step(foliage, STEP)
	_check(foliage.leaves.size() <= foliage.MAX_LEAVES, "%d leaves alive, the cap is %d" % [foliage.leaves.size(), foliage.MAX_LEAVES])
	_check(absf(oak.lean) <= float(oak.style.bend) + 0.001, "the crown leaned %s past its bend" % oak.lean)

	room.queue_free()
	await process_frame

	# a leaf comes down onto a pool, floats on it and drifts, never through it
	for pond in [["res://scenes/rooms/swamp_moon.tscn", "water"], ["res://scenes/rooms/swamp_crypt.tscn", "blood"]]:
		room = load(pond[0]).instantiate()
		root.add_child(room)
		await process_frame
		await physics_frame
		await physics_frame
		await process_frame
		foliage = room.get_node("Foliage")
		foliage.set_process(false)
		_check(not foliage._pools.is_empty(), "%s: the trees do not know its %s" % [pond[0].get_file(), pond[1]])
		if foliage._pools.is_empty():
			room.queue_free()
			await process_frame
			continue
		var pool: Dictionary = foliage._pools[0]
		var over := Vector2(pool.rect.get_center().x, pool.node.surface_y(pool.rect.get_center().x) - 40.0)
		var leaf2 = foliage._spawn(foliage.trees[0], over, Vector2.ZERO)
		_step(foliage, 5.0)
		_check(leaf2.lying and not leaf2.pool.is_empty(), "%s: a leaf fell into the %s and did not float (%s)" % [pond[0].get_file(), pond[1], leaf2.position])
		var top: float = pool.node.surface_y(leaf2.position.x)
		_check(absf(leaf2.position.y - top) < 2.0, "%s: a floating leaf is %s px off the surface" % [pond[0].get_file(), leaf2.position.y - top])
		_check(pool.rect.grow(1.0).has_point(Vector2(leaf2.position.x, pool.rect.position.y + 1.0)), "%s: a floating leaf drifted off its pool" % pond[0].get_file())
		bus.world_impulse.emit(leaf2.position + Vector2(-8, 0), Vector2(1, 0), 1.0, &"dash")
		_check(not leaf2.pool.is_empty(), "%s: a dash lifted a leaf off the %s" % [pond[0].get_file(), pond[1]])
		room.queue_free()
		await process_frame
	if failures == 0:
		print("OK: foliage — %d painted trees, %d old leaves and %d ravens in %s" % [trees_seen, litter, ravens, ROOM.get_file()])
	quit(1 if failures > 0 else 0)


func _step(foliage, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		foliage._process(STEP)
		t += STEP
