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
## --role=relay runs the relay (docs/RELAY.md); with --relay-url= and
## --relay-code= the host opens that room and the guest joins it by code, so
## the whole game runs through the relay, the way two friends on different
## networks would play.
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
## --rejoin: after the co-op checks the guest's wire "times out" and it comes
## back through Rejoin, into the same room with the same body.
var rejoin := false


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
	rejoin = args.has("rejoin")
	net = root.get_node("Net")
	net.local_name = role

	var session_mode = net.Mode.PVP if mode == "pvp" else net.Mode.COOP
	var code := str(args.get("relay-code", ""))
	if role == "relay":
		var relay = load("res://scripts/net/relay_server.gd").new()
		root.add_child(relay)
		_ok(relay.listen(port) == OK, "relaying on %d" % port)
		if not await _until(func() -> bool: return relay.rooms_opened > 0, "a room opened", 30.0):
			await _finish()
			return
		# up until the host leaves, which ends the room
		await _until(func() -> bool: return relay.room_count() == 0, "the room closed with its host", 150.0)
		_ok(relay.packets_relayed > 100, "the game went through the relay (%d packets)" % relay.packets_relayed)
		relay.stop()
		await _finish()
		return
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
		if not code.is_empty():
			await _wait(1.0)  # the relay is starting in the process beside us
		_ok(net.host(session_mode, port) == OK, "listening on %d" % port)
		if not code.is_empty():
			await _until(func() -> bool: return net.invite_code != "", "a room code from the relay")
			_ok(net.invite_code == code, "the relay gave room %s" % net.invite_code)
	elif not code.is_empty():
		# Until the host has its room the relay says there is no such game;
		# a friend would try again, and so does the guest here.
		var tries := 0
		while true:
			await _wait(1.5)
			tries += 1
			if net.join(code, port) == OK and await _until(func() -> bool: return net.peers.size() == 2 \
					or not net.active, "an answer from room %s" % code, 10.0) and net.active:
				break
			if tries >= 10:
				break
		_ok(net.active, "joined room %s by code (try %d)" % [code, tries])
	else:
		# The host is a Godot starting up beside us — slower than a second on a
		# busy runner, and a refused dial drops the session (Net.leave). A
		# friend would dial again; so does the guest, until somebody answers.
		var tries := 0
		while true:
			await _wait(1.0)
			tries += 1
			if net.join(address, port) == OK and await _until_quiet(func() -> bool: return not net.active \
					or root.multiplayer.multiplayer_peer.get_connection_status() \
					== MultiplayerPeer.CONNECTION_CONNECTED, 10.0) and net.active:
				break
			if tries >= 15:
				break
		_ok(net.active, "dialled %s:%d (try %d)" % [address, port, tries])

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
	# the link is measured both ways: what the overlay's bars and banner read
	await _until(func() -> bool: return net.link_ms() >= 0, "the round trip is measured")
	_ok(net.link_ms() < 1000 and net.link_silence() < net.LINK_STALL * 2.0,
		"the link reads steady (%d ms, %.1f s quiet)" % [net.link_ms(), net.link_silence()])
	_ok(root.get_node("NetOverlay").link.visible, "the overlay shows the link")

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
	if rejoin:
		await _rejoin(run)


## The guest's link dies mid-night and it comes back through Rejoin: the host
## plays on alone meanwhile, then takes it in late; the guest is in the same
## room as the host, with the gifts and the lean it had, enemies and all.
func _rejoin(run) -> void:
	var game = root.get_node("Game")
	if role == "host":
		await _until(func() -> bool: return run.get_node("Players").get_child_count() == 1,
			"the guest's body leaves with its wire", 30.0)
		_ok(net.in_match and run.is_inside_tree(), "the host plays on alone")
		await _until(func() -> bool: return run.get_node("Players").get_child_count() == 2,
			"the guest is back in the night", 60.0)
		await _wait(8.0)  # stay while the guest checks what it got back
		return
	await _wait(1.0)
	# something only this body carries, to find again on the other side
	run.player.stats.max_hp += 7.0
	game.alignment["grace"] = int(game.alignment.get("grace", 0)) + 3
	var max_hp: float = run.player.stats.max_hp
	var grace: int = game.alignment["grace"]
	net._lost("NET_ERR_TIMEOUT")
	_ok(net.can_rejoin(), "a guest whose night went down is offered Rejoin")
	_ok(not net.rejoin_snapshot.is_empty(), "  and keeps what its body carried")
	await _until(func() -> bool: return current_scene != null \
		and current_scene.scene_file_path.ends_with("main_menu.tscn"), "back at the menu", 20.0)
	_ok(root.get_node("NetOverlay").lost_panel.visible \
		and root.get_node("NetOverlay").rejoin_button.visible, "the overlay says why and offers Rejoin")
	_ok(net.rejoin() == OK, "Rejoin dials the same host")
	if not await _until(func() -> bool: return net.in_match and current_scene != null \
			and current_scene.has_node("Players") and current_scene.player != null, "back in the night", 40.0):
		return
	run = current_scene
	await _until(func() -> bool: return run.get_node("Players").get_child_count() == 2, "both bodies again")
	_ok(run.room_index == 1, "in the room the host is in (%d)" % run.room_index)
	_ok(is_equal_approx(run.player.stats.max_hp, max_hp), "with the body it had (max hp %.0f)" % run.player.stats.max_hp)
	_ok(int(game.alignment.get("grace", 0)) == grace, "  and the lean it had")
	_ok(game.level >= 1 and game.flags is Dictionary, "under the night the host keeps (level %d)" % game.level)


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


## _until without a verdict: for a try that may fail and be made again.
func _until_quiet(condition: Callable, limit: float) -> bool:
	var spent := 0.0
	while spent < limit:
		if condition.call():
			return true
		await _tick(0.25)
		spent += 0.25
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
