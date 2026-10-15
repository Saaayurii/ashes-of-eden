extends SceneTree
## Chapter VI's chains (docs/CHAPTER6.md §2, §9; scripts/enemies/tether.gd):
##   - a chained walker never stands further from its anchor than its chain,
##     and hunting one beyond it, it hangs there (taut) instead of following;
##   - a chained flyer stays inside its chain's circle;
##   - a lunge that runs out of chain snaps short and the body hangs for its
##     strain time, without striking;
##   - a blow on a taut body lands harder with taut_damage (Loosened Chain);
##   - a chain ring without the abbot's keys only rings — no prompt, nothing
##     opens; with saul_keys it opens, the body is loosed: faster, harder,
##     hunting, chain_opened set;
##   - a fettered angel loosed leaves: no longer counted, the door does not
##     wait for it, fettered_freed set;
##   - the Four Bound: at 0.75 / 0.5 / 0.25 the next wakes at its pillar with
##     a longer chain, no blow skips a pillar while the change runs, and the
##     other three stand at theirs;
##   - a "behind" blow lands on the one at the body's back and never in front;
##   - the omen rule tether_length lengthens every chain.
## The test puts back the flags, the profile and the omen it touches.
##   godot --headless --path . -s scripts/tools/tether_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _settle(seconds := 0.3) -> void:
	await create_timer(seconds, true, false, true).timeout


func _quiet(run) -> void:
	run.cutscene.abort()
	root.get_node("Game").cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false


func _clear(room) -> void:
	for body in get_nodes_in_group("enemies"):
		if not body.is_dead():
			body.queue_free()
	room.alive = 0


## A body of [param id] at [param offset] from the hero, hunting him.
func _spawn(room, player, id: String, offset: Vector2):
	var body = room.spawn_enemy(id, player.global_position + offset, true)
	await _frames(3)  # the anchor is found a frame late (the room's rings come up after it)
	body.aware = true
	return body


func _run() -> void:
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	var profile = root.get_node("Profile")
	var saved_profile: Dictionary = profile.data.duplicate(true)
	var saved_flags: Dictionary = game.flags.duplicate(true)
	var saved_omen: String = game.omen
	game.omen = ""
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	var player = run.player
	run._load_room(run.ROOMS.find("res://scenes/rooms/graveyard_tree.tscn"))
	await _settle(0.4)
	_quiet(run)
	var room = run.room
	for attempt in 8:  # a room may come in waves (Room.waves_json): clear each
		for body in get_nodes_in_group("enemies"):
			if not body.is_dead():
				body.take_damage(99999.0)
		await _frames(6)
		if room.alive == 0 and room.door.open:
			break
	await _settle(0.3)
	_quiet(run)  # the cleared room deals a hand of gifts, which pauses the tree
	_clear(room)
	await _frames(4)
	player.set_physics_process(false)  # the hero stands where the test puts him
	player.hp = 99999.0
	player.stats.max_hp = 99999.0

	# --- a walker on its chain ---------------------------------------------
	var penitent = await _spawn(room, player, "chained_penitent", Vector2(200, 0))
	var tether = penitent._tether
	_check(tether != null and penitent.tethered, "the chained penitent has its chain")
	var length := float(data.enemies.chained_penitent.tether.length)
	_check(absf(tether.length - length) < 0.01, "  of its own length (%.0f)" % tether.length)
	if not is_instance_valid(penitent):
		_check(false, "the penitent stays in the room")
		_finish(game, profile, saved_flags, saved_profile, saved_omen)
		return
	var furthest := 0.0
	var was_taut := false
	var struck_while_taut := false
	for i in 150:
		await physics_frame
		if not is_instance_valid(penitent) or penitent.is_dead():
			print("  (the penitent left the fight at frame %d)" % i)
			break
		furthest = maxf(furthest, absf(penitent.global_position.x - tether.anchor.x))
		if penitent.taut:
			was_taut = true
			if penitent.state == penitent.State.WINDUP and penitent._attack.get("type") != "ranged":
				struck_while_taut = true
	_check(furthest <= length + 1.0 and furthest >= length - 12.0,
		"hunting the hero 200 px off, it never passes its chain (%.0f of %.0f)" % [furthest, length])
	_check(was_taut, "  and hangs on it, taut")
	_check(not struck_while_taut, "  and no blow comes out of a taut chain")

	# --- a lunge that runs out of chain ------------------------------------
	penitent.global_position = tether.anchor - Vector2(length - 20.0, 0)
	tether._strain_left = 0.0
	tether._rest_left = 0.0
	for attack in penitent._attacks:
		if attack.get("type") == "lunge":
			penitent._attack = attack
	penitent._lunge_dir = Vector2.LEFT
	penitent._set_state(penitent.State.STRIKE, 0.38)
	var snapped := false
	for i in 20:
		await physics_frame
		if penitent.state == penitent.State.RECOVER and penitent.taut:
			snapped = true
			break
	_check(snapped, "a lunge that reaches the chain's end snaps short, and the body hangs")
	_check(absf(penitent.global_position.x - tether.anchor.x) <= length + 1.0, "  at the chain's end")
	_check(absf(penitent._state_left - tether.strain_time) < 0.05,
		"  for its strain time (%.2f s)" % tether.strain_time)

	# --- Loosened Chain ------------------------------------------------------
	penitent.taut = true
	tether._strain_left = 5.0
	_check(penitent.is_taut(), "is_taut() reads the hanging body")
	penitent.taut = false
	tether._strain_left = 0.0
	_check(not penitent.is_taut(), "  and not one with slack")

	# --- the chain ring and the abbot's keys ---------------------------------
	_clear(room)
	await _frames(2)
	game.flags.erase("saul_keys")
	game.flags.erase("chain_opened")
	game.flags.erase("fettered_freed")
	var ring = load("res://scenes/props/prop.tscn").instantiate()
	ring.prop_id = "chain"
	ring.position = player.position + Vector2(20, 0)
	player.get_parent().add_child(ring)
	await _frames(2)
	_check(ring.is_in_group("chain_rings"), "the chain ring stands in the room")
	var held = await _spawn(room, player, "chained_penitent", Vector2(10, 0))
	_check(ring.has_meta("chained") and ring.get_meta("chained") == held,
		"a body spawned within %d px is fastened to it" % int(held._tether.ANCHOR_SNAP))
	_check(held._tether.anchor.distance_to(ring.global_position + Vector2(0, -14)) < 1.0, "  its anchor is the ring")
	held.set_physics_process(false)
	ring.take_damage(500.0, player)
	await _frames(2)
	_check(not ring._spent and held.tethered, "a blade only rings on the iron: nothing opens")
	ring._offer()
	_check(not ring._prompt.visible, "  and without the keys it offers nothing")
	ring.open(player)
	await _frames(2)
	_check(not ring._spent and held.tethered, "  nor does interact open it")
	var speed: float = float(held.stats.speed)
	var damage: float = float(held._attacks[0].get("damage", 0))
	var cooldown: float = float(held._attacks[0].get("cooldown", 1.5))
	game.flags["saul_keys"] = true
	ring._offer()
	_check(ring._prompt.visible, "with the abbot's keys it offers Unlock")
	ring.open(player)
	await _frames(2)
	var freed: Dictionary = data.enemies.chained_penitent.freed
	_check(ring._spent and ring.sprite.frame == 2, "  and opens")
	_check(not held.tethered and held.aware and held.state == held.State.CHASE, "  the body is loosed, hunting")
	_check(absf(float(held.stats.speed) - speed * float(freed.speed)) < 0.01, "  faster (×%.2f)" % float(freed.speed))
	_check(absf(float(held._attacks[0].damage) - damage * float(freed.damage)) < 0.01, "  harder (×%.2f)" % float(freed.damage))
	_check(absf(float(held._attacks[0].cooldown) - cooldown * float(freed.cooldown)) < 0.01,
		"  with less rest between blows (×%.2f)" % float(freed.cooldown))
	_check(game.flags.has("chain_opened") and not game.flags.has("fettered_freed"), "  chain_opened is set")
	ring.queue_free()

	# --- the fettered angel: a flyer on its chain, loosed it leaves ---------
	_clear(room)
	await _frames(2)
	var angel = await _spawn(room, player, "fettered_angel", Vector2(240, -30))
	var reach := float(data.enemies.fettered_angel.tether.length)
	var widest := 0.0
	for i in 360:
		await physics_frame
		widest = maxf(widest, angel.global_position.distance_to(angel._tether.anchor))
	_check(widest <= reach + 1.0 and widest >= reach * 0.8, "a chained flyer stays inside its chain's circle (%.0f of %.0f)" % [widest, reach])
	room.alive = 1
	angel.loose()
	await _frames(2)
	_check(room.alive == 0, "loosed, the fettered angel is no longer waited for")
	_check(angel.is_dead() and angel.collision_layer == 0, "  it fights no more")
	_check(game.flags.has("fettered_freed"), "  fettered_freed is set")
	await _settle(1.4)
	_check(not is_instance_valid(angel) or not angel.is_inside_tree(), "  and it is gone")

	# --- a blow out of the back --------------------------------------------
	_clear(room)
	await _frames(2)
	var horse = await _spawn(room, player, "lion_horse", Vector2(60, 0))
	horse.set_physics_process(false)
	var tail: Dictionary = {}
	for attack in horse._attacks:
		if attack.get("behind", false):
			tail = attack
	_check(not tail.is_empty(), "the lion-headed horse has a tail for the one behind it")
	horse.facing = 1
	_check(not horse._in_attack_range(tail, Vector2(30, 0)), "  it does not use it on the one in front")
	_check(horse._in_attack_range(tail, Vector2(-30, 0)), "  only on the one at its back")
	horse._attack = tail
	horse.global_position = player.global_position + Vector2(40, 0)  # the hero at its back
	player._hurt_grace_left = 0.0
	var before: float = player.hp
	await horse._melee_hit()
	_check(player.hp < before, "  and the blow lands behind it (%.0f)" % (before - player.hp))
	horse.global_position = player.global_position + Vector2(-40, 0)  # the hero in front
	player._hurt_grace_left = 0.0
	before = player.hp
	await horse._melee_hit()
	_check(is_equal_approx(player.hp, before), "  and never in front")
	_check(horse.attack_area.scale.x == horse.facing, "  the hitbox turns back to the front after")

	# --- the Four Bound ------------------------------------------------------
	_clear(room)
	await _frames(2)
	var bound = await _spawn(room, player, "four_bound", Vector2(0, 0))
	bound.set_physics_process(false)
	var spec: Dictionary = data.enemies.four_bound.bound_phases
	var bt = bound._tether
	_check(bound.bound_phase == 0 and absf(bt.length - float(spec.lengths[0])) < 0.01,
		"the Hour wakes first, on a chain of %.0f" % bt.length)
	_check(bt._bound.size() == 3, "  the other three stand at their pillars")
	var pillars: Array = bt.pillars()
	var max_hp: float = bound._max_hp
	for phase in range(1, 4):
		bound._apply_damage(max_hp * 4.0, player.global_position, false, false, 0.0)
		var floor_at: float = max_hp * float(spec.at_hp[phase]) if phase < spec.at_hp.size() else 1.0
		_check(bound.bound_phase == phase, "a heavy blow under %.2f wakes the next (%d)" % [float(spec.at_hp[phase - 1]), phase])
		_check(absf(bound.hp - floor_at) < 0.5 and not bound.is_dead(),
			"  and does not skip the next pillar (hp %.0f, held at %.0f)" % [bound.hp, floor_at])
		_check(absf(bt.length - float(spec.lengths[phase])) < 0.01 and bt.anchor == pillars[phase],
			"  its chain is %.0f, from its own pillar" % bt.length)
		_check(bt._bound.size() == 3, "  three still at their pillars")
		bound._apply_damage(max_hp * 4.0, player.global_position, false, false, 0.0)
		_check(bound.bound_phase == phase and not bound.is_dead(), "  no blow passes while the change runs")
		for i in int(ceil(float(spec.swap) * 60.0)) + 4:
			bt.hold(1.0 / 60.0)
		_check(not bt.swapping(), "  the change ends")
	bound._apply_damage(max_hp * 4.0, player.global_position, false, false, 0.0)
	_check(bound.is_dead(), "the Year falls to the last blow")

	# --- the omen: every chain longer ----------------------------------------
	_clear(room)
	await _frames(2)
	data.omens["test_loosed_river"] = {"id": "test_loosed_river", "rules": {"tether_length": 1.5}}
	game.omen = "test_loosed_river"
	var long_one = await _spawn(room, player, "chained_penitent", Vector2(100, 0))
	_check(absf(long_one._tether.length - length * 1.5) < 0.01,
		"under tether_length 1.5 the chain is %.0f, not %.0f" % [long_one._tether.length, length])
	game.omen = saved_omen
	data.omens.erase("test_loosed_river")
	_clear(room)

	_finish(game, profile, saved_flags, saved_profile, saved_omen)


func _finish(game, profile, saved_flags: Dictionary, saved_profile: Dictionary, saved_omen: String) -> void:
	game.omen = saved_omen
	game.flags = saved_flags
	profile.data = saved_profile
	profile.save()
	print("TETHER TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
