extends SceneTree
## Loads every prop strip, exercises ambient/world reactions, and breaks every
## destructible. Run with:
##   godot --headless --path . -s scripts/tools/prop_test.gd

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var data = root.get_node("Data")
	var event_bus = root.get_node("EventBus")
	var scene = load("res://scenes/props/prop.tscn")
	var host := Node2D.new()
	root.add_child(host)
	for prop_id in data.props:
		var prop = scene.instantiate()
		prop.prop_id = prop_id
		host.add_child(prop)
		await process_frame
		_assert(prop.sprite.texture != null, "%s strip loaded" % prop_id)
		_assert(prop.sprite.hframes == int(data.props[prop_id].sprite.frames), "%s frame count" % prop_id)
		event_bus.world_impulse.emit(prop.global_position, Vector2.RIGHT, 1.0, &"dash")
		await process_frame
		_assert(is_zero_approx(prop._kick.y), "%s reaction stays grounded" % prop_id)
		if data.props[prop_id].kind == "destructible":
			# Break from the second idle cell too: its padding may differ from
			# frame zero, but must not shift the authored destruction strip.
			if prop._idle_offsets.size() > 1:
				prop.sprite.frame = 1
				prop._idle_clock = 0.0
				prop._process(0.0)
			prop.take_damage(999.0)
			await create_timer(0.16).timeout
			_assert(prop.sprite.frame == prop.sprite.hframes - 1, "%s reaches remains frame" % prop_id)
			_assert(prop.sprite.offset == prop._authored_sprite_offset, "%s restores remains alignment" % prop_id)
			_assert(prop.sprite.position == prop._base_sprite_position and is_zero_approx(prop.sprite.rotation), "%s remains rest on floor" % prop_id)
		prop.queue_free()
		await process_frame
	host.queue_free()
	await process_frame
	print("PROP TEST %s: %d definitions" % ["FAILED" if _failed else "PASSED", data.props.size()])
	quit(1 if _failed else 0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("  ok   " + message)
	else:
		_failed = true
		printerr("  FAIL " + message)
