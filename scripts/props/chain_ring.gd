extends RefCounted
class_name ChainRing
## The ring a chain is fastened to (prop kind "chain", docs/CHAPTER6.md §9):
## the anchor of the chained body standing nearest it (Tether). A blade only
## rings on the iron; only the keys named by "opens_with" (a flag: the abbot's,
## saul_keys) open it, on `interact` like a cursed chest — then the body held
## to it is loosed (Enemy.loose, on the host). Frames: hanging, a spark, open.

## Where on the strip the chain leaves the ring, above the prop's foot.
const RING_HEIGHT := 14.0


static func setup(prop: Prop) -> void:
	prop.add_to_group("chain_rings")
	prop._add_prompt()
	prop._prompt.modulate = Color(0.85, 0.9, 1.0)


## The flag the ring waits for: without it, no prompt and no opening.
static func can_open(prop: Prop) -> bool:
	return Game.flags.has(str(prop.stats.get("opens_with", "saul_keys")))


## A blow without the keys: the iron rings and throws sparks, nothing breaks.
static func struck(prop: Prop) -> void:
	if prop._spent:
		return
	Audio.play_at(&"block", prop.global_position, -6.0)
	Fx.sparkle(prop.global_position + Vector2(0, -RING_HEIGHT), Color(1.0, 0.92, 0.7), 6, 6.0)
	prop.sprite.frame = 1
	prop.get_tree().create_timer(0.12).timeout.connect(func() -> void:
		if is_instance_valid(prop) and not prop._spent:
			prop.sprite.frame = 0)


## The keys turned (every peer; the host looses the body).
static func unlock(prop: Prop) -> void:
	prop.sprite.frame = 2
	Fx.sparkle(prop.global_position + Vector2(0, -RING_HEIGHT), Color(0.85, 0.9, 1.0), 10, 8.0)
	var held: Variant = prop.get_meta("chained") if prop.has_meta("chained") else null
	if held is Enemy and is_instance_valid(held):
		(held as Enemy).loose()
	elif Audio.has_clip(&"chain_unlock"):
		Audio.play_at(&"chain_unlock", prop.global_position, -4.0)
