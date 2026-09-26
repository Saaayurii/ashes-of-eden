extends SceneTree
## Headless check of the enemy attack choice (Enemy._choose_attack) and of what
## a hit does to the next wind-up:
##   godot --headless -s scripts/tools/attack_pick_test.gd
## With several attacks in range repeats are rare, not forbidden; one attack
## (or one in range) still repeats; phases still gate; a seeded choice is reproducible;
## a flinch or a broken wind-up holds the next telegraph back and drops the glow.
## Exit code 1 on any failure.
## Deliberately untyped w.r.t. game classes, like every -s tool script.

const SEED := 20260926
const PICKS := 300
const STATE_CHASE := 2
const STATE_WINDUP := 3
const STATE_RECOVER := 5

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failed = true

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _spawn(parent: Node, id: String, at: Vector2):
	var enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	enemy.enemy_id = id
	parent.add_child(enemy)
	enemy.global_position = at
	enemy.set_physics_process(false)  # no AI: the test asks for every choice
	return enemy

## [param n] choices as the AI makes them: each one becomes the "last".
func _sequence(enemy, to_target: Vector2, n: int, seed_value: int) -> Array:
	enemy.attack_rng.seed = seed_value
	enemy._last_attack = -1
	var out := []
	for i in n:
		var pick: int = enemy._choose_attack(to_target)
		if pick >= 0:
			enemy._last_attack = pick
		out.append(pick)
	return out

func _repeats(picks: Array) -> int:
	var count := 0
	for i in range(1, picks.size()):
		if picks[i] == picks[i - 1]:
			count += 1
	return count

func _used(picks: Array) -> Array:
	var seen := []
	for p in picks:
		if not seen.has(p):
			seen.append(p)
	seen.sort()
	return seen

func _run() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	await _frames(2)

	# 1. a boss with a repertoire (knight_of_ash: melee, lunge, ranged from 60 %)
	var knight = _spawn(stage, "knight_of_ash", Vector2(200, 200))
	await _frames(2)
	var close := Vector2(40, 0)
	var picks := _sequence(knight, close, PICKS, SEED)
	_check(_repeats(picks) > 0 and _repeats(picks) < PICKS * 0.3,
		"knight: repeated moves rare but possible (%d / %d)" % [_repeats(picks), PICKS - 1])
	_check(_used(picks) == [0, 1], "knight at full health uses melee and lunge only (%s)" % str(_used(picks)))
	_check(picks == _sequence(knight, close, PICKS, SEED), "same seed, same choices")

	# 2. its second phase adds the volley; all three appear, repeats stay rare
	knight.hp = knight._max_hp * 0.5
	picks = _sequence(knight, close, PICKS, SEED)
	_check(_repeats(picks) < PICKS * 0.3, "knight below 60 %%: rare repeats (%d)" % _repeats(picks))
	_check(_used(picks) == [0, 1, 2], "every phase attack gets used (%s)" % str(_used(picks)))
	_check(picks != _sequence(knight, close, PICKS, SEED + 1), "another seed changes three-way choices")
	# the weights still count: melee (3) outweighs each of the other two (2)
	var melee := picks.count(0)
	_check(melee > picks.count(1) and melee > picks.count(2),
		"weights still lean to melee (%d / %d / %d)" % [melee, picks.count(1), picks.count(2)])
	knight.hp = knight._max_hp

	# 3. only one attack in range: it repeats rather than doing nothing
	picks = _sequence(knight, Vector2(300, 0), 20, SEED)
	_check(_used(picks) == [1], "out of melee reach the lunge repeats (%s)" % str(_used(picks)))
	_check(_sequence(knight, Vector2(900, 0), 5, SEED) == [-1, -1, -1, -1, -1], "nothing in range: no attack")

	# 4. the legacy single-attack format keeps its one swing even when an
	# archetype normally extends this cultist with more moves.
	var cultist = _spawn(stage, "cultist", Vector2(400, 200))
	await _frames(2)
	cultist._attacks = [cultist._attacks[0]]
	picks = _sequence(cultist, Vector2(20, 0), 20, SEED)
	_check(_used(picks) == [0] and _repeats(picks) == 19, "a one-attack enemy repeats its swing")

	# 5. a summoner whose summon is spent still casts its bolt
	var caller = _spawn(stage, "cult_caller", Vector2(600, 200))
	await _frames(2)
	picks = _sequence(caller, Vector2(120, 0), PICKS, SEED)
	_check(_repeats(picks) < PICKS * 0.3 and _used(picks) == [0, 1],
		"caller varies summon and bolt (%d repeats)" % _repeats(picks))

	# 6. the ophanim's final phase: beams and dives should mix
	var ophanim = _spawn(stage, "ophanim", Vector2(800, 100))
	await _frames(2)
	ophanim.hp = ophanim._max_hp * 0.3
	picks = _sequence(ophanim, Vector2(20, 10), PICKS, SEED)
	_check(_repeats(picks) < PICKS * 0.3 and _used(picks).size() >= 3,
		"ophanim late phase: varied moves (%d repeats)" % _repeats(picks))

	# 7. a flinch holds the next wind-up back past the hurt pose
	var guard = _spawn(stage, "fallen_guard", Vector2(1000, 200))
	var striker := Node2D.new()
	stage.add_child(striker)
	striker.global_position = Vector2(980, 200)
	await _frames(2)
	guard.aware = true
	guard.state = STATE_CHASE
	guard._attack_cd = 0.0
	guard.take_damage(1.0, striker)
	var flinch := float(guard.stats.get("flinch", 0.18))
	_check(guard.state == STATE_RECOVER, "a hit stops a walking body (state %d)" % guard.state)
	_check(guard._attack_cd >= flinch + guard.HIT_ATTACK_DELAY - 0.001,
		"no wind-up until a beat after the flinch (%.2f s)" % guard._attack_cd)

	# 8. a broken wind-up stops glowing and waits too
	guard.stats.stagger_chance = 1.0
	guard.state = STATE_CHASE
	guard._attack_cd = 0.0
	guard._last_attack = guard._choose_attack(Vector2(20, 0))
	guard._attack = guard._attacks[guard._last_attack]
	guard._begin_windup(Vector2(20, 0))
	_check(guard.state == STATE_WINDUP and guard._telegraph_tween != null, "wind-up telegraphed")
	guard.take_damage(1.0, striker)
	_check(guard.state == STATE_RECOVER, "the hit breaks the wind-up")
	_check(guard._telegraph_tween == null, "the telegraph glow is cancelled")
	_check(guard._attack_cd >= 0.4 + guard.HIT_ATTACK_DELAY - 0.001,
		"the broken attack waits past its recovery (%.2f s)" % guard._attack_cd)
	await create_timer(0.3).timeout
	_check(guard.visual.modulate.is_equal_approx(Color.WHITE), "colour back to normal (%s)" % str(guard.visual.modulate))

	print("attack_pick_test: " + ("FAILED" if _failed else "passed"))
	quit(1 if _failed else 0)
