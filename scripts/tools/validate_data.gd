extends SceneTree
## Validates data files and localization without opening the editor:
##   godot --headless -s scripts/tools/validate_data.gd
## Exit code 1 when anything is wrong. Runs in CI on every pull request,
## so a content contributor gets feedback without launching Godot.

const LOCALES := ["en", "ru", "uk", "zh_CN"]
const PATHS := ["grace", "temptation", "will"]
const EFFECT_TYPES := ["stat", "lifesteal", "extra_life", "heal", "skill"]
const SKILL_KINDS := ["nova", "bolt", "drain"]
const RARITIES := ["common", "rare", "epic", "legendary"]
## Keys of Player.BASE_STATS a "stat" effect may touch. Duplicated on purpose:
## this script runs before the game's classes exist. Keep it in step.
const STATS := ["max_hp", "speed", "acceleration", "jump_velocity", "gravity", "max_jumps",
	"attack_damage", "attack_cooldown", "attack_scale", "crit_chance", "crit_multiplier",
	"backstab_multiplier", "dash_speed", "dash_time", "dash_cooldown", "armor", "lifesteal",
	"extra_lives", "heal_charges", "thorns", "execute", "kill_heal", "clear_heal", "dash_damage",
	"wave_damage", "guard", "essence_bonus", "friction", "slide_friction"]
const BEHAVIOURS := ["walker", "flyer", "boss_ophanim", "caster"]
const ATTACK_TYPES := ["melee", "ranged", "lunge", "beam", "nova", "summon"]
const ANIMATIONS := ["idle", "walk", "interact", "attack", "attack_alt", "special", "hurt", "death"]
const PROP_KINDS := ["destructible", "chest"]
## What a blade landing on this body sounds like (tools/audio/generate_voices.py).
const MATERIALS := ["flesh", "cloth", "mail", "plate", "bone", "feather", "spirit", "gold"]
## Cutscene steps (scripts/ui/cutscene.gd): step -> the fields it must carry.
const CUTSCENE_STEPS := {
	"hold": [], "release": [], "letterbox": [], "wait": ["time"], "camera": ["to"],
	"move": ["who"], "walk": ["who"], "anim": ["who", "anim"], "face": ["who", "dir"],
	"dialogue": ["id"], "shake": [], "sound": ["name"], "music": ["name"], "fade": ["to"],
	"appear": ["who"], "vanish": ["who"],
}
const CUTSCENE_ACTORS := ["player", "boss", "door"]
const REQUIRED := {
	"abilities": ["id", "name", "description", "path", "effects"],
	"enemies": ["id", "name"],
	"dialogues": ["id", "start", "nodes"],
	"cutscenes": ["id", "steps"],
	"chapters": ["id", "chapter", "title", "rooms"],
	"npcs": ["id", "name", "dialogue", "sprite"],
	"props": ["id", "kind", "sprite"],
}

var errors: PackedStringArray = []
var _dialogue_ids := {}
var _npc_ids := {}
## Room scene -> the chapter that claims it; two chapters may not claim one room.
var _room_chapter := {}
var used_keys := {}  # localization key -> where it is used


func _init() -> void:
	var strings := _load_csv("res://localization/strings.csv")
	var counts := {}
	for id in _load_entries("res://data/dialogues"):
		_dialogue_ids[id.get("id", "")] = true
	for id in _load_entries("res://data/npcs"):
		_npc_ids[id.get("id", "")] = true
	_check_enemy_archetypes()
	for collection in REQUIRED:
		var entries := _load_entries("res://data".path_join(collection))
		counts[collection] = entries.size()
		var ids := {}
		for entry in entries:
			_check_entry(collection, entry)
			if entry.has("id"):
				if ids.has(entry.id):
					_error("%s: duplicate id \"%s\"" % [collection, entry.id])
				ids[entry.id] = true
	for key in used_keys:
		if not strings.has(key):
			_error("missing localization key %s (used in %s)" % [key, used_keys[key]])
	for key in strings:
		for i in LOCALES.size():
			if strings[key][i].strip_edges() == "":
				_error("empty %s translation for %s" % [LOCALES[i], key])

	if errors.is_empty():
		print("OK: %s, %d localization keys x %d locales" % [counts, strings.size(), LOCALES.size()])
		quit(0)
	else:
		for e in errors:
			printerr("ERROR: " + e)
		printerr("%d error(s)" % errors.size())
		quit(1)


func _check_entry(collection: String, entry: Dictionary) -> void:
	var where := "%s/%s" % [collection, entry.get("id", "?")]
	for field in REQUIRED[collection]:
		if not entry.has(field):
			_error("%s: missing field \"%s\"" % [where, field])
	match collection:
		"abilities":
			_use_key(entry.get("name", ""), where)
			_use_key(entry.get("description", ""), where)
			if not PATHS.has(entry.get("path")):
				_error("%s: path must be one of %s" % [where, PATHS])
			if not RARITIES.has(entry.get("rarity", "common")):
				_error("%s: rarity must be one of %s" % [where, RARITIES])
			_use_key("RARITY_" + str(entry.get("rarity", "common")).to_upper(), where)
			for effect in entry.get("effects", []):
				if not EFFECT_TYPES.has(effect.get("type")):
					_error("%s: unknown effect type \"%s\"" % [where, effect.get("type")])
				elif effect.get("type") == "stat":
					if not STATS.has(effect.get("stat")):
						_error("%s: unknown stat \"%s\"" % [where, effect.get("stat")])
					if not ["add", "mul"].has(effect.get("op", "add")):
						_error("%s: op must be add or mul" % where)
				elif effect.get("type") == "skill":
					var spec: Dictionary = effect.get("skill", {})
					if not SKILL_KINDS.has(spec.get("kind")):
						_error("%s: skill.kind must be one of %s" % [where, SKILL_KINDS])
					for field in ["cooldown", "damage"]:
						if float(spec.get(field, 0)) <= 0.0:
							_error("%s: skill.%s must be positive" % [where, field])
					if not Color.html_is_valid(str(spec.get("color", ""))):
						_error("%s: skill.color must be #rrggbb" % where)
			_check_effect(entry.get("alignment", {}), where)
			if entry.has("icon") and not FileAccess.file_exists(str(entry.icon)) and not ResourceLoader.exists(str(entry.icon)):
				_error("%s: icon not found: %s" % [where, entry.icon])
		"enemies":
			_use_key(entry.get("name", ""), where)
			if entry.has("lore"):
				_use_key(entry.lore, where)
			for tag in entry.get("tags", []):
				_use_key("TAG_" + str(tag).to_upper(), where)  # the bestiary shows them
			if not entry.has("extends"):
				for field in ["hp", "speed", "damage"]:
					if not entry.has(field):
						_error("%s: missing field \"%s\"" % [where, field])
			if float(entry.get("armor", 0.0)) > 0.5:
				_error("%s: armor above the 50 %% cap" % where)
			if not BEHAVIOURS.has(entry.get("behaviour", "walker")):
				_error("%s: behaviour must be one of %s" % [where, BEHAVIOURS])
			if entry.has("sprite"):
				_check_sprite(entry.sprite, where)
			var attacks: Array = entry.get("attacks", [])
			if entry.has("attack"):
				attacks = attacks + [entry.attack]
			if entry.has("extends"):
				attacks = []  # partial overrides; the base entry is validated on its own
			for attack in attacks:
				if not ATTACK_TYPES.has(attack.get("type")):
					_error("%s: attack.type must be one of %s" % [where, ATTACK_TYPES])
				for field in ["windup", "damage", "cooldown"]:
					if float(attack.get(field, 0)) <= 0.0:
						_error("%s: attack.%s must be positive" % [where, field])
			if entry.has("summons") and not entry.summons.has("id"):
				_error("%s: summons.id missing" % where)
			if entry.has("light"):
				var light: Dictionary = entry.light
				if not Color.html_is_valid(str(light.get("color", entry.get("color", "")))):
					_error("%s: light.color must be #rrggbb" % where)
				if float(light.get("radius", 50)) <= 0.0 or float(light.get("energy", 0.7)) <= 0.0:
					_error("%s: light.radius and light.energy must be positive" % where)
			_check_awareness(entry, where)
			if entry.has("material") and not MATERIALS.has(entry.material):
				_error("%s: material must be one of %s" % [where, MATERIALS])
			if not entry.has("material") and not entry.has("extends"):
				_error("%s: no material — the sword would land on it silently" % where)
		"chapters":
			_use_key(entry.get("chapter", ""), where)
			_use_key(entry.get("title", ""), where)
			if entry.has("subtitle"):
				_use_key(entry.subtitle, where)
			if entry.has("color") and not Color.html_is_valid(str(entry.color)):
				_error("%s: color must be an html colour" % where)
			var rooms: Array = entry.get("rooms", [])
			if rooms.is_empty():
				_error("%s: a chapter with no rooms is never shown" % where)
			for scene in rooms:
				if not FileAccess.file_exists(str(scene)):
					_error("%s: room scene not found: %s" % [where, scene])
				if _room_chapter.has(scene):
					_error("%s: room %s is already claimed by %s" % [where, scene, _room_chapter[scene]])
				_room_chapter[scene] = entry.get("id", "?")
		"props":
			if not PROP_KINDS.has(entry.get("kind")):
				_error("%s: kind must be one of %s" % [where, PROP_KINDS])
			if entry.get("kind") == "destructible" and float(entry.get("hp", 0)) <= 0.0:
				_error("%s: a destructible needs positive hp" % where)
			_check_sprite(entry.get("sprite", {}), where)
			_check_effect(entry.get("effect", {}), where)
			if entry.get("hitbox", [1, 1]).size() != 2:
				_error("%s: hitbox must be [w, h]" % where)
			var icons = entry.get("icon", [])
			for icon in (icons if icons is Array else [icons]):
				if not FileAccess.file_exists(str(icon)) and not ResourceLoader.exists(str(icon)):
					_error("%s: icon not found: %s" % [where, icon])
		"npcs":
			_use_key(entry.get("name", ""), where)
			for key in ["lore", "role", "location"]:
				if entry.has(key):
					_use_key(entry[key], where)
			for line in entry.get("lines", []):
				_use_key(line, where)
			for point in entry.get("path", []):
				if point.size() != 2:
					_error("%s: path points must be [dx, dy]" % where)
			if entry.has("travel") and not entry.travel in ["walk", "fade"]:
				_error("%s: travel must be walk or fade" % where)
			if float(entry.get("wander", 0)) < 0.0:
				_error("%s: wander must be >= 0" % where)
			if entry.has("guard"):
				for field in ["range", "reach", "damage", "cooldown", "speed"]:
					if float(entry.guard.get(field, 1)) <= 0.0:
						_error("%s: guard.%s must be positive" % [where, field])
			_check_sprite(entry.get("sprite", {}), where)
			if entry.has("avatar") and not FileAccess.file_exists(str(entry.avatar)):
				_error("%s: avatar not found: %s" % [where, entry.avatar])
			if not _dialogue_ids.has(entry.get("dialogue", "")):
				_error("%s: unknown dialogue \"%s\"" % [where, entry.get("dialogue", "")])
		"cutscenes":
			_check_cutscene(entry, where)
		"dialogues":
			var nodes: Dictionary = entry.get("nodes", {})
			var blocking: bool = entry.get("blocking", true)
			if not nodes.has(entry.get("start", "")):
				_error("%s: start node \"%s\" not found" % [where, entry.get("start", "")])
			for node_id in nodes:
				var node: Dictionary = nodes[node_id]
				var node_where := "%s#%s" % [where, node_id]
				if node.has("branches"):  # a router node: flags -> next, no text
					for branch in node.branches:
						if not nodes.has(branch.get("next", "")):
							_error("%s: branch -> unknown node \"%s\"" % [node_where, branch.get("next", "")])
					if node.has("next") and not nodes.has(node.next):
						_error("%s: next -> unknown node \"%s\"" % [node_where, node.next])
					continue
				if not blocking and node.has("choices"):
					_error("%s: a non-blocking (caption) dialogue cannot have choices" % node_where)
				_use_key(node.get("speaker", ""), node_where)
				_use_key(node.get("text", ""), node_where)
				if node.has("next") and not nodes.has(node.next):
					_error("%s: next -> unknown node \"%s\"" % [node_where, node.next])
				for choice in node.get("choices", []):
					_use_key(choice.get("text", ""), node_where)
					if choice.has("next") and not nodes.has(choice.next):
						_error("%s: choice -> unknown node \"%s\"" % [node_where, choice.next])
					_check_effect(choice.get("effect", {}), node_where)


## Optional stealth tuning (scripts/enemies/enemy.gd): how far it sees, how it idles.
func _check_awareness(entry: Dictionary, where: String) -> void:
	if entry.has("aware") and not (entry.aware is bool):
		_error("%s: aware must be true or false" % where)
	var sight: Dictionary = entry.get("sight", {})
	for field in sight:
		if not ["range", "height", "behind"].has(field):
			_error("%s: unknown sight.%s" % [where, field])
		elif float(sight[field]) < 0.0 or (field != "behind" and float(sight[field]) <= 0.0):
			_error("%s: sight.%s must be positive" % [where, field])
	var patrol: Dictionary = entry.get("patrol", {})
	for field in patrol:
		match field:
			"radius":
				if float(patrol.radius) <= 0.0:
					_error("%s: patrol.radius must be positive" % where)
			"speed":
				if float(patrol.speed) <= 0.0 or float(patrol.speed) > 1.0:
					_error("%s: patrol.speed is a fraction of speed, in (0, 1]" % where)
			"pause":
				if not (patrol.pause is Array) or patrol.pause.size() != 2 \
						or float(patrol.pause[0]) < 0.0 or float(patrol.pause[1]) < float(patrol.pause[0]):
					_error("%s: patrol.pause must be [min, max] seconds" % where)
			_:
				_error("%s: unknown patrol.%s" % [where, field])


func _check_enemy_archetypes() -> void:
	for entry in _load_entries("res://data/enemy_archetypes"):
		var where := "enemy_archetypes/%s" % entry.get("id", "?")
		if not entry.has("id"):
			_error("%s: missing id" % where)
		if not FileAccess.file_exists(str(entry.get("avatar", ""))):
			_error("%s: avatar not found: %s" % [where, entry.get("avatar", "")])
		for attack in entry.get("attacks", []):
			if not ATTACK_TYPES.has(attack.get("type")):
				_error("%s: unknown attack type %s" % [where, attack.get("type")])
			for field in ["windup", "damage", "cooldown"]:
				if float(attack.get(field, 0)) <= 0.0:
					_error("%s: attack.%s must be positive" % [where, field])
		if entry.has("sprite"):
			for path in entry.sprite.get("animations", {}).values():
				if not FileAccess.file_exists(str(path)):
					_error("%s: sprite file not found: %s" % [where, path])


## Every step is a known kind with its required fields; actors and dialogue
## ids must exist; a scene that holds the controls must give them back.
func _check_cutscene(entry: Dictionary, where: String) -> void:
	var holds := 0
	for step in entry.get("steps", []):
		if not (step is Dictionary):
			_error("%s: steps must be objects" % where)
			continue
		var kind := str(step.get("do", ""))
		if not CUTSCENE_STEPS.has(kind):
			_error("%s: unknown step \"%s\"" % [where, kind])
			continue
		for field in CUTSCENE_STEPS[kind]:
			if not step.has(field):
				_error("%s: step %s needs \"%s\"" % [where, kind, field])
		if step.has("who"):
			_check_actor(step.who, where)
		if kind == "camera" and not (step.to is Array):
			_check_actor(step.to, where)
		if kind == "move" or kind == "walk":
			if not step.has("to") and not step.has("by"):
				_error("%s: step %s needs \"to\" or \"by\"" % [where, kind])
		if kind == "dialogue" and not _dialogue_ids.has(str(step.get("id", ""))):
			_error("%s: unknown dialogue \"%s\"" % [where, step.get("id", "")])
		if step.has("path") and not PATHS.has(str(step.path)):
			_error("%s: step %s: path must be one of %s" % [where, kind, PATHS])
		for key in ["if", "unless"]:
			if step.has(key) and not (step[key] is String or step[key] is Array):
				_error("%s: step %s: %s must be a flag or a list of flags" % [where, kind, key])
		if kind == "hold":
			holds += 1
		elif kind == "release":
			holds -= 1
	if holds > 0:
		_error("%s: holds the controls without a release" % where)


func _check_actor(who: Variant, where: String) -> void:
	var name := str(who)
	if CUTSCENE_ACTORS.has(name):
		return
	if name.begins_with("npc:"):
		if not _npc_ids.has(name.substr(4)):
			_error("%s: unknown NPC \"%s\"" % [where, name.substr(4)])
		return
	_error("%s: unknown actor \"%s\" (player, boss, door, npc:<id>)" % [where, name])


func _check_sprite(sprite: Dictionary, where: String) -> void:
	if sprite.has("animations"):
		if not sprite.has("cell") or sprite.cell.size() != 2:
			_error("%s: sprite.cell must be [w, h]" % where)
		if not sprite.animations.has("idle"):
			_error("%s: sprite.animations needs at least \"idle\"" % where)
		for anim in sprite.animations:
			if not ANIMATIONS.has(anim):
				_error("%s: unknown animation \"%s\" (known: %s)" % [where, anim, ANIMATIONS])
			if not FileAccess.file_exists(sprite.animations[anim]):
				_error("%s: sprite file not found: %s" % [where, sprite.animations[anim]])
	else:
		if not FileAccess.file_exists(sprite.get("path", "")):
			_error("%s: sprite file not found: %s" % [where, sprite.get("path", "")])
		elif sprite.has("cell"):  # one strip, frame count read from the texture
			if sprite.cell.size() != 2 or int(sprite.cell[0]) <= 0 or int(sprite.cell[1]) <= 0:
				_error("%s: sprite.cell must be [w, h]" % where)
		else:
			for field in ["frame_w", "frame_h", "frames"]:
				if int(sprite.get(field, 0)) <= 0:
					_error("%s: sprite.%s must be a positive integer" % [where, field])


func _check_effect(effect: Dictionary, where: String) -> void:
	for key in effect:
		if not PATHS.has(key) and key != "set_flags":
			_error("%s: unknown effect key \"%s\"" % [where, key])


func _use_key(key: String, where: String) -> void:
	if key == "":
		_error("%s: empty localization key" % where)
		return
	used_keys[key] = where


func _load_entries(dir_path: String) -> Array:
	var result := []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_error("missing folder %s" % dir_path)
		return result
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var path := dir_path.path_join(file_name)
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed == null:
			_error("invalid JSON: %s" % path)
			continue
		for entry in (parsed if parsed is Array else [parsed]):
			if entry is Dictionary:
				result.append(entry)
			else:
				_error("%s: entries must be objects" % path)
	return result


func _load_csv(path: String) -> Dictionary:
	var result := {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_error("cannot open %s" % path)
		return result
	var header := file.get_csv_line()
	var expected := PackedStringArray(["keys"] + LOCALES)
	if header != expected:
		_error("%s: header must be %s, got %s" % [path, ",".join(expected), ",".join(header)])
	var line_no := 1
	while not file.eof_reached():
		var line := file.get_csv_line()
		line_no += 1
		if line.size() == 1 and line[0] == "":
			continue
		if line.size() != expected.size():
			_error("%s:%d: expected %d columns, got %d" % [path, line_no, expected.size(), line.size()])
			continue
		if result.has(line[0]):
			_error("%s:%d: duplicate key %s" % [path, line_no, line[0]])
		result[line[0]] = line.slice(1)
	return result


func _error(message: String) -> void:
	errors.append(message)
