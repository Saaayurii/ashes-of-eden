extends Label
class_name MoveHints
## Teaches the special moves in the night, where they are needed
## (docs/TECHNIQUES.md): it watches our own body's fight a few times a second
## and, the first time a moment calls for a move the player has never done,
## says so in one line at the bottom of the screen. Once per move per profile
## (Profile.data.hints_shown), never for a move already done
## (Profile.data.moves_done), never in a scene, never in the practice yard
## (its move list does this job there).
##
## The moments, in the order they are looked for:
##   rising  a flyer overhead, close          → up + attack
##   sweep   a walker winding up at arm's reach → down + attack
##   cleave  an armoured one in reach          → hold attack, let go on the glow
##   lunge   two of them in a row ahead        → back, forward, attack

const CHECK_EVERY := 0.4
const SHOW_FOR := 5.0
## Between two hints, whatever happens: one lesson at a time.
const QUIET_FOR := 25.0

var _clock := 0.0
var _quiet := 0.0
var _showing := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_theme_font_size_override("font_size", int(round(9 * Settings.text_scale())))
	add_theme_color_override("font_color", Color(0.98, 0.88, 0.62))
	add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.06))
	add_theme_constant_override("outline_size", 3)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -170
	offset_right = 170
	offset_top = -58
	offset_bottom = -40
	modulate.a = 0.0


func _process(delta: float) -> void:
	_quiet = maxf(0.0, _quiet - delta)
	if _showing > 0.0:
		_showing -= delta
		if _showing <= 0.0:
			create_tween().tween_property(self, "modulate:a", 0.0, 0.4)
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = CHECK_EVERY
	if _quiet > 0.0 or Game.cutscene or Game.practice != "":
		return
	var hero := _our_body()
	if hero == null or hero.is_dead():
		return
	var id := moment(hero, get_tree().get_nodes_in_group("enemies"))
	if id != "":
		show_hint(id)


## Which move the fight around [param hero] calls for right now, "" for none.
## Static on its inputs so a test can hand it a situation.
static func moment(hero: Node2D, enemies: Array) -> String:
	var walkers_ahead := 0
	var facing: int = hero.get("facing") if hero.get("facing") != null else 1
	var found := {}
	for node in enemies:
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead() or enemy.is_unaware():
			continue
		var d := enemy.global_position - hero.global_position
		var behaviour := str(enemy.stats.get("behaviour", "walker"))
		if behaviour == "flyer" and d.y < -36.0 and absf(d.x) < 60.0:
			found["rising"] = true
		if behaviour in ["walker", "caster"] and absf(d.y) < 20.0:
			if enemy.state == Enemy.State.WINDUP and absf(d.x) < 56.0:
				found["sweep"] = true
			if float(enemy.stats.get("armor", 0.0)) > 0.0 and absf(d.x) < 80.0:
				found["cleave"] = true
			if d.x * facing > 30.0 and absf(d.x) < 170.0:
				walkers_ahead += 1
	if walkers_ahead >= 2:
		found["lunge"] = true
	for id in ["rising", "sweep", "cleave", "lunge"]:
		if found.has(id) and not Profile.data.moves_done.has(id) and not Profile.data.hints_shown.has(id):
			return id
	return ""


func show_hint(id: String) -> void:
	text = tr("HINT_" + id.to_upper())
	Profile.mark_hint(id)
	_quiet = QUIET_FOR
	_showing = SHOW_FOR
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)


func _our_body() -> Player:
	for node in get_tree().get_nodes_in_group("player"):
		if node.is_multiplayer_authority():
			return node as Player
	return null
