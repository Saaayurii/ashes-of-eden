extends SceneTree
## A ranged attack's volley (data/enemies: volley, volley_gap, speed_jitter,
## projectile_scale): rounds come volley_gap apart, aimed anew, each bolt at its
## own speed and the attack's size.

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		_failed = true


## Untyped: a -s script compiles before the autoloads, so no game class names here.
func _bolts(world: Node) -> Array:
	var bolt_script = load("res://scripts/fx/projectile.gd")
	return world.get_children().filter(func(n): return n.get_script() == bolt_script)


func _run() -> void:
	await process_frame
	var world := Node2D.new()
	root.add_child(world)
	var target_script := GDScript.new()
	target_script.source_code = "extends Node2D\nfunc is_dead() -> bool:\n\treturn false\n"
	target_script.reload()
	var target := Node2D.new()
	target.set_script(target_script)
	target.add_to_group("player")
	world.add_child(target)
	target.global_position = Vector2(300, 0)
	var enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	enemy.enemy_id = "cult_caller"
	world.add_child(enemy)
	enemy.global_position = Vector2(0, 0)
	var attack := {"type": "ranged", "damage": 5, "projectile_speed": 150, "projectiles": 3, "spread": 20,
		"speed_jitter": 0.3, "projectile_scale": 1.5, "projectile_style": "hex", "volley": 3, "volley_gap": 0.2}
	enemy._attack = attack
	enemy._strike(target.global_position - enemy.global_position)
	# the later rounds are timers: nothing of them in the frame of the strike
	var first := _bolts(world)
	_check(first.size() == 3, "the first round is three bolts (%d)" % first.size())
	var speeds := {}
	for bolt in first:
		speeds[snappedf(bolt.speed, 0.01)] = true
	_check(speeds.size() > 1, "speed_jitter gives each bolt its own speed")
	_check(first.all(func(b): return absf(b.size - 1.5) < 0.001 and b.visual_style == "hex"), "every bolt has the attack's size and style")
	await create_timer(0.5, false).timeout
	_check(_bolts(world).size() == 9, "three rounds in all (%d bolts)" % _bolts(world).size())
	world.queue_free()
	await process_frame
	print("VOLLEY TEST %s" % ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
