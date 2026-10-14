extends SceneTree
## Chapter III's two armies (docs/CHAPTER3.md §2, §9, scripts/enemies/faction.gd):
##   - two hostile walkers find each other and fight, a blow between them worth
##     damage_between;
##   - a body felled by another opens the door like any, pays essence_between
##     and fills no bestiary page;
##   - with no side chosen both hunt the hero;
##   - with sided_host a spearman does not see, hear or feel him, does not hold
##     the door, and a room of only the spared is open;
##   - striking a spared one breaks the truce with it and the comrades who saw
##     it, sets truce_broken and shuts the door; one further off keeps sparing;
##   - a side chosen mid-room takes hold at once;
##   - a host archer's arrow bites a possessed but passes a spearman;
##   - a shade without a side is hostile to both, two bodies without one never
##     fight, nobody's soldier touches a boss;
##   - the gift Held Truce (truce_hold) keeps the first blow back.
## Puts the profile, the flags and the hero's stats back as it found them.
##   godot --headless --path . -s scripts/tools/faction_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


## A cleared room deals a hand of gifts, which pauses the tree: the bodies
## here must keep moving while the test watches them.
func _frames(count: int) -> void:
	for i in count:
		paused = false
		await physics_frame


func _settle(seconds := 0.3) -> void:
	await _frames(int(seconds * 60.0))


func _clear(room) -> void:
	for attempt in 8:  # a room may come in waves (Room.waves_json): clear each
		for body in get_nodes_in_group("enemies"):
			if not body.is_dead():
				body.take_damage(99999.0)
		await _frames(6)
		if room.alive == 0 and room.door.open:
			return


func _run() -> void:
	var game = root.get_node("Game")
	var profile = root.get_node("Profile")
	var saved_profile: Dictionary = profile.data.duplicate(true)
	var saved_flags: Dictionary = game.flags.duplicate()
	var faction = load("res://scripts/enemies/faction.gd")

	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	var player = run.player
	run._load_room(run.ROOMS.find("res://scenes/rooms/graveyard_tree.tscn"))
	await _settle(0.4)
	run.cutscene.abort()
	game.cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false
	await _frames(4)
	var room = run.room
	await _clear(room)
	_check(room.door.open, "graveyard_tree cleared, door open")
	for flag in ["sided_host", "sided_legion", "sided_none", "truce_broken"]:
		game.flags.erase(flag)
	var saved_hp: float = player.hp
	var here: Vector2 = player.global_position

	# --- sides that hate each other -------------------------------------------
	var spear = room.spawn_enemy("host_spearman", here + Vector2(120, -4), true)
	var possessed = room.spawn_enemy("legion_possessed", here + Vector2(150, -4), true)
	await _frames(2)
	_check(faction.soldiers >= 2, "two bodies with a side are in play (%d)" % faction.soldiers)
	_check(spear._hostile_to(possessed) and possessed._hostile_to(spear), "the host and the legion are hostile both ways")
	_check(spear._hostile_to(player) and possessed._hostile_to(player), "with no side chosen both hunt the hero")
	# one blow, measured: the spearman's thrust on the possessed in front of it
	possessed.global_position = spear.global_position + Vector2(30, 0)
	spear.facing = 1
	spear._attack = spear._attacks[0]
	var before: float = possessed.hp
	spear._melee_hit()
	await _frames(4)
	var expected: float = float(spear._attacks[0].damage) * faction.damage_between() * (1.0 - float(possessed.stats.get("armor", 0.0)))
	_check(absf((before - possessed.hp) - expected) < 0.01, "a blow between soldiers is worth damage_between (%.1f, want %.1f)" % [before - possessed.hp, expected])
	_check(possessed.felled_by_soldier, "and is known to be a soldier's blow")

	# the soldier's kill: the door counts it, the purse a share, the book nothing
	var alive: int = room.alive
	var kills_before := int(profile.data.bestiary.get("legion_possessed", {}).get("kills", 0))
	var essence_before: float = game.essence
	var run_kills: int = run.kills
	possessed.take_damage(99999.0, spear)
	await _frames(4)
	_check(room.alive == alive - 1, "a body felled by a soldier is off the door's count (%d -> %d)" % [alive, room.alive])
	var paid: float = game.essence - essence_before
	var full_pay: float = float(possessed.stats.get("essence", 10))
	_check(paid > 0.0 and paid < full_pay * 0.99, "it pays a share of its essence (%.1f of %.1f)" % [paid, full_pay])
	_check(int(profile.data.bestiary.get("legion_possessed", {}).get("kills", 0)) == kills_before, "the bestiary does not count it")
	_check(run.kills == run_kills, "nor do the night's kills")
	kills_before = int(profile.data.bestiary.get("host_spearman", {}).get("kills", 0))
	spear.take_damage(99999.0, player)
	await _frames(4)
	_check(room.alive == alive - 2 and room.door.open, "the hero's kill opens the door")
	_check(int(profile.data.bestiary.get("host_spearman", {}).get("kills", 0)) == kills_before + 1, "and his kill is in the book")

	# two hostile walkers left alone find each other (both spare the hero here)
	game.flags["sided_host"] = true
	game.flags["sided_legion"] = true
	var a = room.spawn_enemy("host_spearman", here + Vector2(110, -4))
	var b = room.spawn_enemy("legion_possessed", here + Vector2(190, -4))
	a.facing = 1
	b.facing = -1
	await _settle(3.0)
	_check(not a.is_unaware() and not b.is_unaware(), "two hostile walkers notice each other")
	_check(a.hp < a._max_hp or b.hp < b._max_hp or a.is_dead() or b.is_dead(), "and fight")
	_check(player.hp >= saved_hp - 0.01, "neither touches a hero both sides spare")
	for body in [a, b]:
		if is_instance_valid(body) and not body.is_dead():
			body.take_damage(99999.0)
	game.flags.erase("sided_legion")
	await _frames(4)

	# --- a side that spares him --------------------------------------------------
	alive = room.alive
	var spared = room.spawn_enemy("host_spearman", here + Vector2(40, -4))
	await _frames(20)
	_check(spared.spared and not spared.holds_door, "with sided_host a spearman spares him and holds no door")
	_check(room.alive == alive and room.door.open, "a room of only the spared is open")
	spared.facing = -1 if player.global_position.x < spared.global_position.x else 1
	_check(spared._spot_player() == null, "it does not see him standing in front of it")
	spared._notice(player)
	_check(spared.is_unaware(), "nor hear a shout about him")
	player.global_position = spared.global_position
	await _frames(6)
	_check(spared.is_unaware() and player.hp >= saved_hp - 0.01, "nor feel his touch")
	player.global_position = here

	# striking it: it turns, the comrade who saw it turns, one further off does not
	var witness = room.spawn_enemy("host_spearman", spared.global_position + Vector2(70, 0))
	var far = room.spawn_enemy("host_spearman", spared.global_position + Vector2(-260, 0))
	await _frames(4)
	witness.facing = -1
	alive = room.alive
	spared.take_damage(4.0, player)
	await _frames(4)
	_check(not spared.spared and spared.holds_door, "a blow on a spared one breaks its truce")
	_check(not witness.spared, "the comrade who saw it turns too")
	_check(far.spared, "one too far off to see keeps sparing")
	_check(game.flags.has("truce_broken"), "the night remembers it (truce_broken)")
	_check(room.alive == alive + 2 and not room.door.open, "the turned hold the door again (%d -> %d)" % [alive, room.alive])
	_check(spared._hostile_to(player), "and hunt him")
	for body in [spared, witness, far]:
		body.take_damage(99999.0, player)
	await _frames(6)
	_check(room.door.open, "the door opens once the turned are down")

	# a side chosen while its bodies stand
	game.flags.erase("sided_host")
	game.flags.erase("truce_broken")
	alive = room.alive
	var standing = room.spawn_enemy("host_spearman", here + Vector2(220, -4))
	await _frames(2)
	_check(room.alive == alive + 1 and standing.holds_door, "with no side chosen it holds the door")
	game.set_flag("sided_host")
	await _frames(2)
	_check(standing.spared and room.alive == alive and room.door.open, "the parley's answer spares at once and opens the door")
	standing.take_damage(99999.0)
	await _frames(4)

	# --- bolts ----------------------------------------------------------------------
	game.flags.erase("sided_host")
	var archer = room.spawn_enemy("host_archer", here + Vector2(60, -4))
	var target = room.spawn_enemy("legion_possessed", here + Vector2(160, -4))
	await _frames(2)
	var plain := {"type": "ranged", "damage": 10, "projectile_speed": 400, "projectile_style": "host_arrow", "color": "#ffffff"}
	var hit_before: float = target.hp
	archer._spawn_projectile(target.global_position + Vector2(-40, -10), Vector2.RIGHT, false, plain)
	await _frames(20)
	_check(target.hp < hit_before or target.is_dead(), "a host archer's arrow bites a possessed")
	target.take_damage(99999.0)
	var friend = room.spawn_enemy("host_spearman", here + Vector2(160, -4))
	await _frames(2)
	var friend_before: float = friend.hp
	archer._spawn_projectile(friend.global_position + Vector2(-40, -10), Vector2.RIGHT, false, plain)
	await _frames(20)
	_check(friend.hp == friend_before, "and passes through a spearman of its own side")

	# --- nobody's side --------------------------------------------------------------
	var shade = room.spawn_enemy("wormwood_shade", here + Vector2(0, -80))
	var villager = room.spawn_enemy("possessed_villager", here + Vector2(300, -4))
	var wraith = room.spawn_enemy("wraith", here + Vector2(300, -80))
	var boss = room.spawn_enemy("wormwood", here + Vector2(400, -120))
	await _frames(2)
	_check(shade._hostile_to(friend) and friend._hostile_to(shade), "a shade without a side and a spearman are enemies")
	_check(shade._hostile_to(archer) and shade._hostile_to(player), "the shade is everyone's enemy, his too")
	_check(not villager._hostile_to(wraith) and not wraith._hostile_to(villager), "two bodies without a side never fight (chapters I–II)")
	_check(not friend._hostile_to(boss) and not boss._hostile_to(friend), "no soldier touches the star, and it hunts only the hero")
	for body in [archer, friend, shade, villager, wraith, boss]:
		body.queue_free()
	await _frames(2)

	# --- Held Truce ------------------------------------------------------------------
	var had_hold = player.stats.get("truce_hold", 0.0)
	player.stats["truce_hold"] = 1.5
	var fresh = room.spawn_enemy("host_spearman", here + Vector2(80, -4))
	await _frames(2)
	fresh._attack_cd = 0.0
	fresh._notice(player)
	_check(fresh._attack_cd >= 1.5, "Held Truce keeps the first blow back (%.2f s)" % fresh._attack_cd)
	player.stats["truce_hold"] = had_hold
	fresh.queue_free()
	await _frames(2)

	game.flags = saved_flags
	profile.data = saved_profile
	profile.save()
	_check(profile.data == saved_profile, "the profile is put back as it was found")
	print("faction_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)
