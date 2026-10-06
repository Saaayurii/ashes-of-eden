extends SceneTree
## Every room's exit stands in a doorway the room actually has, on its floor:
## a painted room's door sits where its painting draws an arch, a gate or a
## passage (DOORWAYS, reviewed by eye against room_overview_shot.gd), not at a
## point that merely happened to be on the right; and its sill is a floor the
## hero can stand on. Coordinates are the widened room's.
##   godot --headless --path . -s scripts/tools/exits_test.gd

## room -> the painted opening's span in x (left, right) and its sill y
const DOORWAYS := {
	"village_night": [1545, 1580, 260],     # the gate of the chapel, top right
	"graveyard_cross": [1225, 1265, 386],   # the arch under the chapel of the statue
	"graveyard_arches": [1420, 1460, 292],  # the ruined arch with a candle
	"graveyard_tree": [1495, 1540, 241],    # the arch between the gate pillars
	"swamp_threshold": [1460, 1550, 363],   # the open arch across the marsh causeway
	"swamp_moon": [1490, 1540, 413],        # under the gallows with the lantern
	"swamp_red": [1540, 1580, 255],         # the gap in the ruin past the fence
	"swamp_crypt": [1280, 1350, 560],       # the crypt door, down its candle stair
	"catacombs_threshold": [1440, 1510, 415], # the open arch at the causeway's end
	"catacombs_1": [1470, 1505, 440],       # the wooden door on the ossuary floor
	"catacombs_2": [1430, 1470, 229],       # the arch at the end of the upper floor
	"catacombs_3": [1250, 1320, 583],       # the tunnel mouth, bottom right
	"crypt_threshold": [1530, 1570, 498],    # the arch at the open crypt edge
	"crypt_skulls": [1380, 1425, 615],      # the barred arch by the tombstones
	"crypt_lava": [1435, 1470, 208],        # the barred arch at the stair's foot
	"ashes_threshold": [1505, 1570, 392], # open fiery arch over the continuous nave floor
	"gate_threshold": [1460, 1570, 339], # burning arch at the bridge's end
	"hell_gate": [1290, 1350, 372],         # the chained gate of the pit
}

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL ", message)


func _run() -> void:
	var rooms: Array = load("res://scripts/run/run.gd").get_script_constant_map()["ROOMS"]
	for path in rooms:
		var name: String = path.get_file().get_basename()
		var room = load(path).instantiate()
		root.add_child(room)
		current_scene = room
		await physics_frame
		await physics_frame
		var door: Vector2 = room.door.position
		# the sill: the first floor straight under the door's centre
		var space: PhysicsDirectSpaceState2D = room.get_world_2d().direct_space_state
		var ray := PhysicsRayQueryParameters2D.create(room.to_global(door), room.to_global(door + Vector2(0, 80)), 17)
		var hit: Dictionary = space.intersect_ray(ray)
		var sill: float = room.to_local(hit.position).y if not hit.is_empty() else INF
		_check(not hit.is_empty() and absf(sill - door.y - 32.0) <= 2.0,
			"%s: the door at %s does not stand on a floor (sill %s)" % [name, door, sill])
		if DOORWAYS.has(name):
			var span: Array = DOORWAYS[name]
			_check(room.door.painted_arch, "%s: a painted room's exit is its painted doorway" % name)
			_check(door.x >= span[0] and door.x <= span[1] and absf(sill - span[2]) <= 2.0,
				"%s: the door at %s is not in the painted doorway %s" % [name, door, span])
		else:
			_check(not room.door.painted_arch and room.door.get_node("Gate").visible,
				"%s: a built room draws its own gate" % name)
		if failures == 0:
			print("  ok   %s: exit at %s" % [name, door])
		current_scene = null
		room.queue_free()
		await process_frame
	print("EXITS TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
