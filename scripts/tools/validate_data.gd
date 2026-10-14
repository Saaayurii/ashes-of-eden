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
## The dialogue windows' styles, read in _check_dialogue_looks (DialogueLook).
var _look_styles := {}
const LOOK_COLORS := ["bg", "border", "speaker", "text", "caption", "portrait_bg", "portrait_border"]  # DialogueLook.COLORS
const LOOK_NUMBERS := {"border_width": [0, 4], "radius": [0, 12], "speaker_size": [8, 24],
	"text_size": [10, 28], "caption_size": [9, 24]}  # DialogueLook.NUMBERS
const LOOK_KEYS := ["style", "panel", "caption", "portrait", "face"]
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
	"weapons": ["id", "name", "description", "icon", "chain"],
	"endings": ["id", "name", "description", "line", "cutscene", "order", "when"],
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
var _cutscene_ids := {}
## Every ending (data/endings) and those marked "fallback", for the finale and the deeds.
var _ending_ids := {}
var _ending_fallbacks: Array = []
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
## Rooms a draft names that have no scene yet (scene -> draft), printed at the end.
var _planned_rooms := {}


func _init() -> void:
	var strings := _load_csv("res://localization/strings.csv")
	var counts := {}
	for id in _game_entries("dialogues"):
		_dialogue_ids[id.get("id", "")] = true
	for id in _game_entries("npcs"):
		_npc_ids[id.get("id", "")] = true
	for id in _game_entries("props"):
		_prop_ids[id.get("id", "")] = true
	for id in _game_entries("enemies"):
		_enemy_ids[id.get("id", "")] = bool(id.get("boss", false))
	for id in _game_entries("notes"):
		_note_ids[id.get("id", "")] = true
	for id in _game_entries("chapters"):
		_chapter_ids[id.get("id", "")] = true
	for gift in _game_entries("abilities"):
		_ability_paths[gift.get("id", "")] = str(gift.get("path", ""))
	_check_projectiles()
	_check_dialogue_looks()
	_check_action_fx()
	_check_gore()
	_check_liquids()
	_check_player_actions()
	_check_weapons()
	_check_hero()
	_check_game()
	_check_enemy_archetypes()
	_check_enemy_strips()
	var game: Dictionary = _game()
	for entry in _game_entries("endings"):  # a deed may name one before they are checked
		_ending_ids[str(entry.get("id", ""))] = true
	for collection in REQUIRED:
		var entries := _game_entries(collection)
		counts[collection] = entries.size()
		var ids := {}
		for entry in entries:
			if collection == "cutscenes" and entry.has("id"):
				_cutscene_ids[entry.id] = true
			_check_entry(collection, entry)
			if entry.has("id"):
				if ids.has(entry.id):
					_error("%s: duplicate id \"%s\"" % [collection, entry.id])
				ids[entry.id] = true
	_check_game_rooms(game)
	_check_draft_plans()
	_check_finale(game)
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
	_check_foliage()
	_check_telemetry_urls()

	for w in warnings:
		print("WARNING: " + w)
	if not _planned_rooms.is_empty():
		var by_draft := {}
		for scene in _planned_rooms:
			by_draft[_planned_rooms[scene]] = int(by_draft.get(_planned_rooms[scene], 0)) + 1
		for draft in by_draft:
			print("drafts/%s: checked; %d room(s) wait for their paintings" % [draft, by_draft[draft]])
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


## The telemetry server and the feedback form a build ships with (docs/PLAYTEST.md):
## empty (off, hidden) or an address. A typo would only be found by a player's
## silence; https, because the Web build is served over it and may send nowhere else.
func _check_telemetry_urls() -> void:
	for setting in ["ashes/telemetry/url", "ashes/telemetry/feedback_url"]:
		var url := str(ProjectSettings.get_setting(setting, "")).strip_edges()
		if url != "" and not url.begins_with("https://"):
			_error("%s must be empty or an https:// address, not \"%s\"" % [setting, url])


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
			if entry.has("shield") and (float(entry.shield) <= 0.0 or float(entry.shield) > 0.8):
				_error("%s: shield is the share of a frontal blow it turns, in (0, 0.8]" % where)
			var on_death: Dictionary = entry.get("on_death", {})
			if not on_death.is_empty() and not ["explode", "split"].has(on_death.get("type", "")):
				_error("%s: on_death.type must be explode or split" % where)
			if on_death.get("type", "") == "split":
				var into := str(on_death.get("into", ""))
				if not _enemy_ids.has(into) or into == str(entry.get("id", "")):
					_error("%s: on_death.into must be another enemy: %s" % [where, into])
				if int(on_death.get("count", 2)) < 1 or int(on_death.get("count", 2)) > 4:
					_error("%s: on_death.count is 1–4" % where)
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
				_room_missing(entry, str(scene), where, "room scene")
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
			if entry.has("weapon") and not (entry.weapon is bool and entry.get("kind") == "chest"):
				_error("%s: weapon is true or false, on a chest (it lays the night's weapon)" % where)
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
			if entry.has("guardians"):
				if not entry.has("reveals"):
					_error("%s: guardians keep a secret: only a wall that reveals a cache has them" % where)
				for round in entry.guardians:
					if not round is Array or (round as Array).is_empty():
						_error("%s: guardians are rounds, each a non-empty list of [enemy id, dx, dy]" % where)
						continue
					for row in round:
						if not row is Array or row.size() != 3 or not _enemy_ids.has(str(row[0])) or _enemy_ids.get(str(row[0]), false):
							_error("%s: a guardian is [enemy id (not a boss), dx, dy]: %s" % [where, row])
			if entry.has("guarded") and (entry.get("kind") != "chest" or float(entry.guarded) <= 0.0):
				_error("%s: guarded is a radius in pixels, on a chest" % where)
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
		"weapons":
			_check_weapon(entry, where)
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
		"endings":
			_check_ending(entry, where)
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
			_room_missing(entry, "res://scenes/rooms/%s.tscn" % entry.get("id", ""), where, "no room scene of that name")
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
			if entry.has("look"):
				_check_look(entry.look, where)
			for node_id in nodes:
				var node: Dictionary = nodes[node_id]
				var node_where := "%s#%s" % [where, node_id]
				if node.has("look"):
					_check_look(node.look, node_where)
				if node.has("branches"):  # a router node: flags -> next, no text
					for branch in node.branches:
						if branch.has("flag"):
							flags_read[str(branch.flag)] = node_where
						for key in ["path", "habit"]:
							if branch.has(key) and not PATHS.has(str(branch[key])):
								_error("%s: branch %s \"%s\" is not one of %s" % [node_where, key, branch[key], PATHS])
						if branch.has("vial") and (int(branch.vial) < 1 or int(branch.vial) > 5):
							_error("%s: branch vial is 1..5" % node_where)
						if branch.has("nights") and int(branch.nights) < 1:
							_error("%s: branch nights is at least 1 (nights already lived)" % node_where)
						if branch.has("omen") and not _omen_ids().has(str(branch.omen)):
							_error("%s: branch omen \"%s\" names no omen in data/omens" % [node_where, branch.omen])
						if not (branch.has("flag") or branch.has("path") or branch.has("habit") or branch.has("vial") or branch.has("omen") or branch.has("nights")):
							_error("%s: a branch needs a flag, a path, a habit, a vial, an omen or nights to test" % node_where)
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
## A game pack carries its own subset, cut from the merged strings
## (`make_cjk_font.py --pack`), which apply_pack.py puts in the engine's place.
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
		+ "(first seen in %s) — run tools/art/make_cjk_font.py (in a game pack: --pack) and commit the result"
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
	if entry.has("waits") and not (entry.waits is bool):
		_error("%s: waits must be true or false" % where)
	if entry.get("waits", false) and entry.get("aware", false):
		_error("%s: one that waits is never awake from the start" % where)
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
	for entry in _game_entries("enemy_archetypes"):
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
	for entry in _game_entries("enemies"):
		enemies[entry.get("id", "")] = entry.duplicate(true)
	for overlay in _game_entries("enemy_archetypes"):
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
## data/dialogue_looks.json: the windows' styles and the speakers' portraits
## (scripts/ui/dialogue_look.gd, docs/DIALOGUE_LOOKS.md).
func _check_dialogue_looks() -> void:
	var parsed = _doc("dialogue_looks.json")
	if not parsed is Dictionary or not parsed.get("styles") is Dictionary:
		_error("data/dialogue_looks.json: needs a \"styles\" object")
		return
	if not parsed.styles.has("default"):
		_error("data/dialogue_looks.json: the default style is the game's own look and must stay")
	for id in parsed.styles:
		var style = parsed.styles[id]
		var where := "dialogue_looks/%s" % id
		if not style is Dictionary:
			_error("%s: a style is an object" % where)
			continue
		_look_styles[id] = true
		for key in style:
			if LOOK_COLORS.has(key):
				if not Color.html_is_valid(str(style[key])):
					_error("%s: %s is not a colour (#rrggbb or #rrggbbaa): %s" % [where, key, style[key]])
			elif LOOK_NUMBERS.has(key):
				var bounds: Array = LOOK_NUMBERS[key]
				if not (style[key] is float or style[key] is int) or float(style[key]) < bounds[0] or float(style[key]) > bounds[1]:
					_error("%s: %s must be %d..%d" % [where, key, bounds[0], bounds[1]])
			elif key != "name":
				_error("%s: unknown key %s" % [where, key])
	var speakers = parsed.get("speakers", {})
	if not speakers is Dictionary:
		_error("data/dialogue_looks.json: \"speakers\" maps a speaker key to a portrait")
		return
	for speaker in speakers:
		_use_key(str(speaker), "dialogue_looks/speakers")
		var picture := str(speakers[speaker])
		if picture != "" and not ResourceLoader.exists(picture):
			_error("dialogue_looks/speakers/%s: portrait not found: %s" % [speaker, picture])


## A dialogue's or a line's "look": a known style, windows inside the screen.
func _check_look(look, where: String) -> void:
	if not look is Dictionary:
		_error("%s: look is an object" % where)
		return
	for key in look:
		if not LOOK_KEYS.has(key):
			_error("%s: look has an unknown key %s" % [where, key])
	if look.has("style") and not _look_styles.has(str(look.style)):
		_error("%s: look style \"%s\" is not in data/dialogue_looks.json" % [where, look.style])
	if look.has("face") and not ResourceLoader.exists(str(look.face)):
		_error("%s: look face not found: %s" % [where, look.face])
	for window in [["panel", 4], ["caption", 3], ["portrait", 3]]:
		var spot = look.get(window[0])
		if spot == null or (window[0] == "portrait" and spot is bool and spot == false):
			continue
		if not spot is Array or spot.size() != window[1] or spot.any(func(v) -> bool: return not (v is float or v is int)):
			_error("%s: look %s is %d numbers" % [where, window[0], window[1]])
			continue
		var w: float = spot[2]
		var h: float = spot[3] if window[1] == 4 else (36.0 if window[0] == "caption" else w)
		if spot[0] < 0 or spot[1] < 0 or spot[0] + w > 640 or spot[1] + h > 360:
			_error("%s: look %s %s leaves the 640x360 screen" % [where, window[0], spot])
		if window[0] == "panel" and (w < 120 or h < 48):
			_error("%s: look panel is at least 120x48" % where)
		if window[0] == "caption" and w < 80:
			_error("%s: look caption is at least 80 wide" % where)
		if window[0] == "portrait" and (w < 24 or w > 160):
			_error("%s: look portrait is 24..160 px" % where)


func _check_projectiles() -> void:
	var parsed = _doc("projectiles.json")
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
	if attack.has("projectile_range") and (not (attack.projectile_range is float or attack.projectile_range is int) or not is_finite(float(attack.projectile_range)) or float(attack.projectile_range) < 0):
		_error("%s: projectile_range needs a finite nonnegative distance" % where)
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
	var parsed = _doc("action_fx.json")
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


## data/gore.json (scripts/fx/gore.gd): every material is one the enemies use,
## every body is Elian or an enemy, every key one Gore reads, within bounds the
## room can stand (drops are simulated one by one; a body tears into 2–6 pieces).
const GORE_BOUNDS := {"shade": [0, 0.5], "spurt": [0, 4], "drops": [0, 40], "spray": [0, 400], "stain": [0, 3], "stain_life": [0, 120],
	"gush": [0, 80], "pool": [0, 60], "bleed": [0, 5], "limbs": [0, 6], "chance": [0, 1], "fling": [0, 400],
	"mist": [0, 20], "soak": [0, 1], "splash": [0, 6], "run": [0, 40], "drip": [0, 1], "back": [0, 0.6], "cloud": [0, 30], "hiss": [0, 1]}
const GORE_MOVE_BOUNDS := {"aim": [-90, 90], "spread": [0.1, 3], "force": [0, 3], "drops": [0, 3], "height": [-20, 20], "fling": [0, 3],
	"lift": [0, 1], "scatter": [0, 1], "chance": [0, 3], "pool": [0, 3], "jet": [0, 1]}


func _check_gore() -> void:
	var parsed = _doc("gore.json")
	if not parsed is Dictionary or not parsed.get("materials") is Dictionary or not parsed.get("bodies") is Dictionary:
		_error("data/gore.json: needs \"materials\" and \"bodies\" objects")
		return
	var tables := {}
	for material in parsed.materials:
		if not MATERIALS.has(material):
			_error("gore/materials/%s: not a material (%s)" % [material, MATERIALS])
		tables["materials/" + material] = parsed.materials[material]
	if not parsed.materials.has("flesh"):
		_error("gore/materials: needs flesh — it is what an unknown material bleeds")
	for body_key in parsed.bodies:
		if body_key != "elian" and not _enemy_ids.has(body_key):
			_error("gore/bodies/%s: no such body (elian or an enemy id)" % body_key)
		tables["bodies/" + body_key] = parsed.bodies[body_key]
		var own: Dictionary = parsed.bodies[body_key]
		if own.has("material") and not parsed.materials.has(str(own.material)):
			_error("gore/bodies/%s: material %s has no table" % [body_key, own.material])
	var moves = parsed.get("moves", {})
	if not moves is Dictionary:
		_error("gore/moves: must be an object")
		moves = {}
	# the blows the game names, read from gore.gd's MOVES (Gore cannot be compiled before the autoloads)
	var named: Array = []
	var found := RegEx.create_from_string("const MOVES := \\[([^\\]]*)\\]").search(FileAccess.get_file_as_string("res://scripts/fx/gore.gd"))
	if found != null:
		for word in RegEx.create_from_string("\"(\\w+)\"").search_all(found.get_string(1)):
			named.append(word.get_string(1))
	for move in moves:
		if not named.has(move):
			_error("gore/moves/%s: not a blow the game names (%s)" % [move, named])
			continue
		var m: Dictionary = moves[move]
		for key in m:
			if key == "cuts":
				tables["moves/" + move] = {"cuts": m.cuts}
			elif not GORE_MOVE_BOUNDS.has(key):
				_error("gore/moves/%s: unknown key %s (%s)" % [move, key, GORE_MOVE_BOUNDS.keys() + ["cuts"]])
			elif not (m[key] is float or m[key] is int) or float(m[key]) < GORE_MOVE_BOUNDS[key][0] or float(m[key]) > GORE_MOVE_BOUNDS[key][1]:
				_error("gore/moves/%s: %s must be %s..%s" % [move, key, GORE_MOVE_BOUNDS[key][0], GORE_MOVE_BOUNDS[key][1]])
	for where in tables:
		var table: Dictionary = tables[where]
		for key in table:
			if key == "material" and where.begins_with("bodies/"):
				continue
			if key == "cuts":
				if not table.cuts is Dictionary or table.cuts.is_empty():
					_error("gore/%s: cuts must weigh at least one of all, head, half, limb" % where)
					continue
				var weight := 0.0
				for way in table.cuts:
					if not ["all", "head", "half", "limb"].has(way):
						_error("gore/%s: cuts/%s is not a way to tear (all, head, half, limb)" % [where, way])
					elif float(table.cuts[way]) < 0.0 or float(table.cuts[way]) > 10.0:
						_error("gore/%s: cuts/%s must weigh 0..10" % [where, way])
					else:
						weight += float(table.cuts[way])
				if weight <= 0.0:
					_error("gore/%s: cuts all weigh nothing" % where)
				continue
			if key == "blood":
				if not Color.html_is_valid(str(table.blood)):
					_error("gore/%s: blood must be #rrggbb or #rrggbbaa" % where)
				continue
			if not GORE_BOUNDS.has(key):
				_error("gore/%s: unknown key %s" % [where, key])
				continue
			var v := float(table[key])
			if v < GORE_BOUNDS[key][0] or v > GORE_BOUNDS[key][1]:
				_error("gore/%s: %s must be %s..%s" % [where, key, GORE_BOUNDS[key][0], GORE_BOUNDS[key][1]])
		if int(table.get("limbs", 0)) == 1:
			_error("gore/%s: limbs is 0 (never torn) or 2..6" % where)


## Pools (data/liquids.json, scripts/rooms/hazard.gd, docs/LIQUIDS.md): every
## kind has its colours, a body that can be stood in, numbers in bounds, the
## pictures and sounds it names, and every studio pool names a kind.
const LIQUID_BOUNDS := {
	"opacity": [0.0, 1.0], "painted_opacity": [0.0, 1.0], "flow": [0.0, 1.0], "shimmer": [0.0, 1.0], "damage": [0.0, 100.0],
	"waves/amplitude": [0.0, 4.0], "waves/speed": [0.0, 6.0], "waves/length": [8.0, 400.0], "waves/spring": [0.001, 0.2],
	"waves/damping": [0.0, 0.5], "waves/spread": [0.0, 0.45], "waves/splash": [0.0, 4.0],
	"body/drag": [0.1, 1.0], "body/buoyancy": [0.0, 1.0], "body/sink_speed": [10.0, 600.0], "body/swim": [0.0, 500.0],
	"body/swim_cooldown": [0.05, 3.0], "body/jump": [0.2, 1.5],
	"enemy/drag": [0.1, 1.0], "enemy/heal_per_second": [0.0, 20.0],
	"particles/ambient_every": [0.05, 10.0], "particles/trail_time": [0.0, 5.0],
	"light/radius": [8.0, 400.0], "light/energy": [0.0, 3.0], "light/every": [16.0, 1000.0], "light/flicker": [0.0, 1.0],
}
const LIQUID_AMBIENT := ["", "none", "glints", "bubbles", "embers", "gas", "clots"]
const LIQUID_SPLASH := ["drops", "magma", "mud", "blood"]
const LIQUID_TRAIL := ["", "none", "drips", "smoke", "mud"]


func _check_liquids() -> void:
	var parsed = _doc("liquids.json")
	if not parsed is Dictionary or not parsed.get("kinds") is Dictionary or (parsed.kinds as Dictionary).is_empty():
		_error("data/liquids.json: needs a \"kinds\" object")
		return
	var kinds: Dictionary = parsed.kinds
	if not kinds.has("lava"):
		_error("liquids: needs lava — a painted room's hazards are lava pools")
	for id in kinds:
		var spec = kinds[id]
		var where := "liquids/%s" % id
		if not spec is Dictionary:
			_error("%s: must be an object" % where)
			continue
		var colors = spec.get("colors", {})
		for key in ["surface", "body", "deep", "foam"]:
			if not colors is Dictionary or not Color.html_is_valid(str(colors.get(key, ""))):
				_error("%s: colors.%s must be a #colour" % [where, key])
		for path in LIQUID_BOUNDS:
			var parts: PackedStringArray = path.split("/")
			var holder = spec
			if parts.size() == 2:
				holder = spec.get(parts[0], {})
			if not holder is Dictionary or not holder.has(parts[-1]):
				continue
			var v := float(holder[parts[-1]])
			if v < LIQUID_BOUNDS[path][0] or v > LIQUID_BOUNDS[path][1]:
				_error("%s: %s must be %s..%s" % [where, path, LIQUID_BOUNDS[path][0], LIQUID_BOUNDS[path][1]])
		if not spec.get("body") is Dictionary or not spec.body.has("sink_speed"):
			_error("%s: body needs sink_speed (how fast a body sinks in it)" % where)
		var texture := str(spec.get("texture", ""))
		if texture != "" and not ResourceLoader.exists(texture) and not FileAccess.file_exists(texture):
			_error("%s: texture %s does not exist (tools/art/make_liquids.py)" % [where, texture])
		var particles = spec.get("particles", {})
		if particles is Dictionary:
			if not str(particles.get("ambient", "")) in LIQUID_AMBIENT:
				_error("%s: particles.ambient is one of %s" % [where, LIQUID_AMBIENT])
			if not str(particles.get("splash", "drops")) in LIQUID_SPLASH:
				_error("%s: particles.splash is one of %s" % [where, LIQUID_SPLASH])
			if not str(particles.get("trail", "")) in LIQUID_TRAIL:
				_error("%s: particles.trail is one of %s" % [where, LIQUID_TRAIL])
		var enemy = spec.get("enemy", {})
		if enemy is Dictionary and enemy.get("harms") is Dictionary:
			for material in enemy.harms:
				if not MATERIALS.has(material):
					_error("%s: enemy.harms.%s is not a material (%s)" % [where, material, MATERIALS])
		var heal = spec.get("heal", {})
		if heal is Dictionary and heal.has("path") and not ["grace", "temptation", "will"].has(str(heal.path)):
			_error("%s: heal.path is grace, temptation or will" % where)
		if bool(spec.get("burns", false)) and float(spec.get("damage", 0.0)) <= 0.0:
			_error("%s: a liquid that burns needs damage" % where)
		var sounds = spec.get("sounds", {})
		if sounds is Dictionary:
			for key in sounds:
				var cue := str(sounds[key])
				if cue != "" and not _sfx_exists(cue):
					_warn("%s: sounds.%s names %s, which has no clip in assets/audio/sfx" % [where, key, cue])
	# the studio's pools: [kind, x, y, w, h, {painted}?] in finished-room pixels
	var studio_path := "res://tools/rooms/studio_rooms.json"
	if FileAccess.file_exists(studio_path):
		var studio = JSON.parse_string(FileAccess.get_file_as_string(studio_path))
		if studio is Dictionary:
			for room in studio:
				var extra = studio[room]
				if not extra is Dictionary or not extra.has("liquids"):
					continue
				for pool in extra.liquids:
					if not pool is Array or pool.size() < 5 or not kinds.has(str(pool[0])):
						_error("studio_rooms/%s/liquids: %s is not [kind, x, y, w, h] with a kind from data/liquids.json" % [room, pool])
					elif float(pool[3]) < 16.0 or float(pool[4]) < 8.0:
						_error("studio_rooms/%s/liquids: %s is smaller than 16×8" % [room, pool])


func _sfx_exists(cue: String) -> bool:
	var dir := DirAccess.open("res://assets/audio/sfx")
	if dir == null:
		return false
	for file in dir.get_files():
		if file.ends_with(".import"):
			continue
		var stem := file.get_basename()
		if stem == cue or (stem.begins_with(cue + "_") and stem.trim_prefix(cue + "_").is_valid_int()):
			return true
	return false


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
		if not ["nights", "wins", "total_kills", "kills", "known", "notes", "items", "affixes", "moves", "deeds", "fast", "endings"].has(key):
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
	var endings = unlock.get("endings", [])
	if str(endings) != "all":
		for ending in endings:
			if not _ending_ids.has(str(ending)):
				_error("%s: unlock.endings names no ending: %s" % [where, ending])
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


## An ending (data/endings, scripts/run/endings.gd): its words, a cutscene
## that exists, and a "when" in the terms Endings.holds reads. Its flags count
## as read — the ending is what answers them.
func _check_ending(entry: Dictionary, where: String) -> void:
	for key in ["name", "description", "line"]:
		_use_key(entry.get(key, ""), where)
	_ending_ids[str(entry.get("id", ""))] = true
	if not str(entry.get("id", "")).is_valid_identifier():
		_error("%s: the id names a deed and a record: letters, digits, _" % where)
	if not _cutscene_ids.has(entry.get("cutscene", "")):
		_error("%s: unknown cutscene %s" % [where, entry.get("cutscene", "")])
	if not entry.get("order") is float:
		_error("%s: order is a number (lower is tried first)" % where)
	if entry.get("fallback", false):
		_ending_fallbacks.append(entry.id)
	var when = entry.get("when", {})
	if not when is Dictionary or when.is_empty():
		_error("%s: when is {path, lead, balanced, flags, unless}, not empty" % where)
		return
	for key in when:
		match key:
			"path":
				if not PATHS.has(when.path):
					_error("%s: when.path must be one of %s" % [where, PATHS])
			"lead", "balanced":
				if not when[key] is float or int(when[key]) < 0 or int(when[key]) > 20:
					_error("%s: when.%s is a whole number of the hidden counters, 0..20" % [where, key])
			"flags", "unless":
				if not when[key] is Array:
					_error("%s: when.%s is a list of flags" % [where, key])
				else:
					for flag in when[key]:
						flags_read[str(flag)] = where
			_:
				_error("%s: when.%s is not path, lead, balanced, flags or unless" % [where, key])
	if when.has("lead") and not when.has("path"):
		_error("%s: when.lead needs a path to lead" % where)
	if when.has("balanced") and when.has("path"):
		_error("%s: a balanced night leans no way: when.path and when.balanced cannot meet" % where)


## data/game.json "finale" (Endings.finale): the room after which the campaign
## would end, the scene there that comes before an ending, and whether it ends
## yet. Endings need exactly one fallback, so every night has one.
func _check_finale(game: Dictionary) -> void:
	if not _ending_ids.is_empty() and _ending_fallbacks.size() != 1:
		_error("data/endings: exactly one ending is the \"fallback\" (has %s)" % [_ending_fallbacks])
	if not game.has("finale"):
		if not _ending_ids.is_empty():
			_error("data/game.json: endings exist but no \"finale\" says where the campaign ends")
		return
	var finale = game.finale
	if not finale is Dictionary:
		_error("data/game.json: finale is {room, cutscene, ends_campaign}")
		return
	if not game.get("rooms", []).has(finale.get("room", "")):
		_error("data/game.json: finale.room must be one of the rooms: %s" % finale.get("room", ""))
	if finale.has("cutscene") and not _cutscene_ids.has(finale.cutscene):
		_error("data/game.json: finale.cutscene names no cutscene: %s" % finale.cutscene)
	if not finale.get("ends_campaign", false) is bool:
		_error("data/game.json: finale.ends_campaign is true or false")


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
		_room_missing(entry, str(entry.get(key, "")), where, key + " room")
	var options: Dictionary = entry.get("options", {})
	if options.size() < 2:
		_error("%s: a fork needs two ways at least" % where)
	var question: Dictionary = {}
	for dialogue in _game_entries("dialogues"):
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
	for point in _game_entries("rest_points"):
		rested[str(point.get("id", ""))] = true
	for key in options:
		var path := str(options[key])
		if _room_missing(entry, path, where, "option " + key):
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


## Flags the engine itself sets: written in GDScript, not by a choice in data.
## blood_paid: a blood altar's price paid (Run._on_blood_offered).
## waiter_struck: a blow on one that waits, while it still waited (Enemy._apply_damage).
const FLAGS_SET_IN_CODE := ["blood_paid", "waiter_struck"]
## Flags a tool sets on purpose to drive a test, never by play.
const FLAGS_FOR_TESTS := ["save_test"]


## The engine room a game pack's room was made from (`base_room` in its scene), or "".
func _base_room(path: String) -> String:
	var found := RegEx.create_from_string('(?m)^base_room = "(\\w+)"').search(FileAccess.get_file_as_string(path))
	return found.get_string(1) if found != null else ""


## data/backdrops.json (scripts/rooms/backdrop_life.gd): every room of the
## chapter is named, each names a family that exists, each zone a known kind
## and a rect. Whether a rect lies on its picture is backdrop_life_test.gd's.
const BACKDROP_KINDS := ["falls", "water", "sway", "glow", "lava", "haze", "stars", "pulse"]  # BackdropLife.KINDS
const BACKDROP_ZONES := 24  # BackdropLife.MAX_ZONES


## The pictures that are not rooms: every cutscene panel and every passage
## card (Curtain.PASSAGE_ART, read as text — curtain.gd needs the autoloads).
func backdrop_pictures() -> Array:
	var found := {}
	for entry in _game_entries("cutscenes"):
		for step in entry.get("steps", []):
			if step is Dictionary and str(step.get("do", "")) == "panel" and str(step.get("image", "")) != "":
				found[str(step.image)] = true
	var curtain := FileAccess.get_file_as_string("res://scripts/autoload/curtain.gd")
	for each in RegEx.create_from_string("res://assets/ui/transitions/\\w+\\.png").search_all(curtain):
		found[each.get_string()] = true
	return found.keys()


func _check_backdrops() -> void:
	var parsed = _doc("backdrops.json")
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
	for path in DATA_DOC.all_rooms(_doc("game.json")):
		# a game pack's room made from an engine room may take that room's rule (RoomLayers.look_key)
		var own := str(path).get_file().get_basename()
		if not rooms.has(own) and not rooms.has(_base_room(str(path))):
			_error("data/backdrops.json: no rule for %s — its backdrop would stand still" % own)
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


## data/foliage.json (scripts/rooms/foliage.gd): every style is bounded so a
## room can stand it (leaves are simulated one by one, MAX_LEAVES at once),
## and a backdrop zone's "tree" is a sway zone naming a style that exists.
const FOLIAGE_BOUNDS := {"twigs": [0, 1], "stiff": [0.2, 4], "damp": [0.02, 1], "bend": [0, 4], "drift": [0, 0.5],
	"shed": [0, 4], "burst": [0, 40], "fall": [5, 80], "flutter": [0, 40], "rest": [0.5, 30]}
const FOLIAGE_SHAPES := ["leaf", "strand"]
## data/foliage.json "birds": the ravens a tree zone's "birds" seats (Foliage.MAX_BIRDS at most).
const FOLIAGE_BIRD_BOUNDS := {"scare": [16, 200], "flock": [0, 300], "away": [3, 120], "speed": [40, 400]}
const FOLIAGE_BIRD_COLORS := ["body", "rim", "beak"]
const FOLIAGE_MAX_BIRDS := 4


func _check_foliage() -> void:
	var parsed = _doc("foliage.json")
	var styles = parsed.get("styles", {}) if parsed is Dictionary else null
	if not styles is Dictionary or styles.is_empty():
		_error("data/foliage.json: needs a \"styles\" object")
		styles = {}
	for id in styles:
		var style: Dictionary = styles[id]
		for key in style:
			if key == "colors":
				if not style.colors is Array or style.colors.is_empty():
					_error("foliage/%s: colors must be a non-empty list" % id)
				else:
					for each in style.colors:
						if not Color.html_is_valid(str(each)):
							_error("foliage/%s: %s is not a colour" % [id, each])
			elif key == "shape":
				if not FOLIAGE_SHAPES.has(str(style.shape)):
					_error("foliage/%s: shape must be one of %s" % [id, FOLIAGE_SHAPES])
			elif not FOLIAGE_BOUNDS.has(key):
				_error("foliage/%s: unknown key %s (%s)" % [id, key, FOLIAGE_BOUNDS.keys() + ["colors", "shape"]])
			elif not (style[key] is float or style[key] is int) or float(style[key]) < FOLIAGE_BOUNDS[key][0] or float(style[key]) > FOLIAGE_BOUNDS[key][1]:
				_error("foliage/%s: %s must be %s..%s" % [id, key, FOLIAGE_BOUNDS[key][0], FOLIAGE_BOUNDS[key][1]])
	var ravens = parsed.get("birds", {}) if parsed is Dictionary else {}
	if not ravens is Dictionary:
		_error("data/foliage.json: \"birds\" must be an object")
		ravens = {}
	for key in ravens:
		if FOLIAGE_BIRD_COLORS.has(key):
			if not Color.html_is_valid(str(ravens[key])):
				_error("foliage/birds: %s %s is not a colour" % [key, ravens[key]])
		elif not FOLIAGE_BIRD_BOUNDS.has(key):
			_error("foliage/birds: unknown key %s (%s)" % [key, FOLIAGE_BIRD_BOUNDS.keys() + FOLIAGE_BIRD_COLORS])
		elif not (ravens[key] is float or ravens[key] is int) or float(ravens[key]) < FOLIAGE_BIRD_BOUNDS[key][0] or float(ravens[key]) > FOLIAGE_BIRD_BOUNDS[key][1]:
			_error("foliage/birds: %s must be %s..%s" % [key, FOLIAGE_BIRD_BOUNDS[key][0], FOLIAGE_BIRD_BOUNDS[key][1]])
	var rooms: Dictionary = _doc("backdrops.json").get("rooms", {})
	for key in rooms:
		for zone in rooms[key].get("zones", []):
			if zone.has("birds"):
				var count = zone.birds
				if not zone.has("tree"):
					_error("data/backdrops.json: %s: ravens (\"birds\") sit only on a tree zone" % key)
				elif not (count is float or count is int) or float(count) != floorf(float(count)) or int(count) < 0 or int(count) > FOLIAGE_MAX_BIRDS:
					_error("data/backdrops.json: %s: birds must be a whole number 0..%d" % [key, FOLIAGE_MAX_BIRDS])
			if not zone.has("tree"):
				continue
			if str(zone.get("kind", "")) != "sway":
				_error("data/backdrops.json: %s: only a sway zone can be a tree (a %s zone names \"%s\")" % [key, zone.get("kind", ""), zone.tree])
			elif not styles.has(str(zone.tree)):
				_error("data/backdrops.json: %s: tree \"%s\" is not a style of data/foliage.json (%s)" % [key, zone.tree, styles.keys()])


func _check_story_flags() -> void:
	# a game's own flags that something other than a branch reads (game.json "flags_read")
	for flag in DATA_DOC.top("game.json", _validated_roots()).get("flags_read", []):
		flags_read[str(flag)] = "data/game.json"
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
	if effect.has("flask") and (not (effect.flask is float or effect.flask is int) or int(effect.flask) != float(effect.flask)
			or absi(int(effect.flask)) > 3 or int(effect.flask) == 0):
		_error("%s: flask is a whole number of flasks, -3..3 (negative: given away)" % where)
	for key in effect:
		if not PATHS.has(key) and not key in ["set_flags", "flask"]:
			_error("%s: unknown effect key \"%s\"" % [where, key])


func _use_key(key: String, where: String) -> void:
	if key == "":
		_error("%s: empty localization key" % where)
		return
	used_keys[key] = where


func _game() -> Dictionary:
	return DATA_DOC.top("game.json", _validated_roots())


## A collection as the game plays it: the engine's entries under the pack's,
## by id (Data._load_collection), the ones game.json does not inherit or
## excludes left out. A second entry with one id in the same root is kept, so
## the duplicate check sees it.
func _game_entries(collection: String) -> Array:
	var game := _game()
	var entries := []
	var at := {}
	var drafts := _draft_roots()
	for data_root in DATA_DOC.collection_roots(collection, _validated_roots(), game):
		var mine := {}
		for entry in _load_entries(data_root.path_join(collection), data_root != DATA_ROOTS[0]):
			if drafts.has(data_root):
				entry["_draft"] = data_root.get_base_dir().get_file()
			if entry.has("id") and at.has(entry.id) and not mine.has(entry.id):
				entries[at[entry.id]] = entry  # the pack's own replaces the engine's
				mine[entry.id] = true
				continue
			if entry.has("id"):
				mine[entry.id] = true
				if not at.has(entry.id):
					at[entry.id] = entries.size()
			entries.append(entry)
	var excluded: Array = game.get("exclude", {}).get(collection, [])
	return entries.filter(func(e) -> bool: return not excluded.has(e.get("id")))


func _load_entries(dir_path: String, optional := false) -> Array:
	var result := []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		if not optional:
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


## Where data lives, in the order the game lays it (Data.ROOTS): the engine's
## own, then a game pack checked out into ./content (docs/GAME_PACKS.md).
const DATA_DOC := preload("res://scripts/data/data_doc.gd")
const DATA_ROOTS := ["res://data", "res://content/data"]
const DRAFTS := "res://drafts"


## The engine's data and the game pack's, if one is checked out; never a player's mods.
## Then every draft (res://drafts/<name>/data, docs/CHAPTER2.md): a chapter
## written ahead of its paintings. The game never reads a draft (it is not in
## DataDoc.ROOTS, and drafts/.gdignore keeps it out of the import and the
## export); the validator checks it with the rest, so its strings, flags and
## people stay true to the game it will join.
func _validated_roots() -> Array[String]:
	var out: Array[String] = []
	for data_root in DATA_ROOTS:
		if DirAccess.dir_exists_absolute(data_root):
			out.append(data_root)
	return out + _draft_roots()


func _draft_roots() -> Array[String]:
	var out: Array[String] = []
	var drafts := DirAccess.open(DRAFTS)
	if drafts:
		var names := drafts.get_directories()
		names.sort()
		for draft in names:
			if DirAccess.dir_exists_absolute(DRAFTS.path_join(draft).path_join("data")):
				out.append(DRAFTS.path_join(draft).path_join("data"))
	return out



## A draft's room plan (`drafts/<name>/rooms.json`, docs/CHAPTER2.md): every
## room is a scene some chapter area of the drafts lists, and every enemy,
## person, prop, cutscene, rest point, fork and stand-in painting it names
## exists — so the plan the artist works from is the one the data can play.
func _check_draft_plans() -> void:
	var rests := {}
	for rest in _game_entries("rest_points"):
		rests[rest.get("id", "")] = true
	var forks := {}
	for fork in _game_entries("forks"):
		forks[fork.get("id", "")] = true
	for data_root in _draft_roots():
		var path := data_root.get_base_dir().path_join("rooms.json")
		if not FileAccess.file_exists(path):
			continue
		var plan = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not plan is Dictionary or not plan.get("rooms") is Array:
			_error("%s: wants {\"rooms\": [...]}" % path)
			continue
		var seen := {}
		for room in plan.rooms:
			var where := "%s: %s" % [path, room.get("id", "?")]
			var scene := "res://scenes/rooms/%s.tscn" % room.get("id", "")
			if seen.has(scene):
				_error(where + ": listed twice")
			seen[scene] = true
			if not _planned_rooms.has(scene) and not ResourceLoader.exists(scene):
				_error(where + ": no chapter area of the drafts lists this room")
			if not _chapter_ids.has(room.get("area", "")):
				_error("%s: unknown area \"%s\"" % [where, room.get("area", "")])
			for id in room.get("enemies", {}):
				if not _enemy_ids.has(id):
					_error("%s: unknown enemy \"%s\"" % [where, id])
			for id in room.get("npcs", []):
				if not _npc_ids.has(id):
					_error("%s: unknown npc \"%s\"" % [where, id])
			for id in room.get("props", []):
				if not _prop_ids.has(id):
					_error("%s: unknown prop \"%s\"" % [where, id])
			for key in ["intro", "outro"]:
				if room.has(key) and not _cutscene_ids.has(room[key]):
					_error("%s: unknown cutscene \"%s\"" % [where, room[key]])
			if room.has("rest") and not rests.has(room.rest):
				_error("%s: unknown rest point \"%s\"" % [where, room.rest])
			if room.has("fork") and not forks.has(room.fork):
				_error("%s: unknown fork \"%s\"" % [where, room.fork])
			for other in room.get("stand_in", []):
				if not ResourceLoader.exists("res://scenes/rooms/%s.tscn" % other):
					_error("%s: stand-in \"%s\" is not a room" % [where, other])
		for scene in _planned_rooms:
			if _planned_rooms[scene] == data_root.get_base_dir().get_file() and not seen.has(scene):
				_error("%s: %s is in the drafts' data but not in the plan" % [path, scene])

## A room a draft names is allowed not to exist yet: its painting is still to
## come. Counted and printed, never an error — the moment the scene exists it
## is checked like any other.
func _room_missing(entry: Dictionary, scene: String, where: String, what: String) -> bool:
	if FileAccess.file_exists(scene):
		return false
	if entry.has("_draft"):
		_planned_rooms[scene] = entry._draft
	else:
		_error("%s: %s not found: %s" % [where, what, scene])
	return true


## A single-document file merged the way Data.load_doc merges it.
func _doc(file_name: String) -> Dictionary:
	# a root's copy that does not parse is left out of the merge in play: here it is an error
	for data_root in _validated_roots():
		var file: String = data_root.path_join(file_name)
		if FileAccess.file_exists(file) and not JSON.parse_string(FileAccess.get_file_as_string(file)) is Dictionary:
			_error("%s: not a JSON object" % file)
	return DATA_DOC.doc(file_name, _validated_roots())



## data/hero.json (Player.apply_hero): the engine's copy names every key there
## is; a game pack may change any of them and add none.
## data/game.json (docs/GAME_PACKS.md): what the engine asks of the game — its
## rooms, its yard, its menu, the three paths' looks — and every file it names.
func _check_game() -> void:
	var game: Dictionary = DATA_DOC.top("game.json", _validated_roots())
	if game.is_empty():
		_error("data/game.json: missing — the engine has no rooms to run")
		return
	if not game.get("engine") is float or int(game.engine) < 1:
		_error("data/game.json: \"engine\" must name the engine version it was made for (a whole number)")
	elif int(game.engine) > DATA_DOC.ENGINE:
		_error("data/game.json: made for engine %d, this is engine %d — update the engine checkout" % [int(game.engine), DATA_DOC.ENGINE])
	for collection in game.get("exclude", {}):
		if not collection in REQUIRED:
			_error("data/game.json: exclude names \"%s\", which is not a collection" % collection)
	for collection in game.get("inherit", []):
		if not collection in REQUIRED and not collection in ["enemy_archetypes"]:
			_error("data/game.json: inherit names \"%s\", which is not a collection" % collection)
	var rooms: Array = game.get("rooms", [])
	if rooms.is_empty():
		_error("data/game.json: \"rooms\" is empty")
	var seen := {}
	var every: Array = []
	for night in DATA_DOC.nights(game):
		every.append_array(night.get("rooms", []))
	for path in every + [game.get("practice_room", "")]:
		if seen.has(path):
			_error("data/game.json: %s is listed twice" % path)
		seen[path] = true
		if not ResourceLoader.exists(str(path)):
			_error("data/game.json: no scene %s" % path)
	_check_nights(game)
	for night in DATA_DOC.nights(game):
		_check_opening(night.get("opening", {}), "opening" if str(night.id) == "" else "nights.%s.opening" % night.id, game)
	var menu: Dictionary = game.get("menu", {})
	if menu.has("background") and not ResourceLoader.exists(str(menu.background)):
		_error("data/game.json: menu background %s does not exist" % menu.background)
	var paths: Dictionary = game.get("paths", {})
	for path in ["grace", "temptation", "will"]:
		var look: Dictionary = paths.get(path, {})
		for key in ["color", "aura"]:
			if not Color.html_is_valid(str(look.get(key, ""))):
				_error("data/game.json: paths.%s.%s must be a colour (#rrggbb)" % [path, key])
		if not ResourceLoader.exists(str(look.get("icon", ""))):
			_error("data/game.json: paths.%s.icon %s does not exist" % [path, look.get("icon", "")])
		var drift = look.get("drift", [])
		if not drift is Array or drift.size() != 2:
			_error("data/game.json: paths.%s.drift must be [x, y]" % path)
	for key in paths:
		if not key in ["grace", "temptation", "will"]:
			_error("data/game.json: unknown path \"%s\" — the engine counts grace, temptation and will" % key)


## Every room the game plays names only creatures, people, props and scenes the
## game has — the room is read as text, so a pack that borrows an engine room
## learns here which of its story it would need (docs/GAME_PACKS.md).
## A night's opening (game.json "opening", or a later night's): each key names
## a dialogue (intro, last_fall) or a cutscene (prologue…) the game has;
## "wake" says whether he rises out of the grave (true when left out).
func _check_opening(opening: Dictionary, where: String, game: Dictionary) -> void:
	for key in opening:
		if key == "wake":
			if not opening[key] is bool:
				_error("data/game.json: %s.wake must be true or false" % where)
			continue
		var id := str(opening[key])
		var folder := "dialogues" if key in ["intro", "last_fall"] else "cutscenes"
		var found := false
		for data_root in DATA_DOC.collection_roots(folder, _validated_roots(), game):
			for entry in _load_entries(data_root.path_join(folder), true):
				found = found or entry.get("id") == id
		if not found:
			_error("data/game.json: %s.%s names %s \"%s\", which does not exist" % [where, key, folder, id])


## The nights after the first (game.json "nights", DataDoc.nights): each its
## own id and rooms, no room in two nights, opened by a number of dawns, and
## its forks inside it.
func _check_nights(game: Dictionary) -> void:
	var ids := {"": true}
	var owner := {}
	var nights := DATA_DOC.nights(game)
	for i in nights.size():
		var night: Dictionary = nights[i]
		var where := "data/game.json: nights.%s" % night.id
		if i > 0:
			if ids.has(str(night.id)):
				_error("%s is listed twice" % where)
			ids[str(night.id)] = true
			if not (night.get("rooms") is Array) or (night.rooms as Array).is_empty():
				_error("%s: a night with no rooms" % where)
			var dawns = night.get("after_dawns", 0)
			if not (dawns is float or dawns is int) or int(dawns) < 1:
				_error("%s: after_dawns must be 1 or more — the first night is the one always open" % where)
		for path in night.get("rooms", []):
			owner[str(path)] = str(night.id)
	for fork in _game_entries("forks"):
		var in_nights := {}
		for path in [fork.get("after", ""), fork.get("then", "")] + (fork.get("options", {}) as Dictionary).values():
			in_nights[owner.get(str(path), "?")] = true
		if in_nights.size() != 1 or in_nights.has("?"):
			_error("data/forks/%s: its rooms must all be one night's" % fork.get("id", "?"))


func _check_game_rooms(game: Dictionary) -> void:
	var wants := {"enemy_id": [_enemy_ids, "enemy"], "npc_id": [_npc_ids, "npc"], "prop_id": [_prop_ids, "prop"],
		"intro_cutscene": [_cutscene_ids, "cutscene"], "outro_cutscene": [_cutscene_ids, "cutscene"],
		"intro_dialogue": [_dialogue_ids, "dialogue"]}
	var line := RegEx.create_from_string("^(\\w+) = \"([^\"]+)\"$")
	for path in DATA_DOC.all_rooms(game) + [game.get("practice_room", "")]:
		if not ResourceLoader.exists(str(path)):
			continue
		var room := str(path).get_file().get_basename()
		for row in FileAccess.get_file_as_string(str(path)).split("\n"):
			var hit := line.search(row)
			if hit == null or not wants.has(hit.get_string(1)):
				continue
			var want: Array = wants[hit.get_string(1)]
			if not (want[0] as Dictionary).has(hit.get_string(2)):
				_error("%s: the room names %s \"%s\", which this game does not have" % [room, want[1], hit.get_string(2)])


func _check_hero() -> void:
	var known = JSON.parse_string(FileAccess.get_file_as_string("res://data/hero.json"))
	if not known is Dictionary or ["stats", "feel", "moves", "enemy_ai"].any(func(k): return not known.get(k) is Dictionary):
		_error("data/hero.json needs \"stats\", \"feel\", \"moves\" and \"enemy_ai\" objects")
		return
	var hero := _doc("hero.json")
	for key in hero:
		if not key in ["stats", "feel", "moves", "enemy_ai"]:
			_error("hero.json: unknown section %s" % key)
	# the special moves this game's hero has (Player.MOVE_KEYS): on or off, no new ones
	var moves = hero.get("moves", {})
	for key in moves:
		if not known.moves.has(key):
			_error("hero.json moves.%s: the hero has no such move (%s)" % [key, ", ".join(known.moves.keys())])
		elif not moves[key] is bool:
			_error("hero.json moves.%s needs true or false" % key)
	# how enemies fight (Enemy.AI_KEYS, docs/ENEMY_AI.md), and one enemy's own "ai"
	_check_enemy_ai("hero.json enemy_ai", hero.get("enemy_ai", {}), known.enemy_ai)
	for enemy in _game_entries("enemies"):
		var own = enemy.get("ai")
		if own != null:
			_check_enemy_ai("enemy %s: ai" % enemy.get("id", "?"), own if own is Dictionary else {"": own}, known.enemy_ai)
	var unit := ["block_reduction", "knockback_fraction", "desperate_share", "refuse_heal", "dodge_counter_bonus",
		"rally_damage_share", "rally_hit_share", "rally_max_hp_share", "slam_damage_share", "crit_chance"]
	for section in ["stats", "feel"]:
		var given: Dictionary = hero.get(section, {})
		for key: String in given:
			var where := "hero.json %s.%s" % [section, key]
			if not known[section].has(key):
				_error("%s: the hero has no such value" % where)
				continue
			var value = given[key]
			var want = known[section][key]
			if want is Array:
				if not value is Array or value.size() != want.size() or value.any(func(v): return not (v is float or v is int) or v <= 0):
					_error("%s needs %d positive numbers" % [where, want.size()])
			elif want is Dictionary:
				if not value is Dictionary:
					_error("%s needs an object" % where)
					continue
				for k in value:
					if not want.has(k) or not (value[k] is float or value[k] is int) or value[k] <= 0:
						_error("%s.%s needs a positive number for a known move" % [where, k])
			elif not (value is float or value is int) or not is_finite(float(value)):
				_error("%s needs a number" % where)
			elif key == "jump_cut_velocity":
				if value > 0:
					_error("%s is a speed upwards: zero or less" % where)
			elif value < 0:
				_error("%s cannot be negative" % where)
			elif key in unit and value > 1:
				_error("%s is a share: 0..1" % where)
	var stats: Dictionary = hero.get("stats", {})
	for key in ["max_hp", "speed", "gravity", "jump_velocity", "attack_damage"]:
		if stats.has(key) and float(stats[key]) <= 0:
			_error("hero.json stats.%s must be above zero" % key)
	if stats.has("max_jumps") and (int(stats.max_jumps) != stats.max_jumps or stats.max_jumps < 1):
		_error("hero.json stats.max_jumps needs a whole number, at least 1")


## The AI numbers: each a key the engine knows, shaped like the engine's own
## (a list as long, a table with its keys), never negative; shares within 0..1.
func _check_enemy_ai(where: String, given: Dictionary, known: Dictionary) -> void:
	for key: String in given:
		if not known.has(key):
			_error("%s.%s: enemies have no such value" % [where, key])
			continue
		_check_ai_value("%s.%s" % [where, key], given[key], known[key])
		if key in ["execute_below", "repeat_attack_weight"] and (given[key] is float or given[key] is int) and given[key] > 1:
			_error("%s.%s is a share: 0..1" % [where, key])
		if key == "attackers_per_side" and (not (given[key] is float or given[key] is int) or int(given[key]) != given[key] or given[key] < 1):
			_error("%s.%s needs a whole number, at least 1" % [where, key])
		if key == "band_depth" and given[key] is Array and given[key].size() == 2 and given[key][0] > given[key][1]:
			_error("%s.%s is [nearest, furthest]" % [where, key])


func _check_ai_value(where: String, value, want) -> void:
	if want is Array:
		if not value is Array or value.size() != want.size():
			_error("%s needs %d numbers" % [where, want.size()])
			return
		for v in value:
			_check_ai_value(where, v, want[0])
	elif want is Dictionary:
		if not value is Dictionary:
			_error("%s needs an object" % where)
			return
		for k in value:
			if not want.has(k):
				_error("%s.%s: no such key (%s)" % [where, k, ", ".join(want.keys())])
			else:
				_check_ai_value("%s.%s" % [where, k], value[k], want[k])
	elif not (value is float or value is int) or not is_finite(float(value)) or value < 0:
		_error("%s needs a number, zero or more" % where)


## A weapon (data/weapons, docs/WEAPONS.md): every number bounded, every pose
## one Elian has, and a step that leaves a number out only on the sword, whose
## steps are the hero's own swings (hero.json, player_actions.json).
const WEAPON_STEP_BOUNDS := {"multiplier": [0.2, 4.0], "recovery": [0.15, 2.0], "wind": [0.0, 0.3],
	"knockback": [0.0, 4.0], "stagger": [0.0, 1.0], "animation_time": [0.1, 0.6], "speed": [0.5, 2.0]}
const WEAPON_BOUNDS := {"damage": [0.5, 2.0], "backstab": [0.0, 2.0], "poise": [0.0, 0.5],
	"combo_window": [0.4, 2.0], "pitch": [0.5, 1.5], "auto_reach": [24.0, 80.0]}
const WEAPON_STEP_NEEDS := ["multiplier", "recovery", "knockback", "heavy"]
const WEAPON_ANIMATIONS := ["attack", "attack2", "attack3", "thrust", "rising", "dash_strike"]
const WEAPON_ARCS := ["white", "gold", "red", "heavy", "path"]
## A weapon's own frames (`"frames"`, make_weapon_frames.py) must be drawn for
## its chain's poses and for these, which any weapon in hand may be put in
## (Weapons.FRAMED).
const WEAPON_FRAMED := ["draw", "guard", "thrust", "rising", "dash_strike", "lunge", "charge", "cleave", "sweep"]
const HERO_FRAMES := "res://assets/sprites/elian_frames.tres"


func _check_weapon(entry: Dictionary, where: String) -> void:
	_use_key(entry.get("name", ""), where)
	_use_key(entry.get("description", ""), where)
	if not ResourceLoader.exists(str(entry.get("icon", ""))):
		_error("%s: icon not found: %s" % [where, entry.get("icon", "")])
	for key in WEAPON_BOUNDS:
		if entry.has(key):
			_bounded(entry[key], WEAPON_BOUNDS[key], "%s.%s" % [where, key])
	for key in ["hitbox", "offset", "slash_scale"]:
		if entry.has(key):
			_weapon_pair(entry[key], key, where)
	var chain = entry.get("chain", [])
	if not chain is Array or chain.is_empty() or chain.size() > 5:
		_error("%s: chain is 1–5 steps" % where)
		return
	var own: bool = entry.get("id", "") == "sword"
	if entry.has("frames"):
		_check_weapon_frames(str(entry.frames), chain, where)
	for i in chain.size():
		var step = chain[i]
		var at := "%s.chain[%d]" % [where, i]
		if not step is Dictionary:
			_error("%s must be an object" % at)
			continue
		if not WEAPON_ANIMATIONS.has(step.get("animation", "")):
			_error("%s: animation is a pose Elian has: %s" % [at, WEAPON_ANIMATIONS])
		if not own:
			for key in WEAPON_STEP_NEEDS:
				if not step.has(key):
					_error("%s: needs \"%s\" (only the sword's steps fall back on the hero's own)" % [at, key])
		for key in WEAPON_STEP_BOUNDS:
			if step.has(key):
				_bounded(step[key], WEAPON_STEP_BOUNDS[key], "%s.%s" % [at, key])
		if step.has("heavy") and not step.heavy is bool:
			_error("%s.heavy is true or false" % at)
		if step.has("arc") and not WEAPON_ARCS.has(step.arc):
			_error("%s.arc is one of %s" % [at, WEAPON_ARCS])
		for key in ["hitbox", "offset"]:
			if step.has(key):
				_weapon_pair(step[key], key, at)
	var moves = entry.get("techniques", {})
	if not moves is Dictionary:
		_error("%s: techniques is an object of move -> overrides" % where)
	else:
		for move in moves:
			if not move in ["lunge", "cleave", "sweep"] or not moves[move] is Dictionary:
				_error("%s: techniques.%s: only lunge, cleave and sweep, each an object" % [where, move])
				continue
			for key in moves[move]:
				if key in ["hitbox", "offset"]:
					_weapon_pair(moves[move][key], key, "%s.techniques.%s" % [where, move])
				elif key == "multiplier":
					_bounded(moves[move][key], [0.2, 5.0], "%s.techniques.%s.multiplier" % [where, move])
				elif key in WEAPON_STEP_BOUNDS:
					_bounded(moves[move][key], WEAPON_STEP_BOUNDS[key], "%s.techniques.%s.%s" % [where, move, key])
				else:
					_error("%s.techniques.%s: unknown key %s" % [where, move, key])


## Every pose the weapon's chain names, and every one the body may take with
## it in hand, drawn as <frames>_<pose> in the hero's SpriteFrames.
func _check_weapon_frames(prefix: String, chain: Array, where: String) -> void:
	if prefix == "" or not prefix.is_valid_identifier():
		_error("%s: frames is the prefix of its animations in %s (spear -> spear_attack)" % [where, HERO_FRAMES])
		return
	var hero = load(HERO_FRAMES)
	if hero == null:
		_error("%s: cannot load %s" % [where, HERO_FRAMES])
		return
	var poses: Array = WEAPON_FRAMED.duplicate()
	for step in chain:
		if step is Dictionary and not poses.has(str(step.get("animation", ""))):
			poses.append(str(step.get("animation", "")))
	for pose in poses:
		var own := "%s_%s" % [prefix, pose]
		if not hero.has_animation(own):
			_error("%s: no \"%s\" in %s (tools/art/make_weapon_frames.py, build_elian_frames.py)" % [where, own, HERO_FRAMES])
		elif hero.has_animation(pose) and hero.get_frame_count(own) != hero.get_frame_count(pose):
			# a hit frame, a hold, the touch of a technique are counted in the hero's frames
			_error("%s: %s has %d frames, %s has %d" % [where, own, hero.get_frame_count(own), pose, hero.get_frame_count(pose)])


func _bounded(value, bounds: Array, label: String) -> void:
	if not (value is float or value is int) or not is_finite(float(value)) \
			or float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
		_error("%s must be a number in %s–%s" % [label, bounds[0], bounds[1]])


## A hitbox is at most 96×64 and starts in front of the body; an offset keeps
## the box near him; slash_scale stretches the drawn arc 0.4–2×.
func _weapon_pair(pair, key: String, where: String) -> void:
	if not pair is Array or pair.size() != 2 or not ((pair[0] is float or pair[0] is int) and (pair[1] is float or pair[1] is int)):
		_error("%s.%s needs two numbers" % [where, key])
		return
	var x := float(pair[0])
	var y := float(pair[1])
	match key:
		"hitbox":
			if x < 8.0 or x > 96.0 or y < 8.0 or y > 64.0:
				_error("%s.hitbox is 8–96 wide and 8–64 high" % where)
		"offset":
			if x < 0.0 or x > 60.0 or absf(y) > 40.0:
				_error("%s.offset is 0–60 ahead and within 40 up or down" % where)
		"slash_scale":
			if x < 0.4 or x > 2.0 or y < 0.4 or y > 2.0:
				_error("%s.slash_scale is 0.4–2 each way" % where)


## The game must have the sword: every night's first weapon (Weapons.DEFAULT).
func _check_weapons() -> void:
	var ids: Array = _game_entries("weapons").map(func(w: Dictionary) -> String: return str(w.get("id", "")))
	if not ids.has("sword"):
		_error("weapons: the sword (Weapons.DEFAULT) is every night's first and must exist")


func _check_player_actions() -> void:
	var doc = _doc("player_actions.json")
	if not doc is Dictionary or not doc.get("actions") is Dictionary:
		_error("player_actions.json needs an actions object")
		return
	for id: String in doc.actions:
		var action = doc.actions[id]
		if not action is Dictionary:
			_error("player action %s must be an object" % id)
			continue
		for key in ["multiplier", "knockback", "recovery", "animation_time", "stagger", "radius"]:
			if action.has(key) and (not action[key] is float and not action[key] is int or float(action[key]) < 0 or not is_finite(float(action[key]))):
				_error("player action %s.%s needs a finite nonnegative number" % [id, key])
		for key in ["hitbox", "offset"]:
			if action.has(key):
				var pair = action[key]
				if not pair is Array or pair.size() != 2:
					_error("player action %s.%s needs two numbers" % [id, key])
				else:
					for v in pair:
						if not (v is int or v is float) or not is_finite(float(v)) or (key == "hitbox" and float(v) <= 0):
							_error("invalid player action %s.%s" % [id, key])
		if action.has("hit_frame") and (not (action.hit_frame is int or action.hit_frame is float) or int(action.hit_frame) != action.hit_frame or action.hit_frame < 0):
			_error("player action %s.hit_frame needs a nonnegative integer" % id)
		if action.has("sfx") and not action.sfx is String:
			_error("player action %s.sfx needs a sound name" % id)
