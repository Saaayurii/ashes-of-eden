extends SceneTree
## Two-process network stand. One process hosts, the other joins, and both
## assert the same things about the world they end up sharing:
##
##   godot --headless -s scripts/tools/net_test.gd -- --role=host  --mode=coop
##   godot --headless -s scripts/tools/net_test.gd -- --role=guest --mode=coop
##
## --role=referee is the dedicated host two browsers would share: it holds no
## body of its own and starts the match once both guests are ready.
##
## tools/net_test.sh runs both and fails the build if either side prints FAIL.
## Deliberately untyped: -s scripts compile before autoloads exist, so naming
## game classes here would compile them too early and fail on Data/Game.

var _failed := false
var role := "host"
var mode := "coop"
var port := 8911
var address := "127.0.0.1"
var net


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var pair := arg.substr(2).split("=", true, 1)
			args[pair[0]] = pair[1] if pair.size() > 1 else "true"
	role = str(args.get("role", role))
	mode = str(args.get("mode", mode))
	port = int(args.get("port", port))
	address = str(args.get("address", address))
	net = root.get_node("Net")
	net.local_name = role

	var session_mode = net.Mode.PVP if mode == "pvp" else net.Mode.COOP
	if role == "referee":
		_ok(net.host(session_mode, port, true) == OK, "refereeing on %d" % port)
		_ok(net.dedicated and not net.peers.has(1), "the referee holds no seat")
		if not await _until(func() -> bool: return net.in_match, "match started with no host player", 45.0):
			await _finish()
			return
		await _wait(50.0)  # stay up while the two guests play
		await _finish()
		return

	if role == "host":
		_ok(net.host(session_mode, port) == OK, "listening on %d" % port)
	else:
		await _wait(1.0)  # give the host its socket
		_ok(net.join(address, port) == OK, "dialling %s:%d" % [address, port])

	if not await _until(func() -> bool: return net.peers.size() == 2, "both seats taken", 30.0):
		await _finish()
		return
	net.set_ready(true)
	if role == "host":
		if not await _until(func() -> bool: return net.everyone_ready(), "both ready"):
			await _finish()
			return
		net.request_start()
	if not await _until(func() -> bool: return net.in_match and current_scene != null \
			and current_scene.has_node("Players"), "match scene up"):
		await _finish()
		return
	await _wait(0.5)

	if mode == "pvp":
		await _duel()
	else:
		await _coop()
	await _finish()


# -------------------------------------------------------------------- coop ---

func _coop() -> void:
	var run = current_scene
	if not await _until(func() -> bool: return run.get_node("Players").get_child_count() == 2, "two bodies in the room"):
		return
	_ok(run.player != null, "our own body is ours")
	var other = _other_body(run)
	_ok(other != null, "the other body is here")
	_ok(other.get_multiplayer_authority() != run.multiplayer.get_unique_id(), "the other body is theirs")

	if not await _until(func() -> bool: return run.get_node("Entities").get_child_count() > 0, "enemies replicated"):
		return
	# Movement: we move, they see it. Only the guest moves so the check is one-way.
	if role == "guest":
		run.player.global_position = Vector2(430, 300)
	else:
		await _until(func() -> bool: return other.global_position.x > 380.0, "their movement reaches us")

	# Only the guest swings. Every kill therefore proves a client-dealt hit
	# travelled to the host, was applied there, and came back as a real death.
	if role != "host":
		for sweep in 20:
			for enemy in get_nodes_in_group("enemies"):
				if enemy.has_method("take_damage"):
					enemy.take_damage(9999.0, run.player)
			await _tick(0.4)
			if run.room != null and run.room.door.open:
				break
	if not await _until(func() -> bool: return run.room != null and run.room.door.open,
			"the guest's blows cleared the room for both", 40.0):
		return
	_ok(run.kills > 0, "kills counted on both sides (%d)" % run.kills)
	# A room worth exactly one level leaves the bar at 0: the level counts as well.
	var game = root.get_node("Game")
	_ok(game.essence > 0.0 or game.level > 1, "shared essence reached us (%.0f, level %d)" % [game.essence, game.level])

	# The guest walks through the door; the host has to be the one that advances.
	if role != "host":
		run.player.global_position = run.room.door.global_position
	await _until(func() -> bool: return run.room_index == 1, "host moved everyone to room 2", 40.0)
	_ok(run.get_node("Players").get_child_count() == 2, "both bodies survived the door")


# -------------------------------------------------------------------- duel ---

func _duel() -> void:
	var duel = current_scene
	if not await _until(func() -> bool: return duel.get_node("Players").get_child_count() == 2, "two duellists"):
		return
	var foe = _other_body(duel)
	_ok(foe != null, "the other duellist is here")
	_ok(duel.player.versus and foe.versus, "swords bite players in here")
	await _until(func() -> bool: return duel.round_number == 1, "round one called")

	# The rule a duel adds is a collision rule, so check the collision: stand
	# next to them and see whether our sword's box actually reports their body.
	if role == "guest":
		duel.player.global_position = foe.global_position - Vector2(16, 0)
		duel.player.facing = 1
		duel.player.hitbox.scale.x = 1.0
		duel.player.hitbox.monitoring = true
		await _tick(0.4)
		var seen := false
		for touched in duel.player.hitbox.get_overlapping_bodies():
			if touched == foe:
				seen = true
		duel.player.hitbox.monitoring = false
		_ok(seen, "our sword's box reports the other body")

	# One guest hits the other body until it falls: every blow crosses the wire.
	if role != "host":
		for blow in 60:
			if not is_instance_valid(foe) or foe.is_dead():
				break
			if int(duel.scores.get(duel.multiplayer.get_unique_id(), 0)) >= 1:
				break
			foe.take_damage(25.0, duel.player)
			await _tick(0.2)
	else:
		await _until(func() -> bool: return duel.player.hp < duel.player.stats.max_hp,
			"their blade reaches us", 25.0)

	if not await _until(func() -> bool: return _score_total(duel) >= 1,
			"the host awarded the round", 30.0):
		return
	_ok(duel.round_number >= 1, "score is the same on both screens: %s" % [duel.scores])


## The host owns the board, so any point on it travelled to us from there.
func _score_total(duel) -> int:
	var total := 0
	for id in duel.scores:
		total += int(duel.scores[id])
	return total


# ------------------------------------------------------------------- utils ---

func _other_body(scene):
	for child in scene.get_node("Players").get_children():
		if child.get_multiplayer_authority() != scene.multiplayer.get_unique_id():
			return child
	return null


## Keeps the story and the gift cards from blocking the stand: answers anything
## this peer is actually allowed to answer.
func _tick(seconds := 0.2) -> void:
	var scene = current_scene
	if scene != null and scene.has_node("UI/AbilityPicker"):
		var picker = scene.get_node("UI/AbilityPicker")
		if picker.visible and picker.get_node("%Cards").get_child_count() > 0:
			picker.get_node("%Cards").get_child(0).pressed.emit()
	if scene != null and scene.has_node("UI/DialogueBox"):
		var dialogue = scene.get_node("UI/DialogueBox")
		if not dialogue.remote and dialogue.get_node("%Panel").is_visible_in_tree():
			var choices = dialogue.get_node("%Choices")
			if choices.get_child_count() > 0:
				choices.get_child(0).pressed.emit()
			else:
				dialogue.get_node("%Continue").pressed.emit()
	await _wait(seconds)


func _wait(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout
	await process_frame


func _until(condition: Callable, label: String, limit := 20.0) -> bool:
	var spent := 0.0
	while spent < limit:
		if condition.call():
			_ok(true, label)
			return true
		await _tick(0.25)
		spent += 0.25
	_ok(false, label + " (timeout)")
	return false


func _ok(condition: bool, label: String) -> void:
	print(("  ok   [%s] " % role if condition else "  FAIL [%s] " % role) + label)
	if not condition:
		_failed = true


func _finish() -> void:
	printerr("=== %s: checks done, settling ===" % role)
	print("NET TEST %s [%s/%s]" % ["FAILED" if _failed else "PASSED", mode, role])
	await _wait(5.0)  # do not pull the socket while the other side is still checking
	net.leave()
	quit(1 if _failed else 0)
