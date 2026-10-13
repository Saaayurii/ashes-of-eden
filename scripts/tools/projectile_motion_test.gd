extends SceneTree
## Checks the actual flight displacement used by hostile and cosmetic bolts.

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		_failed = true


func _flight(kind: String, amount: float, steps := 10) -> Vector2:
	var bolt = load("res://scripts/fx/projectile.gd").new()
	bolt.speed = 100.0
	bolt.motion = kind
	bolt.motion_amount = amount
	for i in steps:
		bolt._advance_motion(0.1)
	var ending: Vector2 = bolt.position
	bolt.free()
	return ending


func _run() -> void:
	for kind in ["straight", "accelerate", "wave", "arc", "return"]:
		var capped = load("res://scripts/fx/projectile.gd").new()
		capped.speed = 100.0
		capped.motion = kind
		capped.motion_amount = 12.0 if kind == "wave" else 0.5
		capped.max_distance = 35.0
		for i in 20:
			capped._advance_motion(0.1)
		_check(is_equal_approx(capped._travelled, 35.0) and capped.position.length() <= 35.01, kind + " stops at its traveled distance cap")
		capped.free()
	var net_enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	net_enemy.enemy_id = "cultist"
	root.add_child(net_enemy)
	net_enemy.set_physics_process(false)
	net_enemy._net_projectile(Vector2.ZERO, Vector2.RIGHT, 100.0, "#ffffff", "sacred", "straight", 0.0, 1.0, 75.0)
	var copies = root.get_children().filter(func(n): return n.get_script() == load("res://scripts/fx/projectile.gd"))
	_check(copies.size() == 1 and copies[0].cosmetic and copies[0].max_distance == 75.0, "network copies use the same distance cap")
	for copy in copies: copy.free()
	net_enemy.queue_free()
	var straight := _flight("straight", 0.0)
	var wave := _flight("wave", 13.0)
	var faster := _flight("accelerate", 0.55)
	var arc := _flight("arc", 46.0)
	var psalm_early := _flight("surge", 0.45, 4)
	var psalm_late := _flight("surge", 0.45, 20)
	var wheel_out := _flight("return", 2.25, 20)
	var wheel_back := _flight("return", 2.25, 30)
	_check(straight.distance_to(Vector2(100, 0)) < 0.01, "straight flight retains its old distance")
	_check(absf(wave.x - straight.x) < 0.01 and absf(wave.y) > 3.0,
		"wraith flight weaves sideways")
	_check(faster.x > straight.x + 20.0 and absf(faster.y) < 0.01,
		"zealot bolt accelerates toward its target")
	_check(absf(arc.x - straight.x) < 0.01 and arc.y > 20.0,
		"ash bolt drops through its flight")
	_check(psalm_early.x < 15.0 and psalm_late.x > 170.0,
		"preacher's psalm pauses, then surges")
	_check(wheel_out.x > 190.0 and wheel_back.x < wheel_out.x - 40.0,
		"ophanim wheel doubles back after a missed pass")
	# a homing bolt bends toward the body it hunts, a straight one does not
	var quarry := Node2D.new()
	quarry.add_to_group("player")
	root.add_child(quarry)
	quarry.global_position = Vector2(200, 120)
	var seeker = load("res://scenes/fx/projectile.tscn").instantiate()
	seeker.speed = 100.0
	seeker.motion = "home"
	seeker.motion_amount = 2.0
	root.add_child(seeker)
	for i in 20:
		seeker._advance_motion(0.1)
	_check(seeker.position.y > 40.0, "a homing bolt turns toward its quarry")
	_check(seeker.direction.length() > 0.99, "it keeps its speed while turning")
	seeker.free()
	quarry.free()
	print("PROJECTILE MOTION TEST %s" % ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
