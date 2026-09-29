extends SceneTree
## Checks the actual flight displacement used by hostile and cosmetic bolts.

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		_failed = true


func _flight(kind: String, amount: float) -> Vector2:
	var bolt = load("res://scripts/fx/projectile.gd").new()
	bolt.speed = 100.0
	bolt.motion = kind
	bolt.motion_amount = amount
	for i in 10:
		bolt._advance_motion(0.1)
	var ending: Vector2 = bolt.position
	bolt.free()
	return ending


func _run() -> void:
	var straight := _flight("straight", 0.0)
	var wave := _flight("wave", 13.0)
	var faster := _flight("accelerate", 0.55)
	var arc := _flight("arc", 46.0)
	_check(straight.distance_to(Vector2(100, 0)) < 0.01, "straight flight retains its old distance")
	_check(absf(wave.x - straight.x) < 0.01 and absf(wave.y) > 3.0,
		"wraith flight weaves sideways")
	_check(faster.x > straight.x + 20.0 and absf(faster.y) < 0.01,
		"zealot bolt accelerates toward its target")
	_check(absf(arc.x - straight.x) < 0.01 and arc.y > 20.0,
		"ash bolt drops through its flight")
	print("PROJECTILE MOTION TEST %s" % ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
