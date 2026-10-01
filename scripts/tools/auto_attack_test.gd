extends SceneTree
## The assist swing (Settings.auto_attack, Player._auto_swing):
##   - off, the sword waits for the button;
##   - on, it swings at an awake enemy within reach, turning to one behind;
##   - never at a sleeper (the backstab stays the player's), never out of reach;
##   - the settings menu offers it, and it is saved.
## Puts the setting back through its setter.
##   godot --headless --path . -s scripts/tools/auto_attack_test.gd

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


func _foe(run, hero, dx: float, aware: bool):
	var foe = run._spawn_enemy("cultist", hero.global_position + Vector2(dx, -4), aware)
	await physics_frame
	foe.set_physics_process(false)  # stands where it is put
	foe.global_position = hero.global_position + Vector2(dx, -4)
	foe.stats.hp = 100000.0
	foe.set("_max_hp", 100000.0)
	foe.hp = 100000.0
	if aware:
		foe.aware = true
	return foe


func _run() -> void:
	var settings = root.get_node("Settings")
	var was: bool = settings.auto_attack
	settings.set_auto_attack(false)

	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.8)
	var run = current_scene
	run.transition.instant = true
	run._load_room(1)
	await _settle(0.4)
	run.cutscene.abort()
	root.get_node("Game").cutscene = false
	if run.dialogue.visible:
		run.dialogue.call("_on_skip")
	for body in get_nodes_in_group("enemies"):
		body.queue_free()
	await _settle(0.3)
	var hero = run.player
	hero.facing = 1

	var foe = await _foe(run, hero, 30.0, true)
	await _settle(1.0)
	_check(foe.hp == 100000.0, "off: the sword waits for the button")
	settings.set_auto_attack(true)
	await _settle(1.2)
	_check(foe.hp < 100000.0, "on: it swings at an awake one in reach")
	foe.queue_free()
	await _settle(0.8)

	var behind = await _foe(run, hero, -30.0, true)
	await _settle(1.2)
	_check(behind.hp < 100000.0 and hero.facing == -1, "it turns to one behind")
	behind.queue_free()
	await _settle(0.8)

	var sleeper = await _foe(run, hero, 30.0, false)
	await _settle(1.2)
	_check(sleeper.hp == 100000.0, "never at a sleeper: the backstab stays a choice")
	sleeper.queue_free()
	var far = await _foe(run, hero, 120.0, true)
	await _settle(1.0)
	_check(far.hp == 100000.0, "never out of reach")
	far.queue_free()

	var menu = run.get_node("UI/PauseMenu/Settings")
	menu._refresh()
	_check(menu.find_child("AutoAttackRow", true, false) != null and menu._auto_attack.button_pressed,
		"the settings offer it, switched on")
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	_check(bool(cfg.get_value("access", "auto_attack", false)), "and keep it")

	settings.set_auto_attack(was)
	current_scene = null
	run.queue_free()
	await _settle(0.2)
	print("AUTO ATTACK TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
