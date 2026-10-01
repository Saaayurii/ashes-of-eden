extends RefCounted
class_name Omens
## The omen of the night (data/omens, docs/OMENS.md): from the fourth night on,
## most nights are drawn under one — a trade, never a plain curse or a plain
## gift: the dead give more and hit harder, the altars run dry and the Ash
## runs richer. Its "rules" are the vials' rules (Vials stacks them on top of
## the vial's), plus "essence" (Game.add_essence) and "ash" (the night's pay).
## Solo only, none in the practice yard; the night of the day draws the day's
## own, the same for everyone.

## Finished nights before the first omen: the first three nights are plain.
const FROM_NIGHT := 3
## How often a night has an omen at all, once they have begun.
const CHANCE := 0.6


static func spec(id: String) -> Dictionary:
	return Data.omens.get(id, {})


## The rules [param id] lays on a night ({} for none).
static func rules(id := "") -> Dictionary:
	if id == "":
		id = Game.omen
	return spec(id).get("rules", {})


## One omen or none, drawn with [param rng]: CHANCE of one, then each the same.
static func roll(rng: RandomNumberGenerator) -> String:
	var ids: Array = Data.omens.keys()
	ids.sort()  # the same seed draws the same omen on every machine
	if ids.is_empty() or rng.randf() >= CHANCE:
		return ""
	return str(ids[rng.randi_range(0, ids.size() - 1)])


## The omen a new night is played under. A tool script (`godot -s`) draws
## none unless it asks ([param in_tools]): a test that starts a run measures
## blows and flasks, and a random omen would move them under it.
static func for_new_night(in_tools := false) -> String:
	if Net.active or Game.practice != "":
		return ""
	var args := OS.get_cmdline_args()
	if not in_tools and (args.has("-s") or args.has("--script")):
		return ""
	var rng := RandomNumberGenerator.new()
	if Game.daily != "":
		rng.seed = Daily.seed_of(Game.daily) + 1
		return roll(rng)
	if int(Profile.data.get("nights", 0)) < FROM_NIGHT:
		return ""
	rng.randomize()
	return roll(rng)
