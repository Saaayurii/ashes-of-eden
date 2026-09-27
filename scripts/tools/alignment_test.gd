extends SceneTree
## Headless check of everything the run's lean changes, sound and body
## (Audio.alignment_layer and Player._mark_body, both fed by _update_aura):
##   godot --headless -s scripts/tools/alignment_test.gd
## Level counters play nothing and mark nothing; a lean brings the right layer
## in and the right mark on; a deeper lean is louder; switching sides switches
## both; levelling out takes them away again. Exit code 1 on any failure.
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

	# --- the same lean, on the body ------------------------------------------
	var room = load("res://scenes/rooms/graveyard.tscn").instantiate()
	root.add_child(room)
	var player = load("res://scenes/player/player.tscn").instantiate()
	room.add_child(player)
	player.global_position = Vector2(300, 220)
	await _settle(0.4)

	player._mark_body("", 0.0)
	await _settle()
	var level_material = player.body.material
	_check(level_material == null
			or level_material.get_shader_parameter("strength") == 0.0,
		"a level run marks the body with nothing")

	for path_mode in [["grace", 0], ["temptation", 1], ["will", 2]]:
		var path: String = path_mode[0]
		player._mark_body(path, 0.8)
		await _settle()
		var material = player.body.material
		_check(material is ShaderMaterial, "%s puts a shader on the body" % path)
		if material is ShaderMaterial:
			_check(int(material.get_shader_parameter("mode")) == int(path_mode[1]),
				"  and asks for its own mark (mode %d)" % int(path_mode[1]))
			_check(absf(float(material.get_shader_parameter("strength")) - 0.8) < 0.01,
				"  at the strength it was given")

	# Back to level: the shader may stay bound, but it must do nothing.
	player._mark_body("", 0.0)
	await _settle()
	_check(float(player.body.material.get_shader_parameter("strength")) == 0.0,
		"levelling out turns the mark off")

	print("ALIGNMENT TEST " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
