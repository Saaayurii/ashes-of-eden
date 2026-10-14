extends RefCounted
class_name Fruit
## The garden's fruit (docs/CHAPTER5.md §2): a prop of `"kind": "fruit"`
## (data/props) hung on a tree or laid on a table. Eating is a choice, never an
## accident: it is taken on `interact` (Prop's prompt, `PROMPT_EAT`), never by
## walking into it. A fruit lifts the sting first and then heals (Player.eat) —
## the one heal the sting does not stop, which is its temptation — and adds to
## the night's surfeit (Game.surfeit), which thickens every locust cloud still
## to come (Swarm.size_for). Once a night: an eaten fruit is remembered in
## Game.flags under "eaten:<room>/<node>", which a save carries; a rest point
## does not grow it back. The first one sets the night's flag `fruit_eaten`.
## Online the opener's peer sends Prop._net_open as for a chest; the surfeit is
## the host's to count, the heal the eater's own.
##   heal           share of max_hp, 0.05..0.5 (× the omen's fruit_heal)
##   surfeit        units, 1..3 (× the omen's surfeit_per_fruit)
##   lifts_torment  bool, true by default
##   style          fig | grapes | pomegranate | feast (crumbs' colour)

const STYLES := {
	"fig": Color("#6a3a5a"),
	"grapes": Color("#5a3a6a"),
	"pomegranate": Color("#b0303a"),
	"feast": Color("#c8a060"),
}
const FLAG := "fruit_eaten"


static func is_fruit(stats: Dictionary) -> bool:
	return str(stats.get("kind", "")) == "fruit"


## The key an eaten fruit is remembered by: its room and its node.
static func key(prop: Node) -> String:
	var room := prop.get_tree().get_first_node_in_group("room") if prop.is_inside_tree() else null
	var where := room.scene_file_path.get_file().get_basename() if room != null else ""
	return "eaten:%s/%s" % [where, prop.name]


static func eaten(prop: Node) -> bool:
	return Game.flags.has(key(prop))


## Every peer, once the fruit is taken: crumbs, and the eater's own body heals.
static func eat(prop: Node2D, eater: Player) -> void:
	var stats: Dictionary = prop.stats
	var tint: Color = STYLES.get(str(stats.get("style", "fig")), STYLES.fig)
	Fx.debris(prop.global_position + Vector2(0, -8), tint, 6)
	Fx.sparkle(prop.global_position + Vector2(0, -8), Color(1.0, 0.9, 0.7), 6, 6.0)
	Audio.play_at(&"eat", prop.global_position, -3.0)
	prop.visible = false
	Game.flags[key(prop)] = true
	if eater != null and eater._is_mine():
		var share := clampf(float(stats.get("heal", 0.25)), 0.05, 0.5) * float(Vials.rule("fruit_heal"))
		eater.eat(share, bool(stats.get("lifts_torment", true)))
	if not Net.active or prop.multiplayer.is_server():
		Game.surfeit += maxi(1, int(stats.get("surfeit", 1))) * maxi(1, int(Vials.rule("surfeit_per_fruit")))
		Game.flags[FLAG] = true
	EventBus.fruit_eaten.emit(str(prop.get("prop_id")), Game.surfeit)
