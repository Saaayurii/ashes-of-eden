extends Node
## Opt-in telemetry (docs/PLAYTEST.md): the Playtest autoload's events of a
## night, folded into one record and sent to the project's server, so the four
## numbers of docs/CORE_LOOP.md and docs/BALANCE_PROBE.md come from players
## and not only from whoever made the game.
##
## Nothing leaves the machine unless all of these hold:
##   - a server is set: `ashes/telemetry/url` in project.godot, or
##     `--telemetry-url=` on the command line (empty = off, and nothing is
##     even recorded);
##   - the player said yes (Settings.telemetry, asked once by
##     TelemetryConsent on the first launch, a switch in Settings);
##   - it is not a tool script (`-s`), unless the test asks (allow_in_tools).
## A record carries a random install id and the night's events — rooms, what
## laid him low, gifts, vial, omen, platform — never a name, an address or a
## file of the player's. The practice yard is not a night (Playtest drops it);
## a night of the day says which try of that day it was (`daily_try`), and
## every record has its own id so a resent batch is counted once.
##
## Sending never blocks or breaks play: records wait in a small file
## (user://telemetry_queue.json, so a night ended by quitting goes out on the
## next launch), go in batches through one HTTPRequest, and a failure only
## waits longer before the next try (RETRY_SECONDS, doubled, capped).

const URL_SETTING := "ashes/telemetry/url"
const FEEDBACK_SETTING := "ashes/telemetry/feedback_url"
## Bumped when a record's shape changes; tools/telemetry/pull.py reads it.
const FORMAT := 1
const BATCH := 10
## Records kept while the server cannot be reached; the oldest go first.
const QUEUE_MAX := 60
## Events kept from one night: enough for the longest chapter many times over.
const EVENTS_MAX := 600
## The flood of small hurts is already in each room_clear's damage.
const DROPPED_EVENTS := ["hurt"]
const RETRY_SECONDS := 30.0
const RETRY_MAX := 600.0
const TIMEOUT := 15.0

## A tool script that wants it on (telemetry_test.gd); every other -s run sends nothing.
var allow_in_tools := false
## Overrides the project setting and the command line (the test's own server).
var url_override := ""
## Records waiting to go, oldest first.
var queue: Array = []
## Batches the server took (for the test and a curious debugger).
var sent := 0
## Tries that failed since the last success.
var failures := 0

var _http: HTTPRequest
var _in_flight: Array = []  # ids of the records in the request under way
var _wait := 0.0
var _night: Dictionary = {}  # the night being recorded, {} between nights
var _state := {}  # install id, daily tries (user://telemetry.cfg)
var _dir := "user://"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _is_tool():
		_dir = "user://telemetry_tools/"  # a test never touches the player's queue
		DirAccess.make_dir_recursive_absolute(_dir)
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT
	_http.use_threads = false  # the Web export has none to spare
	add_child(_http)
	_http.request_completed.connect(_on_completed)
	_load()
	EventBus.night_retried.connect(_on_retry)
	Settings.changed.connect(_on_settings_changed)


func _process(delta: float) -> void:
	if queue.is_empty() or not _in_flight.is_empty():
		return
	_wait -= delta
	if _wait <= 0.0:
		flush()


## The server records go to: "" when the build ships without one, or names
## something that is not an http(s) address (which is as good as none).
func endpoint() -> String:
	var url := str(ProjectSettings.get_setting(URL_SETTING, ""))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--telemetry-url="):
			url = arg.trim_prefix("--telemetry-url=")
	if url_override != "":
		url = url_override
	url = url.strip_edges()
	return url if url.begins_with("https://") or url.begins_with("http://") else ""


## Where "Send feedback" leads (pause menu, the night's end): "" hides the button.
static func feedback_url() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--feedback-url="):
			return arg.trim_prefix("--feedback-url=")
	return str(ProjectSettings.get_setting(FEEDBACK_SETTING, ""))


## Whether there is anyone to ask: a build with no server never asks.
func can_ask() -> bool:
	return endpoint() != "" and (not _is_tool() or allow_in_tools)


## Whether this night is recorded and sent.
func enabled() -> bool:
	return can_ask() and bool(Settings.telemetry)


func install_id() -> String:
	return str(_state.get("install", ""))


## One Playtest event (Playtest._write hands each one over). A night starts at
## run_start and goes into the queue at run_end.
func record(kind: String, fields: Dictionary) -> void:
	if not enabled():
		_night = {}
		return
	if kind == "run_start":
		_begin_night(fields)
	if _night.is_empty() or DROPPED_EVENTS.has(kind):
		return
	var events: Array = _night.events
	if events.size() < EVENTS_MAX:
		var copy := fields.duplicate(true)
		copy["e"] = kind
		events.append(copy)
	if kind == "run_end":
		_end_night(fields)


func _begin_night(fields: Dictionary) -> void:
	if install_id() == "":
		_state["install"] = _random_id()
	var daily := str(Game.daily)
	var tries := 0
	if daily != "":
		var days: Dictionary = _state.get("daily", {})
		tries = int(days.get(daily, 0)) + 1
		_state["daily"] = {daily: tries}  # only today's is worth keeping
	_save_state()
	_night = {
		"format": FORMAT,
		"id": _random_id(),
		"install": install_id(),
		"version": str(fields.get("version", ProjectSettings.get_setting("application/config/version", ""))),
		"platform": OS.get_name(),
		"web": OS.has_feature("web"),
		"locale": str(Settings.locale),
		"difficulty": str(Settings.difficulty),
		"nights": int(Profile.data.get("nights", 0)),  # nights before this one: 0 = the first
		"daily": daily,
		"daily_try": tries,
		"online": bool(Net.active),
		"events": [],
	}


func _end_night(fields: Dictionary) -> void:
	var night := _night
	_night = {}
	night["won"] = bool(fields.get("won", false))
	night["seconds"] = float(fields.get("seconds", 0.0))
	night["summary"] = summarise(night.events)
	enqueue(night)


## The four numbers' raw material, from a night's events (also read back by
## tools/telemetry/pull.py, which can rebuild it from the events alone).
static func summarise(events: Array) -> Dictionary:
	var out := {"rooms": 0, "last_room": "", "by": "", "died": false, "first_gift_t": -1.0,
		"gifts": [], "refused": 0, "skipped": [], "choices": {}, "vial": 0, "omen": "", "level": 1}
	for e in events:
		if not e is Dictionary:
			continue
		match str(e.get("e", "")):
			"room_start":
				out.rooms = maxi(int(out.rooms), int(e.get("index", 0)))
				out.last_room = str(e.get("room", ""))
			"gift":
				if float(out.first_gift_t) < 0.0:
					out.first_gift_t = float(e.get("t", 0.0))
				out.gifts.append(str(e.get("id", "")))
			"refuse":
				out.refused = int(out.refused) + 1
				if float(out.first_gift_t) < 0.0:
					out.first_gift_t = float(e.get("t", 0.0))  # a hand was dealt all the same
			"skip":
				out.skipped.append(str(e.get("dialogue", "")))
			"choice":
				out.choices[str(e.get("dialogue", ""))] = str(e.get("choice", ""))
			"death":
				out.died = true
				out.by = str(e.get("by", ""))
			"run_end":
				out.vial = int(e.get("vial", 0))
				out.omen = str(e.get("omen", ""))
				out.level = int(e.get("level", 1))
	return out


## Into the queue and onto the disk at once, then out when the line is free.
func enqueue(record_: Dictionary) -> void:
	queue.append(record_)
	while queue.size() > QUEUE_MAX:
		queue.pop_front()
	_save_queue()
	_wait = 0.0


## Another night after a death (EventBus.night_retried): docs/CORE_LOOP.md's
## third number. A record of its own, since the night it follows has gone.
func _on_retry() -> void:
	if not enabled():
		return
	enqueue({"format": FORMAT, "kind": "retry", "id": _random_id(), "install": install_id(),
		"nights": int(Profile.data.get("nights", 0)), "daily": str(Game.daily)})


## Sends the oldest batch now, if anything waits and nothing is under way.
## Returns whether a request went out.
func flush() -> bool:
	if not enabled() or queue.is_empty() or not _in_flight.is_empty():
		return false
	var batch: Array = queue.slice(0, BATCH)
	var body := JSON.stringify({"format": FORMAT, "records": batch})
	# text/plain keeps a browser from sending a preflight first; the server
	# answers one anyway (tools/telemetry/server.py).
	var err := _http.request(endpoint(), PackedStringArray(["Content-Type: text/plain"]), HTTPClient.METHOD_POST, body)
	if err != OK:
		_failed()
		return false
	_in_flight = batch.map(func(r: Dictionary) -> String: return str(r.get("id", "")))
	return true


func _on_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var ids := _in_flight
	_in_flight = []
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		_failed()
		return
	queue = queue.filter(func(r: Dictionary) -> bool: return not ids.has(str(r.get("id", ""))))
	_save_queue()
	sent += 1
	failures = 0
	_wait = 0.0  # the rest at once


func _failed() -> void:
	failures += 1
	_wait = minf(RETRY_SECONDS * pow(2.0, failures - 1), RETRY_MAX)


## A no forgets what was waiting and who this install was.
func _on_settings_changed() -> void:
	if Settings.telemetry:
		return
	_night = {}
	if not queue.is_empty() or install_id() != "":
		queue = []
		_state.erase("install")
		_save_queue()
		_save_state()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_dir + "telemetry.cfg") == OK:
		_state = {"install": str(cfg.get_value("telemetry", "install", "")),
			"daily": cfg.get_value("telemetry", "daily", {})}
		if not _state.daily is Dictionary:
			_state.daily = {}
	var text := FileAccess.get_file_as_string(_dir + "telemetry_queue.json")
	var parsed = JSON.parse_string(text) if text != "" else null
	queue = []
	if parsed is Array:
		for r in parsed:
			if r is Dictionary and r.has("id"):
				queue.append(r)


func _save_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("telemetry", "install", install_id())
	cfg.set_value("telemetry", "daily", _state.get("daily", {}))
	cfg.save(_dir + "telemetry.cfg")


func _save_queue() -> void:
	var file := FileAccess.open(_dir + "telemetry_queue.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(queue))


## Forgets the queue and the install id in the tool directory (telemetry_test.gd).
func reset_for_tools() -> void:
	if not _is_tool():
		return
	queue = []
	_state = {}
	_night = {}
	_in_flight = []
	sent = 0
	failures = 0
	_wait = 0.0
	_http.cancel_request()
	_save_queue()
	_save_state()


static func _random_id() -> String:
	return Crypto.new().generate_random_bytes(12).hex_encode()


static func _is_tool() -> bool:
	for arg in OS.get_cmdline_args():
		if arg == "-s" or arg == "--script":
			return true
	return false
