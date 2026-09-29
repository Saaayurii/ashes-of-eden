extends SceneTree
## Skins as data (data/skins): free ones unlock by play and only by play, a
## locked or unknown one is never worn, the choice is kept in Settings, the
## body is dyed with it, the other player sees it, and the settings menu
## lists every one with the locked ones greyed.
##   godot --headless --path . -s scripts/tools/skins_test.gd

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _run() -> void:
	var skins = load("res://scripts/player/skins.gd")
	var profile = root.get_node("Profile")
	var settings = root.get_node("Settings")
	var data = root.get_node("Data")
	var saved_profile: Dictionary = profile.data.duplicate(true)
	var saved_skin: String = settings.skin
	_check(data.skins.has("pilgrim") and skins.ids()[0] == "pilgrim", "the default cloak comes first")
	for id in data.skins:
		_check(str(data.skins[id].get("sku", "")) == "", "%s is free: the store comes later" % id)

	profile.data.nights = 0
	profile.data.total_kills = 0
	profile.data.bestiary = {}
	_check(skins.unlocked("pilgrim"), "the red cloak is his from the first night")
	_check(not skins.unlocked("grave_moss"), "grave moss: locked before three nights")
	profile.data.nights = 3
	_check(skins.unlocked("grave_moss"), "grave moss: three nights survived")
	_check(not skins.unlocked("bone_white"), "bone white: locked while the Ophanim stands")
	profile.data.bestiary["ophanim"] = {"seen": true, "kills": 1}
	_check(skins.unlocked("bone_white"), "bone white: the Ophanim put down")
	profile.data.total_kills = 300
	_check(skins.unlocked("ember"), "ember: three hundred put to rest")
	_check(not skins.unlocked("no_such_cloak"), "an unknown cloak is never unlocked")
	data.skins["store_test"] = {"id": "store_test", "sku": "x", "unlock": {}}
	_check(not skins.unlocked("store_test"), "a store skin stays locked without a store")
	data.skins.erase("store_test")

	profile.data.nights = 0
	_check(skins.worn("grave_moss") == "pilgrim", "a locked choice falls back to the default")

	var hero = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(hero)
	await process_frame
	settings.set_skin("bone_white")
	await process_frame
	_check(hero.skin == "bone_white", "our body wears what Settings says")
	var material = hero.body.material
	_check(material is ShaderMaterial and material.get_shader_parameter("skin_on")
		and is_equal_approx(float(material.get_shader_parameter("cloak_hue")), float(data.skins.bone_white.cloak.hue)),
		"the body is dyed with it")
	settings.set_skin("pilgrim")
	await process_frame
	_check(not material.get_shader_parameter("skin_on"), "back in red: the dye is off")
	_check(hero.NET_PROPERTIES.has(".:skin"), "the other player sees our cloak")
	hero.queue_free()

	var menu = load("res://scenes/ui/settings_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var picker = menu._skin
	_check(picker != null and picker.item_count == data.skins.size(), "the menu lists every cloak")
	var locked_greyed := true
	for i in picker.item_count:
		var id: String = skins.ids()[i]
		locked_greyed = locked_greyed and picker.is_item_disabled(i) == not skins.unlocked(id)
	_check(locked_greyed, "the locked ones are greyed")
	menu.queue_free()

	profile.data = saved_profile
	settings.set_skin(saved_skin)
	print("SKINS TEST %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	await process_frame
	quit(0 if failures == 0 else 1)
