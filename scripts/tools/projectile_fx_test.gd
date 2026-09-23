extends SceneTree
## Headless regression for painted projectile styles and death-affinity rules.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	enemy.stats = {"tags": ["human", "cult"]}
	assert(enemy._soul_affinity() == "light")
	enemy.stats = {"tags": ["human", "possessed"]}
	assert(enemy._soul_affinity() == "dark")
	enemy.stats = {"tags": ["angel", "boss"]}
	assert(enemy._soul_affinity() == "light")
	enemy.stats = {"tags": ["undead", "fallen"]}
	assert(enemy._soul_affinity() == "dark")
	enemy.enemy_id = "wraith"
	assert(enemy._projectile_style() == "wraith")
	enemy.enemy_id = "cult_caller"
	enemy.stats = {"tags": ["human", "cult"]}
	assert(enemy._projectile_style() == "umbral")
	enemy.enemy_id = "zealot"
	enemy.stats = {"tags": ["human", "heaven"]}
	assert(enemy._projectile_style() == "sacred")
	enemy.free()
	for style in ["blade", "sacred", "umbral", "wraith"]:
		var projectile = load("res://scenes/fx/projectile.tscn").instantiate()
		projectile.visual_style = style
		projectile._set_art()
		assert(projectile.get_node("Art").texture != null)
		assert(projectile.get_node("Art").texture.get_width() == 96)
		projectile.free()
	print("PASS: projectile art and enemy essence affinity")
	quit()
