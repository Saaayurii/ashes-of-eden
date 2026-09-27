extends SceneTree
## Headless check of the music layer that follows the run's lean (Audio.alignment_layer,
## fed by Player._update_aura):
##   godot --headless -s scripts/tools/alignment_layer_test.gd
## Level counters play nothing, a lean brings the right layer in, a deeper lean
## is louder, switching sides switches the file, and levelling out fades it
## away again. Exit code 1 on any failure.
## Deliberately untyped w.r.t. game classes, like every -s tool script.

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failed = true


func _settle(seconds := 0.1) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	var audio = root.get_node("Audio")
	await _settle()

	# `playing` is no use here: --headless runs the dummy audio driver, which
	# never reports a player as playing, so everything below reads the stream
	# and the volume instead. Those are what decide what comes out of the
	# speakers anyway.

	# Nothing at all while the counters are level.
	audio.alignment_layer("", 0.0)
	await _settle()
	_check(audio._layer.volume_db < -60.0, "a level run plays no layer")

	# A lean brings its own file in.
	audio.alignment_layer("grace", 1.0)
	await _settle(0.3)
	_check(audio._layer.stream != null
			and str(audio._layer.stream.resource_path).contains("layer_grace"),
		"leaning grace starts grace's own layer (%s)"
		% str(audio._layer.stream.resource_path).get_file())
	# The fade is long on purpose, so wait it out rather than guessing.
	await _settle(4.0)
	var loud: float = audio._layer.volume_db
	_check(loud > -40.0, "it fades up to something audible (%.1f dB)" % loud)

	# Switching sides switches the file.
	audio.alignment_layer("temptation", 1.0)
	await _settle(0.3)
	_check(str(audio._layer.stream.resource_path).contains("layer_temptation"),
		"leaning the other way swaps the file")

	# A shallow lean is quieter than a committed one.
	await _settle(4.0)
	var deep: float = audio._layer.volume_db
	audio.alignment_layer("temptation", 0.2)
	await _settle(4.0)
	var shallow: float = audio._layer.volume_db
	_check(shallow < deep - 3.0,
		"a shallow lean is quieter than a deep one (%.1f < %.1f dB)" % [shallow, deep])

	# Levelling out takes it away again.
	audio.alignment_layer("", 0.0)
	await _settle(5.5)
	_check(audio._layer.volume_db < -60.0, "levelling out fades it back to silence")

	# A layer the build does not carry must not crash anything.
	audio.alignment_layer("no_such_path", 1.0)
	await _settle(0.2)
	_check(true, "an unknown path is survived")

	print("ALIGNMENT LAYER TEST " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
