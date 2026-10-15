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
	"graveyard_cross": [2480, 2550, 302],   # composed: the gate atop the hill
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
	"seir_road": [1485, 1535, 567],             # the dark passage under the town wall
	"seir_gate": [1510, 1560, 545],             # the arch beside the gatehouse
	"seir_street": [1510, 1560, 535],           # the harbour arch with the lantern
	"seir_square": [1530, 1580, 577],           # the arched door off the square
	"seir_roofs": [1535, 1585, 274],            # the rooftop door under the chimney
	"seir_canal": [1520, 1570, 403],            # the arch at the canal's end
	"seir_quay": [1550, 1600, 490],             # the gap in the quay wall
	"seir_wrecks": [1507, 1557, 507],           # the arch in the dock wall
	"seir_warehouses": [1505, 1555, 597],       # the open bay of the last warehouse
	"seir_breakwater": [1523, 1573, 432],       # the lighthouse door
	"seir_lighthouse_stair": [1485, 1535, 119], # the arch at the top of the stair
	"seir_lighthouse": [1545, 1595, 495],       # the arch past the lamp room
	"tyre_causeway": [1550, 1600, 498],         # the gate's arch at the causeway's end
	"tyre_counting_house": [1510, 1560, 574],   # the arch past the tellers' tables
	"tyre_dark_quarter": [1535, 1585, 546],     # the alley mouth at the street's end
	"tyre_bright_quay": [1535, 1585, 485],      # the lit arch over the quay
	"tyre_dyeworks": [1530, 1580, 505],         # the arch past the last vat
	"tyre_gate": [1510, 1560, 514],             # the inner arch into the city
	"tyre_lamp_market": [1510, 1560, 518],      # the arcade's far passage
	"tyre_rich_gate": [1510, 1560, 579],        # the side passage past the shrine
	"tyre_vaults": [1515, 1565, 541],           # the arch past the cage
	"tyre_galleys": [1525, 1570, 445],          # the harbour tower's lit door
	"tyre_palace_stair": [1370, 1415, 176],     # the arch at the head of the stair
	"tyre_throne": [1530, 1580, 521],           # the arch behind the throne
	"marah_gallows": [1320, 1350, 605],         # the path between the rocks
	"marah_ford": [1530, 1580, 536],            # the dark arch in the far bank
	"marah_host_bank": [1545, 1590, 540],       # the open flap of the last tent
	"marah_field": [1525, 1555, 555],           # the gap in the stakes
	"marah_bitter_wells": [1525, 1590, 473],    # the arch out of the cellar
	"marah_dry_bed": [1515, 1580, 550],         # the cave in the bank
	"marah_trench": [1530, 1590, 592],          # the far end of the trench
	"marah_legion_bank": [1500, 1560, 472],     # the gate in the stockade
	"marah_parley": [1535, 1595, 538],          # the far flap
	"marah_siege": [1545, 1600, 602],           # the gap behind the tower
	"marah_springs_path": [1505, 1570, 135],    # the gap between the rocks at the top
	"marah_wormwood_spring": [1540, 1590, 590], # the arch on the right
	"engedi_smoke_road": [1535, 1585, 572],           # the dark gap between the rocks
	"engedi_vineyard_gate": [1500, 1550, 572],        # the open vineyard gate
	"engedi_terraces": [1520, 1570, 150],             # the arch atop the terraces
	"engedi_spring": [1545, 1595, 572],               # the cave mouth past the fountain
	"engedi_orchard": [1535, 1585, 580],              # the arch under the vines
	"engedi_arbor": [1535, 1585, 575],                # the arch at the arbor's end
	"engedi_feast_hall": [1520, 1570, 582],           # the arch past the brazier
	"engedi_pit_rim": [1535, 1585, 549],              # the doorway up the steps
	"engedi_hives": [1520, 1570, 587],                # the arch in the hive wall
	"engedi_wine_press": [1520, 1570, 533],           # the arch beside the press
	"engedi_pit_stair": [1520, 1570, 603],            # the arch at the stair's foot
	"engedi_abyss_mouth": [1535, 1585, 440],          # the arch into the pit
}

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL ", message)


func _run() -> void:
	var rooms: Array = root.get_node("Data").all_rooms()
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
