extends SceneTree
## The secrets of chapter I, headless:
##   godot --headless --path . -s scripts/tools/secret_test.gd
## Every bricked-up wall placed in a room breaks under the sword, the cache it
## hid appears where it stood, opening it files the record in the bestiary and
## pays its Ash — once. The player's own profile is put back afterwards.

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var data_loader = root.get_node("Data")
	var profile = root.get_node("Profile")
	var game = root.get_node("Game")
	var saved_profile: Dictionary = profile.data.duplicate(true)
	var found := {}
	var heard := []
	root.get_node("EventBus").note_found.connect(func(note_id: String, first: bool) -> void: heard.append([note_id, first]))
	for scene in ["res://scenes/rooms/village_night.tscn", "res://scenes/rooms/swamp_crypt.tscn", "res://scenes/rooms/catacombs_2.tscn"]:
		var room = load(scene).instantiate()
		root.add_child(room)
		current_scene = room
		await _settle(0.2)
		var walls := []
		for prop in get_nodes_in_group("props"):
			if room.is_ancestor_of(prop) and prop.stats.has("reveals"):
				walls.append(prop)
		_assert(walls.size() == 1, "%s: one secret wall (%d)" % [scene.get_file(), walls.size()])
		for wall in walls:
			var hidden: String = wall.stats.reveals
			var at: Vector2 = wall.global_position
			# a bricked-up doorway, not a patch of bricks: its niche is drawn
			# behind it, or the painting has the arch (NICHE_PAINTED)
			var niche = wall.get_node_or_null("Niche")
			_assert(niche != null or wall.prop_id == "secret_wall_catacombs",
				"%s: stands in a doorway" % wall.prop_id)
			if niche != null:
				_assert(niche.get_index() == 0 and niche.texture.get_width() > wall.sprite.texture.get_width() / wall.sprite.hframes,
					"%s: the niche frames the wall from behind" % wall.prop_id)
			var hits := 0
			while not wall._spent and hits < 20:
				wall.take_damage(12.0)
				hits += 1
			_assert(hits >= 2, "%s: takes more than one blow (%d)" % [wall.prop_id, hits])
			if niche != null:
				_assert(is_instance_valid(niche) and niche.visible, "%s: the doorway stays when the wall comes down" % wall.prop_id)
			await _settle(0.5)
			var cache = null
			for prop in get_nodes_in_group("props"):
				if prop.prop_id == hidden:
					cache = prop
			_assert(cache != null, "%s: reveals %s" % [wall.prop_id, hidden])
			if cache == null:
				continue
			_assert(cache.global_position.distance_to(at) < 1.0, "%s: stands where the wall stood" % hidden)
			var note: String = cache.stats.note
			profile.data.bestiary.erase("note:" + note)
			var ash_before: int = game.ash_earned
			cache._pay_out()
			_assert(game.ash_earned - ash_before == int(cache.stats.ash), "%s: pays %d ash the first time" % [hidden, int(cache.stats.ash)])
			_assert(profile.bestiary_entry("note:" + note).get("met", false), "%s: the record opens in the bestiary" % note)
			ash_before = game.ash_earned
			cache._pay_out()
			_assert(game.ash_earned == ash_before, "%s: no ash the second time" % hidden)
			_assert(data_loader.dialogues.has(data_loader.notes[note].dialogue), "%s: has a caption to read" % note)
			found[note] = true
		room.queue_free()
		await _settle(0.1)
	_assert(found.size() == data_loader.notes.size(), "every record is placed somewhere (%d/%d)" % [found.size(), data_loader.notes.size()])
	_assert(heard.size() == found.size() * 2 and heard[0][1] and not heard[1][1], "note_found: first, then again")
	_assert(game.flags.has("read_letters"), "the preacher's letters set read_letters")
	profile.data = saved_profile
	profile.save()
	print("SECRET TEST PASSED" if failures == 0 else "SECRET TEST FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)


func _settle(seconds: float) -> void:
	await create_timer(seconds).timeout


func _assert(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		failures += 1
