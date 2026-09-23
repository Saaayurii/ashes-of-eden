extends SceneTree
## Regression test for room-owned delayed ambience. It destroys rooms while
## bird gaps and one-shot particle effects are still pending; no callback may
## retain the freed room or one of its sprites.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var run = load("res://scenes/run/run.tscn").instantiate()
	root.add_child(run)
	current_scene = run
	# This test is about what a freed room leaves behind, not about the curtain:
	# with the transition instant, _load_room stays synchronous and every one of
	# the 28 rooms below is really built and really torn down.
	run.transition.instant = true
	await process_frame
	await process_frame
	var event_bus := root.get_node("EventBus")
	for index in 28:
		event_bus.world_impulse.emit(Vector2(320, 220), Vector2.RIGHT, 1.0, &"stress")
		run._load_room(index % run.ROOMS.size())
		await process_frame
	# The old raven callbacks used gaps up to twelve seconds. Waiting beyond
	# that proves none of those callbacks captured a sprite from a freed room.
	await create_timer(12.5).timeout
	print("ROOM TRANSITION STRESS PASSED: 28 rapid loads, delayed ambience drained")
	quit()
