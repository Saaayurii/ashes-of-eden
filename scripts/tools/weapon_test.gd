extends SceneTree
## Weapons (data/weapons, docs/WEAPONS.md), swung as a player swings them, in
## the practice yard against the straw man. For each weapon it measures:
##   - reach: the farthest gap at which the chain's first blow still lands;
##   - the chain: the poses it plays, in order, and what each blow is worth;
##   - damage a second over six seconds of attack pressed as soon as it is back.
## Then what each one is for: the sword is exactly the hero's own chain (10 · 11
## · 16, attack / attack2 / attack3), the spear reaches furthest, the headsman's
## blade hits hardest and stands its ground (poise), the knives are quick, short
## and cruel to a back. And the way they come: a gold chest lays one a night,
## taking it lays the old one down, the yard's rack holds the rest, and a save
## keeps it (an old save is the sword).
##   godot --headless --fixed-fps 60 --path . -s scripts/tools/weapon_test.gd

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


func _tap(action: String, hold := 2) -> void:
	Input.action_press(action)
	await _frames(hold)
	Input.action_release(action)
	await _frames(1)


func _settle(seconds := 0.3) -> void:
	await create_timer(seconds, true, false, true).timeout


func _place(hero, dummy, gap: float) -> void:
	hero.global_position = dummy.global_position + Vector2(-gap, -4)
	hero.velocity = Vector2.ZERO
	hero.facing = 1
	hero.body.flip_h = false
	hero.hitbox.scale.x = hero.stats.attack_scale
	hero._attack_cd = 0.0
	hero._combo = 0
	hero._combo_timer = 0.0
	dummy.hp = dummy._max_hp
	await _frames(3)


## The farthest gap (px, body to body) at which the first blow lands.
func _reach(hero, dummy) -> float:
	var best := 0.0
	var gap := 8.0
	while gap <= 110.0:
		await _place(hero, dummy, gap)
		await _tap("attack")
		await _settle(0.45)
		if dummy.hp < dummy._max_hp:
			best = gap
		gap += 4.0
	return best


func _run() -> void:
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	var weapons = load("res://scripts/combat/weapons.gd")
	game.practice = "training_dummy"
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.8)
	var run = current_scene
	run.transition.instant = true
	await _settle(0.3)
	var hero = run.player
	hero.stats.crit_chance = 0.0
	var dummy = null
	for body in get_nodes_in_group("enemies"):
		dummy = body
	_check(dummy != null and dummy.enemy_id == "training_dummy", "the yard stands a straw man up")
	_check(hero.weapon == "sword" and game.weapon == "sword", "a night starts with the sword")
	var swing: float = hero.stats.attack_damage
	var cooldown: float = hero.stats.attack_cooldown

	var ids: Array = data.weapons.keys()
	ids.sort()
	var found := {}
	print("  weapon      reach  chain                                     per blow (x%.0f)        dps" % swing)
	for id in ids:
		hero.equip(id)
		await _frames(2)
		var reach: float = await _reach(hero, dummy)
		# the chain, step by step, close in
		await _place(hero, dummy, 18.0)
		var poses: Array = []
		var drawn: Array = []
		var blows: Array = []
		var steps: int = weapons.chain(id).size()
		for i in steps:
			var before: float = dummy.hp
			await _tap("attack")
			poses.append(str(hero.body.get_meta(&"pose", "")))
			drawn.append(str(hero.body.animation))
			while hero._attack_cd > 0.0:
				await physics_frame
			await _frames(1)
			blows.append(snappedf((before - dummy.hp) / swing, 0.01))
		_check(hero._combo == 0, "%s: the chain has %d steps and starts again" % [id, steps])
		# drawn with its own frames (data/weapons "frames"), the sword with the hero's
		var prefix: String = weapons.frames(id)
		var want_drawn: Array = poses.map(func(p: String) -> String: return p if prefix == "" else "%s_%s" % [prefix, p])
		_check(drawn == want_drawn, "%s: drawn with %s (%s)" % [id, "its own frames" if prefix != "" else "the hero's own", drawn])
		# six seconds of attack pressed as soon as it is back
		await _place(hero, dummy, 18.0)
		var dealt := 0.0
		var last: float = dummy.hp
		var clock := 0.0
		while clock < 6.0:
			if hero._attack_cd <= 0.0:
				# keep at the straw man as a player would: the blows push it back
				hero.global_position.x = dummy.global_position.x - 18.0
				await _tap("attack")
				clock += 3.0 / 60.0
			else:
				await physics_frame
				clock += 1.0 / 60.0
			if dummy.hp < last:
				dealt += last - dummy.hp
			last = dummy.hp
		await _settle(0.4)
		if dummy.hp < last:
			dealt += last - dummy.hp
		var dps := dealt / 6.0
		found[id] = {"reach": reach, "poses": poses, "blows": blows, "dps": dps}
		print("  %-10s %5.0f  %-41s %-22s %5.1f" % [id, reach, " / ".join(poses), " · ".join(blows.map(func(b: float) -> String: return "%.2f" % b)), dps])
		# what the data says it should come to, wind-ups included
		var expected: float = weapons.chain_damage(id) * swing / weapons.chain_time(id, cooldown)
		_check(absf(dps - expected) <= expected * 0.2, "%s: damage a second as the data says (%.1f, data %.1f)" % [id, dps, expected])

	var sword: Dictionary = found.get("sword", {})
	_check(sword.get("poses", []) == ["attack", "attack2", "attack3"], "the sword is the hero's own chain (%s)" % [sword.get("poses")])
	_check(sword.get("blows", []) == [1.0, 1.1, 1.6], "  worth 10 · 11 · 16, as before weapons (%s)" % [sword.get("blows")])
	_check(sword.get("reach", 0.0) >= 30.0 and sword.get("reach", 0.0) <= 50.0, "  and reaches where it did (%.0f)" % sword.get("reach", 0.0))
	if found.has("spear"):
		_check(found.spear.reach >= sword.reach + 16.0, "the spear reaches further (%.0f vs %.0f)" % [found.spear.reach, sword.reach])
		_check(found.spear.poses[0] == "thrust", "  and its chain is thrusts")
	if found.has("headsman"):
		_check(found.headsman.blows.size() == 2 and found.headsman.blows.min() > 1.6, "the headsman's blade: two blows, each harder than the sword's finisher (%s)" % [found.headsman.blows])
	if found.has("daggers"):
		_check(found.daggers.blows.size() == 4 and found.daggers.blows.max() < 1.0, "the knives: four light cuts (%s)" % [found.daggers.blows])
		_check(found.daggers.reach < sword.reach, "  at shorter reach (%.0f vs %.0f)" % [found.daggers.reach, sword.reach])
	for id in found:
		_check(found[id].dps >= sword.dps * 0.75 and found[id].dps <= sword.dps * 1.25, "%s stays near the sword's damage a second (%.1f vs %.1f)" % [id, found[id].dps, sword.dps])

	# a back: the knives' first cut against the sword's, on a foe that never saw it
	var stab := {}
	for id in ["sword", "daggers"]:
		hero.equip(id)
		await _place(hero, dummy, 60.0)
		var cultist = run.room.spawn_enemy("cultist", hero.global_position + Vector2(20, 0), false)
		await _frames(2)
		cultist.global_position = hero.global_position + Vector2(18, 0)
		cultist.facing = 1
		var full: float = cultist.hp
		await _tap("attack")
		await _settle(0.3)
		stab[id] = full - cultist.hp
		cultist.take_damage(99999.0)
		await _settle(0.3)
	var want: float = (0.55 * (hero.stats.backstab_multiplier + 1.0)) / (1.0 * hero.stats.backstab_multiplier)
	_check(stab.get("sword", 0.0) > 0.0 and absf(stab.daggers / stab.sword - want) < 0.05,
		"a back is worth a whole blow more to the knives (%.1f vs the sword's %.1f)" % [stab.get("daggers", 0.0), stab.get("sword", 0.0)])

	# poise: mid-swing the headsman's blade pays less for a wound
	var taken := {}
	for id in ["sword", "headsman"]:
		hero.equip(id)
		await _place(hero, dummy, 60.0)
		hero.hp = hero.stats.max_hp
		await _tap("attack")
		hero._hurt_grace_left = 0.0
		var was: float = hero.hp
		hero.take_damage(10.0)
		taken[id] = was - hero.hp
		await _settle(0.8)
	_check(absf(taken.headsman - taken.sword * 0.7) < 0.01, "the headsman's blade stands its ground mid-swing (%.1f vs %.1f)" % [taken.headsman, taken.sword])

	# a technique on a weapon: the spear lunges further
	hero.equip("spear")
	await _place(hero, dummy, 60.0)
	hero._technique("lunge")  # placed and sized before its first await
	var lunge: Vector2 = (hero.hitbox_collision.shape as RectangleShape2D).size
	_check(lunge.x == 84.0, "the spear's lunge reaches further (%.0f)" % lunge.x)
	await _settle(0.6)

	# swapping: what is held is laid down where the new one lay
	hero.equip("sword")
	var drop = load("res://scripts/props/weapon_drop.gd").lay(run.room, "spear", run.room.to_local(hero.global_position))
	await _frames(2)
	_check(drop.local_taker() == hero, "a weapon on the floor is at hand")
	drop.take(hero)
	_check(hero.weapon == "spear" and drop.weapon == "sword", "taking it lays the sword down in its place")
	_check(game.weapons_used.has("spear"), "  and the night remembers it held the spear")
	drop.queue_free()

	# the yard's rack: every weapon not in hand
	var rack = run.room.get_node_or_null("WeaponRack")
	_check(rack != null and rack.get_child_count() == ids.size() - 1, "the yard's rack holds the others")

	# a save keeps it; an old one is the sword
	var saves = root.get_node("Saves")
	var snapshot: Dictionary = saves.capture(run.room.scene_file_path, 0, 0.0, hero)
	_check(snapshot.player.get("weapon") == "spear", "a save keeps the weapon in hand")
	hero.equip("sword")
	saves.restore(snapshot, hero)
	_check(hero.weapon == "spear" and game.weapon == "spear", "  and gives it back")
	var old: Dictionary = snapshot.duplicate(true)
	old.player.erase("weapon")
	saves.restore(old, hero)
	_check(hero.weapon == "sword", "an old save, from before weapons, is the sword")

	# the chest: one a night, never the one in hand, never in the yard
	game.practice = ""
	game.weapon_found = false
	var chest = load("res://scenes/props/prop.tscn").instantiate()
	chest.prop_id = "chest_gold"
	chest.position = run.room.to_local(hero.global_position) + Vector2(160, 0)  # not walked into
	run.room.add_child(chest)
	await _frames(2)
	var before := _drops(run.room)
	chest._lay_weapon(hero)
	var laid := _drops(run.room)
	_check(laid.size() == before.size() + 1 and game.weapon_found, "a gold chest lays a weapon beside itself")
	var new_drop = laid.filter(func(d) -> bool: return not before.has(d))
	_check(not new_drop.is_empty() and new_drop[0].weapon != hero.weapon, "  never the one in hand")
	chest._lay_weapon(hero)
	_check(_drops(run.room).size() == laid.size(), "  and only one a night")
	game.practice = "training_dummy"

	game.new_run()
	await process_frame
	print("WEAPON TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(1 if failures > 0 else 0)


func _drops(room: Node) -> Array:
	return room.find_children("*", "Node2D", true, false).filter(func(n) -> bool:
		return n.get_script() == load("res://scripts/props/weapon_drop.gd"))
