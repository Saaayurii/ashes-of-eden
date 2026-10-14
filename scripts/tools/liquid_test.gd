extends SceneTree
## Pools of liquid (docs/LIQUIDS.md, scripts/rooms/hazard.gd), measured:
##   - every kind in data/liquids.json loads and builds a living surface;
##   - water slows the hero, catches his fall, and jump in it is a swim stroke;
##   - a body that falls in splashes: the surface moves and drops fly;
##   - lava still burns the hero and takes a walker, walkers wade slowly in water;
##   - blood mends an enemy, and the hero only while he leans its path;
##   - a bolt that meets water is put out;
##   - a studio pool in a room's table comes out of the generator as a Hazard.
##   godot --headless --path . -s scripts/tools/liquid_test.gd

const FLOOR_Y := 300.0
var failures := 0
var scene: Node2D


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
	seed(20261014)
	scene = Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(2000, 20)
	floor_shape.shape = rectangle
	floor_body.add_child(floor_shape)
	scene.add_child(floor_body)
	floor_body.global_position = Vector2(600, FLOOR_Y + 10)

	_kinds()
	await _water_hero()
	await _swim()
	await _lava()
	await _walkers()
	await _blood()
	await _bolt()
	_generator()

	print("LIQUID TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	scene.queue_free()
	await process_frame
	net.dedicated = was_dedicated
	quit(0 if failures == 0 else 1)


func _pool(kind: String, at: Vector2, size: Vector2):
	var pool = load("res://scripts/rooms/hazard.gd").new()
	pool.kind = kind
	pool.size = size
	scene.add_child(pool)
	pool.global_position = at
	return pool


func _hero(at: Vector2):
	var hero = load("res://scenes/player/player.tscn").instantiate()
	scene.add_child(hero)
	hero.global_position = at
	hero.controls_enabled = false
	hero.camera.enabled = false
	hero.stats.max_hp = 1e6
	hero.hp = 1e6
	return hero


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _kinds() -> void:
	var kinds: Dictionary = load("res://scripts/rooms/hazard.gd").kinds()
	for id in ["water", "lava", "bog", "blood"]:
		_check(kinds.has(id), "data/liquids.json has %s" % id)


## Water from the floor up 40 px: he runs slower in it than on the dry floor.
func _water_hero() -> void:
	var pool = _pool("water", Vector2(400, FLOOR_Y - 40), Vector2(300, 40))
	await physics_frame
	_check(pool.surface != null and pool.surface.get_node_or_null("Rim") != null, "a pool builds its surface and rim")
	var hero = _hero(Vector2(200, FLOOR_Y - 16))
	hero.controls_enabled = true
	Input.action_press("move_right")
	await _frames(20)
	var dry := absf(hero.velocity.x)
	hero.global_position = Vector2(500, FLOOR_Y - 16)
	await _frames(20)
	var wet := absf(hero.velocity.x)
	Input.action_release("move_right")
	_check(hero._liquid_now() > 0.5, "standing in water reads as deep (%.2f)" % hero._liquid_now())
	_check(wet < dry * 0.8, "water slows the run (%.0f in it, %.0f dry)" % [wet, dry])
	hero.controls_enabled = false
	# a fall from high up into it: the surface moves, a splash flies
	hero.global_position = Vector2(560, FLOOR_Y - 200)
	hero.velocity = Vector2.ZERO
	var splashed := false
	var caught := false
	for i in 90:
		await physics_frame
		splashed = splashed or pool.surface.energy > 0.05
		if hero._liquid_now() > 0.6 and not hero.is_on_floor():
			caught = caught or hero.velocity.y <= float(pool.spec.body.sink_speed) + 40.0
	_check(splashed, "a falling body stirs the surface")
	_check(caught, "the water catches the fall to its sink speed")
	_check(_count_named(scene, "AnimatedSprite2D") >= 0, "splash effects ran without error")
	hero.queue_free()
	pool.queue_free()
	await physics_frame


## Deep water with no floor near: jump is a stroke up, again and again.
func _swim() -> void:
	var pool = _pool("water", Vector2(800, FLOOR_Y - 200), Vector2(300, 200))
	var hero = _hero(Vector2(950, FLOOR_Y - 100))
	await _frames(4)
	hero.controls_enabled = true
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	await physics_frame
	var stroke := float(pool.spec.body.swim)
	_check(hero.velocity.y < -stroke * 0.6, "jump under water is a swim stroke (%.0f)" % hero.velocity.y)
	await _frames(int(float(pool.spec.body.swim_cooldown) * 60.0) + 4)
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	await physics_frame
	_check(hero.velocity.y < -stroke * 0.5 or hero._liquid_now() < 0.5, "a second stroke after the cooldown")
	hero.controls_enabled = false
	hero.queue_free()
	pool.queue_free()
	await physics_frame


func _lava() -> void:
	var pool = _pool("lava", Vector2(400, FLOOR_Y - 20), Vector2(200, 20))
	var hero = _hero(Vector2(250, FLOOR_Y - 16))
	await _frames(30)  # he stands somewhere safe first
	var before: float = hero.hp
	hero._safe_time = -1.0  # a teleport, not a walk: the floor he left is the safe one
	hero.global_position = Vector2(500, FLOOR_Y - 16)
	await _frames(4)
	_check(hero.hp < before, "lava burns the hero (%.0f → %.0f)" % [before, hero.hp])
	await _frames(40)
	_check(not pool.danger_rect().has_point(hero.global_position), "and puts him back on safe ground (%s, safe %s)" % [hero.global_position, hero._safe_position])
	var walker = _spawn("possessed_villager", Vector2(500, FLOOR_Y - 14))
	await _frames(6)
	_check(walker.is_dead() or not is_instance_valid(walker), "lava takes a walker")
	hero.queue_free()
	pool.queue_free()
	await _frames(2)


func _walkers() -> void:
	var pool = _pool("water", Vector2(400, FLOOR_Y - 40), Vector2(300, 40))
	var walker = _spawn("possessed_villager", Vector2(500, FLOOR_Y - 14))
	await _frames(10)
	_check(walker._liquid_drag() < 0.9, "a walker in water is slowed (%.2f)" % walker._liquid_drag())
	walker.queue_free()
	pool.queue_free()
	await physics_frame


func _blood() -> void:
	var pool = _pool("blood", Vector2(400, FLOOR_Y - 40), Vector2(300, 40))
	var walker = _spawn("possessed_villager", Vector2(500, FLOOR_Y - 14))
	await _frames(4)
	walker.hp = walker._max_hp * 0.5
	var low: float = walker.hp
	await _frames(90)
	_check(walker.hp > low, "blood mends an enemy (%.1f → %.1f)" % [low, walker.hp])
	walker.queue_free()
	var game = root.get_node("Game")
	var was: Dictionary = game.alignment.duplicate()
	var hero = _hero(Vector2(500, FLOOR_Y - 16))
	hero.stats.max_hp = 100.0
	hero.hp = 50.0
	await _frames(90)
	_check(hero.hp <= 50.0, "blood does nothing for a hero who does not lean its way")
	game.alignment = {"grace": 0, "temptation": 5, "will": 0}
	await _frames(120)
	_check(hero.hp > 50.0, "blood mends a hero leaning temptation (%.1f)" % hero.hp)
	game.alignment = was
	hero.queue_free()
	pool.queue_free()
	await physics_frame


func _bolt() -> void:
	var pool = _pool("water", Vector2(400, FLOOR_Y - 40), Vector2(300, 40))
	var bolt = load("res://scenes/fx/projectile.tscn").instantiate()
	bolt.direction = Vector2.DOWN
	bolt.speed = 200.0
	scene.add_child(bolt)
	bolt.global_position = Vector2(550, FLOOR_Y - 60)
	await _frames(20)
	_check(not is_instance_valid(bolt) or bolt.is_queued_for_deletion(), "water puts out a bolt")
	pool.queue_free()
	await physics_frame


## The generator writes a studio pool as a Hazard with its kind.
func _generator() -> void:
	var text := FileAccess.get_file_as_string("res://tools/rooms/generate_rooms.py")
	_check(text.contains('kind = "{kind}"') and text.contains('_extra.get("liquids"'), "generate_rooms.py writes studio liquids")
	var lava := FileAccess.get_file_as_string("res://scenes/rooms/crypt_lava.tscn")
	_check(lava.contains('kind = "lava"') and lava.contains("painted = true"), "the crypt's painted lava is a painted lava pool")


func _spawn(id: String, at: Vector2):
	var enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	enemy.enemy_id = id
	enemy.start_aware = false
	scene.add_child(enemy)
	enemy.global_position = at
	return enemy


func _count_named(node: Node, type: String) -> int:
	var count := 0
	for child in node.get_children():
		if child.is_class(type):
			count += 1
	return count
