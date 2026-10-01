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
## Resonances awake this night (scripts/combat/resonances.gd): derived from
## the gifts, kept so each is applied to the body once.
var resonances: Array[String] = []
## Items found this run, by id (ItemSystem): each at most once.
var items: Array[String] = []
## Rest points used this night, by room scene path: each once.
var rested: Dictionary = {}
## Rooms entered this night, by scene path, in order: the way the map draws
## (scripts/ui/chapter_map.gd), which side of each fork included.
var walked: Array[String] = []
var wave := 0
## Which place of the chapter we are in (data/chapters/*.json, an id). The
## curtain announces it; the bestiary remembers where a creature was first met.
var place := ""
## Run clock in seconds, kept by the Run scene; drives enemy time scaling.
var elapsed := 0.0
var essence := 0.0
var level := 1
var ash_earned := 0
## The enemy id being practised against in the practice yard, or "" for a
## real night (docs/PRACTICE.md). Set by the bestiary before the Run starts
## and cleared when it is left; new_run does not touch it, the Run calls
## new_run itself. While set nothing counts: no essence, no Ash, no
## bestiary, no profile, no save.
var practice := ""
## The date of the night of the day being played (scripts/run/daily.gd), "" for
## an ordinary night. Set by the main menu like practice, kept across new_run.
var daily := ""
## Whether the night of the day just finished beat the day's best (end screen).
var daily_best := false
## Rooms this body cleared without a wound, this night (Run._on_unscathed).
var unscathed := 0
## What laid our own body low this night (Player.slain_by): an enemy id,
## "lava", "fall", or "" while it stands. The end screen, the chronicle and
## the bestiary read it.
var slain_by := ""
## The last blows our own body took this night, oldest first, at most
## LAST_BLOWS of them: {by: what Player._blame names, amount}. The end screen
## shows them under the killer, so a death reads as the fight it was.
var last_blows: Array = []
const LAST_BLOWS := 3
## The omen this night is drawn under (data/omens, Omens), "" for a plain night.
var omen := ""
## The vial of wrath this night is played under (scripts/run/vials.gd), 0 for none.
var vial := 0
## Times the gift cards may still be dealt again tonight (the rosary, Relics).
var rerolls := 0
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
	resonances = []
	items = []
	rested = {}
	walked = []
	wave = 0
	place = ""
	elapsed = 0.0
	essence = 0.0
	level = 1
	ash_earned = 0
	unscathed = 0
	slain_by = ""
	last_blows = []
	omen = ""
	vial = 0
	rerolls = 0
	essence_bonus = 0.0


## One more blow taken by our own body (Player._apply_damage).
func note_blow(by: String, amount: float) -> void:
	last_blows.append({"by": by, "amount": roundi(amount)})
	while last_blows.size() > LAST_BLOWS:
		last_blows.pop_front()


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


## How far the leading path is ahead of the next one: the aura shows from 2
## (Player._update_aura), and a night counts towards a habit from 2 too.
func lead() -> int:
	var path := dominant_path()
	var ahead := 1 << 30
	for other in PATHS:
		if other != path:
			ahead = mini(ahead, int(alignment[path]) - int(alignment.get(other, 0)))
	return ahead


## Essence needed to finish the current level: 140 × 1.3^(level−1) (docs/BALANCE.md).
func essence_needed() -> float:
	return 140.0 * pow(1.3, level - 1)


func add_essence(amount: float) -> void:
	# an omen may make the dead give more (data/omens: "essence")
	essence += amount * (1.0 + essence_bonus) * float(Vials.rule("essence"))
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
## In practice the clock does not harden anybody: the foe stays the one met.
func enemy_hp_multiplier() -> float:
	return Settings.difficulty_hp() * float(Vials.rule("enemy_hp")) \
		* (1.0 + (0.0 if practice != "" else 0.06 * floorf(elapsed / 180.0)))


func enemy_damage_multiplier() -> float:
	return Settings.difficulty_damage() * float(Vials.rule("enemy_damage")) \
		* (1.0 + (0.0 if practice != "" else 0.04 * floorf(elapsed / 180.0)))
