extends SceneTree
## Validates data files and localization without opening the editor:
##   godot --headless -s scripts/tools/validate_data.gd
## Exit code 1 when anything is wrong. Runs in CI on every pull request,
## so a content contributor gets feedback without launching Godot.

## Secret walls set into an arch the room's painting already has; every other
## one brings its own niche (tools/art/make_secret_walls.py).
const NICHE_PAINTED := ["secret_wall_catacombs"]
const LOCALES := ["en", "ru", "uk", "zh_CN"]
const PATHS := ["grace", "temptation", "will"]
const EFFECT_TYPES := ["stat", "lifesteal", "extra_life", "heal", "skill"]
const SKILL_KINDS := ["nova", "bolt", "drain", "toll", "hex", "blink"]
const RARITIES := ["common", "rare", "epic", "legendary"]
## Keys of Player.BASE_STATS a "stat" effect may touch. Duplicated on purpose:
## this script runs before the game's classes exist. Keep it in step.
const STATS := ["max_hp", "speed", "acceleration", "jump_velocity", "gravity", "max_jumps",
	"attack_damage", "attack_cooldown", "attack_scale", "crit_chance", "crit_multiplier",
	"backstab_multiplier", "dash_speed", "dash_time", "dash_cooldown", "armor", "lifesteal",
	"extra_lives", "heal_charges", "thorns", "execute", "kill_heal", "clear_heal", "dash_damage",
	"wave_damage", "guard", "essence_bonus", "friction", "slide_friction",
	"heal_burst", "parry_stun", "chest_heal", "backstab_refresh", "clean_clear_charge", "wrath_after_hit",
	"desperate_crit_heal", "technique_heal", "windup_bonus", "charge_speed", "parry_window",
	"cursed_damage", "chosen_damage", "curse_relief", "covetous"]
## The mechanics an item may carry (Player.BASE_STATS): interactions, not "+3 damage".
const ITEM_STATS := ["heal_burst", "parry_stun", "chest_heal", "backstab_refresh", "clean_clear_charge",
	"wrath_after_hit", "desperate_crit_heal"]
## The moves Player reports through EventBus.technique_performed.
const TECHNIQUES := ["lunge", "cleave", "sweep", "rising", "dash_strike", "slam", "wall_jump", "riposte", "backstab"]
const BEHAVIOURS := ["walker", "flyer", "boss_ophanim", "caster", "seal", "dummy"]
const ATTACK_TYPES := ["melee", "ranged", "lunge", "beam", "nova", "summon"]
## How a bolt may fly (scripts/fx/projectile.gd _advance_motion).
const PROJECTILE_MOTIONS := ["straight", "wave", "accelerate", "arc", "surge", "return", "home"]
const BURST_FX := ["sparkle", "ash", "debris", "spark"]
## The looks of data/projectiles.json, read in _check_projectiles: style -> frames.
var _flight_styles := {}
const ANIMATIONS := ["idle", "walk", "interact", "attack", "attack_alt", "special", "hurt", "death"]
const PROP_KINDS := ["destructible", "chest"]
## What a blade landing on this body sounds like (tools/audio/generate_voices.py).
const MATERIALS := ["flesh", "cloth", "mail", "plate", "bone", "feather", "spirit", "gold"]
## Cutscene steps (scripts/ui/cutscene.gd): step -> the fields it must carry.
const CUTSCENE_STEPS := {
	"hold": [], "release": [], "letterbox": [], "wait": ["time"], "camera": [],
	"title": [], "flash": [], "fx": ["kind"], "presence": [],
	"move": ["who"], "walk": ["who"], "anim": ["who", "anim"], "face": ["who", "dir"],
	"dialogue": ["id"], "shake": [], "sound": ["name"], "music": ["name"], "fade": ["to"],
	"appear": ["who"], "vanish": ["who"], "panel": ["image"], "panel_clear": [],
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
	"notes": ["id", "name", "dialogue"],
	"items": ["id", "name", "description", "rarity", "icon", "effects"],
	"rest_points": ["id", "at"],
	"skins": ["id", "name", "description", "unlock"],
	"techniques": ["id", "name", "input"],
	"forks": ["id", "after", "dialogue", "options", "then"],
	"achievements": ["id", "name", "description", "unlock"],
	"resonances": ["id", "name", "description", "needs", "effects"],
	"vials": ["id", "tier", "name", "description", "rules"],
	"relics": ["id", "name", "description", "cost", "effects"],
	"omens": ["id", "name", "description", "rules"],
	"affixes": ["id", "name", "color", "mods"],
}

var errors: PackedStringArray = []
## Printed and counted, but they do not fail the build. A line that reads the
## same in two languages is usually an untranslated string and occasionally the
## right answer, and CI is not the one who should decide which.
var warnings: PackedStringArray = []
var _dialogue_ids := {}
var _npc_ids := {}
var _prop_ids := {}
var _enemy_ids := {}
var _note_ids := {}
var _chapter_ids := {}
var _ability_paths := {}  # gift id -> its path
## Room scene -> the chapter that claims it; two chapters may not claim one room.
var _room_chapter := {}
var used_keys := {}  # localization key -> where it is used
## Story flags, both ways: who writes one and who ever looks at it. A flag
## written and never read is a choice the world forgot to react to; a flag
## read and never written is a branch no player will ever see. Both are
## silent — the game runs, the line simply never comes up — so they are
## checked rather than noticed.
var flags_set := {}
var flags_read := {}


func _init() -> void:
	var strings := _load_csv("res://localization/strings.csv")
	var counts := {}
	for id in _load_entries("res://data/dialogues"):
		_dialogue_ids[id.get("id", "")] = true
	for id in _load_entries("res://data/npcs"):
		_npc_ids[id.get("id", "")] = true
	for id in _load_entries("res://data/props"):
		_prop_ids[id.get("id", "")] = true
	for id in _load_entries("res://data/enemies"):
		_enemy_ids[id.get("id", "")] = bool(id.get("boss", false))
	for id in _load_entries("res://data/notes"):
		_note_ids[id.get("id", "")] = true
	for id in _load_entries("res://data/chapters"):
		_chapter_ids[id.get("id", "")] = true
	for gift in _load_entries("res://data/abilities"):
		_ability_paths[gift.get("id", "")] = str(gift.get("path", ""))
	_check_projectiles()
	_check_action_fx()
	_check_enemy_archetypes()
	_check_enemy_strips()
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
	_check_untranslated(strings)
	_check_cjk_font(strings)
	_check_glyphs(strings)
	_check_story_flags()
	_check_backdrops()

	for w in warnings:
		print("WARNING: " + w)
	if errors.is_empty():
		print("OK: %s, %d localization keys x %d locales%s"
			% [counts, strings.size(), LOCALES.size(),
			   "" if warnings.is_empty() else ", %d warning(s)" % warnings.size()])
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
					if spec.get("kind") == "bolt":
						_check_volley(spec, where + ": skill", str(spec.get("style", "sacred")), str(spec.get("motion", "straight")))
			_check_effect(entry.get("alignment", {}), where)
			if entry.has("icon") and not FileAccess.file_exists(str(entry.icon)) and not ResourceLoader.exists(str(entry.icon)):
				_error("%s: icon not found: %s" % [where, entry.icon])
		"enemies":
			_use_key(entry.get("name", ""), where)
			if entry.has("lore"):
				_use_key(entry.lore, where)
			# the advice the night's end gives when this one laid him low
			if entry.has("tip"):
				_use_key(entry.tip, where)
			elif entry.get("bestiary", true) and not ["seal", "dummy"].has(entry.get("behaviour", "walker")) \
					and not entry.has("extends"):
				_error("%s: an enemy that can kill needs a \"tip\" (how to meet it)" % where)
			# a boss is named on arrival by the cutscene's title card
			if entry.has("epithet"):
				_use_key(entry.epithet, where)
			elif entry.get("boss", false) and not entry.has("extends"):
				_error("%s: a boss needs an \"epithet\" for its title card" % where)
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
			if entry.has("seal_phase"):
				var phase: Dictionary = entry.seal_phase
				if not _enemy_ids.has(str(phase.get("seal", ""))):
					_error("%s: seal_phase.seal is not an enemy: %s" % [where, phase.get("seal", "")])
				if float(phase.get("at_hp", 0)) <= 0.0 or float(phase.get("at_hp", 0)) >= 1.0:
					_error("%s: seal_phase.at_hp is a share of health, in (0, 1)" % where)
				if float(phase.get("exposed", 0)) <= 0.0:
					_error("%s: seal_phase.exposed must be positive — the damage phase is the point" % where)
				for room in phase.get("points", {}):
					if not FileAccess.file_exists("res://scenes/rooms/%s.tscn" % room):
						_error("%s: seal_phase.points names no room: %s" % [where, room])
					if (phase.points[room] as Array).size() < 1:
						_error("%s: seal_phase.points.%s is empty" % [where, room])
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
			if entry.has("item") and (entry.get("kind") != "chest" or not ["common", "rare"].has(entry.item)):
				_error("%s: item is \"common\" or \"rare\", on a chest" % where)
			if entry.has("prompt"):
				_use_key(entry.prompt, where)
			if entry.has("interact") and not (entry.interact is bool and entry.get("kind") == "chest"):
				_error("%s: interact is true or false, on a chest" % where)
			if entry.has("requires_flag"):
				flags_read[str(entry.requires_flag)] = where  # the prop waits for it
			if entry.has("curse") and (entry.get("kind") != "chest" or not (entry.curse is float or entry.curse is int)
					or int(entry.curse) < 1 or int(entry.curse) > 30):
				_error("%s: curse is a number of kills (1–30), on a chest" % where)
			if entry.has("blood_price") and (not entry.get("interact", false)
					or float(entry.blood_price) < 0.05 or float(entry.blood_price) > 0.3):
				_error("%s: blood_price is a share of the bar (0.05–0.3), on a chest opened by hand (interact)" % where)
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
			if entry.has("reveals"):
				if entry.get("kind") != "destructible":
					_error("%s: only a destructible can hide another prop" % where)
				if not _prop_ids.has(entry.reveals) or entry.reveals == entry.get("id"):
					_error("%s: reveals unknown prop %s" % [where, entry.reveals])
			if entry.has("niche") and not FileAccess.file_exists(str(entry.niche)) and not ResourceLoader.exists(str(entry.niche)):
				_error("%s: niche not found: %s" % [where, entry.niche])
			if entry.has("reveals") and entry.get("still", false) and not entry.has("niche") \
					and not NICHE_PAINTED.has(entry.get("id")):
				_error("%s: a secret wall needs a doorway to brick up: a niche, or an arch the painting has (NICHE_PAINTED)" % where)
			if entry.has("note") and not _note_ids.has(entry.note):
				_error("%s: unknown note %s" % [where, entry.note])
			if int(entry.get("ash", 0)) > 0 and not entry.has("note"):
				_error("%s: ash is paid once per record; a cache with ash needs a note" % where)
		"items":
			_use_key(entry.get("name", ""), where)
			_use_key(entry.get("description", ""), where)
			if not ["common", "rare"].has(entry.get("rarity", "")):
				_error("%s: rarity must be common or rare" % where)
			if not ResourceLoader.exists(str(entry.get("icon", ""))):
				_error("%s: icon not found: %s" % [where, entry.get("icon", "")])
			for effect in entry.get("effects", []):
				# an item changes how something behaves: a mechanic stat, never a raw number
				if effect.get("type") != "stat" or not ITEM_STATS.has(effect.get("stat")):
					_error("%s: an item's effect is one of the item mechanics %s" % [where, ITEM_STATS])
		"forks":
			_check_fork(entry, where)
		"techniques":
			_use_key(entry.get("name", ""), where)
			_use_key(entry.get("input", ""), where)
			# the moves the yard lists are the ones the body can do
			if not TECHNIQUES.has(entry.get("id", "")):
				_error("%s: no such move in Player (known: %s)" % [where, TECHNIQUES])
		"achievements":
			_check_achievement(entry, where)
		"resonances":
			_check_resonance(entry, where)
		"vials":
			_check_vial(entry, where)
		"relics":
			_check_relic(entry, where)
		"omens":
			_check_omen(entry, where)
		"affixes":
			_use_key(entry.get("name", ""), where)
			for key in entry.get("mods", {}):
				var value := float(entry.mods[key])
				match key:
					"hp", "damage", "speed", "cooldown":
						if value < 0.5 or value > 2.0:
							_error("%s: mods.%s is a multiplier, 0.5..2" % [where, key])
					"armor":
						if value < 0.0 or value > 0.3:
							_error("%s: mods.armor adds 0..0.3 (an elite stays killable)" % where)
					_:
						_error("%s: mods.%s is not hp, damage, speed, cooldown or armor" % [where, key])
		"skins":
			_use_key(entry.get("name", ""), where)
			_use_key(entry.get("description", ""), where)
			for key in entry.get("unlock", {}):
				if not ["nights", "total_kills", "kills"].has(key):
					_error("%s: unlock.%s is not nights, total_kills or kills" % [where, key])
			for enemy in entry.get("unlock", {}).get("kills", {}):
				if not _enemy_ids.has(enemy):
					_error("%s: unlock.kills names no enemy: %s" % [where, enemy])
			var sku := str(entry.get("sku", ""))
			if sku != "" and not (sku.begins_with("steam:") and sku.trim_prefix("steam:").is_valid_int()):
				_error("%s: sku is \"steam:<dlc app id>\" (StoreBridge.owns knows no other store yet): %s" % [where, sku])
			var cloak: Dictionary = entry.get("cloak", {})
			if float(cloak.get("hue", 0.0)) < 0.0 or float(cloak.get("hue", 0.0)) > 1.0:
				_error("%s: cloak.hue is 0..1" % where)
			if entry.has("armor") and not Color.html_is_valid(str(entry.armor)):
				_error("%s: armor must be #rrggbb" % where)
		"rest_points":
			# the id is the room it stands in
			if not FileAccess.file_exists("res://scenes/rooms/%s.tscn" % entry.get("id", "")):
				_error("%s: no room scene of that name" % where)
			var at = entry.get("at", [])
			if not at is Array or at.size() != 2:
				_error("%s: at is [x, y] on the room's floor" % where)
		"notes":
			_use_key(entry.get("name", ""), where)
			if not _dialogue_ids.has(entry.get("dialogue", "")):
				_error("%s: unknown dialogue %s" % [where, entry.get("dialogue", "")])
			if entry.has("place") and not _chapter_ids.has(entry.place):
				_error("%s: unknown place %s" % [where, entry.place])
			if entry.has("avatar") and not ResourceLoader.exists(str(entry.avatar)):
				_error("%s: avatar not found: %s" % [where, entry.avatar])
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
						if branch.has("flag"):
							flags_read[str(branch.flag)] = node_where
						for key in ["path", "habit"]:
							if branch.has(key) and not PATHS.has(str(branch[key])):
								_error("%s: branch %s \"%s\" is not one of %s" % [node_where, key, branch[key], PATHS])
						if branch.has("vial") and (int(branch.vial) < 1 or int(branch.vial) > 5):
							_error("%s: branch vial is 1..5" % node_where)
						if branch.has("omen") and not _omen_ids().has(str(branch.omen)):
							_error("%s: branch omen \"%s\" names no omen in data/omens" % [node_where, branch.omen])
						if not (branch.has("flag") or branch.has("path") or branch.has("habit") or branch.has("vial") or branch.has("omen")):
							_error("%s: a branch needs a flag, a path, a habit, a vial or an omen to test" % node_where)
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
			_check_reachable(entry, where)


## The Chinese is drawn with a subset of Noto Serif SC holding exactly the
## characters the game used when it was generated (tools/art/make_cjk_font.py).
## Add a line of Chinese with a character outside it and a desktop still looks
## right — Godot falls back to a system font — while the Web build, which has
## no system fonts, draws tofu. Nobody would catch that until a player did, so
## it is checked here instead.
const CJK_FONT := "res://assets/fonts/NotoSerifSC-Subset.ttf"


func _check_cjk_font(strings: Dictionary) -> void:
	if not ResourceLoader.exists(CJK_FONT):
		_error("%s is missing — run tools/art/make_cjk_font.py" % CJK_FONT)
		return
	var font: FontFile = load(CJK_FONT)
	if font == null:
		_error("%s will not load as a font" % CJK_FONT)
		return
	var zh := LOCALES.find("zh_CN")
	var missing := {}
	for key in strings:
		for ch in strings[key][zh]:
			# Below U+2000 is ASCII and punctuation the Latin faces cover.
			if ch.unicode_at(0) > 0x2000 and not font.has_char(ch.unicode_at(0)):
				missing[ch] = key
	if missing.is_empty():
		return
	var chars := missing.keys()
	chars.sort()
	_error("%d character(s) in the zh_CN text are not in the subsetted font: %s "
		% [chars.size(), "".join(chars).left(40)]
		+ "(first seen in %s) — run tools/art/make_cjk_font.py and commit the result"
		% missing[chars[0]])


## Every character the game can put on screen must be in a font it ships: the
## Latin face (EB Garamond, which Forum falls back to) or the CJK subset. A
## desktop hides a gap behind a system font; the Web draws a box — "▸" in the
## talk prompt and "✓ ★" in the move list did exactly that. Checks every
## locale's strings and the non-ASCII literals in scripts, scenes and data.
const BODY_FONT := "res://assets/fonts/EBGaramond-Variable.ttf"


func _check_glyphs(strings: Dictionary) -> void:
	var body: FontFile = load(BODY_FONT)
	var cjk: FontFile = load(CJK_FONT)
	if body == null or cjk == null:
		return
	var missing := {}
	for key in strings:
		for text in strings[key]:
			_note_missing(str(text), body, cjk, missing, key)
	for path in _files_under("res://scripts", ["gd"]) + _files_under("res://scenes", ["tscn"]) \
			+ _files_under("res://data", ["json"]):
		if path.begins_with("res://scripts/tools/"):
			continue
		_note_missing(FileAccess.get_file_as_string(path), body, cjk, missing, path, true)
	if missing.is_empty():
		return
	var chars := missing.keys()
	chars.sort()
	for ch in chars:
		_error("'%s' (U+%04X, in %s) is in no font the game ships: the Web build draws a box. "
			% [ch, ch.unicode_at(0), missing[ch]]
			+ "Use another mark, or add it to the marks in tools/art/make_cjk_font.py and rerun it")


## [param literals_only]: in source, only what sits between double quotes is
## ever drawn; comments may say what they like.
func _note_missing(text: String, body: FontFile, cjk: FontFile, missing: Dictionary, where: String,
		literals_only := false) -> void:
	var inside := not literals_only
	for i in text.length():
		var code := text.unicode_at(i)
		if literals_only:
			if code == 0x22:
				inside = not inside
				continue
			if code == 0x0A:
				inside = false
		if not inside or code < 0x80 or code == 0xFEFF:
			continue
		if not body.has_char(code) and not cjk.has_char(code):
			missing[text[i]] = where


func _files_under(dir: String, extensions: Array) -> Array:
	var found: Array = []
	for file in DirAccess.get_files_at(dir):
		if extensions.has(file.get_extension()):
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_files_under(dir.path_join(sub), extensions))
	return found


## A translation identical to the English is, nine times in ten, a line that
## was copied across to fill the column and never came back. It is a warning
## and not an error because the tenth time it is correct: a name, a number, a
## dash, a word that is the same in both languages. Those cases are listed
## below so the warning list stays short enough to read.
##
## Chinese is exempt: a zh_CN cell that matched the English would be caught by
## eye immediately, and the ones that legitimately match (numerals, "—") are
## the same ones listed here anyway.
const SAME_IN_ANY_LANGUAGE := ["—", "-", "...", "…", "?", "!", "Elian", "Ophanim"]


func _check_untranslated(strings: Dictionary) -> void:
	for key in strings:
		var english: String = strings[key][0].strip_edges()
		if english == "" or english in SAME_IN_ANY_LANGUAGE or english.is_valid_float():
			continue
		for i in range(1, LOCALES.size()):
			if LOCALES[i] == "zh_CN":
				continue
			if strings[key][i].strip_edges() == english:
				_warn("%s reads the same as en for %s (\"%s\")"
					% [LOCALES[i], key, english.left(40)])


## Every node has to be walkable to from "start". A node nobody points at is
## dead weight: a line somebody wrote, translated into four languages, and
## then orphaned by rewiring the branch that used to reach it. It costs
## nothing at runtime and it is almost always a mistake, so it is an error
## rather than a warning — deleting it is one line, and so is linking it back.
func _check_reachable(entry: Dictionary, where: String) -> void:
	var nodes: Dictionary = entry.get("nodes", {})
	var start := str(entry.get("start", ""))
	if not nodes.has(start):
		return  # already reported; walking from a node that does not exist finds nothing
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var node: Dictionary = nodes[queue.pop_back()]
		for next in _exits(node):
			if nodes.has(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	var orphans: Array = []
	for node_id in nodes:
		if not seen.has(node_id):
			orphans.append(str(node_id))
	if not orphans.is_empty():
		orphans.sort()
		_error("%s: node(s) unreachable from \"%s\": %s" % [where, start, ", ".join(orphans)])


## Everywhere one node can hand off to another: straight on, through an answer,
## or through a router's branches and its fallback.
func _exits(node: Dictionary) -> Array:
	var out: Array = []
	if node.has("next"):
		out.append(str(node.next))
	for choice in node.get("choices", []):
		if choice.has("next"):
			out.append(str(choice.next))
	for branch in node.get("branches", []):
		if branch.has("next"):
			out.append(str(branch.next))
	return out


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


## Every strip a creature plays is cut on its cell, as merged (base file plus
## archetype): a width that is not a whole number of frames plays a sliver of
## the next pose, a wrong height slides the feet off the floor. Every bolt it
## throws is one of the animated flights, not the static fallback.
func _check_enemy_strips() -> void:
	# merged the way Data merges them (-s runs before the autoloads exist)
	var enemies := {}
	for entry in _load_entries("res://data/enemies"):
		enemies[entry.get("id", "")] = entry.duplicate(true)
	for overlay in _load_entries("res://data/enemy_archetypes"):
		var base: Dictionary = enemies.get(overlay.get("id", ""), {})
		for key in overlay:
			if key == "sprite" and base.get("sprite") is Dictionary:
				base.sprite.merge(overlay.sprite, true)
			elif key != "id":
				base[key] = overlay[key]
		if overlay.has("attacks"):
			base.erase("attack")
	for id in enemies:
		var spec: Dictionary = enemies[id].get("sprite", {})
		if spec.has("like"):
			spec = enemies.get(str(spec.like), {}).get("sprite", {})
		if spec.has("animations") and spec.has("cell"):
			var cell := Vector2i(int(spec.cell[0]), int(spec.cell[1]))
			for anim in spec.animations:
				var texture = load(str(spec.animations[anim]))
				if texture == null:
					continue
				var size: Vector2i = texture.get_size()
				if size.x % cell.x != 0 or size.y != cell.y:
					_error("enemies/%s: %s is %dx%d, not whole %dx%d frames" % [id, anim, size.x, size.y, cell.x, cell.y])
		var attacks: Array = enemies[id].get("attacks", [])
		if enemies[id].has("attack"):
			attacks = attacks + [enemies[id].attack]
		for attack in attacks:
			if attack.has("telegraph_fx") and not attack.telegraph_fx in ["glow", "none"]:
				_error("enemies/%s: telegraph_fx must be glow or none" % id)
			if attack.has("impact_fx") and (attack.get("type") != "nova" or not attack.impact_fx in ["magic", "dust", "none"]):
				_error("enemies/%s: impact_fx must be magic, dust or none on a nova" % id)
			if attack.has("hit_frame"):
				var frame := float(attack.hit_frame)
				var animation := str(attack.get("animation", "attack"))
				var texture = load(str(spec.get("animations", {}).get(animation, "")))
				if texture == null or frame < 0 or frame != floorf(frame) or frame >= texture.get_width() / int(spec.get("cell", [24, 28])[0]):
					_error("enemies/%s: hit_frame must name an existing zero-based animation frame" % id)
			if attack.get("type") == "ranged":
				var style := str(attack.get("projectile_style", ""))
				if int(_flight_styles.get(style, 0)) < 2:
					_error("enemies/%s: a ranged attack needs an animated projectile_style from data/projectiles.json (%s)"
						% [id, ", ".join(_flight_styles.keys().filter(func(k): return int(_flight_styles[k]) > 1))])
				_check_volley(attack, "enemies/" + id, style, str(attack.get("projectile_motion", "straight")))


## data/projectiles.json: every look a bolt can take, its strip whole frames.
func _check_projectiles() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/projectiles.json"))
	if not parsed is Dictionary or not parsed.get("styles") is Dictionary:
		_error("data/projectiles.json: needs a \"styles\" object")
		return
	for key in parsed.styles:
		var look: Dictionary = parsed.styles[key]
		var where := "projectiles/%s" % key
		var frames := int(look.get("frames", 1))
		_flight_styles[key] = frames
		var texture = load(str(look.get("sheet", ""))) if ResourceLoader.exists(str(look.get("sheet", ""))) else null
		if texture == null:
			_error("%s: sheet not found: %s" % [where, look.get("sheet", "")])
		elif frames < 1 or texture.get_width() % frames != 0:
			_error("%s: %s is %d px wide, not %d whole frames" % [where, look.sheet, texture.get_width(), frames])
		if frames > 1 and float(look.get("fps", 10)) <= 0.0:
			_error("%s: an animated strip needs a positive fps" % where)
		if not float(look.get("scale", 0.62)) > 0.0:
			_error("%s: scale must be positive" % where)
		for part in look.get("burst", []):
			if not BURST_FX.has(str(part.get("fx", ""))):
				_error("%s: burst fx must be one of %s" % [where, BURST_FX])
	for needed in ["blade", "sacred"]:   # the player's swing wave and a parried bolt
		if not _flight_styles.has(needed):
			_error("data/projectiles.json: the %s style is needed by the game itself" % needed)


## A ranged attack or a bolt skill: a known style and motion, and a volley that stays readable.
func _check_volley(attack: Dictionary, where: String, style: String, motion: String) -> void:
	if not _flight_styles.has(style):
		_error("%s: projectile style %s is not in data/projectiles.json" % [where, style])
	var amount := float(attack.get("motion_amount", 0.0))
	if not PROJECTILE_MOTIONS.has(motion):
		_error("%s: unknown projectile motion %s" % [where, motion])
	elif motion != "straight" and amount <= 0.0:
		_error("%s: %s needs positive motion_amount" % [where, motion])
	elif motion == "return" and amount >= 4.0:
		_error("%s: return must turn before the projectile expires" % where)
	elif motion == "home" and amount > 4.0:
		_error("%s: a bolt that turns faster than 4 rad/s cannot be dodged" % where)
	var volley := int(attack.get("volley", 1))
	if volley < 1 or volley > 5:
		_error("%s: volley must be 1..5 rounds" % where)
	if volley > 1 and not (float(attack.get("volley_gap", 0.25)) >= 0.08 and float(attack.get("volley_gap", 0.25)) <= 1.5):
		_error("%s: volley_gap must be 0.08..1.5 s" % where)
	if float(attack.get("speed_jitter", 0.0)) < 0.0 or float(attack.get("speed_jitter", 0.0)) > 0.5:
		_error("%s: speed_jitter must be 0..0.5" % where)
	var size := float(attack.get("projectile_scale", 1.0))
	if size < 0.4 or size > 2.5:
		_error("%s: projectile_scale must be 0.4..2.5" % where)
	if int(attack.get("projectiles", 1)) < 1 or int(attack.get("projectiles", 1)) > 9:
		_error("%s: projectiles must be 1..9" % where)


## data/action_fx.json: every emitter names a kind and an anchor ActionFx knows,
## every trigger is an event the game sends or a name an animation could have.
func _check_action_fx() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/action_fx.json"))
	if not parsed is Dictionary or not parsed.get("bodies") is Dictionary:
		_error("data/action_fx.json: needs a \"bodies\" object")
		return
	var fx_kinds := ["dust", "puff", "sparkle", "ash", "debris", "ring", "flash"]   # ActionFx.KINDS
	var anchors := ["feet", "body", "head", "hand", "back"]   # ActionFx.ANCHORS
	for body_key in parsed.bodies:
		if body_key != "elian" and not _enemy_ids.has(body_key):
			_error("action_fx/%s: no such body (elian or an enemy id)" % body_key)
		for trigger in parsed.bodies[body_key]:
			for spec in parsed.bodies[body_key][trigger]:
				var where := "action_fx/%s/%s" % [body_key, trigger]
				if not fx_kinds.has(str(spec.get("fx", ""))):
					_error("%s: fx must be one of %s" % [where, fx_kinds])
				if not anchors.has(str(spec.get("at", "feet"))):
					_error("%s: at must be one of %s" % [where, anchors])
				if not ["start", "frames", "every"].has(str(spec.get("when", "start"))):
					_error("%s: when must be start, frames or every" % where)
				if str(spec.get("when", "")) == "every" and float(spec.get("every", 0.3)) < 0.05:
					_error("%s: every must be at least 0.05 s" % where)
				if int(spec.get("count", 6)) < 1 or int(spec.get("count", 6)) > 60:
					_error("%s: count must be 1..60" % where)
				if spec.has("color") and not Color.html_is_valid(str(spec.color)):
					_error("%s: color must be #rrggbb or #rrggbbaa" % where)


## A deed (data/achievements, scripts/meta/achievements.gd): every condition is
## one Achievements reads, names what exists, and asks for at least one.
func _check_achievement(entry: Dictionary, where: String) -> void:
	_use_key(entry.get("name", ""), where)
	_use_key(entry.get("description", ""), where)
	var counters := _deed_counters()
	var unlock: Dictionary = entry.get("unlock", {})
	if unlock.is_empty():
		_error("%s: a deed with no condition would never be done" % where)
	if not str(entry.id).is_valid_identifier():
		_error("%s: the id is also the store's API name: letters, digits, _" % where)
	if int(entry.get("ash", 0)) < 0 or int(entry.get("ash", 0)) > 50:
		_error("%s: ash is 0..50 (docs/BALANCE.md: permanent power stays small)" % where)
	for key in unlock:
		if not ["nights", "wins", "total_kills", "kills", "known", "notes", "items", "affixes", "moves", "deeds", "fast"].has(key):
			_error("%s: unlock.%s is not a condition Achievements reads" % [where, key])
	for key in ["nights", "wins", "total_kills"]:
		if unlock.has(key) and int(unlock[key]) < 1:
			_error("%s: unlock.%s must be at least 1" % [where, key])
	for key in ["known", "notes", "items", "affixes"]:
		if unlock.has(key) and str(unlock[key]) != "all" and int(unlock[key]) < 1:
			_error("%s: unlock.%s is a number or \"all\"" % [where, key])
	for enemy in unlock.get("kills", {}):
		if not _enemy_ids.has(enemy):
			_error("%s: unlock.kills names no enemy: %s" % [where, enemy])
	var moves = unlock.get("moves", [])
	if str(moves) != "all":
		for move in moves:
			if not TECHNIQUES.has(move):
				_error("%s: unlock.moves names no move: %s" % [where, move])
	for boss in unlock.get("fast", {}):
		if not bool(_enemy_ids.get(boss, false)):
			_error("%s: unlock.fast names no boss: %s" % [where, boss])
		elif float(unlock.fast[boss]) <= 0.0:
			_error("%s: unlock.fast.%s is a time in seconds" % [where, boss])
	for counter in unlock.get("deeds", {}):
		if not counters.has(counter):
			_error("%s: unlock.deeds.%s is not counted (Achievements.COUNTERS: %s)" % [where, counter, counters])


## A resonance (data/resonances, scripts/combat/resonances.gd): a count of one
## path's gifts a path can reach, or two gifts or more that exist, of more than
## one path (a pair within a path is what the count is for). Its effects are
## mechanics the caps hold, like a gift's.
func _check_resonance(entry: Dictionary, where: String) -> void:
	_use_key(entry.get("name", ""), where)
	_use_key(entry.get("description", ""), where)
	var needs: Dictionary = entry.get("needs", {})
	if needs.has("path"):
		var count := int(needs.get("count", 0))
		var offered := _ability_paths.values().count(str(needs.path))
		if not PATHS.has(str(needs.path)):
			_error("%s: needs.path must be one of %s" % [where, PATHS])
		elif count < 2 or count > offered:
			_error("%s: needs.count is 2..%d (the gifts %s has)" % [where, offered, needs.path])
	elif needs.has("gifts"):
		var paths := {}
		for gift in needs.gifts:
			if not _ability_paths.has(gift):
				_error("%s: needs.gifts names no gift: %s" % [where, gift])
			else:
				paths[_ability_paths[gift]] = true
		if needs.gifts.size() < 2 or paths.size() < 2:
			_error("%s: a pair of gifts crosses paths (within one path the count does it)" % where)
	else:
		_error("%s: needs is {path, count} or {gifts}" % where)
	for effect in entry.get("effects", []):
		if effect.get("type") != "stat" or not STATS.has(effect.get("stat")):
			_error("%s: a resonance's effect is a stat from Player.BASE_STATS" % where)
		elif not ["add", "mul"].has(effect.get("op", "add")):
			_error("%s: op is add or mul" % where)
	if entry.get("effects", []).is_empty():
		_error("%s: a resonance that does nothing" % where)


## A relic (data/relics, scripts/meta/relics.gd): bought with Ash, once. A stat
## is one Player.BASE_STATS has; a reroll is one more deal of the gift cards.
## The "early_" relics are made from the late gifts in code and need no entry.
func _check_relic(entry: Dictionary, where: String) -> void:
	_use_key(entry.get("name", ""), where)
	_use_key(entry.get("description", ""), where)
	if int(entry.get("cost", 0)) <= 0:
		_error("%s: a relic costs Ash" % where)
	if str(entry.id).begins_with("early_"):
		_error("%s: early_ relics are made from the late gifts, not written" % where)
	for effect in entry.get("effects", []):
		match str(effect.get("type", "")):
			"stat":
				if not STATS.has(effect.get("stat")):
					_error("%s: no such stat %s" % [where, effect.get("stat")])
			"reroll":
				pass
			_:
				_error("%s: a relic's effect is a stat or a reroll" % where)
	if entry.has("needs") and not FileAccess.get_file_as_string("res://data/relics/reliquary.json").contains('"%s"' % entry.needs):
		_error("%s: needs names no relic" % where)


## A vial of wrath (data/vials, scripts/run/vials.gd): a tier 1..5 once each,
## rules Vials knows how to stack, a promotion only to an elite of that kind.
var _vial_tiers := {}
var _omens_read := {}


## Every omen id in data/omens, read straight from the files (a dialogue may
## be checked before the omens are).
func _omen_ids() -> Dictionary:
	if _omens_read.is_empty():
		var dir := DirAccess.open("res://data/omens")
		if dir != null:
			for file in dir.get_files():
				if file.ends_with(".json"):
					var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/omens/" + file))
					for entry in (parsed if parsed is Array else [parsed]):
						if entry is Dictionary:
							_omens_read[str(entry.get("id", ""))] = true
	return _omens_read


func _check_vial(entry: Dictionary, where: String) -> void:
	_use_key(entry.get("name", ""), where)
	_use_key(entry.get("description", ""), where)
	var tier := int(entry.get("tier", 0))
	if tier < 1 or tier > 5 or _vial_tiers.has(tier):
		_error("%s: tier is 1..5 and each once" % where)
	_vial_tiers[tier] = true
	if float(entry.get("ash", 1.0)) < 1.0:
		_error("%s: a vial never pays less than a plain night" % where)
	var rules: Dictionary = entry.get("rules", {})
	for key in rules:
		if not ["flasks", "enemy_damage", "enemy_hp", "promote_chance", "rest_heal", "promote"].has(key):
			_error("%s: rules.%s is not a rule Vials stacks" % [where, key])
	for from in rules.get("promote", {}):
		var to := str(rules.promote[from])
		if not _enemy_ids.has(from) or not _enemy_ids.has(to):
			_error("%s: promote %s -> %s names no enemy" % [where, from, to])
	if float(rules.get("promote_chance", 0.0)) > 1.0 or float(rules.get("rest_heal", 1.0)) <= 0.0:
		_error("%s: promote_chance is 0..1 and rest_heal above 0" % where)


## An omen (data/omens, scripts/run/omens.gd): a trade — at least one rule
## that helps and one that hurts — in rules Vials stacks, plus "essence" and
## "ash", never a pay below a plain night.
func _check_omen(entry: Dictionary, where: String) -> void:
	_use_key(entry.get("name", ""), where)
	_use_key(entry.get("description", ""), where)
	var rules: Dictionary = entry.get("rules", {})
	var helps := false
	var hurts := false
	for key in rules:
		var value = rules[key]
		match key:
			"essence", "ash":
				helps = helps or float(value) > 1.0
				hurts = hurts or float(value) < 1.0
			"flasks":
				helps = helps or int(value) > 0
				hurts = hurts or int(value) < 0
			"enemy_damage", "enemy_hp", "skill_cooldown":
				hurts = hurts or float(value) > 1.0
				helps = helps or float(value) < 1.0
			"enemy_sight":
				helps = helps or float(value) < 1.0
				hurts = hurts or float(value) > 1.0
			"promote_chance":
				hurts = hurts or float(value) > 0.0
				if float(value) > 1.0:
					_error("%s: promote_chance is 0..1" % where)
			"rest_heal":
				hurts = hurts or float(value) < 1.0
				if float(value) <= 0.0:
					_error("%s: rest_heal above 0" % where)
			"promote":
				for from in value:
					if not _enemy_ids.has(from) or not _enemy_ids.has(str(value[from])):
						_error("%s: promote %s -> %s names no enemy" % [where, from, value[from]])
			_:
				_error("%s: rules.%s is not a rule an omen can carry" % [where, key])
	if not (helps and hurts):
		_error("%s: an omen is a trade: something that helps and something that hurts" % where)
	if rules.has("promote_chance") != rules.has("promote"):
		_error("%s: promote_chance and promote come together" % where)


## Achievements.COUNTERS, read from the source: that script names autoloads,
## which a tool script (-s) cannot load before they exist.
func _deed_counters() -> Array:
	var source := FileAccess.get_file_as_string("res://scripts/meta/achievements.gd")
	var found := RegEx.create_from_string("const COUNTERS := \\[([^\\]]*)\\]").search(source)
	if found == null:
		_error("scripts/meta/achievements.gd: no COUNTERS list to check deeds against")
		return []
	var counters := []
	for name in RegEx.create_from_string("\"([a-z0-9_]+)\"").search_all(found.get_string(1)):
		counters.append(name.get_string(1))
	return counters


## A fork (data/forks, scripts/run/route.gd) splits the chapter's way and
## joins it again. Its rooms must exist, its question must be a dialogue
## whose answers are its options, and no option may carry story: a scene, a
## person, a rest point — the night that did not take that way would lose it.
func _check_fork(entry: Dictionary, where: String) -> void:
	for key in ["after", "then"]:
		if not FileAccess.file_exists(str(entry.get(key, ""))):
			_error("%s: %s room not found: %s" % [where, key, entry.get(key, "")])
	var options: Dictionary = entry.get("options", {})
	if options.size() < 2:
		_error("%s: a fork needs two ways at least" % where)
	var question: Dictionary = {}
	for dialogue in _load_entries("res://data/dialogues"):
		if dialogue.get("id", "") == entry.get("dialogue", ""):
			question = dialogue
	if question.is_empty():
		_error("%s: no dialogue %s asks the way" % [where, entry.get("dialogue", "")])
	else:
		var answers := {}
		for node in question.get("nodes", {}).values():
			for choice in node.get("choices", []):
				answers[str(choice.get("id", ""))] = true
		for key in options:
			if not answers.has(key):
				_error("%s: no answer in %s picks the way \"%s\"" % [where, question.id, key])
	var rested := {}
	for point in _load_entries("res://data/rest_points"):
		rested[str(point.get("id", ""))] = true
	for key in options:
		var path := str(options[key])
		if not FileAccess.file_exists(path):
			_error("%s: option %s not found: %s" % [where, key, path])
			continue
		var scene := FileAccess.get_file_as_string(path)
		var story := []
		for field in ["intro_cutscene", "outro_cutscene", "intro_dialogue"]:
			var at := scene.find(field + " = \"")
			if at >= 0 and scene.substr(at + field.length() + 4, 1) != "\"":
				story.append(field)
		if scene.find("npc_id = ") >= 0:
			story.append("a person")
		if rested.has(path.get_file().get_basename()):
			story.append("a rest point")
		if not story.is_empty():
			_error("%s: %s carries story (%s) and cannot be a way some nights skip" % [where, path.get_file(), ", ".join(story)])


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
		if kind == "camera":
			if step.has("between"):
				if not (step.between is Array) or step.between.size() != 2:
					_error("%s: camera between needs two actors" % where)
				else:
					for actor in step.between:
						_check_actor(actor, where)
			elif not step.has("to"):
				_error("%s: step camera needs \"to\" or \"between\"" % where)
			elif not (step.to is Array):
				_check_actor(step.to, where)
		if (kind == "move" or kind == "walk") and step.has("to") and not (step.to is Array):
			_check_actor(step.to, where)
		if kind == "fx":
			if not ["ash", "sparkle", "dust", "puff", "light", "debris"].has(str(step.kind)):
				_error("%s: fx kind must be ash, sparkle, dust, puff, light or debris" % where)
			if step.has("at") and not (step.at is Array):
				_check_actor(step.at, where)
		if kind == "title":
			if not step.has("who") and not step.has("name"):
				_error("%s: a title needs \"who\" or \"name\"" % where)
			if step.has("at") and not ["top", "bottom"].has(str(step.at)):
				_error("%s: a title stands at \"top\" or \"bottom\"" % where)
			for key in ["name", "subtitle"]:
				if step.has(key):
					_use_key(step[key], where)
		if kind == "dialogue" and step.has("cast"):
			if not (step.cast is Dictionary):
				_error("%s: cast must map speakers to actors" % where)
			else:
				for speaker in step.cast:
					_use_key(speaker, where)
					_check_actor(step.cast[speaker], where)
		if kind == "move" or kind == "walk":
			if not step.has("to") and not step.has("by"):
				_error("%s: step %s needs \"to\" or \"by\"" % [where, kind])
		if kind == "dialogue" and not _dialogue_ids.has(str(step.get("id", ""))):
			_error("%s: unknown dialogue \"%s\"" % [where, step.get("id", "")])
		if kind == "panel" and not FileAccess.file_exists(str(step.get("image", ""))):
			_error("%s: missing cutscene panel \"%s\"" % [where, step.get("image", "")])
		if step.has("path") and not PATHS.has(str(step.path)):
			_error("%s: step %s: path must be one of %s" % [where, kind, PATHS])
		for key in ["if", "unless"]:
			if not step.has(key):
				continue
			if not (step[key] is String or step[key] is Array):
				_error("%s: step %s: %s must be a flag or a list of flags" % [where, kind, key])
				continue
			for flag in (([step[key]] if step[key] is String else step[key]) as Array):
				flags_read[str(flag)] = where
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
	if sprite.has("like"):
		if not _enemy_ids.has(str(sprite.like)):
			_error("%s: sprite.like names unknown enemy \"%s\"" % [where, sprite.like])
		return
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


## Flags the engine itself reads. They are named in GDScript rather than in
## data, so the validator cannot find them by reading data/ alone.
const FLAGS_READ_IN_CODE := ["voice_yes", "matthew_confessed", "matthew_judged",
	"matthew_released", "matthew_book_revealed", "read_letters"]
## Flags the engine itself sets: written in GDScript, not by a choice in data.
## blood_paid: a blood altar's price paid (Run._on_blood_offered).
const FLAGS_SET_IN_CODE := ["blood_paid"]
## Flags a tool sets on purpose to drive a test, never by play.
const FLAGS_FOR_TESTS := ["save_test"]


## data/backdrops.json (scripts/rooms/backdrop_life.gd): every room of the
## chapter is named, each names a family that exists, each zone a known kind
## and a rect. Whether a rect lies on its picture is backdrop_life_test.gd's.
const BACKDROP_KINDS := ["falls", "water", "sway", "glow", "lava", "haze", "stars", "pulse"]  # BackdropLife.KINDS
const BACKDROP_ZONES := 24  # BackdropLife.MAX_ZONES


## The pictures that are not rooms: every cutscene panel and every passage
## card (Curtain.PASSAGE_ART, read as text — curtain.gd needs the autoloads).
func backdrop_pictures() -> Array:
	var found := {}
	for entry in _load_entries("res://data/cutscenes"):
		for step in entry.get("steps", []):
			if step is Dictionary and str(step.get("do", "")) == "panel" and str(step.get("image", "")) != "":
				found[str(step.image)] = true
	var curtain := FileAccess.get_file_as_string("res://scripts/autoload/curtain.gd")
	for each in RegEx.create_from_string("res://assets/ui/transitions/\\w+\\.png").search_all(curtain):
		found[each.get_string()] = true
	return found.keys()


func _check_backdrops() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/backdrops.json"))
	if not parsed is Dictionary:
		_error("data/backdrops.json: not a JSON object")
		return
	var families: Dictionary = parsed.get("families", {})
	# the flames take the colour of the path he leans to: one tint per path
	var lean: Dictionary = parsed.get("lean", {})
	for path in ["grace", "temptation", "will"]:
		if not lean.has(path) or not Color.html_is_valid(str(lean[path])):
			_error("data/backdrops.json: lean needs a colour for %s" % path)
	var rooms: Dictionary = parsed.get("rooms", {})
	# run.gd needs the autoloads to compile; its ROOMS are read as text
	var run := FileAccess.get_file_as_string("res://scripts/run/run.gd")
	var listed := run.substr(run.find("const ROOMS := ["))
	listed = listed.substr(0, listed.find("]"))
	var scene := RegEx.create_from_string("rooms/(\\w+)\\.tscn")
	for found in scene.search_all(listed):
		if not rooms.has(found.get_string(1)):
			_error("data/backdrops.json: no rule for %s — its backdrop would stand still" % found.get_string(1))
	# every picture a scene shows or a passage card carries breathes too
	for picture in backdrop_pictures():
		if not rooms.has(picture.get_file().get_basename()):
			_error("data/backdrops.json: no rule for %s — the picture would stand still" % picture)
	for key in rooms:
		var room: Dictionary = rooms[key]
		if not families.has(str(room.get("family", ""))):
			_error("data/backdrops.json: %s names an unknown family \"%s\"" % [key, room.get("family", "")])
		var zones: Array = room.get("zones", [])
		if zones.size() > BACKDROP_ZONES:
			_error("data/backdrops.json: %s has %d zones, the shader holds %d" % [key, zones.size(), BACKDROP_ZONES])
		for zone in zones:
			if not BACKDROP_KINDS.has(str(zone.get("kind", ""))):
				_error("data/backdrops.json: %s: unknown zone kind \"%s\"" % [key, zone.get("kind", "")])
			var rect = zone.get("rect", [])
			if not rect is Array or rect.size() != 4 or float(rect[2]) <= 0.0 or float(rect[3]) <= 0.0:
				_error("data/backdrops.json: %s: a %s zone needs rect [x, y, w, h]" % [key, zone.get("kind", "")])


func _check_story_flags() -> void:
	for flag in FLAGS_READ_IN_CODE:
		flags_read[flag] = "scripts/"
	for flag in FLAGS_SET_IN_CODE:
		flags_set[flag] = "scripts/"
	for flag in FLAGS_FOR_TESTS:
		flags_set[flag] = "a test"
		flags_read[flag] = "a test"
	var orphans: Array = []
	for flag in flags_set:
		if not flags_read.has(flag):
			orphans.append("%s (set in %s)" % [flag, flags_set[flag]])
	var ghosts: Array = []
	for flag in flags_read:
		if not flags_set.has(flag):
			ghosts.append("%s (read in %s)" % [flag, flags_read[flag]])
	orphans.sort()
	ghosts.sort()
	if not orphans.is_empty():
		_warn("flag(s) set but never read — the world does not react: %s"
			% ", ".join(orphans))
	if not ghosts.is_empty():
		_error("flag(s) read but never set — that branch cannot be reached: %s"
			% ", ".join(ghosts))


func _check_effect(effect: Dictionary, where: String) -> void:
	for flag in effect.get("set_flags", []):
		flags_set[str(flag)] = where
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


func _warn(message: String) -> void:
	warnings.append(message)
