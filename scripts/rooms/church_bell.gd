extends Node2D
## The bell of the church. It rings when the player, talking to Father
## Matthew, chooses to ring it (dialogue npc_matthew, choice "bell"): three
## strokes, each a flash from the tower and a tremor. A quiet scene's one
## loud moment; the flag matthew_bell is what the story remembers.

const STROKES := 3

var _rung := false


func _ready() -> void:
	EventBus.choice_made.connect(_on_choice)


func _on_choice(dialogue_id: String, choice_id: String) -> void:
	if _rung or dialogue_id != "npc_matthew" or choice_id != "bell":
		return
	_rung = true
	_ring()


func _ring() -> void:
	for stroke in STROKES:
		Audio.play(&"bell", 0.0, 1.0 - stroke * 0.02)
		Juice.shake(2.5)
		Fx.flash(global_position, Color(1.0, 0.9, 0.7), 240.0, 1.2, 0.8)
		Fx.sparkle(global_position + Vector2(0, 30), Color(1.0, 0.9, 0.6), 10, 30.0)
		await get_tree().create_timer(1.4).timeout
		if not is_inside_tree():
			return
