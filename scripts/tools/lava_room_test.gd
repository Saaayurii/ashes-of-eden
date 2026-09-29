extends SceneTree
## Expanded lava paintings: no safety floor, correct hazard bounds, safe return.
const POOLS := {
	"crypt_lava": [Rect2(750, 694, 720, 26)],
	"hell_gate": [Rect2(425, 694, 262, 26), Rect2(801, 694, 310, 26), Rect2(1310, 694, 88, 26)],
}
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("LAVA_FAIL ", message)

func _run() -> void:
	for key in POOLS:
		var room = load("res://scenes/rooms/%s.tscn" % key).instantiate()
		root.add_child(room)
		current_scene = room
		await physics_frame
		await physics_frame
		_check(not room.has_node("Shrine"), "%s has a redundant exit statue" % key)
		var spanning := false
		for shape in room.get_node("Geometry").get_children():
			if shape is CollisionShape2D and shape.shape is RectangleShape2D:
				spanning = spanning or (shape.shape.size.x >= room.width * 0.9 and shape.position.y > room.height * 0.5)
		_check(not spanning, "%s has an invisible bottom floor" % key)
		if key == "hell_gate":
			for step in [Rect2(1525, 563, 75, 12), Rect2(1550, 493, 50, 12)]:
				var has_collision := false
				for collider in room.get_node("Ledges").get_children():
					if collider is CollisionShape2D and collider.shape is RectangleShape2D:
						var bounds := Rect2(collider.position - collider.shape.size * .5, collider.shape.size)
						if bounds == step:
							has_collision = collider.one_way_collision
				var has_art := false
				for sprite in room.get_node("Terrain").get_children():
					if sprite is Sprite2D and sprite.position == step.position:
						has_art = sprite.region_enabled and absf(sprite.region_rect.size.x * sprite.scale.x - step.size.x) < 0.01 \
							and sprite.get("wall_on_right") == true \
							and sprite.texture.resource_path.ends_with("hell_cornice_v1.png")
				_check(has_collision and has_art, "hell_gate return cornice has unmatched art/collision")
				_check(step.end.x == room.width, "hell_gate return cornice detached from right wall")
			for point in [Vector2(850, 310), Vector2(1120, 358)]:
				var ray := PhysicsRayQueryParameters2D.create(point - Vector2(0, 2), point + Vector2(0, 8), 17)
				_check(room.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(), "hell_gate distant scenery is solid at %s" % point)
		for i in POOLS[key].size():
			var expected: Rect2 = POOLS[key][i]
			var pool = room.get_node("Hazard%d" % (i + 1))
			_check(Rect2(pool.position, pool.size) == expected, "%s pool %d bounds" % [key, i + 1])
			# Check both ends too: a shifted hazard used to leave the widened
			# painting's right half harmless, while burning unrelated masonry.
			for fraction in [0.05, 0.95]:
				var hero = load("res://scenes/player/player.tscn").instantiate()
				room.add_child(hero)
				hero.controls_enabled = false
				hero.place_in_room(room.player_spawn.global_position)
				await physics_frame
				var hp_before: float = hero.hp
				hero.global_position = expected.position + Vector2(expected.size.x * fraction, -5)
				hero.velocity = Vector2.ZERO
				for frame in 6:
					await physics_frame
				_check(hero.hp < hp_before, "%s pool %d edge %s does not burn" % [key, i + 1, fraction])
				await create_timer(0.45).timeout
				_check(not hero.is_dead() and hero.global_position.distance_to(room.player_spawn.global_position) < 55, "%s pool %d fails to return hero safely" % [key, i + 1])
				hero.queue_free()
				await physics_frame
		var falling = load("res://scenes/player/player.tscn").instantiate()
		room.add_child(falling)
		falling.controls_enabled = false
		falling.stats.extra_lives = 2
		falling.place_in_room(Vector2(100, 725))
		for frame in 60:
			if falling.is_dead():
				break
			await physics_frame
		_check(falling.is_dead() and falling.fell_outside_room, "%s fall outside painting must be fatal" % key)
		current_scene = null
		room.queue_free()
		await physics_frame
	print("LAVA_ROOM_TEST %s" % ("PASSED" if failures == 0 else "FAILED"))
	quit(0 if failures == 0 else 1)
