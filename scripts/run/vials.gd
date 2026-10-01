extends RefCounted
class_name Vials
## The vials of wrath (data/vials, docs/VIALS.md): after a dawn the next one
## opens, and a night can be played under any vial opened so far. Each adds
## one rule to the ones below it, so the fifth holds all five:
##   promote_chance / promote  a common one rises as its elite (Run._spawn_enemy)
##   flasks                    flasks carried into the night (Player._ready)
##   enemy_damage / enemy_hp   on top of the difficulty (Game.enemy_*_multiplier)
##   rest_heal                 what an altar gives back (Player.rest)
## and the night's Ash is multiplied by the vial's own "ash". Solo only: online
## the two bodies would each carry their own, and the host's enemies one.

const TIERS := 5
## How a rule stacks as the vials pile up.
const ADD := ["flasks"]
const MUL := ["enemy_damage", "enemy_hp", "essence"]
const MAX := ["promote_chance"]
const MIN := ["rest_heal"]
const DEFAULTS := {"flasks": 0, "enemy_damage": 1.0, "enemy_hp": 1.0, "promote_chance": 0.0, "rest_heal": 1.0,
	"essence": 1.0}


## The vial of [param tier], {} for none.
static func spec(tier: int) -> Dictionary:
	for vial in Data.vials.values():
		if int(vial.get("tier", 0)) == tier:
			return vial
	return {}


## Every rule in force under [param tier] (Game.vial by default — and then
## the night's omen on top, which stacks the same way: data/omens).
static func rules(tier := -1) -> Dictionary:
	var tonight := tier < 0
	if tonight:
		tier = Game.vial
	var out := DEFAULTS.duplicate()
	out["promote"] = {}
	for t in range(1, tier + 1):
		_stack(out, spec(t).get("rules", {}))
	if tonight:
		_stack(out, Omens.rules())
	return out


static func _stack(out: Dictionary, own: Dictionary) -> void:
	for key in own:
		if key in ADD:
			out[key] += own[key]
		elif key in MUL:
			out[key] *= float(own[key])
		elif key in MAX:
			out[key] = maxf(out[key], float(own[key]))
		elif key in MIN:
			out[key] = minf(out[key], float(own[key]))
		elif own[key] is Dictionary and out.get(key) is Dictionary:
			out[key].merge(own[key], true)


static func rule(key: String) -> Variant:
	return rules().get(key, DEFAULTS.get(key, 0))


## The Ash a night under [param tier] is worth, per Ash earned (tonight's
## omen's "ash" too, when the tier is tonight's).
static func ash_multiplier(tier := -1) -> float:
	var omen := 1.0
	if tier < 0:
		tier = Game.vial
		omen = float(Omens.rules().get("ash", 1.0))
	return (float(spec(tier).get("ash", 1.0)) if tier > 0 else 1.0) * omen


## The vials this profile may choose: 0 (none) up to the one its last dawn opened.
static func opened() -> int:
	return clampi(int(Profile.data.get("vials_opened", 0)), 0, TIERS)


## The vial a new night is played under: the one chosen in Settings, if this
## profile has opened it; none online or in the practice yard.
static func for_new_night() -> int:
	if Net.active or Game.practice != "":
		return 0
	return clampi(Settings.vial, 0, opened())
