extends Node
## Run-wide state: the three hidden alignment counters, story flags and
## the gifts (abilities) taken this run. The player never sees the numbers;
## the world reacts to them (dialogue, visuals, endings).

const PATH_GRACE := "grace"
const PATH_TEMPTATION := "temptation"
const PATH_WILL := "will"
const PATHS := [PATH_GRACE, PATH_TEMPTATION, PATH_WILL]

var alignment: Dictionary = {}
var flags: Dictionary = {}
## A cutscene is playing: enemies hold where they stand, the player's hands are off the controls.
var cutscene := false
var abilities: Array[Dictionary] = []
## Items found this run, by id (ItemSystem): each at most once.
var items: Array[String] = []
## Rest points used this night, by room scene path: each once.
var rested: Dictionary = {}
var wave := 0
## Which place of the chapter we are in (data/chapters/*.json, an id). The
## curtain announces it; the bestiary remembers where a creature was first met.
var place := ""
## Run clock in seconds, kept by the Run scene; drives enemy time scaling.
var elapsed := 0.0
var essence := 0.0
var level := 1
var ash_earned := 0
## What the greedier gifts add to every kill. Mirrored here from the player's
## stats by AbilitySystem, because the essence bar is the run's, not the body's.
var essence_bonus := 0.0


func _ready() -> void:
	new_run()


func new_run() -> void:
	cutscene = false
	alignment = {PATH_GRACE: 0, PATH_TEMPTATION: 0, PATH_WILL: 0}
	flags = {}
	abilities = []
	items = []
	rested = {}
	wave = 0
	place = ""
	elapsed = 0.0
	essence = 0.0
	level = 1
	ash_earned = 0
	essence_bonus = 0.0


## Applies an "effect" block from data, e.g. {"grace": 1, "set_flags": ["stranger_spared"]}.
func apply_effect(effect: Dictionary) -> void:
	if effect.is_empty():
		return
	for path in PATHS:
		alignment[path] += int(effect.get(path, 0))
	for flag in effect.get("set_flags", []):
		flags[flag] = true
	EventBus.alignment_changed.emit(alignment.duplicate())


## The path the player leans towards. Ties resolve to Will: the human default.
func dominant_path() -> String:
	var best := PATH_WILL
	for path in [PATH_GRACE, PATH_TEMPTATION]:
		if alignment[path] > alignment[best]:
			best = path
	return best


## Essence needed to finish the current level: 140 × 1.3^(level−1) (docs/BALANCE.md).
func essence_needed() -> float:
	return 140.0 * pow(1.3, level - 1)


func add_essence(amount: float) -> void:
	essence += amount * (1.0 + essence_bonus)
	var leveled := false
	while essence >= essence_needed():
		essence -= essence_needed()
		level += 1
		leveled = true
	EventBus.essence_changed.emit(essence, essence_needed(), level)
	if leveled:
		EventBus.level_up.emit(level)


## Essence is shared in co-op and counted by the host; this is how a client
## is told where the shared bar stands. No level_up is fired here: the host
## announces that separately so both players are offered a gift at once.
func set_essence(value: float, new_level: int) -> void:
	essence = value
	level = new_level
	EventBus.essence_changed.emit(essence, essence_needed(), level)


## Enemy stat multipliers for this moment of the run: difficulty mode × time scaling.
func enemy_hp_multiplier() -> float:
	return Settings.difficulty_hp() * (1.0 + 0.06 * floorf(elapsed / 180.0))


func enemy_damage_multiplier() -> float:
	return Settings.difficulty_damage() * (1.0 + 0.04 * floorf(elapsed / 180.0))
