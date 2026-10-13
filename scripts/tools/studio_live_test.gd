extends SceneTree
## The studio's sandbox (StudioLive, `--studio-live`): what the studio posts —
## strips as base64 PNG, a cell, the enemy it fights like — becomes the foe in
## the practice yard, built through the same Enemy._setup_sprite as a file:
##   - only `--studio-live` asks for it;
##   - a post makes a creature on its base, with her strips and none of the base's;
##   - the yard's foe is swapped for it, and swapped again on the next post;
##   - a strip that is not whole cells is left out, a post without idle is refused.
##   godot --headless --path . -s scripts/tools/studio_live_test.gd

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


func _foes() -> Array:
	return get_nodes_in_group("enemies").filter(func(e) -> bool: return not e.is_dead())


## A strip of `frames` cells, each a different colour, as the studio sends it.
func _strip(cell: Vector2i, frames: int) -> String:
	var picture := Image.create(cell.x * frames, cell.y, false, Image.FORMAT_RGBA8)
	for i in frames:
		picture.fill_rect(Rect2i(i * cell.x + 8, 4, cell.x - 16, cell.y - 5), Color.from_hsv(i / float(frames), 0.6, 0.7))
	return "data:image/png;base64," + Marshalls.raw_to_base64(picture.save_png_to_buffer())


func _run() -> void:
	var action_fx = load("res://scripts/fx/action_fx.gd")
	var projectile_script = load("res://scripts/fx/projectile.gd")
	var player_script = load("res://scripts/player/player.gd")
	var enemy_script = load("res://scripts/enemies/enemy.gd")
	var game = root.get_node("Game")
	var data = root.get_node("Data")
	var live_script = load("res://scripts/run/studio_live.gd")
	_check(live_script.requested(PackedStringArray(["--studio-live"])), "--studio-live asks for the sandbox")
	_check(not live_script.requested(PackedStringArray(["--studio-preview", "practice=cultist"])), "nothing else does")

	game.practice = live_script.WAITING_FOR
	change_scene_to_file("res://scenes/run/run.tscn")
	await _settle(0.8)
	var run = current_scene
	run.transition.instant = true
	run._start_studio_live()
	await _settle(0.4)
	_check(run.room_index == run.PRACTICE_INDEX, "the sandbox is the practice yard")
	_check(_foes().size() == 1 and _foes()[0].enemy_id == "training_dummy", "with the straw man until the studio posts")

	var cell := Vector2i(32, 40)
	var spec: Dictionary = run.studio_live.apply({
		"type": "ashes-live", "name": "Лучница", "extends": "cultist", "cell": [cell.x, cell.y], "fps": 7,
		"strips": {"idle": _strip(cell, 2), "walk": _strip(cell, 3), "attack": _strip(Vector2i(30, 40), 4)},
	})
	_check(not spec.is_empty() and data.enemies.has(live_script.ID), "a post becomes a creature in Data")
	_check(spec.get("hp") == data.enemies.cultist.get("hp") and spec.get("behaviour") == data.enemies.cultist.get("behaviour") and spec.get("attacks") == data.enemies.cultist.get("attacks"), "that fights like the one it extends")
	_check(spec.get("name") == "Лучница", "under the name she gave it")
	_check(spec.sprite.animations.keys().size() == 2 and not spec.sprite.animations.has("attack"),
		"a strip that is not whole cells is left out, the base's strips are not borrowed")
	await _settle(0.4)
	var foes := _foes()
	_check(foes.size() == 1 and foes[0].enemy_id == live_script.ID, "the yard's foe is hers now")
	if foes.size() == 1:
		var frames: SpriteFrames = foes[0].sprite.sprite_frames
		_check(frames.get_frame_count("idle") == 2 and frames.get_frame_count("walk") == 3, "its frames are her strips")
		_check(frames.get_frame_texture("idle", 0).get_size() == Vector2(cell), "cut at her cell")

	run.studio_live.apply({"type": "ashes-live", "extends": "cultist", "cell": [cell.x, cell.y], "strips": {"idle": _strip(cell, 4)}})
	await _settle(0.4)
	foes = _foes()
	_check(foes.size() == 1 and foes[0].sprite.sprite_frames.get_frame_count("idle") == 4, "the next post swaps it again")
	_check(run.studio_live.apply({"type": "ashes-live", "cell": [32, 40], "strips": {"walk": _strip(cell, 2)}}).is_empty(),
		"a post without an idle strip is refused")
	_check(live_script.build_spec({"extends": "ophanim", "cell": [32, 40], "strips": {"idle": _strip(cell, 1)}}).get("hp") == data.enemies.cultist.get("hp"),
		"a boss is no base: it falls back to the cultist")

	# how the sandbox shows it: one animation on the spot, slowed down, three of them
	run.studio_live.apply({"type": "ashes-live", "extends": "cultist", "cell": [cell.x, cell.y],
		"strips": {"idle": _strip(cell, 2), "walk": _strip(cell, 3)}})
	await _settle(0.3)
	run.studio_live.set_view({"anim": "walk", "speed": 0.5, "count": 3})
	await _settle(0.4)
	foes = _foes()
	_check(foes.size() == 3 and foes.all(func(e) -> bool: return e.enemy_id == live_script.ID), "three of them side by side")
	_check(foes.all(func(e) -> bool: return e.showcase == "walk" and e.sprite.animation == "walk"), "each standing and playing its walk")
	_check(is_equal_approx(root.get_node("Juice").base_scale, 0.5), "the game at half speed")
	var at: float = foes[0].global_position.x if foes.size() > 0 else 0.0
	await _settle(0.5)
	_check(foes.size() > 0 and absf(foes[0].global_position.x - at) < 1.0, "on the spot, not walking off")
	run.studio_live.set_view({"anim": "", "speed": 9, "count": 0})
	await _settle(0.4)
	foes = _foes()
	_check(foes.size() == 1 and foes[0].showcase == "", "back to one, fighting")
	_check(is_equal_approx(root.get_node("Juice").base_scale, 1.0), "at full speed (speed is clamped)")

	# Data-only posts preserve the real art and apply gameplay/FX immediately.
	var draft_attack := {"type": "nova", "animation": "special", "range": 95, "radius": 72,
		"windup": 0.4, "damage": 12, "cooldown": 4, "hit_frame": 1, "telegraph_fx": "none", "impact_fx": "dust"}
	var dust := {"special": [{"fx": "dust", "at": "feet", "when": "frames", "frames": [1]}]}
	run.studio_live.apply({"type": "ashes-live", "mode": "data", "extends": "possessed_villager",
		"spec": {"hp": 123, "attacks": [draft_attack]}, "bodies": {"studio_live": dust},
		"styles": {"test": {"light": 31}}, "player_actions": {"cleave": {"multiplier": 5}},
		"abilities": {"studio_test": {"id": "studio_test"}},
		"hero": {"stats": {"speed": 222.0}, "feel": {"parry_window": 0.4}}})
	await _settle(0.4)
	foes = _foes()
	_check(foes.size() == 1 and foes[0].stats.hp == 123 and foes[0]._attacks[0].damage == 12, "live drafts replace enemy stats and damage")
	_check(foes[0].sprite.sprite_frames.has_animation("special"), "data-only posts keep original sprite strips")
	_check(action_fx.rules("studio_live") == dust and projectile_script.style("test").light == 31, "particle and projectile drafts reach the engine")
	_check(player_script.action_spec("cleave").multiplier == 5 and data.abilities.has("studio_test"), "hero action and gift drafts reach the engine")
	var heroes := root.get_tree().get_nodes_in_group("player")
	_check(is_equal_approx(player_script.PARRY_WINDOW, 0.4) and not heroes.is_empty() and is_equal_approx(float(heroes[0].stats.speed), 222.0),
		"a hero draft reaches the class and the body in the yard")
	player_script.apply_hero(data.hero)
	run._studio_live_control({"command": "force", "attack": 0, "distance": 50, "debug": true})
	_check(foes[0].state == enemy_script.State.WINDUP and foes[0]._attack.damage == 12, "force uses the selected real attack and its windup")
	await _settle(0.1)
	var left: float = foes[0]._state_left
	run._studio_live_control({"command": "pause", "paused": true})
	await _settle(0.15)
	_check(is_equal_approx(foes[0]._state_left, left), "pause freezes real attack timing")
	run._studio_live_control({"command": "step"})
	await _settle(0.1)
	_check(paused and foes[0]._state_left < left, "step advances physics and pauses again")
	run._studio_live_control({"command": "pause", "paused": false})
	await _settle(0.6)
	_check(foes[0].state != enemy_script.State.WINDUP and not foes[0]._strike_wait, "the selected sprite frame resolves the live impact")
	# a gift from the studio: a skill goes into his hands and is cast at once, any other gift is taken once
	var hero = run.player
	run._studio_live_control({"command": "gift", "gift": "radiance", "debug": true})
	_check(hero.skill.get("kind", "") == "nova" and hero._skill_cd > 0.0, "a gift's skill is handed over and cast")
	data.abilities["studio_stat"] = {"id": "studio_stat", "name": "ABILITY_RADIANCE_NAME", "description": "ABILITY_RADIANCE_DESC", "path": "grace", "rarity": "common", "effects": [{"type": "stat", "stat": "max_hp", "op": "add", "value": 10}]}
	var max_hp: float = hero.stats.max_hp
	run._studio_live_control({"command": "gift", "gift": "studio_stat", "debug": true})
	run._studio_live_control({"command": "gift", "gift": "studio_stat", "debug": true})
	_check(is_equal_approx(hero.stats.max_hp, max_hp + 10.0), "a gift pressed twice is taken once")
	run._studio_live_control({"command": "gift", "gift": "no_such_gift", "debug": true})
	_check(hero.skill.get("kind", "") == "nova", "an unknown gift changes nothing")
	game.practice = ""
	print("studio_live_test: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)
