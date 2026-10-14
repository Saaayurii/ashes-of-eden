extends SceneTree
## Opt-in telemetry (scripts/autoload/telemetry.gd, docs/PLAYTEST.md): with no
## server or no yes nothing is recorded or sent; with both, a night's Playtest
## events become one record, records go out in batches to a server (a tiny one
## here, on a TCPServer), a dead, wrong or failing server only keeps them for
## later, the practice yard sends nothing, a night of the day says which try it
## was, a no forgets the queue — and the player's settings are put back.
##   godot --headless --path . -s scripts/tools/telemetry_test.gd

var failures := 0
var _server := TCPServer.new()
var _peers: Array = []  # [StreamPeerTCP, PackedByteArray so far]
var bodies: Array = []  # parsed JSON of every POST received
var answer_code := 200


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _run() -> void:
	var settings = root.get_node("Settings")
	var telemetry = root.get_node("Telemetry")
	var playtest = root.get_node("Playtest")
	var game = root.get_node("Game")
	var bus = root.get_node("EventBus")
	var was_on: bool = settings.telemetry
	var was_asked: bool = settings.telemetry_asked
	var was_daily: String = game.daily
	var was_practice: String = game.practice

	telemetry.allow_in_tools = true
	telemetry.reset_for_tools()
	_check(_server.listen(0, "127.0.0.1") == OK, "a test server listens")
	var url := "http://127.0.0.1:%d/collect" % _server.get_local_port()

	# --- no server: nothing is asked, recorded or sent
	telemetry.url_override = ""
	_check(str(ProjectSettings.get_setting("ashes/telemetry/url", "")) == "", "the repository ships with no server")
	_check(not telemetry.can_ask(), "no server: the player is never asked")
	settings.set_telemetry(true)
	_night(telemetry, false)
	_check(telemetry.queue.is_empty(), "no server: a night is not even recorded")

	# --- a server, but the player said no
	telemetry.url_override = url
	_check(telemetry.can_ask(), "a server: the question may be asked")
	settings.set_telemetry(false)
	_night(telemetry, false)
	_check(telemetry.queue.is_empty() and not telemetry.flush(), "a no: nothing queued, nothing sent")
	await _pump(20)
	_check(bodies.is_empty(), "a no: the server heard nothing")

	# --- a yes: nights become records, sent in batches
	settings.set_telemetry(true)
	for i in 12:
		_night(telemetry, i == 0)
	_check(telemetry.queue.size() == 12, "a yes: twelve nights, twelve records waiting")
	await _until(func() -> bool: return telemetry.queue.is_empty(), 300)
	_check(telemetry.queue.is_empty(), "every record went out")
	_check(bodies.size() == 2, "in batches of ten: two requests (%d)" % bodies.size())
	var records: Array = []
	for body in bodies:
		records.append_array(body.get("records", []))
	_check(records.size() == 12, "the server got all twelve")
	var first: Dictionary = records[0] if not records.is_empty() else {}
	var install: String = telemetry.install_id()
	_check(install.length() == 24 and str(first.get("install", "")) == install, "a random install id, the same on every record")
	var ids := {}
	for r in records:
		ids[str(r.get("id", ""))] = true
	_check(ids.size() == 12, "every record its own id, so a resend counts once")
	var kinds: Array = first.get("events", []).map(func(e: Dictionary) -> String: return str(e.get("e", "")))
	_check(not kinds.has("hurt") and kinds.has("room_clear") and kinds.has("run_end"), "the night's events, without the flood of hurts")
	var summary: Dictionary = first.get("summary", {})
	_check(summary.get("rooms") == 3 and summary.get("by") == "possessed" and bool(summary.get("died")),
		"the summary: rooms reached and what laid him low")
	_check(is_equal_approx(float(summary.get("first_gift_t", -1)), 40.0), "the summary: when the first gift came")
	_check(summary.get("skipped", []) == ["ch1_stranger"], "the summary: the dialogue skipped")
	_check(summary.get("gifts", []) == ["vampirism"] and str(summary.get("omen", "x")) == "", "the summary: gifts, omen")
	for key in ["version", "platform", "nights", "daily", "seconds", "won"]:
		_check(first.has(key), "a record says %s" % key)
	var text := JSON.stringify(records)
	for word in ["user://", OS.get_environment("USER"), OS.get_environment("HOME")]:
		if word != "":
			_check(not text.contains(word), "nothing personal in a record (%s)" % word)

	# --- through Playtest, as in play: the yard is not a night
	var before: int = telemetry.queue.size()
	var was_active: bool = playtest._active
	playtest._active = true
	game.practice = "training_dummy"
	playtest._write("run_start", {"version": "t"})
	playtest._write("run_end", {"won": false, "seconds": 1.0, "level": 1, "gifts": 0, "alignment": {}, "omen": "", "vial": 0})
	_check(telemetry.queue.size() == before, "the practice yard sends nothing")
	game.practice = ""
	playtest._write("run_start", {"version": "t"})
	playtest._write("run_end", {"won": false, "seconds": 1.0, "level": 1, "gifts": 0, "alignment": {}, "omen": "", "vial": 0})
	playtest._active = was_active
	_check(telemetry.queue.size() == before + 1, "a night through Playtest is recorded")
	await _until(func() -> bool: return telemetry.queue.is_empty(), 200)

	# --- the night of the day: which try it was
	game.daily = "2026-10-14"
	_night(telemetry, false)
	_night(telemetry, false)
	game.daily = was_daily
	var tries: Array = telemetry.queue.map(func(r: Dictionary) -> int: return int(r.get("daily_try", 0)))
	_check(tries == [1, 2], "a second daily try says so (%s)" % str(tries))
	bus.night_retried.emit()
	_check(telemetry.queue.size() == 3 and str(telemetry.queue[2].get("kind", "")) == "retry", "Again after a death is a record of its own")
	await _until(func() -> bool: return telemetry.queue.is_empty(), 200)

	# --- a failing server keeps the records and waits longer
	answer_code = 500
	var sent_before: int = telemetry.sent
	_night(telemetry, false)
	await _until(func() -> bool: return telemetry.failures > 0, 200)
	_check(telemetry.failures == 1 and telemetry.queue.size() == 1 and telemetry.sent == sent_before,
		"a 500: kept, one failure")
	_check(telemetry._wait >= telemetry.RETRY_SECONDS - 1.0, "and the next try waits")
	answer_code = 200

	# --- a dead server and a nonsense address are harmless
	telemetry.url_override = "http://127.0.0.1:1/collect"
	telemetry._wait = 0.0
	await _until(func() -> bool: return telemetry.failures > 1, 600)
	_check(telemetry.failures >= 2 and telemetry.queue.size() == 1, "nobody listening: kept, the game goes on")
	telemetry.url_override = "not a url at all"
	var started := Time.get_ticks_msec()
	telemetry._in_flight = []
	_check(telemetry.endpoint() == "" and not telemetry.flush(), "a nonsense address is no server: nothing sent")
	_check(Time.get_ticks_msec() - started < 100, "and nothing waited on it")
	_check(telemetry.queue.size() == 1 and telemetry._wait > 0.0, "kept for a better day")
	var waited: float = telemetry._wait
	for i in 8:
		telemetry._failed()
	_check(telemetry._wait <= telemetry.RETRY_MAX and telemetry._wait >= waited, "the wait doubles, capped")

	# --- the queue is on the disk, and a no forgets it and the install
	telemetry._load()
	_check(telemetry.queue.size() == 1, "the queue survives a restart")
	settings.set_telemetry(false)
	_check(telemetry.queue.is_empty() and telemetry.install_id() == "", "a no forgets the queue and the install id")
	telemetry._load()
	_check(telemetry.queue.is_empty(), "and the disk forgets them too")

	# --- the menus
	settings.set_telemetry_asked(false)
	telemetry.url_override = url
	var consent_script = load("res://scripts/ui/telemetry_consent.gd")
	_check(consent_script.wanted(), "first launch with a server: asked")
	var consent = consent_script.new()
	root.add_child(consent)
	consent.open()
	_check(consent.visible and root.gui_get_focus_owner() == consent.find_child("No", true, false), "the question is on screen, focus on No")
	consent.answer(false)
	_check(settings.telemetry_asked and not settings.telemetry and not consent_script.wanted(), "a no is an answer: never asked again")
	consent.queue_free()
	var feedback = load("res://scripts/ui/feedback_button.gd")
	_check(feedback.make() == null, "no feedback link: no button")

	# --- put back what we found, the way it is saved
	telemetry.url_override = ""
	telemetry.allow_in_tools = false
	telemetry.reset_for_tools()
	game.practice = was_practice
	settings.set_telemetry(was_on)
	settings.set_telemetry_asked(was_asked)
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	_check(bool(cfg.get_value("privacy", "telemetry", false)) == was_on
		and bool(cfg.get_value("privacy", "telemetry_asked", false)) == was_asked, "the player's settings are as they were")
	_server.stop()

	print("telemetry_test: %s" % ("PASS" if failures == 0 else "%d FAIL" % failures))
	quit(1 if failures else 0)


## One night as Playtest would hand it over.
func _night(telemetry, first: bool) -> void:
	var events := [
		["run_start", {"version": "test", "difficulty": "standard", "platform": "test", "t": 0.0}],
		["room_start", {"room": "village_night", "index": 1, "t": 0.0}],
		["hurt", {"room": "village_night", "fraction": 0.1, "t": 12.0}],
		["room_clear", {"room": "village_night", "seconds": 38.0, "damage": 0.1, "deaths": 0, "t": 38.0}],
		["gift", {"id": "vampirism", "rarity": "common", "path": "temptation", "t": 40.0}],
		["room_start", {"room": "graveyard_cross", "index": 2, "t": 41.0}],
		["skip", {"dialogue": "ch1_stranger", "t": 60.0}],
		["room_start", {"room": "graveyard_arches", "index": 3, "t": 90.0}],
		["death", {"room": "graveyard_arches", "x": 10, "y": 20, "by": "possessed", "t": 120.0}],
		["run_end", {"won": false, "seconds": 120.0, "level": 2, "gifts": 1, "alignment": {}, "omen": "", "vial": 0, "t": 120.0}],
	]
	for pair in events:
		telemetry.record(pair[0], pair[1].duplicate())


## Lets the HTTPRequest and our server run for [param frames] frames.
func _pump(frames: int) -> void:
	for i in frames:
		_serve()
		await process_frame
		OS.delay_msec(5)


func _until(done: Callable, frames: int) -> void:
	for i in frames:
		if done.call():
			return
		await _pump(1)


## A server of a few lines: reads one request per connection, answers answer_code.
func _serve() -> void:
	while _server.is_connection_available():
		_peers.append([_server.take_connection(), PackedByteArray()])
	for entry in _peers.duplicate():
		var peer: StreamPeerTCP = entry[0]
		peer.poll()
		var available := peer.get_available_bytes()
		if available > 0:
			var got: Array = peer.get_partial_data(available)
			if got[0] == OK:
				entry[1].append_array(got[1])
		var text: String = (entry[1] as PackedByteArray).get_string_from_utf8()
		var split := text.find("\r\n\r\n")
		if split < 0:
			continue
		var length := 0
		for line in text.substr(0, split).split("\r\n"):
			if line.to_lower().begins_with("content-length:"):
				length = int(line.split(":")[1].strip_edges())
		var body_bytes: PackedByteArray = (entry[1] as PackedByteArray).slice(text.substr(0, split + 4).to_utf8_buffer().size())
		if body_bytes.size() < length:
			continue
		if answer_code == 200:
			var parsed = JSON.parse_string(body_bytes.get_string_from_utf8())
			if parsed is Dictionary:
				bodies.append(parsed)
		var reply := "HTTP/1.1 %d X\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok" % answer_code
		peer.put_data(reply.to_utf8_buffer())
		peer.disconnect_from_host()
		_peers.erase(entry)
