extends SceneTree
## Rest points and items (docs/BALANCE.md), measured:
##   - every item mechanic does what its card says, and nothing without it;
##   - a chest finds an item of its rarity, each item once a night, a save keeps them;
##   - resting heals and refills, raises the common dead but not an elite,
##     shuts the door until they are down again, and works once a night.
##   godot --headless --path . -s scripts/tools/rest_items_test.gd

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


func _load(run, name: String) -> void:
	run._load_room(run.ROOMS.find("res://scenes/rooms/%s.tscn" % name))
	await _settle(0.4)
	_quiet(run)
	await _frames(4)


func _enemies(run) -> Array:
	var out: Array = []
	for node in get_nodes_in_group("enemies"):
		if not node.is_dead():
			out.append(node)
	return out


func _run() -> void:
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	var saves = root.get_node("Saves")
	var items = load("res://scripts/combat/item_system.gd")
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	var player = run.player
	await _load(run, "graveyard_tree")
	var foe = _enemies(run)[0]
	foe.aware = true
	foe.state = foe.State.CHASE

	# --- the mechanics, one by one ---------------------------------------------
	player.hp = 40.0
	player.global_position = foe.global_position + Vector2(-20, 0)
	var foe_hp: float = foe.hp
	player.stats.heal_burst = 18.0
	player.heal_charges = 2
	player._healing_left = 0.01
	await _frames(3)
	_check(foe.hp < foe_hp, "censer: the flask scorches the enemy beside it (%s -> %s)" % [foe_hp, foe.hp])
	player.stats.heal_burst = 0.0

	await _settle(0.4)
	foe.state = foe.State.CHASE
	player.global_position = foe.global_position + Vector2(-30, 0)
	player.stats.parry_stun = 0.8
	player._parry(null, foe.global_position.x)
	_check(foe.state == foe.State.RECOVER, "bell: a parry stops every enemy near")
	player.stats.parry_stun = 0.0

	player.stats.clean_clear_charge = 1.0
	player.heal_charges = 1
	player._wounded_this_room = false
	root.get_node("EventBus").room_cleared.emit(1)
	_check(player.heal_charges == 2, "vigil: a room cleared without a wound fills a flask")
	player._wounded_this_room = true
	root.get_node("EventBus").room_cleared.emit(1)
	_check(player.heal_charges == 2, "vigil: not after a wound")
	player.stats.clean_clear_charge = 0.0

	player.stats.wrath_after_hit = 0.8
	player.hp = player.stats.max_hp
	player._hurt_grace_left = 0.0
	player.take_damage(5.0)
	_check(player._wrath_left > 0.0, "halo: a wound opens the wrath window")
	player.stats.wrath_after_hit = 0.0
	player._wrath_left = 0.0

	# a real swing, for the three that live inside it
	player.stats.crit_chance = 1.0
	player.stats.desperate_crit_heal = 6.0
	player.hp = player.stats.max_hp * 0.2
	var low: float = player.hp
	player.global_position = foe.global_position + Vector2(-18, 0)
	player.facing = 1
	player.hitbox.scale.x = 1
	player._attack_cd = 0.0
	player._attack()
	await _frames(4)
	_check(player.hp > low, "feather: a crit near death heals (%s -> %s)" % [low, player.hp])
	player.stats.desperate_crit_heal = 0.0
	player.stats.crit_chance = 0.05
	player.hp = player.stats.max_hp

	# grave salt: a blow in the back gives the roll back
	var sleeper = null
	for body in _enemies(run):
		if body != foe:
			sleeper = body
	if sleeper != null:
		sleeper.aware = false
		sleeper.state = sleeper.State.PATROL
		sleeper._target = null
		player.global_position = sleeper.global_position + Vector2(-18, 0)
		player.facing = 1
		player.stats.backstab_refresh = 1.0
		player._dash_cd = 2.0
		player._attack_cd = 0.0
		await _frames(1)
		player._attack()
		await _frames(4)
		_check(player._dash_cd == 0.0, "salt: a backstab gives the roll back")
		player.stats.backstab_refresh = 0.0
		# halo: the swing inside the window lands harder than one outside it
		var dummy = run.room.spawn_enemy("fallen_guard", player.global_position + Vector2(18, -4), true)
		await _frames(4)
		# held still: an aware walker keeps its distance (docs/ENEMY_AI.md) and
		# would step out of the first swing, which then read as 0 damage
		dummy.set_physics_process(false)
		player.stats.crit_chance = 0.0
		var hits: Array = []
		for wrath in [0.0, 0.8]:
			await _settle(0.35)
			dummy.hp = dummy._max_hp
			dummy.velocity = Vector2.ZERO
			dummy._knockback = Vector2.ZERO
			player.global_position = dummy.global_position + Vector2(-18, 4)
			player.facing = 1
			player.hitbox.scale.x = 1
			player.stats.wrath_after_hit = wrath
			player._wrath_left = 1.0 if wrath > 0.0 else 0.0
			player._attack_cd = 0.0
			player._combo = 0
			await _frames(1)
			player._attack()
			await _frames(4)
			hits.append(dummy._max_hp - dummy.hp)
		var plain: float = hits[0]
		var angry: float = hits[1]
		_check(plain > 0.0 and absf(angry - plain * 1.8) < 0.5, "halo: the wounded swing hits harder (%s vs %s)" % [angry, plain])
		dummy.take_damage(99999.0)
		player.stats.wrath_after_hit = 0.0
		player.stats.crit_chance = 0.05

	# --- chests, rarity, once a night, saves -------------------------------------
	game.items.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rare: String = items.roll("rare", rng)
	_check(data.items[rare].rarity == "rare", "a gold chest finds a rare item")
	for id in data.items:
		if data.items[id].rarity == "rare":
			game.items.append(id)
	var fallback: String = items.roll("rare", rng)
	_check(fallback != "" and data.items[fallback].rarity == "common", "rares gone: it finds a common one")
	game.items.clear()
	var knot_heal: float = player.stats.chest_heal
	items.give(player, "pilgrims_knot")
	_check(player.stats.chest_heal > knot_heal and game.items.has("pilgrims_knot"), "an item goes onto the body")
	items.give(player, "pilgrims_knot")
	_check(game.items.count("pilgrims_knot") == 1, "each item once a night")
	var chest = load("res://scenes/props/prop.tscn").instantiate() if ResourceLoader.exists("res://scenes/props/prop.tscn") else null
	if chest != null:
		chest.prop_id = "chest_gold"
		run.room.add_child(chest)
		chest.global_position = player.global_position + Vector2(60, 0)
		await _frames(2)
		player.hp = 50.0
		var before_items: int = game.items.size()
		chest._on_body_entered(player)
		await _frames(2)
		_check(game.items.size() == before_items + 1, "a gold chest opened: an item found")
		_check(player.hp > 50.0, "the knot: an opened chest heals")
	var saved: Dictionary = saves.capture(run.ROOMS[run.room_index], 0, 0.0, player)
	saved = saves.validate(JSON.parse_string(JSON.stringify(saved)))
	var found: Array = game.items.duplicate()
	saves.restore(saved, player)
	_check(game.items == found, "a save keeps the items found (%s)" % [game.items])

	# --- a rest ---------------------------------------------------------------------
	var point = run.room.get_node_or_null("RestPoint")
	_check(point != null, "graveyard_tree has its rest point")
	if point != null:
		var commons := 0
		for body in _enemies(run):
			if body.get("_hanging"):  # on a noose nothing lands (Enemy._hang): cut it down first
				body._snap(get_first_node_in_group("player"))
			body.take_damage(99999.0)
			commons += 1
		await _frames(4)
		_check(run.room.door.open, "the room cleared, the door opens")
		player.hp = 20.0
		player.heal_charges = 0
		player.global_position = point.global_position + Vector2(0, -15)
		await _frames(6)
		_check(point.rest(player), "resting with nobody near")
		await _frames(4)
		_check(player.hp == player.stats.max_hp and player.heal_charges == int(player.stats.heal_charges),
			"rested: whole again, every flask full")
		_check(_enemies(run).size() == run.room._from_markers.size(), "the common dead are up again (%d)" % _enemies(run).size())
		_check(not run.room.door.open, "and the door shut behind them")
		_check(run.checkpoint.player.hp == player.stats.max_hp and run.checkpoint.game_state.rested.size() == 1,
			"the autosave remembers the rest")
		_check(not point.rest(player), "once a night")
		for body in _enemies(run):
			if body.get("_hanging"):  # on a noose nothing lands (Enemy._hang): cut it down first
				body._snap(get_first_node_in_group("player"))
			body.take_damage(99999.0)
		await _frames(4)
		_check(run.room.door.open, "down again: the door opens again")

	# --- elites stay dead -------------------------------------------------------------
	await _load(run, "catacombs_2")
	var elites := 0
	for body in _enemies(run):
		if body.enemy_id == "elite_possessed":
			elites += 1
		if body.get("_hanging"):  # on a noose nothing lands (Enemy._hang): cut it down first
			body._snap(get_first_node_in_group("player"))
		body.take_damage(99999.0)
	await _frames(4)
	run.room.respawn_commons()
	await _frames(2)
	var risen_elites := 0
	for body in _enemies(run):
		if body.enemy_id == "elite_possessed":
			risen_elites += 1
	_check(elites > 0 and risen_elites == 0 and not _enemies(run).is_empty(), "a rest raises the commons, not the elite")

	print("REST ITEMS TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	current_scene = null
	run.queue_free()
	await process_frame
	for voice in root.get_node("Audio").get_children():
		if voice is AudioStreamPlayer:
			voice.stop()
	await create_timer(0.15, true, false, true).timeout
	quit(0 if failures == 0 else 1)
