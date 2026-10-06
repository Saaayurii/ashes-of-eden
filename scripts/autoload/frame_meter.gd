extends Node
## How the frame holds up where the game really runs — a phone, a browser.
## In a debug build (the test APK, an editor run) or with `--frame-meter`,
## every WINDOW seconds it prints one line to the log: where we are, frames
## per second, mean and 95th-percentile frame time, how many frames missed
## 30 fps, and the settings that change the cost (backdrop life, motion,
## lighting, flashes). A setting changed in the pause menu ends the window
## at once, so each line measures one configuration. Read it with
##   adb logcat -s godot | grep FrameMeter
## or the browser's console. Never in a release build, never under -s.

const WINDOW := 10.0
const SLOW_MS := 33.4
const TAG := "[FrameMeter]"

var _deltas: PackedFloat32Array = []
var _started := 0
var _last := 0


func _ready() -> void:
	var asked := OS.get_cmdline_user_args().has("--frame-meter") or OS.get_cmdline_args().has("--frame-meter")
	if (not OS.is_debug_build() and not asked) or _is_tool() or DisplayServer.get_name() == "headless":
		set_process(false)
		return
	process_mode = PROCESS_MODE_ALWAYS
	Settings.changed.connect(_flush)
	EventBus.lighting_changed.connect(_flush)
	var window := DisplayServer.window_get_size()
	print("%s on: %s, %s, %dx%d window" % [TAG, OS.get_name(), RenderingServer.get_video_adapter_name(), window.x, window.y])


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last != 0:
		_deltas.append((now - _last) / 1000.0)
	else:
		_started = now
	_last = now
	if (now - _started) / 1000000.0 >= WINDOW:
		_flush()


## Prints the window so far (if it has enough frames to mean anything) and
## starts a new one.
func _flush() -> void:
	if _deltas.size() >= 30:
		print(line(_deltas, _where(), _settings()))
	_deltas.clear()
	_last = 0


## One log line for a window of frame times in ms.
static func line(deltas: PackedFloat32Array, where: String, settings: String) -> String:
	var sorted := deltas.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	for ms in deltas:
		total += ms
		if ms > SLOW_MS:
			slow += 1
	var mean := total / deltas.size()
	return "%s %s: %.1f fps, %.1f ms mean, %.1f ms p95, %d/%d over %.0f ms | %s" % [TAG, where,
		1000.0 / mean, mean, sorted[int(sorted.size() * 0.95)], slow, deltas.size(), SLOW_MS, settings]


func _where() -> String:
	for room in get_tree().get_nodes_in_group("room"):
		return str(room.scene_file_path.get_file().get_basename())
	var scene := get_tree().current_scene
	return str(scene.name) if scene != null else "?"


func _settings() -> String:
	# lighting off also rests the backdrop life (BackdropLife.apply_settings)
	return "lighting+life %s, backdrop motion %s, flashes %s" % [
		"on" if Settings.lighting else "off", "on" if Settings.backdrop_motion else "off", Settings.flashes]


static func _is_tool() -> bool:
	for arg in OS.get_cmdline_args():
		if arg == "-s" or arg == "--script":
			return true
	return false
