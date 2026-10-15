extends SceneTree
## Reflections (docs/CHAPTER7.md §9, scripts/enemies/mirror.gd): a reflection
## fights with its quarry's weapon — one blow per step of the chain, every
## wind-up at least max(0.6 s, 1.5 × the hero's own) — answers with the move he
## used last (a lunge is copied, a slam is not; the proud one keeps two), rolls
## out from under a swing without turning invulnerable, lies in the floor until
## he comes within its "rise", and dies as glass: no blood, no pieces.
##   godot --headless --path . -s scripts/tools/mirror_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _settle(seconds := 0.3) -> void:
	await create_timer(seconds, true, false, true).timeout


func _copies(enemy) -> Array:
	var out: Array = []
	for attack in enemy._attacks:
		if attack.has("copy"):
			out.append(str(attack.copy))
	return out


func _run() -> void:
	var mirror = load("res://scripts/enemies/mirror.gd")
	var weapons = load("res://scripts/combat/weapons.gd")
	var gore = load("res://scripts/fx/gore.gd")
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	var bus = root.get_node("EventBus")
	var profile = root.get_node("Profile")
	var saved = profile.data.duplicate(true)

	print("the chain, weapon by weapon")
	var spec: Dictionary = data.enemies["mirror_elian"].mirror
	var proud: Dictionary = data.enemies["proud_mirror"].mirror
	for id in ["sword", "spear", "daggers", "headsman"]:
		_check(data.weapons.has(id), "%s is a weapon" % id)
		var chain: Array = weapons.chain(id)
		for which in [spec, proud]:
			var attacks: Array = mirror.attacks_for(id, which, 14.0)
			_check(attacks.size() == chain.size(), "%s: %d blows for %d steps" % [id, attacks.size(), chain.size()])
			var slowest_short := INF
			for i in attacks.size():
				var hero: float = mirror.hero_time(chain[i])
				var floor_at := maxf(0.6, 1.5 * hero)
				slowest_short = minf(slowest_short, float(attacks[i].windup) - floor_at)
				_check(str(attacks[i].animation) == str(chain[i].get("animation", "attack")) and int(attacks[i].chain) == i,
					"  %s step %d in the hero's own pose (%s)" % [id, i, attacks[i].animation])
			_check(slowest_short >= -0.0001, "  %s: every wind-up ≥ max(0.6, 1.5 × the hero's) (scale %.1f)" % [id, float(which.windup_scale)])
			_check(float(attacks.back().recover) >= mirror.RECOVER, "  %s: open after the last step" % id)

	print("in a room")
	game.vial = 0
	game.omen = ""
	game.night = "hall"
	data.use_night("hall")
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	run._load_room(run.ROOMS.find("res://scenes/rooms/hall_sea_of_glass.tscn"))
	await _settle(0.4)
	run.cutscene.abort()
	game.cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false
	for node in get_nodes_in_group("enemies"):
		node.queue_free()
	await _settle(0.1)
	var player = run.player
	player.set_physics_process(false)
	var at: Vector2 = player.global_position

	print("the copied move")
	var one = run._spawn_enemy("mirror_elian", at + Vector2(40, -10), true)
	await process_frame
	one.set_physics_process(false)
	one._target = player
	var mine = one.get_node("Mirror")
	_check(mine != null and not mine.is_lying(), "an aware reflection stands with its Mirror")
	mine.choose(Vector2(-40, 0))
	_check(_copies(one).is_empty(), "nothing done yet: nothing copied")
	bus.technique_performed.emit("lunge")
	_check(player.last_technique == "lunge", "our body notes its last move (%s)" % player.last_technique)
	mine.choose(Vector2(-40, 0))
	_check(_copies(one) == ["lunge"], "after a lunge the reflection has a lunge (%s)" % [_copies(one)])
	bus.technique_performed.emit("slam")
	mine.choose(Vector2(-40, 0))
	_check(not _copies(one).has("slam"), "a slam is not copied (%s)" % [_copies(one)])
	bus.technique_performed.emit("sweep")
	mine.choose(Vector2(-40, 0))
	_check(_copies(one) == ["sweep"], "one remembered: the sweep took the lunge's place (%s)" % [_copies(one)])
	var kept: Array[String] = ["lunge"]
	kept = mirror.remember(kept, "cleave", 2)
	var two_kept: bool = kept == ["lunge", "cleave"]
	kept = mirror.remember(kept, "sweep", 2)
	_check(two_kept and kept == ["cleave", "sweep"],
		"the proud one keeps the last two")
	var picked: int = mine.choose(Vector2(-30, 0))
	_check(picked >= 0, "in reach, a blow is chosen (%d)" % picked)

	print("the roll")
	mine.roll_away(1.0)
	_check(mine.is_rolling(), "a roll begins")
	var hp: float = one.hp
	one.take_damage(10.0, player, {})
	_check(one.hp < hp, "a blow mid-roll lands: no invulnerability (%.0f → %.0f)" % [hp, one.hp])

	print("the rise")
	var lying = run._spawn_enemy("mirror_elian", at + Vector2(400, -10), false)
	await process_frame
	var floor_mirror = lying.get_node("Mirror")
	_check(floor_mirror.is_lying() and not lying.visual.visible and lying.collision_layer == 0
		and not lying.is_in_group("enemies"), "unaware with a rise: it lies hidden in the floor")
	_check(run.room.holds_door("mirror_elian"), "  but it holds the door: it lives, it only lies")
	await _settle(0.3)
	_check(floor_mirror.is_lying(), "  he is 400 px away: it stays down (rise %d)" % int(spec.rise))
	player.global_position = lying.global_position + Vector2(-float(spec.rise) + 20, 0)
	await _settle(0.2)
	_check(not floor_mirror.is_lying() and lying.visual.visible and lying.collision_layer != 0
		and lying.is_in_group("enemies"), "he comes within %d: it gets up" % int(spec.rise))
	await _settle(mirror.WAKE_TIME + 0.3)
	_check(lying.aware, "  and once it has stood, it knows him")

	print("glass")
	var shards: Dictionary = gore.spec("mirror_elian", "glass")
	_check(int(shards.limbs) == 0 and float(shards.pool) == 0.0 and int(shards.gush) == 0 and float(shards.bleed) == 0.0,
		"no gush, no pool, no wound, nothing to tear")
	_check(int(gore.spec("proud_mirror", "glass").limbs) == 0, "  the proud one neither")
	_check(not gore.death(one, "mirror_elian", "glass", one.sprite, Vector2.RIGHT, true, "attack3"),
		"a violent death leaves it whole")
	one.take_damage(9999.0, player, {})
	await _settle(0.3)
	var pieces := 0
	for node in run.find_children("*", "GorePiece", true, false):
		pieces += 1
	_check(pieces == 0, "killed: no pieces on the floor")

	game.night = ""
	data.use_night("")
	profile.data = saved
	profile.save()
	print("mirror_test: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
