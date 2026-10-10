extends SceneTree
## Actual frame changes resolve damage once; interrupted attacks do not land.
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("ATTACK_FRAME_FAIL: " + label)

func _run() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	enemy.enemy_id = "possessed_villager"
	arena.add_child(enemy)
	enemy.set_physics_process(false)
	var player = load("res://scenes/player/player.tscn").instantiate()
	arena.add_child(player)
	player.set_physics_process(false)
	player.global_position = enemy.global_position + Vector2(20, 0)
	var before: float = player.hp
	enemy._attack = enemy._attacks[2].duplicate(true)
	_check(enemy._attack.get("impact_fx") == "dust" and enemy._attack.get("telegraph_fx") == "none", "dust preset has no magic telegraph")
	enemy._begin_windup(Vector2.RIGHT)
	_check(enemy.sprite.frame == 0 and not enemy.sprite.is_playing(), "windup holds the first frame")
	_check(enemy._telegraph_tween == null, "dust windup creates no glow tween")
	enemy._strike(Vector2.RIGHT)
	enemy.sprite.pause()
	_check(not enemy.sprite.sprite_frames.get_animation_loop("special"), "timed special does not loop and emit another impact")
	_check(player.hp == before and enemy._strike_wait, "no early damage at animation start")
	await create_timer(0.15).timeout
	_check(player.hp == before, "waiting on a paused sprite does not cause timer damage")
	enemy.sprite.frame = 1
	_check(player.hp < before and not enemy._strike_wait, "damage lands on second frame")
	var after: float = player.hp
	enemy.sprite.frame = 2
	enemy.sprite.frame = 0
	enemy.sprite.frame = 1
	_check(player.hp == after, "later frames and loops cannot resolve another hit")
	enemy._strike(Vector2.RIGHT)
	enemy.sprite.pause()
	enemy._set_state(enemy.State.RECOVER, 0.2)
	enemy.sprite.frame = 1
	_check(not enemy._strike_wait and player.hp == after, "interruption cancels pending hit")
	# The animation signal, rather than manually advanced frames, follows fps.
	enemy.sprite.sprite_frames.set_animation_speed("special", 3.0)
	enemy._strike(Vector2.RIGHT)
	await create_timer(0.15).timeout
	_check(enemy._strike_wait, "a slower animation waits longer")
	await create_timer(0.25).timeout
	_check(not enemy._strike_wait, "a playing sprite resolves when the actual frame arrives")
	enemy._attack.hit_frame = 99
	enemy._strike(Vector2.RIGHT)
	enemy.sprite.pause()
	_check(enemy._strike_frame == enemy.sprite.sprite_frames.get_frame_count("special") - 1, "shorter live strips clamp the hit frame")
	enemy.sprite.frame = enemy._strike_frame
	_check(not enemy._strike_wait, "a live strip cannot leave an attack waiting forever")
	current_scene = null
	arena.queue_free()
	await process_frame
	print("ENEMY_ATTACK_FRAME_TEST %s" % ("PASSED" if failures == 0 else "FAILED"))
	quit(0 if failures == 0 else 1)
