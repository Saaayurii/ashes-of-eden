class_name AbilitySystem
## Applies a gift (ability) from res://data/abilities to the player, then
## clamps to the soft caps from docs/BALANCE.md so no single combination
## breaks the game.
## Effect types understood so far:
##   {"type": "stat", "stat": "attack_damage", "op": "add" | "mul", "value": 5}
##   {"type": "lifesteal", "value": 0.15}
##   {"type": "extra_life", "value": 1}
##   {"type": "heal", "value": 30 | "full"}
## Mechanics (thorns, execute, guard, waves, ...) are plain entries of
## Player.BASE_STATS set through "stat", so a new one is data plus the code
## that reads it — see docs/DATA_FORMATS.md for the full list.
## Add a new type here AND to scripts/tools/validate_data.gd.

## stat -> [min, max] relative to Player.BASE_STATS
const CAPS := {
	"attack_cooldown": [0.5, 10.0],  # attack speed +100 %
	"crit_chance": [0.0, 0.5],
	"speed": [0.5, 1.6],
	"dash_cooldown": [1.2, 10.0],
	"lifesteal": [0.0, 0.15],
	"armor": [0.0, 0.5],
	"thorns": [0.0, 0.6],
	"execute": [0.0, 1.2],
	"kill_heal": [0.0, 10.0],
	"clear_heal": [0.0, 40.0],
	"dash_damage": [0.0, 45.0],
	"wave_damage": [0.0, 1.2],
	"essence_bonus": [0.0, 0.6],
	"guard": [0.0, 3.0],
	# item mechanics (data/items)
	"heal_burst": [0.0, 60.0],
	"parry_stun": [0.0, 1.5],
	"chest_heal": [0.0, 40.0],
	"backstab_refresh": [0.0, 1.0],
	"clean_clear_charge": [0.0, 1.0],
	"wrath_after_hit": [0.0, 1.0],
	"desperate_crit_heal": [0.0, 12.0],
}
## Caps expressed as multipliers of the base value rather than absolutes.
const RELATIVE := ["attack_cooldown", "speed"]


static func apply(player: Player, ability: Dictionary) -> void:
	for effect in ability.get("effects", []):
		match effect.get("type", ""):
			"stat":
				_apply_stat(player, effect)
			"lifesteal":
				player.stats.lifesteal += float(effect.get("value", 0.0))
			"extra_life":
				player.stats.extra_lives += int(effect.get("value", 1))
			"skill":
				player.skill = effect.get("skill", {}).duplicate()
			"heal":
				var value = effect.get("value", "full")
				player.heal(player.stats.max_hp if value is String else float(value))
			_:
				push_warning("Unknown effect type \"%s\" in ability %s" % [effect.get("type"), ability.id])
	_clamp(player)
	# The essence bar belongs to the run, not to the body carrying the gift.
	Game.essence_bonus = player.stats.essence_bonus
	player.refresh_stats()
	Game.apply_effect(ability.get("alignment", {}))
	Game.abilities.append(ability)
	EventBus.ability_acquired.emit(ability)


static func _apply_stat(player: Player, effect: Dictionary) -> void:
	var stat: String = effect.get("stat", "")
	if not player.stats.has(stat):
		push_warning("Unknown stat \"%s\"" % stat)
		return
	var value := float(effect.get("value", 0))
	match effect.get("op", "add"):
		"add":
			player.stats[stat] += value
		"mul":
			player.stats[stat] *= value
		_:
			push_warning("Unknown op \"%s\"" % effect.get("op"))


static func _clamp(player: Player) -> void:
	for stat in CAPS:
		var lo: float = CAPS[stat][0]
		var hi: float = CAPS[stat][1]
		if RELATIVE.has(stat):
			lo *= Player.BASE_STATS[stat]
			hi *= Player.BASE_STATS[stat]
		player.stats[stat] = clampf(player.stats[stat], lo, hi)
	player.stats.max_hp = maxf(player.stats.max_hp, 10.0)
