extends SceneTree
## Headless check that every gift mechanic actually does what its card says:
##   godot --headless -s scripts/tools/gift_test.gd
## The smoke test only proves a run can be finished; this one takes each
## mechanic in turn (ward, thorns, execute, kill/clear heal, essence, the
## cutting roll, the finisher's arc, rarity weights) and measures it.
## Deliberately untyped, like every -s script: see smoke_test.gd.

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	var bus = root.get_node("EventBus")
	# load(), not preload(): the gift system names Game, which only exists once
	# the autoloads are up — a preload would compile it too early.
	var abilities = load("res://scripts/combat/ability_system.gd")
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	var player = run.player
	_assert(player != null, "run loaded with a player")

	# --- every gift applies cleanly on its own body ---------------------------
	var base_hp: float = player.stats.max_hp
	for ability in data.abilities.values():
		var before: Dictionary = player.stats.duplicate()
		abilities.apply(player, ability)
		player.stats = before
		_assert(ability.has("rarity"), "%s has a rarity" % ability.id)
	game.new_run()  # the loop above took every gift
	player.stats.max_hp = base_hp
	player.hp = base_hp
	player._guard_left = 0  # the wards it granted outlive the restored stats

	# --- a ward eats one blow whole, then it is gone ---------------------------
	player.stats.guard = 1
	player.refresh_stats()
	player.take_damage(20.0)
	_assert(is_equal_approx(player.hp, base_hp), "ward absorbs the first blow")
	player.take_damage(20.0)
	_assert(player.hp < base_hp, "the second blow lands")
	bus.room_started.emit(1)
	player.hp = base_hp
	player.take_damage(20.0)
	_assert(is_equal_approx(player.hp, base_hp), "ward refills when a room starts")
	player.stats.guard = 0
	player._guard_left = 0

	var enemy = _living_enemy(run)
	_assert(enemy != null, "an enemy to test on")
	if enemy == null:
		return _finish()

	# --- thorns: the attacker pays part of the blow ---------------------------
	player.stats.thorns = 0.5
	player.hp = base_hp
	var enemy_hp: float = enemy.hp
	player.take_damage(20.0, enemy)
	_assert(enemy.hp < enemy_hp, "thorns wound the attacker (%.1f -> %.1f)" % [enemy_hp, enemy.hp])
	player.stats.thorns = 0.0

	# --- execute: worth nothing on a healthy body, more on a spent one ---------
	enemy.hp = enemy._max_hp
	var healthy: float = enemy.hp
	enemy.take_damage(1.0, player, {"execute": 1.0, "knockback": 0.0})
	var healthy_loss: float = healthy - enemy.hp
	enemy.hp = enemy._max_hp * 0.2
	var spent: float = enemy.hp
	enemy.take_damage(1.0, player, {"execute": 1.0, "knockback": 0.0})
	var spent_loss: float = spent - enemy.hp
	_assert(spent_loss > healthy_loss * 1.9, "execute doubles the blow on a spent enemy (%.1f vs %.1f)" % [spent_loss, healthy_loss])
	_assert(enemy.hp > 0.0, "the execution test left the enemy standing")
	enemy.hp = enemy._max_hp

	# --- kill and clear heal ---------------------------------------------------
	player.stats.kill_heal = 4.0
	player.hp = 50.0
	bus.enemy_died.emit(&"test", Vector2.ZERO)
	_assert(is_equal_approx(player.hp, 54.0), "a kill returns health")
	player.stats.kill_heal = 0.0
	player.stats.clear_heal = 25.0
	bus.room_cleared.emit(1)
	_assert(is_equal_approx(player.hp, 79.0), "a cleared room returns health")
	player.stats.clear_heal = 0.0

	# --- essence bonus ---------------------------------------------------------
	game.essence = 0.0
	game.essence_bonus = 0.2
	game.add_essence(10.0)
	_assert(is_equal_approx(game.essence, 12.0), "greed adds 20% essence")
	game.essence_bonus = 0.0
	game.essence = 0.0

	# --- the cutting roll: one cut per roll, however long it overlaps ----------
	player.stats.dash_damage = 18.0
	player.global_position = enemy.global_position
	enemy.hp = enemy._max_hp
	var before_roll: float = enemy.hp
	player._roll()
	await _frames(6)
	var roll_loss: float = before_roll - enemy.hp
	_assert(roll_loss > 0.0, "the roll cuts what it passes through (%.1f)" % roll_loss)
	_assert(roll_loss < 18.0 * 1.5, "one roll is one cut, not one per frame")
	player.stats.dash_damage = 0.0
	await _frames(20)  # let the roll run out

	# --- the finisher's arc bites enemies and nothing else ---------------------
	player.stats.wave_damage = 0.8
	player.global_position = enemy.global_position - Vector2(90, 0)
	player.facing = 1
	enemy.hp = enemy._max_hp
	var before_wave: float = enemy.hp
	player._throw_wave()
	var arcs := 0
	for node in player.get_parent().get_children():
		if node.get("friendly") == true:
			arcs += 1
	_assert(arcs == 1, "the finisher throws one friendly arc")
	player.hp = base_hp
	await _settle(0.8)
	_assert(enemy.hp < before_wave, "the arc hits the enemy ahead (%.1f -> %.1f)" % [before_wave, enemy.hp])
	player.stats.wave_damage = 0.0

	# --- the moves' gifts --------------------------------------------------------
	# Cruel Opening: the same swing on the same body, idle and winding up.
	# Every body in the room holds still: a stray blow from another one would
	# be read as a heal that did not happen.
	var frozen: Array = run.entities.get_children().filter(func(n): return n.has_method("take_damage"))
	for body in frozen:
		body.set_physics_process(false)
	enemy.aware = true
	player.stats.crit_chance = 0.0
	player.global_position = enemy.global_position - Vector2(22, 0)
	player.facing = 1
	player.body.flip_h = false
	player.hitbox.scale.x = player.stats.attack_scale
	var swing_loss = func(winding: bool) -> float:
		enemy.hp = enemy._max_hp
		enemy.state = enemy.State.WINDUP if winding else enemy.State.CHASE
		player._combo = 0
		player._attack_cd = 0.0
		player._attack()
		await _frames(4)
		return enemy._max_hp - enemy.hp
	player.stats.windup_bonus = 0.5
	var idle_loss: float = await swing_loss.call(false)
	var windup_loss: float = await swing_loss.call(true)
	_assert(idle_loss > 0.0 and absf(windup_loss / idle_loss - 1.5) < 0.05,
		"cruel opening: a wind-up takes half again (%.1f vs %.1f)" % [windup_loss, idle_loss])
	player.stats.windup_bonus = 0.0
	enemy.state = enemy.State.CHASE
	await _frames(30)
	# Benediction: a special move that lands heals; a plain swing does not
	player.stats.technique_heal = 4.0
	player.hp = 50.0
	player._attack_cd = 0.0
	player._attack()
	await _frames(4)
	_assert(is_equal_approx(player.hp, 50.0), "benediction: a plain swing heals nothing")
	await _frames(40)
	enemy.hp = enemy._max_hp
	player._attack_cd = 0.0
	player._technique("sweep")
	await _frames(4)
	_assert(is_equal_approx(player.hp, 54.0), "benediction: a sweep that lands heals 4 (%.1f)" % player.hp)
	player.stats.technique_heal = 0.0
	player.hp = base_hp
	# Quick Study and Watchman's Patience: the charge and the parry's moment
	var plain_charge: float = player.charge_needed()
	player.stats.charge_speed = 0.4
	_assert(absf(plain_charge / player.charge_needed() - 1.4) < 0.001, "quick study: the cleave glows 40% sooner")
	player.stats.charge_speed = 0.0
	player.stats.parry_window = 0.06
	player._block_cd = 0.0
	player._raise_block(true)
	_assert(is_equal_approx(player._parry_left, player.PARRY_WINDOW + 0.06), "watchman's patience: the parry lasts 0.06 s longer")
	player._lower_block()
	player.stats.parry_window = 0.0
	for body in frozen:
		if is_instance_valid(body):
			body.set_physics_process(true)

	# --- rarity: legendaries are rare, commons are not -------------------------
	var counts := {"common": 0, "rare": 0, "epic": 0, "legendary": 0}
	var pool: Array = data.abilities.values().filter(func(a): return a.path == "grace")
	for i in 4000:
		counts[run._weighted_pick(pool).rarity] += 1
	_assert(counts.common > counts.rare and counts.rare > counts.epic and counts.epic > counts.legendary,
		"rarity weights order the offers %s" % counts)
	_assert(counts.legendary > 0, "a legendary still turns up")

	# --- gifts that arrive on a later night ------------------------------------
	# Some cards name the night they start appearing on, so a fifth run can
	# hold something the first could not (Run.gift_locked).
	var gated: Array = data.abilities.values().filter(
		func(a): return int(a.get("unlock_nights", 0)) > 0)
	_assert(not gated.is_empty(), "some gifts are held back for a later night")
	if not gated.is_empty():
		var profile = root.get_node("Profile")
		var nights_before: int = profile.data.nights
		var gate: Dictionary = gated[0]
		var needs := int(gate.unlock_nights)

		profile.data.nights = 0
		_assert(run.gift_locked(gate), "on the first night %s is not offered" % gate.id)
		_assert(run.gifts_unlocked_tonight().is_empty(),
			"the first night announces nothing")

		profile.data.nights = needs
		_assert(not run.gift_locked(gate), "on night %d it is" % needs)
		var tonight: Array = run.gifts_unlocked_tonight().map(func(a): return a.id)
		_assert(tonight.has(gate.id), "and it is what that night announces %s" % [tonight])

		profile.data.nights = needs + 1
		_assert(not run.gift_locked(gate), "it stays available afterwards")
		_assert(not run.gifts_unlocked_tonight().map(func(a): return a.id).has(gate.id),
			"but is not announced twice")

		# A gift with no night named has always been available.
		var ungated: Array = data.abilities.values().filter(
			func(a): return int(a.get("unlock_nights", 0)) == 0)
		profile.data.nights = 0
		_assert(not ungated.is_empty() and not run.gift_locked(ungated[0]),
			"a gift with no night named is never held back")
		profile.data.nights = nights_before
	_finish()


func _living_enemy(run):
	for node in run.entities.get_children():
		if node.has_method("take_damage") and node.get("hp") != null and node.hp > 0.0 \
				and not node.stats.get("boss", false):
			return node
	return null


func _finish() -> void:
	print("GIFT TEST FAILED" if _failed else "GIFT TEST PASSED")
	quit(1 if _failed else 0)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _settle(seconds := 0.2) -> void:
	await create_timer(seconds).timeout


func _assert(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failed = true
