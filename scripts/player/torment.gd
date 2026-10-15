extends RefCounted
class_name Torment
## The locust's sting (docs/CHAPTER5.md §2, Rev. 9:5–6): a stung body heals
## with nothing — flask, rest, gifts, items, pools — until it passes. It never
## hurts and never kills: "they shall seek death and not find it". A new sting
## keeps the longer of the two, never a sum, never past CAP. A fruit, time, a
## death and a revive lift it; the Seal on the Brow keeps it off altogether.
## The rules live here; Player holds `torment` and asks `can_heal()`.

const CAP := 12.0
## The brown tremor along his edge (alignment_marks.gdshader `torment`).
const TREMOR := 0.85
## Glut counts at most this many of the night's surfeit.
const GLUT_COUNT := 8
## Seeking Death: the sting a refused death leaves, seconds.
const REFUSED_STING := 4.0


static func apply(player: Player, seconds: float) -> void:
	if player.is_dead() or seconds <= 0.0 or player.stats.get("torment_immune", 0.0) > 0.0:
		return
	var sting := seconds * float(Vials.rule("torment"))
	if sting > player.torment:
		Audio.play(&"locust_hum", -8.0)
	player.torment = minf(CAP, maxf(player.torment, sting))


## Every frame, every body: our own counts down; all show the tremor.
static func tick(player: Player, delta: float) -> void:
	if player.torment > 0.0 and player._is_mine():
		player.torment = maxf(0.0, player.torment - delta)
	_show(player)


static func _show(player: Player) -> void:
	var body := player.body
	if body == null:
		return
	var strength := clampf(player.torment / 3.0, 0.0, 1.0) * TREMOR * Settings.flash_scale()
	if strength <= 0.0:
		if body.material is ShaderMaterial:
			(body.material as ShaderMaterial).set_shader_parameter("torment", 0.0)
		return
	player._marks_material().set_shader_parameter("torment", strength)


## The flask pressed under the sting: an empty sound and a mark over his head.
static func deny(player: Player) -> void:
	Audio.play(&"denied", -4.0)
	Fx.puff(player.global_position + Vector2(0, -30), 0.5, Color(0.55, 0.38, 0.22))
	Fx.popup(player.global_position + Vector2(0, -40), player.tr("HUD_TORMENT"), Color(0.85, 0.6, 0.35))


## Seeking Death (`death_refused`): once a room, a killing blow leaves one hp
## and a sting. Never in the practice yard, where nobody dies anyway.
static func refuse_death(player: Player) -> bool:
	if player.stats.get("death_refused", 0.0) <= 0.0 or player._death_refused_room or Game.practice != "":
		return false
	player._death_refused_room = true
	player.hp = 1.0
	apply(player, REFUSED_STING)
	Fx.puff(player.global_position + Vector2(0, -12), 1.0, Color(0.5, 0.36, 0.24))
	return true


## Glut (+ per surfeit, counted to GLUT_COUNT) and Honeyed Sting (while stung).
static func damage_factor(player: Player) -> float:
	var factor := 1.0
	var glut := float(player.stats.get("glut", 0.0))
	if glut > 0.0:
		factor *= 1.0 + glut * mini(Game.surfeit, GLUT_COUNT)
	var honey := float(player.stats.get("torment_damage", 0.0))
	if honey > 0.0 and player.torment > 0.0:
		factor *= 1.0 + honey
	return factor
