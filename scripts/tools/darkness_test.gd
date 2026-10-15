extends SceneTree
## Bought light (docs/CHAPTER4.md §2, §9, scripts/rooms/darkness.gd, lamp.gd),
## in the counting house of Tyre (dark 0.6, three lamps for sale):
##   - the room sinks its night by its "dark", play reads the same depth with
##     the lights off, and the yard is never dark;
##   - every body carries a lantern; Zacchaeus's light widens it;
##   - a lamp is bought with essence (× the night's lamp_price), is kept in
##     Game.lamps_lit, and a poor body cannot buy it;
##   - a wind-up lights itself (≥ 48 px, from 0.3 up) and its light goes with
##     the blow; in a lit room it adds nothing;
##   - a body outside the light shows two pixels of eyes;
##   - dark-adapted bodies are quicker in the dark and will not step into a lamp;
##   - a cutpurse's blow takes essence and its death gives it back;
##   - the Prince's douse puts every lamp out and sells them again dearer.
##   godot --headless --path . -s scripts/tools/darkness_test.gd

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


func _run() -> void:
	var game = root.get_node("Game")
	var settings = root.get_node("Settings")
	var had_sold: bool = game.flags.has("zacchaeus_sold")
	game.flags.erase("zacchaeus_sold")
	var had_night: String = game.night
	game.night = "tyre"

	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.5)
	var run = current_scene
	run.transition.instant = true
	var player = run.player
	run._load_room(run.ROOMS.find("res://scenes/rooms/tyre_counting_house.tscn"))
	await _settle(0.4)
	run.cutscene.abort()
	game.cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	paused = false
	await _frames(4)
	var room = run.room
	for body in get_nodes_in_group("enemies"):
		body.queue_free()
	await _frames(2)

	# --- the dark itself
	var dark = room.get_node_or_null("Darkness")
	_check(dark != null, "the counting house has its Darkness node")
	if dark == null:
		quit(1)
		return
	var darkness_class = dark.get_script()
	_check(is_equal_approx(dark.dark, 0.6), "its table's dark is 0.6 (%.2f)" % dark.dark)
	_check(is_equal_approx(darkness_class.depth(self), 0.6), "play reads a depth of 0.6")
	await _settle(1.0)
	var ambient = room.get_node_or_null("Ambient")
	var shown: float = dark.shown()
	if settings.lighting:
		_check(shown > 0.5, "the night has sunk toward black (%.2f shown)" % shown)
		_check(ambient == null or ambient.color.v < 0.6, "the room's Ambient is darker (%s)" % [ambient.color if ambient else "none"])
	var had_lighting: bool = settings.lighting
	settings.lighting = false
	_check(dark._target() == 0.0, "with the lights off nothing is drawn darker")
	_check(is_equal_approx(darkness_class.depth(self), 0.6), "but play still reads 0.6")
	settings.lighting = had_lighting
	game.practice = "training_dummy"
	_check(darkness_class.depth(self) == 0.0, "the yard is never dark")
	game.practice = ""

	# --- the lantern
	await _frames(2)
	var lantern = player.get_node_or_null("DarkLantern")
	_check(lantern != null, "the hero carries a lantern here")
	_check(is_equal_approx(darkness_class.lantern_radius(player), darkness_class.HERO_LANTERN),
		"of %d px" % darkness_class.HERO_LANTERN)
	game.flags["zacchaeus_sold"] = true
	_check(is_equal_approx(darkness_class.lantern_radius(player), darkness_class.HERO_LANTERN + darkness_class.BOUGHT_LANTERN),
		"Zacchaeus's light widens it to %d" % (darkness_class.HERO_LANTERN + darkness_class.BOUGHT_LANTERN))
	game.flags.erase("zacchaeus_sold")

	# --- lamps
	var lamps: Array = get_nodes_in_group("lamps")
	_check(lamps.size() == 3, "three lamps for sale (%d)" % lamps.size())
	var lamp = lamps[0]
	_check(not lamp.lit, "a lamp starts cold")
	var at: Vector2 = lamp.get_parent().global_position + Vector2(0, -30)
	_check(not darkness_class.lit_at(self, at, null, true), "no bought light where it stands")
	game.essence = 0.0
	_check(lamp.payment(player) == "", "a poor body cannot pay")
	_check(not lamp.buy(player), "and does not light it")
	var cost: int = lamp.cost()
	_check(cost == 20, "it costs its price (%d)" % cost)
	game.essence = 50.0
	_check(lamp.buy(player), "bought with essence")
	_check(lamp.lit and is_equal_approx(game.essence, 50.0 - cost), "lit, and the bar paid (%.0f left)" % game.essence)
	_check(game.lamps_lit.has(lamp.key()), "kept in Game.lamps_lit as %s" % lamp.key())
	await _settle(0.5)
	_check(darkness_class.lit_at(self, at, null, true), "its light counts as light")
	var saves = root.get_node("Saves")
	var state: Dictionary = saves.capture(room.scene_file_path, 0, 0.0, player)
	_check(var_to_str(state).find(lamp.key()) >= 0, "a checkpoint keeps the lamps lit")
	_check(not lamp.buy(player) and is_equal_approx(game.essence, 50.0 - cost), "a lit lamp is not sold twice")

	# --- the other ways to pay
	var other = lamps[1]
	game.essence = 7.0
	player.stats["mite"] = 1.0
	_check(other.payment(player) == "mite", "the widow's mite: too poor, but it pays all there is")
	_check(other.buy(player) and other.lit and game.essence == 0.0, "and lights it with the 7 there were")
	player.stats["mite"] = 0.0
	var third = lamps[2]
	var max_hp: float = player.stats.max_hp
	game.essence = 100.0
	player.stats["lamp_blood"] = 0.1
	_check(third.payment(player) == "blood", "a body that pays in blood")
	third.buy(player)
	_check(third.lit and is_equal_approx(game.essence, 100.0) and player.stats.max_hp < max_hp,
		"pays no essence and loses %.0f of its health" % (max_hp - player.stats.max_hp))
	player.stats["lamp_blood"] = 0.0
	player.stats.max_hp = max_hp

	# --- free_if: burns for nothing once the story set it
	var data = root.get_node("Data")
	game.flags["zacchaeus_down"] = true
	var hook = load("res://scenes/props/prop.tscn").instantiate()
	hook.prop_id = "tyre_lamp_hook"
	room.add_child(hook)
	hook.global_position = player.global_position + Vector2(-400, 0)
	await _frames(2)
	var hook_lamp = hook.get_node_or_null("Lamp")
	_check(hook_lamp != null and hook_lamp.lit, "a hook lamp burns from the start when Zacchaeus came down")
	_check(is_equal_approx(game.essence, 100.0), "for nothing")
	game.flags.erase("zacchaeus_down")
	hook.queue_free()

	# --- an omen's lamp_price and dark
	data.omens["test_dear_light"] = {"id": "test_dear_light", "rules": {"lamp_price": 1.5, "dark": 1.25}}
	var had_omen: String = game.omen
	game.omen = "test_dear_light"
	var fresh = load("res://scenes/props/prop.tscn").instantiate()
	fresh.prop_id = "tyre_lamp"
	room.add_child(fresh)
	fresh.global_position = player.global_position + Vector2(-500, 0)
	await _frames(2)
	_check(fresh.get_node("Lamp").cost() == 30, "an omen's lamp_price makes a lamp of 20 cost 30 (%d)" % fresh.get_node("Lamp").cost())
	_check(is_equal_approx(darkness_class.depth(self), 0.75), "and its dark deepens the room to 0.75 (%.2f)" % darkness_class.depth(self))
	game.omen = had_omen
	data.omens.erase("test_dear_light")
	fresh.queue_free()

	# --- dark_sight thins what we see, not what play reads
	player.stats["dark_sight"] = 0.2
	_check(not settings.lighting or is_equal_approx(dark._target(), 0.4), "dark_sight 0.2 shows a room of 0.6 as 0.4")
	player.stats["dark_sight"] = 0.0

	# --- wind-ups light themselves
	var guard = room.spawn_enemy("tyre_guard", player.global_position + Vector2(200, 0))
	await _frames(4)
	var far: Vector2 = guard.global_position
	darkness_class.telegraph(guard, 0.8)
	await _frames(2)
	var windup = guard.get_node_or_null("WindupLight")
	_check(windup != null and windup.radius >= 48.0, "a wind-up lights itself (%s px)" % [windup.radius if windup else "none"])
	_check(windup != null and windup.energy >= 0.25, "from the first frame (%.2f)" % [windup.energy if windup else 0.0])
	_check(darkness_class.lit_at(self, far), "the body winding up stands in light")
	darkness_class.clear_telegraph(guard)
	await _frames(2)
	_check(guard.get_node_or_null("WindupLight") == null or guard.get_node("WindupLight").is_queued_for_deletion(),
		"the blow takes the light with it")

	# --- every attack of every enemy of the chapter lights itself, and is as long as in the light
	var unlit := Vector2.INF
	for x in range(40, int(room.width) - 40, 20):
		var spot := Vector2(x, player.global_position.y)
		if not darkness_class.lit_at(self, spot) and not darkness_class.lit_at(self, spot + Vector2(0, -20)):
			unlit = spot
			break
	_check(unlit != Vector2.INF, "somewhere in the counting house is dark")
	for id in ["tyre_guard", "cutpurse", "debt_wraith", "dim_star", "woe_eagle", "dye_drowned", "tyre_treasurer", "prince_of_tyre"]:
		var body = room.spawn_enemy(id, unlit)
		await _frames(2)
		var all_lit := true
		var all_long := true
		for attack in body._attacks:
			body.global_position = unlit
			body._attack = attack
			body._begin_windup(Vector2(1, 0))
			all_long = all_long and is_equal_approx(body._state_left, float(attack.get("windup", 0.5)))
			all_lit = all_lit and darkness_class.lit_at(self, body.global_position)
			darkness_class.clear_telegraph(body)
			await _frames(1)
		_check(all_lit, "%s: every wind-up lights itself where it is dark" % id)
		_check(all_long, "%s: and none is shorter than its JSON" % id)
		body.queue_free()
		await _frames(1)

	# --- eyes in the dark
	guard.global_position = lamp.get_parent().global_position + Vector2(600, 0)
	await _settle(0.3)
	var eyes = guard.get_node_or_null("DarkEyes")
	if settings.lighting and not darkness_class.lit_at(self, guard.global_position, guard):
		_check(eyes != null and eyes.visible, "a body outside the light shows its eyes")
	_check(eyes == null or eyes.get_child_count() >= 2, "two pixels of them")

	# --- dark-adapted
	var enemy_dark = load("res://scripts/enemies/enemy_dark.gd")
	var thief = room.spawn_enemy("cutpurse", player.global_position + Vector2(300, 0))
	await _frames(4)
	_check(is_equal_approx(enemy_dark.speed_factor(thief), enemy_dark.ADAPTED_SPEED), "a cutpurse is quicker in the dark")
	_check(is_equal_approx(enemy_dark.speed_factor(guard), 1.0), "a guard is not")
	var lamp_at: Vector2 = lamp.get_parent().global_position + Vector2(0, -30)
	thief.global_position = lamp_at + Vector2(90, 0)
	var step: Vector2 = enemy_dark.keep_out_of_light(thief, Vector2(-80, 0), 1.0 / 60.0)
	_check(step.x == 0.0, "and will not step into a lamp's light (%s)" % step)
	step = enemy_dark.keep_out_of_light(thief, Vector2(80, 0), 1.0 / 60.0)
	_check(step.x > 0.0, "but may step out of it")

	# --- the cutpurse's cut
	game.essence = 30.0
	enemy_dark.steal(thief, player)
	_check(is_equal_approx(game.essence, 27.0), "a cutpurse's blow takes 3 essence (%.1f left)" % game.essence)
	var before: float = game.essence
	enemy_dark.give_back(thief)
	_check(game.essence > before + 2.5, "its death gives it back (%.1f)" % game.essence)

	# --- the douse
	dark.douse_all(0.85, 2.0)
	await _frames(2)
	_check(not lamp.lit and not game.lamps_lit.has(lamp.key()), "the douse puts a bought lamp out")
	_check(is_equal_approx(dark.dark, 0.85), "and the room sinks to 0.85")
	_check(lamp.for_sale() and lamp.cost() == 40, "it sells again at twice the price (%d)" % lamp.cost())
	game.essence = 100.0
	_check(lamp.buy(player) and lamp.lit, "and can be bought again")
	_check(is_equal_approx(game.essence, 60.0), "for 40 (%.0f left)" % game.essence)

	# --- a lit room: no darkness, the wind-up adds nothing
	dark.remove_from_group("darkness")
	darkness_class.telegraph(guard, 0.8)
	_check(guard.get_node_or_null("WindupLight") == null, "in a lit room a wind-up adds no light")
	dark.add_to_group("darkness")

	# --- the playtest log hears a lamp, the probe counts it among the trades
	var probe = load("res://scripts/tools/balance_probe.gd")
	DirAccess.make_dir_recursive_absolute("user://playtest_tools")
	var log_path := "user://playtest_tools/lamps.jsonl"
	var file := FileAccess.open(log_path, FileAccess.WRITE)
	file.store_string('{"e":"lamp","price":20,"how":"essence"}\n{"e":"lamp","price":40,"how":"blood"}\n{"e":"lamp","price":10,"how":"mite"}\n{"e":"run_end","won":true}\n')
	file = null
	var rows := "\n".join(probe.trade_rows([log_path]))
	_check(rows.contains("| lamp bought | 2 | 1 | 1 |") and rows.contains("| lamp in blood | 1 | 1 | 1 |"),
		"the probe counts lamps bought and lamps paid in blood:\n%s" % rows)
	DirAccess.remove_absolute(log_path)

	# --- the lamps lit survive a load
	game.lamps_lit = {"tyre_counting_house:Prop2": true}
	var snapshot: Dictionary = saves.capture(room.scene_file_path, 0, 0.0, player)
	game.lamps_lit = {}
	saves.restore(snapshot, player)
	_check(game.lamps_lit.has("tyre_counting_house:Prop2"), "Game.lamps_lit comes back with a loaded checkpoint")

	game.lamps_lit = {}
	game.night = had_night
	root.get_node("Data").use_night(had_night)
	if had_sold:
		game.flags["zacchaeus_sold"] = true
	print("darkness_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)
